import UIKit

/// 渲染方根视图：把 layoutSubviews 转给持有它的渲染方排版。
final class LyricStageRootView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

// 静态排版型样例（classic 原型，自有风格实现）：
// 整页歌词排版——全部行纵向排满一页可滚长卷，当前行以宋体粗体
// +全亮呈现，其余行按与当前行的距离衰减透明度；换行时自动把
// 当前行滚到视口中央。点任意行 seek 到该行（走协议控制回传）。
// 只经 LyricStage 协议拿数据：快照给曲目/歌词/调色板，逐帧位置
// 由宿主 frameTick 喂入，时钟源不在本类。
final class ClassicStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = LyricStageRootView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var lineLabels: [UILabel] = []
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var currentIndex: Int? = nil
    private var isActive = false
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private let emptyLabel = UILabel()

    init() {
        view = rootView
        rootView.backgroundColor = .clear
        rootView.onLayout = { [weak self] in self?.performLayout() }
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        rootView.addSubview(scrollView)
        stack.axis = .vertical
        stack.alignment = .fill
        scrollView.addSubview(stack)
        emptyLabel.text = "暂无歌词"
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        rootView.addSubview(emptyLabel)
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        let trackId = snapshot.track?.id
        if trackId != builtTrackId || snapshot.lines.count != builtLineCount {
            builtTrackId = trackId
            builtLineCount = snapshot.lines.count
            currentIndex = nil
            rebuildLines()
        }
        applyPalette()
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let idx = LyricParser.currentIndex(in: snapshot.lines, at: position)
        guard idx != currentIndex else { return }
        currentIndex = idx
        restyleLines()
        scrollToCurrent(animated: true)
    }

    func unmount() {
        isActive = false
        context = nil
    }

    // MARK: 构建与样式

    private func rebuildLines() {
        for label in lineLabels { label.removeFromSuperview() }
        lineLabels.removeAll()
        guard let snapshot else { return }
        emptyLabel.isHidden = !snapshot.lines.isEmpty
        scrollView.isHidden = snapshot.lines.isEmpty
        for (row, line) in snapshot.lines.enumerated() {
            let label = UILabel()
            label.text = line.text
            label.numberOfLines = 0
            label.textAlignment = .center
            label.tag = row
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(
                target: self, action: #selector(lineTapped(_:))))
            stack.addArrangedSubview(label)
            lineLabels.append(label)
        }
        restyleLines()
        rootView.setNeedsLayout()
    }

    private func fontSize() -> CGFloat {
        min(max(rootView.bounds.width * 0.05, 16), 22)
    }

    private func restyleLines() {
        guard let snapshot else { return }
        let size = fontSize()
        stack.spacing = size * 0.95
        for (row, label) in lineLabels.enumerated() {
            let isCurrent = row == currentIndex
            let distance = currentIndex.map { abs(row - $0) } ?? 99
            label.font = isCurrent
                ? Self.songtiBold(size: size + 1.5)
                : Self.songtiLight(size: size)
            let base = snapshot.palette.text
            label.textColor = isCurrent
                ? base
                : base.withAlphaComponent(distance <= 1 ? 0.55 : distance <= 3 ? 0.38 : 0.26)
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.55
            label.layer.shadowRadius = 3
            label.layer.shadowOffset = .zero
        }
    }

    private func applyPalette() {
        guard let snapshot else { return }
        emptyLabel.font = Self.songtiLight(size: fontSize())
        emptyLabel.textColor = snapshot.palette.text.withAlphaComponent(0.5)
        restyleLines()
    }

    private func scrollToCurrent(animated: Bool) {
        guard let idx = currentIndex, lineLabels.indices.contains(idx) else { return }
        let label = lineLabels[idx]
        let targetY = label.frame.midY - scrollView.bounds.height / 2
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(
            CGPoint(x: 0, y: min(max(targetY, 0), maxY)), animated: animated)
    }

    @objc private func lineTapped(_ gesture: UITapGestureRecognizer) {
        guard let label = gesture.view as? UILabel,
              let snapshot, snapshot.lines.indices.contains(label.tag) else { return }
        context?.sendCommand(LyricStageCommand(
            kind: .seek(to: snapshot.lines[label.tag].start),
            source: LyricStageRegistry.info(for: snapshot.styleId)?.sourceTag ?? "stage.classic"))
    }

    // MARK: 布局

    private func performLayout() {
        let bounds = rootView.bounds
        scrollView.frame = bounds
        let horizontalPadding: CGFloat = 28
        let width = max(bounds.width - horizontalPadding * 2, 0)
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: width, height: .greatestFiniteMagnitude))
        stack.frame = CGRect(x: horizontalPadding, y: 0, width: width, height: fitting.height)
        scrollView.contentInset = UIEdgeInsets(
            top: bounds.height * 0.32, left: 0, bottom: bounds.height * 0.32, right: 0)
        scrollView.contentSize = CGSize(width: bounds.width, height: fitting.height)
        emptyLabel.frame = bounds
        restyleLines()
    }

    static func songtiBold(size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
    }

    static func songtiLight(size: CGFloat) -> UIFont {
        UIFont(name: "STSongti-SC-Light", size: size)
            ?? .systemFont(ofSize: size, weight: .light)
    }
}
