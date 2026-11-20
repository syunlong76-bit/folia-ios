import Foundation

// 字幕设置存储（3.7 (55) 工作流 D）：网页版 useTypographySettingsStore
// 里字幕浮层那一组的原生承接——隐藏开关 / 行布局 / 透明度 / 背景 /
// 后续行模糊 / 缩放 / 副字幕内容。UserDefaults 落盘（键 folia.subtitle.*），
// 每次实际变更 post .foliaSubtitleSettingsChanged，字幕层
// （SubtitleOverlayView）与调节面板（SubtitleSettingsPanelViewController）
// 同源订阅、即时生效。
//
// 缺省值对网页口径（useTypographySettingsStore 初值）：
// - hidePlayerTranslationSubtitle = false → isHidden 缺省 false（默认开启）
// - subtitleOverlayOpacity 缺省 0.6，钳制 [0.2, 1]，步进 0.05
// - subtitleOverlayBackground 缺省 true
// - subtitleUpcomingLyricsBlur 缺省 true
// - subtitleFontScale 缺省 1，钳制 [0.85, 1.4]，步进 0.05
// - subtitleContentMode 缺省 .translation
// - subtitleOverlayLayout 网页缺省 'translation'（单行译文）。原生改
//   'current+translation'（当前句＋译文）：协议 LyricLine 与仓库行表
//   LyricLineData 均无 translation / romanization 字段（2026-11-21
//   grep 实查，StillStageRenderer 头注同结论），单行译文在原生恒无
//   内容可显、只剩后续预览兜底，与「字幕层显示当前歌词行」的任务
//   口径冲突；'current+translation' 在译文数据缺失时译文行自动省
//   略、当前句照常显示，数据将来补齐后译文行自动出现。单行译文
//   布局本身在面板里仍可选（行数 1 ＋ 第一行＝译文）。

/// 副字幕内容（网页 SubtitleContentMode）：译文 / 罗马音 / 两者 / 无。
/// 原生消费点在 SubtitleOverlayView.resolve：决定布局里的译文/罗马音
/// 行是否参与呈现。当前歌词数据无译文/罗马音字段，该过滤暂无可见
/// 差异（见 SubtitleOverlayView 头注），不是只存不用。
enum SubtitleContentMode: String, CaseIterable {
    case translation
    case romanization
    case both
    case none

    var displayName: String {
        switch self {
        case .translation: return "译文"
        case .romanization: return "罗马音"
        case .both: return "两者"
        case .none: return "无"
        }
    }
}

/// 字幕行来源（网页 SubtitleOverlayRowSource）。
enum SubtitleRowSource: String, CaseIterable {
    case current
    case next
    case translation
    case romanization

    var displayName: String {
        switch self {
        case .current: return "当前句"
        case .next: return "下一句"
        case .translation: return "译文"
        case .romanization: return "罗马音"
        }
    }

    /// 第一行可选集（网页 SUBTITLE_OVERLAY_SINGLE_ROWS）。
    static let singleRowOptions: [SubtitleRowSource] = [.current, .translation, .romanization]
    /// 第二行起可选集（网页 SUBTITLE_OVERLAY_FOLLOW_ROWS）。
    static let followRowOptions: [SubtitleRowSource] = [.next, .translation, .romanization]
}

final class SubtitleSettingsStore {

    static let shared = SubtitleSettingsStore()
    static let changedNotification = Notification.Name("folia.subtitleSettings.changed")

    private enum Key {
        static let hidden = "folia.subtitle.hidden"
        static let layout = "folia.subtitle.layout"
        static let opacity = "folia.subtitle.opacity"
        static let background = "folia.subtitle.background"
        static let blurUpcoming = "folia.subtitle.blurUpcoming"
        static let fontScale = "folia.subtitle.fontScale"
        static let contentMode = "folia.subtitle.contentMode"
    }

    /// 原生缺省布局（理由见文件头注）。
    static let defaultLayout = "current+translation"
    private static let rowsOnlySuffix = "|only"

    private let defaults = UserDefaults.standard

