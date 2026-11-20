import UIKit

// 舞台底部字幕层（3.7 (55) 工作流 D）：网页版 VisualizerSubtitleOverlay
// 的原生承接——此前原生舞台无底部字幕层本体（migration 审计）。
// 挂在点播台上方、歌词渲染层之上，pointer-events 与网页一致为 none
// （isUserInteractionEnabled = false，不抢舞台手势）。
//
// 时钟纪律：不自建时钟。宿主 StageViewController 在 frameStep 里把
// 喂给渲染器的同一个锚点外推位置（positionNow()）与同一份行表
// （linesCache 派生的 [LyricLine]）逐帧喂入 update(lines:position:)；
// 当前行判定走 LyricParser.currentIndex，与各渲染器同口径。
//
// 呈现规则逐项对网页 resolveVisualizerSubtitleOverlayContent：
// - 隐藏开关开 / 无行表 → 整层不显。
// - 按 SubtitleSettingsStore.layout 的行表逐行解析：current = 当前
// 行原文；next = 后续行依次消费；translation / romanization =
// 当前行的译文 / 罗马音——原生数据缺失恒为空、该行省略（见下）。
// - 只有 next 行成立时整组作废（网页同规则：next 行只能跟在行自身
// 的内容行之下）；行表全部无内容且布局允许预览时，改显后续歌词
// 预览（最多 2 行，即面板「下二句」口径）。
// - 含不可读文本（纯符号/分隔行）不显，与网页 hasReadableText 同规。
//
// 数据缺口（2026-11-21 grep 实查）：协议 LyricLine（LyricStageProtocol）
// 字段只有 id/start/end/text/words/singingRatio；仓库行表 LyricLineData
// 只有 time/text/words；LyricRepository.Entry 无译文字段。故译文与
// 罗马音在原生均无数据源（网页 Line.translation /.romanization 是
// 可选字段、网页侧有数据才有）。本层如实不造：alternateText 恒返回
// nil，布局/副字幕内容里选到译文/罗马音时对应行不显；协议将来扩
// 字段后只需改 alternateText 一处。
//
// 设置消费点（SubtitleSettingsStore，本层全量订阅即时生效）：
// - isHidden → 整层显隐；opacity → 整层 alpha；hasBackground → 背景
// 辉光层显隐；fontScale → 全部行字号倍率；layout（行数/各行内容/
// 预览开关）→ resolve 的行表；blurUpcoming → 预览行与 next 行的
// 模糊近似呈现（见下方注）；contentMode → resolve 里译文/罗马音
// 行的参与过滤（.none 全滤、.translation 只留译文、.romanization
// 只留罗马音、.both 全留）。
// 模糊近似：iOS 无公开的文本高斯模糊 API，blurUpcoming 开时预览行
// 以 alpha 0.55 + 柔和阴影呈现、关时 alpha 1 无阴影——开关真改变
// 呈现，但不是 CSS blur-[1px] 的等值复刻（报告 partial）。
final class SubtitleOverlayView: UIView {

    /// 内容/设置变化后高度可能变，宿主据此重跑布局（layoutStage
    /// 里按 preferredHeight 定帧）。
    var onNeedsRelayout: (() -> Void)?

    private let store = SubtitleSettingsStore.shared
    private let backgroundGlow = UIView()
    private let stack = UIStackView()
    private var rowLabels: [UILabel] = []

