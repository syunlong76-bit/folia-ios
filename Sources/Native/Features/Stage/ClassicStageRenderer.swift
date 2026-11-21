import UIKit

// 流光 classic（3.7 (26) 照搬对齐版，M2'）：按 folia-major 网页版
// classic/Visualizer.tsx 的展示行为逐项实现，不再是 (14) 的自有
// 风格整页滚动版。对齐要点（依据文件见 (26) 回报附表）：
//  - 画面只呈现当前一行：行容器入场 scale 0.9/透明、出场 scale
//    1.1/透明（各 0.3s，网页 blur 分量原生以缩放+透明近似）；
//    前奏与行间长空档无当前行时画面空白（网页 waitingForMusic
//    文案三份语言文件均为空串，实际即空白）。
//  - 行内逐词三态（waiting/active/passed）由共享 GlowWordEngine
//    驱动：词姿态以行 startTime 为种子确定性伪随机（偏移 ±20pt、
//    旋转 ±5°、缩放 1.1–1.3、active ×1.4 弹簧入场），词间距按
//    网页的溢出感知公式逐对计算。
//  - 整行排版：flex-wrap 等价的流式折行，行距 = 字号 ×1.22；
//    每行的 justify/align 由种子在网页同一组选项里选定；块高
//    下限 300pt、块在渲染区内居中，两侧留白 32pt。
//  - 字号 clamp(36, 6vmin, 72)（vmin 取快照视口短边，与网页
//    iOS lyricViewportUnit='vmin' 口径一致），字重 700 宋体。
//  - 歌词区在网页为 pointer-events-none：点行 seek 不属于本
//    样式行为，本版移除（seek 走宿主进度条）。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置。
final class ClassicStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    private let floatView = UIView()
    /// 粒子换行层（3.7 (49)）：盖在行容器之上，过渡期间
    /// 真实新行先藏在本层之下、reveal 点淡入衔接。
    private let particleView = ParticleTransitionView()
    private var particleHiddenContainer: UIView?
    private var lineContainer: UIView?
    private var wordViews: [GlowWordView] = []
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var activeLineId: Int? = nil
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var builtFontSize: CGFloat = 0

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.addSubview(floatView)
        rootView.addSubview(particleView)
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
            clearLine(animated: false)
        }
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if isActive {
            StageBreathingFloat.start(on: floatView)
        } else {
            StageBreathingFloat.stop(on: floatView)
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let idx = Self.activeIndex(in: snapshot.lines, at: position)
        if idx != activeLineId {
            transitionLine(to: idx, position: position)
        }
        for word in wordViews { word.update(position: position) }
        particleView.tick()
    }

    func unmount() {
        isActive = false
        StageBreathingFloat.stop(on: floatView)
        particleView.cancel()
        particleHiddenContainer = nil
        context = nil
    }

    // MARK: 当前行判定

    /// 当前行 = 最后一个 start ≤ position 的行；行结束后留
    /// 0.35s 余像（网页 renderEnd 的出场余量近似），其后若下
    /// 一行未开始则无当前行（画面空白，与网页一致）。
    static func activeIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int? = nil
        for (index, line) in lines.enumerated() {
            if line.start <= position { result = index } else { break }
        }
        guard let idx = result else { return nil }
        if position > lines[idx].end + 0.35 { return nil }
        return idx
    }

    // MARK: 行构建与切换

    private func clearLine(animated: Bool) {
        particleView.cancel()
        particleHiddenContainer = nil
        if let container = lineContainer {
            container.removeFromSuperview()
        }
        lineContainer = nil
        wordViews = []
        activeLineId = nil
    }

    private func transitionLine(to idx: Int?, position: TimeInterval) {
        let oldIdx = activeLineId
        let old = lineContainer
        lineContainer = nil
        wordViews = []
        activeLineId = idx

        // 粒子换行（3.7 (49)）：自然顺翻（旧行→紧邻下一
        // 行、位置落在新行行首 1.2s 内）时，旧行先快照采
        // 样再移除，粒子散开接管出场；seek/跳行/回退/空档
        // 断档一律走原出入场，不触发仪式。
        var outgoingField: ParticleField?
        if let old {
            let oldHidden = old === particleHiddenContainer
            if oldHidden { particleHiddenContainer = nil }
            if !oldHidden,
               StageEffectSettings.particleFlipEnabled,
               particleView.isAvailable,
               let oldIdx, let idx, idx == oldIdx + 1,
               let snapshot, snapshot.lines.indices.contains(idx),
               position - snapshot.lines[idx].start < 1.2 {
                outgoingField = ParticleFieldSampler.sample(
                    view: old, in: rootView, maxPoints: 1600)
            }
            if outgoingField != nil || oldHidden {
                old.removeFromSuperview()
                if oldHidden { particleView.cancel() }
            } else {
                // 旧行出场：scale 1.1 + 淡出 0.3s 后移除（网页 exit）。
                UIView.animate(withDuration: 0.3, delay: 0,
                               options: [.curveEaseInOut]) {
                    old.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                    old.alpha = 0
                } completion: { _ in old.removeFromSuperview() }
            }
        }
        guard let idx, let snapshot,
              snapshot.lines.indices.contains(idx) else { return }
        let built = buildLineContainer(line: snapshot.lines[idx])
        lineContainer = built.container
        wordViews = built.words
        floatView.addSubview(built.container)
        layoutLineContainer(built.container)
        for word in built.words { word.snap(position: position) }

        if let outgoingField {
            // 新行采样：snap 后词多为 waiting（alpha 0），
            // 采样前临时全显、采完恢复。采到则真实行先隐
            // 藏，粒子聚拢成字、reveal 点淡入衔接（跳过原
            // 0.9 缩放入场，粒子目标即恒等几何）。
            let savedAlphas = built.words.map { $0.alpha }
            for word in built.words { word.alpha = 1 }
            let incomingField = ParticleFieldSampler.sample(
                view: built.container, in: rootView, maxPoints: 1600)
            for (word, saved) in zip(built.words, savedAlphas) {
                word.alpha = saved
            }
            if let incomingField {
                built.container.alpha = 0
                particleHiddenContainer = built.container
                let container = built.container
                particleView.onReveal = { [weak self, weak container] in
                    guard let self, let container,
                          self.particleHiddenContainer === container
                    else { return }
                    self.particleHiddenContainer = nil
                    UIView.animate(withDuration: 0.25) {
                        container.alpha = 1
                    }
                }
                particleView.begin(outgoing: outgoingField,
                                   incoming: incomingField)
                return
            }
        }
        // 新行入场：scale 0.9/透明 → 恒等（网页 initial/animate）。
        built.container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        built.container.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            built.container.transform = .identity
            built.container.alpha = 1
        }
    }

    /// 字号（网页 mainFontSize，iOS vmin 口径）：
    /// clamp(2.25rem, 6vmin, 4.5rem)，rem = 16。
    private func fontSize() -> CGFloat {
        let viewport = snapshot?.viewport.size ?? rootView.bounds.size
        let vmin = min(viewport.width, viewport.height)
        guard vmin > 0 else { return 36 }
        return max(36, min(6 * vmin / 100, 72))
    }

    private func buildLineContainer(line: LyricLine)
        -> (container: UIView, words: [GlowWordView]) {
        guard let snapshot else { return (UIView(), []) }
        let size = fontSize()
        builtFontSize = size
        let font = StageFonts.bold(size: size)
        let profile = StageLineProfile.profile(for: line)
        let units = StageLyricUnits.units(for: line)
        let palette = snapshot.palette
        let seed = line.start
        let isInterlude = line.text == "......"

        // 词姿态（网页 placementOf，种子 = 行 startTime +
        // 词序 + 分量偏移；normal 强度档）。
        var poses: [StageWordPose] = []
        var widths: [CGFloat] = []
        for (i, unit) in units.enumerated() {
            let r = { (offset: Double) in
                stageSeededRandom(seed + Double(i) + offset)
            }
            if isInterlude {
                poses.append(StageWordPose(
                    x: 0, y: CGFloat(r(2) - 0.5) * 15,
                    rotate: 0, scale: 1.5, passedRotate: 0))
            } else {
                poses.append(StageWordPose(
                    x: CGFloat(r(1) - 0.5) * 40,
                    y: CGFloat(r(2) - 0.5) * 40,
                    rotate: CGFloat(r(3) - 0.5) * 10,
                    scale: CGFloat(1.1 + r(4) * 0.2),
                    passedRotate: CGFloat(r(8) - 0.5) * 45))
            }
            widths.append((unit.text as NSString).size(withAttributes: [.font: font]).width)
        }

        // 词间距（网页非 legacy 分支公式）：按相邻两词在
        // active 缩放下的溢出量 + 横向姿态差算，×0.7 间距
        // 倍率，下限 0.12em × 0.7。间奏行恒 3rem。
        var margins: [CGFloat] = []
        for i in units.indices {
            if isInterlude { margins.append(48); continue }
            guard i + 1 < units.count else { margins.append(0); continue }
            let sI = poses[i].scale * 1.4
            let sN = poses[i + 1].scale * 1.4
            let halfI = widths[i] * (sI - 1) / 2
            let halfN = widths[i + 1] * (sN - 1) / 2
            let xDiff = poses[i].x - poses[i + 1].x
            let gap = 0.05 * size
            let calculated = (halfI + halfN + xDiff + gap) * 0.7
            margins.append(max(0.12 * size * 0.7, calculated))
        }

        var words: [GlowWordView] = []
        for (i, unit) in units.enumerated() {
            let word = GlowWordView(
                unit: unit, pose: poses[i], font: font,
                baseColor: palette.primary, activeColor: palette.accent,
                profile: profile)
            words.append(word)
        }

        // 流式折行（flex-wrap 等价）：可用宽 = 渲染宽 − 64。
        let bounds = rootView.bounds
        let availWidth = max(bounds.width - 64, 0)
        let pitch = size * 1.22
        var rows: [[Int]] = []
        var row: [Int] = []
        var rowWidth: CGFloat = 0
        for i in units.indices {
            let itemWidth = widths[i] + margins[i]
            if !row.isEmpty && rowWidth + itemWidth > availWidth {
                rows.append(row)
                row = []
                rowWidth = 0
            }
            row.append(i)
            rowWidth += itemWidth
        }
        if !row.isEmpty { rows.append(row) }

        // 每行 justify（种子选定，网页 normal 档五选项）与
        // align（三选项）：justifyIndex = floor(seed % 5)，
        // alignIndex = floor((seed × 2) % 3)。
        let justify = isInterlude ? 1
            : Int((seed.truncatingRemainder(dividingBy: 5)).rounded(.down))
        let align = Int(((seed * 2).truncatingRemainder(dividingBy: 3)).rounded(.down))

        let container = UIView()
        container.isUserInteractionEnabled = false
        let blockHeight = pitch * CGFloat(rows.count)
        let containerHeight = max(300, blockHeight)
        var placed: [(view: GlowWordView, frame: CGRect)] = []
        for (rowIndex, rowItems) in rows.enumerated() {
            // flex 口径：行内每词的右边距都占位（含行末词）。
            let itemsWidth = rowItems.reduce(CGFloat(0)) {
                $0 + widths[$1] + margins[$1]
            }
            var startX: CGFloat = 0
            var extraGap: CGFloat = 0
            switch justify {
            case 1: startX = (availWidth - itemsWidth) / 2          // center
            case 2: startX = availWidth - itemsWidth                // end
            case 3:                                                  // around
                if !rowItems.isEmpty {
                    let unit = (availWidth - itemsWidth) / CGFloat(rowItems.count)
                    startX = unit / 2
                    extraGap = unit
                }
            case 4:                                                  // between
                if rowItems.count > 1 {
                    extraGap = (availWidth - itemsWidth) / CGFloat(rowItems.count - 1)
                }
            default: break                                           // start
            }
            var cursor = startX
            let rowY = (containerHeight - blockHeight) / 2 + pitch * CGFloat(rowIndex)
            for i in rowItems {
                let word = words[i]
                let wordHeight = word.bounds.height
                var y = rowY
                switch align {
                case 0: y = rowY                                     // start
                case 2: y = rowY + pitch - wordHeight                // end
                default: y = rowY + (pitch - wordHeight) / 2         // center
                }
                placed.append((word, CGRect(
                    x: cursor, y: y, width: widths[i], height: wordHeight)))
                cursor += widths[i] + margins[i] + extraGap
            }
        }
        container.frame = CGRect(
            x: 32, y: 0, width: availWidth, height: containerHeight)
        for (word, frame) in placed {
            word.frame = frame
            container.addSubview(word)
        }
        return (container, words)
    }

    private func layoutLineContainer(_ container: UIView) {
        let bounds = rootView.bounds
        container.frame.origin = CGPoint(
            x: 32, y: (bounds.height - container.bounds.height) / 2)
        container.frame.size.width = max(bounds.width - 64, 0)
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0 else { return }
        floatView.frame = bounds
        particleView.frame = bounds
        if let container = lineContainer {
            // 字号随视口变（旋转/分屏）时重建当前行保口径。
            if abs(fontSize() - builtFontSize) > 0.5, let idx = activeLineId {
                let position = context?.positionNow() ?? 0
                lineContainer?.removeFromSuperview()
                lineContainer = nil
                wordViews = []
                activeLineId = nil
                transitionLine(to: idx, position: position)
            } else {
                layoutLineContainer(container)
            }
        }
    }
}
