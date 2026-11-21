import UIKit

// 静止 still（M2' 照搬对齐版）：按 folia-major 网页版
// still/VisualizerStill.tsx 的展示行为逐项实现。依据文件：
// VisualizerStill.tsx、still/entry.tsx、utils/fontStacks.ts、
// types.ts 的 Line、VisualizerShell.tsx（renderBackground=false）。
// 对齐要点：
//  - 本质是静态三行排版：只呈现 effectiveIndex 的前一行 / 当前行 /
//    后一行（offset -1/0/+1），无逐词辉光、无种子随机、无呼吸浮动、
//    无任何过渡动画——网页侧行切换就是 React 直接重渲染，行内
//    没有 framer-motion / CSS transition（壳层的 transition-colors
//    只作用于背景色，本样式 renderBackground=false 且背景透明，
//    不落）。故本文件不复用 GlowWordView / StageBreathingFloat /
//    stageSeededRandom，只复用根视图 LyricStageRootView、字体
//    StageFonts 与 LyricParser.currentIndex（当前行判定同口径）。
//  - effectiveIndex 冻结语义（网页 useState + useEffect）：宿主
//    当前行 = -1（前奏 / 行间空档 / 未开始）时不清空、不回退，
//    冻结在上一有效行；初值 max(0, currentLineIndex)，即进台时
//    无当前行先以第 0 行为当前行展示；effectiveIndex 超出新歌
//    行数时重置为 0。原生以 frameTick 的位置算原始当前行
//    （LyricParser.currentIndex：最后一个 start ≤ position），
//    为 nil 时即对应网页 -1，冻结不动。
//  - 字号为固定 rem（非 vmin 缩放，与 classic 不同）：当前行
//    正文 2.5rem = 40pt、相邻行 3xl = 30pt；字重当前 700 /
//    相邻 600（resolveThemeFontWeight 的 fallback，主题自带
//    fontWeight 时网页会整体覆盖，协议无此字段，未落）；
//    颜色正文 = theme.primaryColor → 协议 palette.primary；
//    不透明度当前 1.0 / 相邻 0.30；字距 0.02em；行高当前
//    leading-tight = 1.25、相邻 text-3xl 自带 36/30 = 1.2。
//    lyricsFontScale 在原生落点为视口 dynamicTypeScale（本期
//    恒 1），乘到字号上。
//  - 布局：整屏纵向居中列，左右留白 px-12 = 48pt，底部
//    pb-16 = 64pt（居中基准因此上移），行间 gap-8 = 32pt，
//    行块最大宽 max-w-4xl = 896pt；缺行（首行之前 / 末行之后）
//    用 h-20 = 80pt 空占位，与网页一致。
//  - 暗角：正文层下有一层径向渐变（ellipse at center，
//    transparent 0% → #000 100%），非 daylight 不透明度 0.65、
//    daylight 0.30 + multiply。协议无 isDaylight 字段，原生以
//    palette.isDark 近似（!isDark → 0.30），multiply 混合模式
//    未落（渐变层仅黑到透明，观感差异小，见回报档案）。
//  - 译文行未落：网页读 line.translation（types.ts Line 的可选
//    字段），但协议 LyricLine 无译文字段、宿主解析器也不产出，
//    数据源缺失；正文行为不受影响，待协议扩展后再补。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置，不自建时钟源。
final class StillStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private let vignetteLayer = CAGradientLayer()
    /// 三个行槽（offset -1/0/+1），init 时建好、终身复用，
    /// 数量恒定不随歌词行数增长。
    private var slotContainers: [UIView] = []
    private var slotLabels: [UILabel] = []
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    /// 网页 effectiveIndex：冻结语义见头部注释。
    private var effectiveIndex = 0
    private var contentDirty = true
    private var builtTrackId: String? = nil
    private var builtLineCount = -1

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.locations = [0, 1]
        vignetteLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.65).cgColor,
        ]
        rootView.layer.addSublayer(vignetteLayer)
        for _ in 0..<3 {
            let container = UIView()
            container.isUserInteractionEnabled = false
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            // drop-shadow-md 的原生近似（正文层柔和投影，
            // 与 GlowWordView 正文阴影同口径）。
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.3
            label.layer.shadowRadius = 4
            label.layer.shadowOffset = CGSize(width: 0, height: 2)
            container.addSubview(label)
            rootView.addSubview(container)
            slotContainers.append(container)
            slotLabels.append(label)
        }
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        self.snapshot = snapshot
        if snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            // 网页 effect 的越界重置：新歌行数变少时回到 0。
            if effectiveIndex >= snapshot.lines.count {
                effectiveIndex = 0
            }
        }
        // 调色板 / 视口变化也要重刷正文样式与暗角。
        contentDirty = true
        updateVignette()
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        // 本样式无任何动画 / 时钟源，inactive 时 frameTick
        // 自行守门即可，无待停的工作。
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let lines = snapshot.lines
        guard !lines.isEmpty else { return }
        // 原始当前行：nil 对应网页 currentLineIndex = -1，
        // 冻结 effectiveIndex 不动（不清空、不回退）。
        guard let raw = LyricParser.currentIndex(in: lines, at: position) else {
            if effectiveIndex >= lines.count {
                effectiveIndex = 0
                contentDirty = true
                rootView.setNeedsLayout()
            }
            return
        }
        if raw != effectiveIndex {
            effectiveIndex = raw
            contentDirty = true
            rootView.setNeedsLayout()
        }
    }

    func unmount() {
        isActive = false
        context = nil
        snapshot = nil
        for label in slotLabels { label.text = nil }
    }

    // MARK: 暗角

    /// 径向渐变不透明度：非 daylight 0.65 / daylight 0.30；
    /// isDaylight 协议无字段，以 palette.isDark 近似。
    private func updateVignette() {
        guard let snapshot else { return }
        // 暗角强度 (62) 由 StillTuning62.vignetteScale 调制。
        let alpha: CGFloat = (snapshot.palette.isDark ? 0.65 : 0.30)
            * CGFloat(StillTuning62.vignetteScale)
        vignetteLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(alpha).cgColor,
        ]
    }

    // MARK: 正文内容

    /// 字号（网页固定 rem，rem = 16）：当前行 2.5rem = 40，
    /// 相邻行 text-3xl = 30；乘 dynamicTypeScale（网页
    /// lyricsFontScale 的原生落点，本期恒 1）。
    private func fontSize(isCurrent: Bool) -> CGFloat {
        let scale = snapshot?.viewport.dynamicTypeScale ?? 1
        return (isCurrent ? 40 : 30) * scale
    }

    /// 刷新三个行槽的正文与样式（仅在内容变更时调用）。
    private func refreshContent() {
        guard let snapshot else { return }
        let lines = snapshot.lines
        for slot in 0..<3 {
            let offset = slot - 1
            let isCurrent = offset == 0
            let lineIndex = effectiveIndex + offset
            let label = slotLabels[slot]
            guard lines.indices.contains(lineIndex) else {
                label.attributedText = nil
                label.isHidden = true
                continue
            }
            let size = fontSize(isCurrent: isCurrent)
            // 字重：(62) 由 StillTuning62.fontWeightChoice 决定
            // （细/常规/粗三档同落三行；此前恒 bold 700）。
            let font: UIFont
            switch StillTuning62.fontWeightChoice {
            case "light": font = StageFonts.light(size: size)
            case "regular":
                font = UIFont(name: "STSongti-SC-Regular", size: size)
                    ?? .systemFont(ofSize: size, weight: .regular)
            default: font = StageFonts.bold(size: size)
            }
            // 行高：当前 leading-tight = 1.25 × 40 = 50；
            // 相邻 text-3xl 自带行高 36（30 × 1.2）。
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let lineHeight = isCurrent ? size * 1.25 : size * 1.2
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: snapshot.palette.primary,
                .kern: size * 0.02,
                .paragraphStyle: paragraph,
            ]
            label.attributedText = NSAttributedString(
                string: lines[lineIndex].text, attributes: attributes)
            label.alpha = isCurrent ? 1 : StagePalette.nonCurrentAlphaFloor // (61) WC：非当前行 0.3→0.45
            label.isHidden = false
        }
        contentDirty = false
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        vignetteLayer.frame = bounds
        if contentDirty { refreshContent() }
        // 行块宽：屏宽 − 左右 48 × 2，上限 max-w-4xl = 896。
        let slotWidth = min(max(bounds.width - 96, 0), 896)
        let slotX = (bounds.width - slotWidth) / 2
        // 各槽高度：有行按正文折行实高，缺行 h-20 = 80 占位。
        var heights: [CGFloat] = []
        for slot in 0..<3 {
            let label = slotLabels[slot]
            if label.isHidden {
                heights.append(80)
            } else {
                let fit = label.sizeThatFits(CGSize(
                    width: slotWidth, height: CGFloat.greatestFiniteMagnitude))
                heights.append(fit.height)
            }
        }
        // 纵向居中列：gap-8 = 32；pb-16 = 64 使居中基准上移。
        let totalHeight = heights.reduce(0, +) + 32 * 2
        var cursorY = (bounds.height - 64 - totalHeight) / 2
        for slot in 0..<3 {
            let container = slotContainers[slot]
            container.frame = CGRect(
                x: slotX, y: cursorY, width: slotWidth, height: heights[slot])
            slotLabels[slot].frame = container.bounds
            cursorY += heights[slot] + 32
        }
    }
}