    /// 演唱会让位（3.7 (55) DS 修正1）：「汪汪队开大会」样式的底部
    /// 提词条与本层同槽，提词条优先——让位期间整层隐藏、update
    /// 喂入不呈现。这是同槽让位不是设置失效：切走该样式即恢复，
    /// 设置本身照常保存与生效（其他样式下全量消费）。
    private var concertYielded = false
    private var lastLines: [LyricLine] = []
    private var lastPosition: TimeInterval = 0
    private var lastSignature = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundGlow.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        backgroundGlow.layer.cornerRadius = 14
        backgroundGlow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundGlow)
        stack.axis =.vertical
        stack.alignment =.center
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
        backgroundGlow.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundGlow.trailingAnchor.constraint(equalTo: trailingAnchor),
        backgroundGlow.topAnchor.constraint(equalTo: topAnchor),
        backgroundGlow.bottomAnchor.constraint(equalTo: bottomAnchor),
        stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
        stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
        stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
        stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        // 宽度上限对网页 max-w-2xl（672pt）：宽屏/横屏不拉满。
        let maxWidth = stack.widthAnchor.constraint(lessThanOrEqualToConstant: 672)
        maxWidth.priority =.required
        maxWidth.isActive = true
        NotificationCenter.default.addObserver(
        self, selector: #selector(settingsChanged),
        name: SubtitleSettingsStore.changedNotification, object: nil)
        applyChrome()
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 宿主喂入（与渲染器同一位置、同一行表）

    func update(lines: [LyricLine], position: TimeInterval) {
        lastLines = lines
        lastPosition = position
        resolveAndRender()
    }

    /// 切歌时宿主可先行清屏（行表未到货期间不留上一首的字幕）。
    func reset() {
        lastLines = []
        lastPosition = 0
        lastSignature = ""
        render(rows: [], upcoming: [])
    }

    /// 演唱会同槽让位开关（宿主按 activeStyleId 逐帧喂入，状态
    /// 未变时为空操作）：让位开始/结束各落一条面包屑。
    func setConcertYielded(_ yielded: Bool) {
        guard yielded != concertYielded else { return }
        concertYielded = yielded
        Breadcrumbs.log("stage.subtitle.yield concert=\(yielded ? 1 : 0)")
        if yielded {
            render(rows: [], upcoming: [])
            isHidden = true
        } else {
            resolveAndRender()
            onNeedsRelayout?()
        }
    }

    @objc private func settingsChanged() {
        applyChrome()
        resolveAndRender()
        onNeedsRelayout?()
    }

    private func applyChrome() {
        alpha = CGFloat(store.opacity)
        backgroundGlow.isHidden =!store.hasBackground
    }

    // MARK: - 解析（网页 resolveVisualizerSubtitleOverlayContent 移植）

    private struct ResolvedRow {
        let source: SubtitleRowSource
        let text: String
        let isSecondary: Bool
    }

    /// 译文/罗马音取数：原生歌词数据无此字段，恒 nil（见头注）。
    /// 协议扩字段后在此按行取真值，其余逻辑不动。
    private func alternateText(for line: LyricLine,
    source: SubtitleRowSource) -> String? {
        nil
    }

    /// contentMode 对译文/罗马音行的参与过滤（真消费点）。
    private func contentModeAllows(_ source: SubtitleRowSource) -> Bool {
        switch source {
            case.translation: return store.contentMode ==.translation || store.contentMode ==.both
            case.romanization: return store.contentMode ==.romanization || store.contentMode ==.both
            default: return true
        }
    }

    private static func hasReadableText(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    private func resolveAndRender() {
        guard !concertYielded else {
            if !isHidden { isHidden = true }
            return
        }
        guard!store.isHidden,!lastLines.isEmpty else {
            render(rows: [], upcoming: [])
            return
        }
        let idx = LyricParser.currentIndex(in: lastLines, at: lastPosition)
        let line = idx.map { lastLines[$0]}
        let previewLines: [LyricLine] = idx.map { i in
            Array(lastLines.dropFirst(i + 1))
        }?? lastLines
        let readablePreview = previewLines.filter { Self.hasReadableText($0.text)}

        var rows: [ResolvedRow] = []
        var nextIndex = 0
        if let line {
            for (rowIndex, source) in store.rows.enumerated() {
                if source ==.next {
                    if nextIndex < readablePreview.count {
                        rows.append(ResolvedRow(
                        source:.next, text: readablePreview[nextIndex].text,
                        isSecondary: rowIndex > 0))
                    }
                    nextIndex += 1
                    continue
                }
                let text: String?
                if source ==.current {
                    text = line.text
                } else if contentModeAllows(source) {
                    text = alternateText(for: line, source: source)
                } else {
                    text = nil
                }
                guard let text, Self.hasReadableText(text) else { continue}
                // 译文/罗马音与上方行同文时只显一次（网页同规则）。
                if source!=.current,
                rows.contains(where: { $0.source!=.next && $0.text == text}) {
                    continue
                }
                rows.append(ResolvedRow(
                source: source, text: text, isSecondary: rowIndex > 0))
            }
        }
        // 只有 next 行成立 → 整组作废（网页同规则）。
        if!rows.isEmpty, rows.allSatisfy({ $0.source ==.next}) {
            rows = []
        }
        var upcoming: [String] = []
        if rows.isEmpty, line!= nil, store.previewsUpcoming {
            upcoming = readablePreview.prefix(2).map { $0.text}
        }
        render(rows: rows, upcoming: upcoming)
        // 面包屑去重：签名（行号＋行表构成＋预览数）变化才落盘。
        let signature = "\(idx?? -1)|\(rows.map { $0.source.rawValue}.joined(separator: ","))|\(upcoming.count)|\(store.layout)"
        if signature!= lastSignature {
            lastSignature = signature
            Breadcrumbs.log("stage.subtitle.show idx=\(idx?? -1)"
            + " rows=\(rows.count) upcoming=\(upcoming.count)"
            + " layout=\(store.layout)")
        }
    }

    // MARK: - 渲染

    private func render(rows: [ResolvedRow], upcoming: [String]) {
        let texts: [(text: String, isSecondary: Bool, isUpcoming: Bool)] =
        rows.map { ($0.text, $0.isSecondary, $0.source ==.next)}
        + upcoming.map { ($0, false, true)}
        let signature = texts.map { "\($0.text)|\($0.isSecondary)|\($0.isUpcoming)"}
        .joined(separator: "\u{1}") + "|\(store.fontScale)|\(store.blurUpcoming)"
        // 文本构成未变时不重建标签（逐帧调用，避免无谓布局抖动）。
        if signature == renderSignature { return}
        renderSignature = signature
        for label in rowLabels { label.removeFromSuperview()}
        rowLabels = []
        for item in texts {
            let label = UILabel()
            label.text = item.text
            label.textAlignment =.center
            label.numberOfLines = item.isUpcoming? 1: 2
            label.lineBreakMode = item.isUpcoming?.byTruncatingTail:.byWordWrapping
            // 字号对网页 subtitleFontSizes：主行 clamp(1.125rem, 2.6vw,
            // 1.25rem) ≈ 19pt、预览行 clamp(0.875rem, 2vw, 1rem) ≈ 15pt，
            // 均乘字幕缩放；副行再乘 SECONDARY_TRACK_SIZE_FACTOR 0.88
            // 与 0.82 不透明度（subtitleTrackStyle 网页同值）。字号
            // 下限 12pt：缩放 0.85 时预览行 15×0.85≈12.75 仍达标，
            // 钳制兜底防更小。
            let base: CGFloat = item.isUpcoming? 15: 19
            var size = base * CGFloat(store.fontScale)
            if item.isSecondary { size *= 0.88}
            label.font =.systemFont(ofSize: max(12, size),
            weight: item.isSecondary?.regular:.medium)
            label.textColor = UIColor.white.withAlphaComponent(
            item.isSecondary? 0.82: 0.92)
            if item.isUpcoming {
                applyUpcomingStyle(to: label)
            } else {
                label.shadowColor = UIColor.black.withAlphaComponent(0.45)
                label.shadowOffset = CGSize(width: 0, height: 1)
            }
            stack.addArrangedSubview(label)
            rowLabels.append(label)
        }
        let shouldShow =!texts.isEmpty
        if isHidden == shouldShow {
            isHidden =!shouldShow
            if shouldShow {
                Breadcrumbs.log("stage.subtitle.visible rows=\(texts.count)")
            }
        }
        onNeedsRelayout?()
    }

    private var renderSignature = ""

    /// 后续行样式：blurUpcoming 开 = 低透明＋柔影（CSS 模糊的近似，
    /// 见头注 partial 说明）；关 = 常规不透明。
    private func applyUpcomingStyle(to label: UILabel) {
        if store.blurUpcoming {
            label.alpha = 0.55
            label.shadowColor = UIColor.white.withAlphaComponent(0.35)
            label.shadowOffset =.zero
        } else {
            label.alpha = 1
            label.shadowColor = UIColor.black.withAlphaComponent(0.45)
            label.shadowOffset = CGSize(width: 0, height: 1)
        }
    }

    /// 当前内容在给定宽度下的高度（宿主 layoutStage 定帧用）：
    /// 无内容时 0（整层隐藏、不占位）。
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard!isHidden,!rowLabels.isEmpty else { return 0}
        let fitting = CGSize(width: width, height:.greatestFiniteMagnitude)
        return ceil(stack.systemLayoutSizeFitting(fitting).height) + 14
    }
}