    private init() {
        isHidden = defaults.bool(forKey: Key.hidden)
        let storedLayout = defaults.string(forKey: Key.layout)
        layout = (storedLayout.flatMap { Self.isValidLayout($0) ? $0 : nil })
            ?? Self.defaultLayout
        opacity = defaults.object(forKey: Key.opacity) as? Double
            ?? 0.6
        hasBackground = defaults.object(forKey: Key.background) as? Bool ?? true
        blurUpcoming = defaults.object(forKey: Key.blurUpcoming) as? Bool ?? true
        fontScale = defaults.object(forKey: Key.fontScale) as? Double ?? 1.0
        contentMode = defaults.string(forKey: Key.contentMode)
            .flatMap { SubtitleContentMode(rawValue: $0) } ?? .translation
        opacity = Self.clampOpacity(opacity)
        fontScale = Self.clampFontScale(fontScale)
    }

    // MARK: - 设置项（didSet 落盘＋广播；字幕层即时消费）

    /// 隐藏底部字幕层（网页 hidePlayerTranslationSubtitle）。
    var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            defaults.set(isHidden, forKey: Key.hidden)
            notifyChanged("hidden=\(isHidden)")
        }
    }

    /// 行布局原始串（网页 SubtitleOverlayLayout，如 "current+next"、
    /// "translation|only"）。改布局请走下方 setRowCount / setRow /
    /// setPreviewsUpcoming，它们按网页 subtitleOverlayLayout.ts 的
    /// 同名函数语义编辑本串。
    private(set) var layout: String {
        didSet {
            guard layout != oldValue else { return }
            defaults.set(layout, forKey: Key.layout)
            notifyChanged("layout=\(layout)")
        }
    }

    /// 字幕透明度（网页 subtitleOverlayOpacity，[0.2, 1]）。
    var opacity: Double {
        didSet {
            let clamped = Self.clampOpacity(opacity)
            if clamped != opacity { opacity = clamped; return }
            guard opacity != oldValue else { return }
            defaults.set(opacity, forKey: Key.opacity)
            notifyChanged("opacity=\(String(format: "%.2f", opacity))")
        }
    }

    /// 字幕背景辉光（网页 subtitleOverlayBackground）。
    var hasBackground: Bool {
        didSet {
            guard hasBackground != oldValue else { return }
            defaults.set(hasBackground, forKey: Key.background)
            notifyChanged("background=\(hasBackground)")
        }
    }

    /// 后续歌词（预览行）模糊（网页 subtitleUpcomingLyricsBlur）。
    var blurUpcoming: Bool {
        didSet {
            guard blurUpcoming != oldValue else { return }
            defaults.set(blurUpcoming, forKey: Key.blurUpcoming)
            notifyChanged("blurUpcoming=\(blurUpcoming)")
        }
    }

    /// 字幕缩放（网页 subtitleFontScale，[0.85, 1.4]）。
    var fontScale: Double {
        didSet {
            let clamped = Self.clampFontScale(fontScale)
            if clamped != fontScale { fontScale = clamped; return }
            guard fontScale != oldValue else { return }
            defaults.set(fontScale, forKey: Key.fontScale)
            notifyChanged("fontScale=\(String(format: "%.2f", fontScale))")
        }
    }

    /// 副字幕内容（网页 subtitleContentMode）。
    var contentMode: SubtitleContentMode {
        didSet {
            guard contentMode != oldValue else { return }
            defaults.set(contentMode.rawValue, forKey: Key.contentMode)
            notifyChanged("contentMode=\(contentMode.rawValue)")
        }
    }

    private func notifyChanged(_ what: String) {
        Breadcrumbs.log("stage.subtitle.setting \(what)")
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    static func clampOpacity(_ value: Double) -> Double {
        min(1, max(0.2, value))
    }

    static func clampFontScale(_ value: Double) -> Double {
        min(1.4, max(0.85, value))
    }

    // MARK: - 布局代数（网页 subtitleOverlayLayout.ts 逐函数移植）

    /// 布局的行表（自上而下），剥掉 |only 后缀后按 "+" 拆分。
    var rows: [SubtitleRowSource] { Self.rows(of: layout) }

    var rowCount: Int { rows.count }

    /// 布局行无内容可显时是否预览后续歌词（无 |only 后缀 = 预览）。
    var previewsUpcoming: Bool { !layout.hasSuffix(Self.rowsOnlySuffix) }

    static func rows(of layout: String) -> [SubtitleRowSource] {
        let body = layout.hasSuffix(rowsOnlySuffix)
            ? String(layout.dropLast(rowsOnlySuffix.count)) : layout
        return body.split(separator: "+").compactMap {
            SubtitleRowSource(rawValue: String($0))
        }
    }

    static func isValidLayout(_ value: String) -> Bool {
        let rows = rows(of: value)
        guard (1...3).contains(rows.count),
              let first = rows.first,
              SubtitleRowSource.singleRowOptions.contains(first)
        else { return false }
        return rows.dropFirst().allSatisfy {
            SubtitleRowSource.followRowOptions.contains($0)
        }
    }

    private static func joined(_ rows: [SubtitleRowSource],
                               previewsUpcoming: Bool) -> String {
        let body = rows.map { $0.rawValue }.joined(separator: "+")
        return previewsUpcoming ? body : body + rowsOnlySuffix
    }

    /// 改行数（网页 withSubtitleOverlayRowCount）：缩到 1 行时保留
    /// 首个译文/罗马音行（都没有则当前句）；自 1 行扩行时首行固定
    /// 当前句、原单行内容降为第二行；新增行取布局尚未展示的内容。
    func setRowCount(_ count: Int) {
        let target = min(3, max(1, count))
        let current = rows
        guard target != current.count else { return }
        let nextRows: [SubtitleRowSource]
        if target == 1 {
            if current.count == 1 { return }
            let single = current.first(where: {
                $0 == .translation || $0 == .romanization
            }) ?? .current
            nextRows = [single]
        } else {
            let first: SubtitleRowSource = current.count == 1 ? .current : current[0]
            var follows: [SubtitleRowSource]
            if current.count == 1 {
                follows = [current[0] == .current ? .next : current[0]]
            } else {
                follows = Array(current.dropFirst())
            }
            while follows.count < target - 1 {
                let candidate = [SubtitleRowSource.translation, .romanization, .next]
                    .first(where: { $0 != first && !follows.contains($0) }) ?? .next
                follows.append(candidate)
            }
            nextRows = [first] + Array(follows.prefix(target - 1))
        }
        layout = Self.joined(nextRows, previewsUpcoming: previewsUpcoming)
    }

    /// 改某一行的内容（网页 withSubtitleOverlayRow）：第一行改成与
    /// 下方某行相同的内容时，那一行顺移为布局尚未展示的内容，
    /// 避免同内容叠两行。
    func setRow(at index: Int, source: SubtitleRowSource) {
        var next = rows
        guard next.indices.contains(index) else { return }
        if index == 0 {
            guard SubtitleRowSource.singleRowOptions.contains(source) else { return }
        } else {
            guard SubtitleRowSource.followRowOptions.contains(source) else { return }
        }
        next[index] = source
        if index == 0 {
            for at in 1..<next.count where next[at] == source {
                next[at] = [SubtitleRowSource.translation, .romanization]
                    .first(where: { !next.contains($0) }) ?? .next
            }
        }
        layout = Self.joined(next, previewsUpcoming: previewsUpcoming)
    }

    /// 预览后续歌词开关（网页 withSubtitleOverlayUpcomingPreview）。
    func setPreviewsUpcoming(_ on: Bool) {
        guard on != previewsUpcoming else { return }
        layout = Self.joined(rows, previewsUpcoming: on)
    }
}

extension Notification.Name {
    /// 字幕设置变更（3.7 (55) 工作流 D）：SubtitleSettingsStore 每次
    /// 实际变更后发出，字幕层与调节面板订阅即时刷新。
    static let foliaSubtitleSettingsChanged =
        Notification.Name("folia.subtitleSettings.changed")
}
