import UIKit
import QuartzCore
import CoreImage

// 深廊 corridor（原创稿二，2026-11-20 定稿，DESIGN.md 第二稿）：
// 歌词排成向远处收束的长廊，镜头随演唱前行。舞台恒定四槽
// （上一行/当前行/下一行/下二行），父层 sublayerTransform
// m34 = −1/900 提供透视，各槽位容器以 CATransform3D 定位。
//
// 焦点与虚化：只有当前行是活字（GlowWordEngine，辉光半径
// 8pt、accent 色、waiting 漂移/旋转以零姿态关闭——waiting
// 态在 GlowWordView 内 alpha 恒 0，零姿态下 active/passed
// 变换为恒等，无可见漂移）；非当前行一律一次性快照（建行
// 时 UIGraphicsImageRenderer 渲染 + CIFilter 高斯模糊预烘
// 焙、crop 回原尺寸），逐帧零滤镜成本。
//
// 活字↔快照交接协议（DESIGN §②，DS 对账 #4）：快照在行进入
// 下二行槽位时预烘焙全部档位；推进弹簧期间禁止生成快照，
// 缺图降级 0.3s 交叉淡化；离任行弹簧头 150ms 内淡化为自身
// 快照；接任行以去模糊快照随行推进，落位停稳 150ms 后淡化
// 切活字。时钟纪律：只消费宿主 frameTick，不自建时钟源。

// MARK: - 快照缓存（LRU 8）

final class LineSnapshotCache {
    private var images: [String: UIImage] = [:]
    private var order: [String] = []
    let capacity = 8

    func image(forKey key: String) -> UIImage? { images[key] }

    func store(_ image: UIImage, forKey key: String) {
        if images[key] == nil { order.append(key) }
        images[key] = image
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
        while order.count > capacity {
            let victim = order.removeFirst()
            images[victim] = nil
        }
    }

    func removeAll() {
        images.removeAll()
        order.removeAll()
    }
}

// MARK: - 单行内容视图（快照图层 + 活字层二选一呈现）

final class CorridorLineView: UIView {
    let line: LyricLine
    let imageView = UIImageView()
    let liveContainer = UIView()
    var wordViews: [GlowWordView] = []

    init(line: LyricLine, size: CGSize) {
        self.line = line
        super.init(frame: CGRect(origin: .zero, size: size))
        isUserInteractionEnabled = false
        imageView.frame = bounds
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        liveContainer.frame = bounds
        liveContainer.isUserInteractionEnabled = false
        liveContainer.alpha = 0
        addSubview(imageView)
        addSubview(liveContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSnapshot(_ image: UIImage?) {
        imageView.image = image
        imageView.alpha = 1
        liveContainer.alpha = 0
    }
}

// MARK: - 槽位几何（DESIGN §② 槽位表）

private struct CorridorSlotGeometry {
    var z: CGFloat
    var scale: CGFloat
    var yFactor: CGFloat   // × S（当前行字号）
    var rotateXDegrees: CGFloat
    var alpha: CGFloat
    var blurRadius: CGFloat
}

private let corridorSlots: [CorridorSlotGeometry] = [
    // 0 上一行 / 1 当前行 / 2 下一行 / 3 下二行
    CorridorSlotGeometry(z: 140, scale: 1.06, yFactor: 1.7, rotateXDegrees: -7, alpha: 0.30, blurRadius: 6),
    CorridorSlotGeometry(z: 0, scale: 1.0, yFactor: 0, rotateXDegrees: 0, alpha: 1.0, blurRadius: 0),
    CorridorSlotGeometry(z: -160, scale: 0.78, yFactor: -1.35, rotateXDegrees: 9, alpha: 0.75, blurRadius: 3),
    CorridorSlotGeometry(z: -300, scale: 0.58, yFactor: -2.4, rotateXDegrees: 13, alpha: 0.45, blurRadius: 5),
]

// MARK: - 渲染方

final class CorridorStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    /// 透视父层：sublayerTransform m34 = −1/900。
    private let perspectiveView = UIView()
    private let vanishingGradient = CAGradientLayer()
    private let snapshotCache = LineSnapshotCache()
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false
    /// 在场内容：行下标（lines 数组序）→ 内容视图。
    private var contents: [Int: CorridorLineView] = [:]
    /// 当前行下标（前奏时为 -1 哨兵：槽位按 base=-1 排布）。
    private var baseIndex: Int? = nil
    private var liveIndex: Int? = nil
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var lastPosition: TimeInterval = 0
    private var hasPosition = false
    private var springInFlight = false
    private static let breathingKey = "corridor.breathing"

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = true
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 900.0
        perspectiveView.layer.sublayerTransform = perspective
        perspectiveView.isUserInteractionEnabled = false
        rootView.addSubview(perspectiveView)
        vanishingGradient.type = .radial
        vanishingGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        vanishingGradient.endPoint = CGPoint(x: 1, y: 1)
        rootView.layer.addSublayer(vanishingGradient)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) { self.context = context }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        let trackChanged = snapshot.track?.id != builtTrackId
        self.snapshot = snapshot
        if trackChanged || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            // 快照按 track.id 失效（DESIGN §⑤）。
            snapshotCache.removeAll()
            clearContents()
        }
        updateVanishingGradient()
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if isActive && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !UIAccessibility.isReduceMotionEnabled {
            startBreathing()
        } else {
            perspectiveView.layer.removeAnimation(forKey: Self.breathingKey)
        }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let lines = snapshot.lines
        guard !lines.isEmpty, rootView.bounds.width > 0 else { return }
        let jumped = hasPosition && (position < lastPosition - 0.3 || position - lastPosition > 1.5)
        let raw = LyricParser.currentIndex(in: lines, at: position)
        let targetBase = raw ?? -1
        if jumped || baseIndex == nil {
            snapToBase(targetBase, position: position)
        } else if targetBase != baseIndex {
            transitionToBase(targetBase, position: position)
        }
        if let live = liveIndex, let content = contents[live] {
            for word in content.wordViews { word.update(position: position) }
        }
        lastPosition = position
        hasPosition = true
    }

    func unmount() {
        isActive = false
        perspectiveView.layer.removeAnimation(forKey: Self.breathingKey)
        clearContents()
        snapshotCache.removeAll()
        context = nil
    }

    // MARK: 呼吸漂移

    /// 焦平面整体漂移：StageBreathingFloat 的 7s 周期口径，
    /// 幅值按 DESIGN 压到 ±3pt。StageBreathingFloat 的幅值
    /// 写死（±14/+6.3pt）且在本任务不可改的共享文件里，故
    /// 在本文件按同周期/同曲线族复刻一支 ±3pt 版（偏差已
    /// 在回报中注明）。
    private func startBreathing() {
        guard perspectiveView.layer.animation(forKey: Self.breathingKey) == nil else { return }
        let ys: [CGFloat] = [0, -3, 0, 1.4, 0]
        let scales: [CGFloat] = [1, 1.005, 1, 0.998, 1]
        var transforms: [CATransform3D] = []
        for i in ys.indices {
            var t = CATransform3DMakeTranslation(0, ys[i], 0)
            t = CATransform3DScale(t, scales[i], scales[i], 1)
            transforms.append(t)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = transforms.map { NSValue(caTransform3D: $0) }
        animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        animation.duration = 7
        animation.repeatCount = .infinity
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        animation.isRemovedOnCompletion = false
        perspectiveView.layer.add(animation, forKey: Self.breathingKey)
    }

    // MARK: 灭点渐变

    private func updateVanishingGradient() {
        guard let snapshot else { return }
        vanishingGradient.colors = [
            snapshot.palette.accent.withAlphaComponent(0.10).cgColor,
            UIColor.clear.cgColor,
        ]
    }

    // MARK: 字号与快照烘焙

    private func baseFontSize() -> CGFloat {
        let viewport = snapshot?.viewport.size ?? rootView.bounds.size
        let vmin = min(viewport.width, viewport.height)
        guard vmin > 0 else { return 36 }
        return max(36, min(6 * vmin / 100, 72))
    }

    /// 长句优先压字号：一行放进可用宽（屏宽 − 64），下限 18。
    private func fontSize(for line: LyricLine) -> CGFloat {
        let avail = max(rootView.bounds.width - 64, 0)
        var size = baseFontSize()
        guard avail > 0 else { return size }
        while size > 18 {
            let font = StageFonts.bold(size: size)
            let width = (line.text as NSString).size(withAttributes: [.font: font]).width
            if width <= avail { break }
            size -= 2
        }
        return size
    }

    private func contentSize(for line: LyricLine) -> CGSize {
        CGSize(width: max(rootView.bounds.width - 64, 0),
               height: fontSize(for: line) * 1.5)
    }

    private func snapshotKey(line: LyricLine, radius: CGFloat, colorRole: String) -> String {
        "\(builtTrackId ?? "")|\(line.id)|\(Int(radius * 10))|\(colorRole)|\(Int(rootView.bounds.width))"
    }

    /// 一次性快照：渲染行文本 → CIFilter 高斯模糊 → crop 回
    /// 原尺寸。radius 0 即干净版（交接专用）。压暗以槽位
    /// alpha 承担（DESIGN 允许二选一），不烘进图里。
    private func bakeSnapshot(line: LyricLine, radius: CGFloat,
                              color: UIColor, colorRole: String) -> UIImage? {
        let key = snapshotKey(line: line, radius: radius, colorRole: colorRole)
        if let cached = snapshotCache.image(forKey: key) { return cached }
        let size = contentSize(for: line)
        guard size.width > 0 else { return nil }
        let font = StageFonts.bold(size: fontSize(for: line))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let plain = renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color,
            ]
            let textSize = (line.text as NSString).size(withAttributes: attributes)
            let rect = CGRect(x: (size.width - textSize.width) / 2,
                              y: (size.height - textSize.height) / 2,
                              width: textSize.width, height: textSize.height)
            (line.text as NSString).draw(in: rect, withAttributes: attributes)
        }
        var result = plain
        if radius > 0, let ciImage = CIImage(image: plain) {
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(radius, forKey: kCIInputRadiusKey)
            let context = CIContext()
            let cropped = filter?.outputImage?.cropped(to: ciImage.extent)
            if let cropped, let cg = context.createCGImage(cropped, from: cropped.extent) {
                result = UIImage(cgImage: cg, scale: 2, orientation: .up)
            }
        }
        snapshotCache.store(result, forKey: key)
        return result
    }

    /// 预烘焙一行的全部档位（行进入下二行槽位时调用）：
    /// 干净版 + 下一行 3pt + 下二行 5pt + 上一行 6pt。
    /// 低电量：模糊半径减半。
    private func prebake(line: LyricLine) {
        guard let snapshot else { return }
        let palette = snapshot.palette
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let factor: CGFloat = lowPower ? 0.5 : 1
        _ = bakeSnapshot(line: line, radius: 0, color: palette.primary, colorRole: "clean")
        _ = bakeSnapshot(line: line, radius: 3 * factor, color: palette.primary, colorRole: "next")
        _ = bakeSnapshot(line: line, radius: 5 * factor, color: palette.primary, colorRole: "next2")
        _ = bakeSnapshot(line: line, radius: 6 * factor, color: palette.secondary, colorRole: "prev")
    }

    private func snapshotImage(line: LyricLine, slot: Int) -> UIImage? {
        guard let snapshot else { return nil }
        let palette = snapshot.palette
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let factor: CGFloat = lowPower ? 0.5 : 1
        switch slot {
        case 0:
            return bakeSnapshot(line: line, radius: 6 * factor, color: palette.secondary, colorRole: "prev")
        case 2:
            return bakeSnapshot(line: line, radius: 3 * factor, color: palette.primary, colorRole: "next")
        case 3:
            return bakeSnapshot(line: line, radius: 5 * factor, color: palette.primary, colorRole: "next2")
        default:
            return bakeSnapshot(line: line, radius: 0, color: palette.primary, colorRole: "clean")
        }
    }

    // MARK: 活字构建

    private func buildLive(into content: CorridorLineView, line: LyricLine,
                           position: TimeInterval) {
        guard let snapshot else { return }
        for sub in content.liveContainer.subviews { sub.removeFromSuperview() }
        content.wordViews = []
        let size = fontSize(for: line)
        let font = StageFonts.bold(size: size)
        let profile = StageLineProfile(wordLookahead: 0.15, glowRadius: 8)
        let units = StageLyricUnits.units(for: line)
        var words: [GlowWordView] = []
        var widths: [CGFloat] = []
        for unit in units {
            let word = GlowWordView(
                unit: unit, pose: StageWordPose(),
                font: font, baseColor: snapshot.palette.primary,
                activeColor: snapshot.palette.accent, profile: profile)
            words.append(word)
            widths.append(word.bounds.width)
        }
        let spacing: CGFloat = 4
        let total = widths.reduce(0, +) + spacing * CGFloat(max(words.count - 1, 0))
        var x = (content.bounds.width - total) / 2
        for (i, word) in words.enumerated() {
            word.frame.origin = CGPoint(
                x: x, y: (content.bounds.height - word.bounds.height) / 2)
            x += widths[i] + spacing
            content.liveContainer.addSubview(word)
            word.snap(position: position)
        }
        content.wordViews = words
    }

    // MARK: 槽位落位

    private func applyGeometry(to content: CorridorLineView, slot: Int,
                               size: CGFloat, reduceMotion: Bool) {
        let bounds = rootView.bounds
        content.center = CGPoint(x: bounds.width / 2, y: bounds.height * 0.44)
        let geometry = corridorSlots[slot]
        if reduceMotion {
            // 降级：rotateX 归零、无 z 位移（交叉淡化在切换处）。
            content.layer.transform = CATransform3DMakeScale(
                geometry.scale, geometry.scale, 1)
        } else {
            var transform = CATransform3DMakeTranslation(
                0, geometry.yFactor * size, geometry.z)
            transform = CATransform3DRotate(
                transform, geometry.rotateXDegrees * .pi / 180, 1, 0, 0)
            transform = CATransform3DScale(transform, geometry.scale, geometry.scale, 1)
            content.layer.transform = transform
        }
        content.alpha = geometry.alpha
    }

    private func makeContent(lineIndex: Int) -> CorridorLineView? {
        guard let snapshot, snapshot.lines.indices.contains(lineIndex) else { return nil }
        let line = snapshot.lines[lineIndex]
        let content = CorridorLineView(line: line, size: contentSize(for: line))
        perspectiveView.addSubview(content)
        return content
    }

    private func clearContents() {
        for (_, content) in contents { content.removeFromSuperview() }
        contents = [:]
        baseIndex = nil
        liveIndex = nil
        springInFlight = false
    }

    // MARK: snap 落位（seek/切歌/首建）

    private func snapToBase(_ base: Int, position: TimeInterval) {
        guard let snapshot else { return }
        for (_, content) in contents {
            content.layer.removeAllAnimations()
            content.removeFromSuperview()
        }
        contents = [:]
        liveIndex = nil
        baseIndex = base
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        for slot in 0..<4 {
            let lineIndex = base + slot - 1
            guard snapshot.lines.indices.contains(lineIndex),
                  let content = makeContent(lineIndex: lineIndex) else { continue }
            contents[lineIndex] = content
            let line = snapshot.lines[lineIndex]
            if slot == 3 { prebake(line: line) }
            if slot == 1 {
                buildLive(into: content, line: line, position: position)
                content.liveContainer.alpha = 1
                content.imageView.alpha = 0
                liveIndex = lineIndex
            } else {
                content.showSnapshot(snapshotImage(line: line, slot: slot))
            }
            applyGeometry(to: content, slot: slot,
                          size: fontSize(for: line), reduceMotion: reduceMotion)
            if slot == 1 {
                // 对焦呼吸（snap 时也走一遍落位呼吸）。
                focusBreathing(on: content)
            }
        }
    }

    /// 对焦呼吸：scale 1.015→1.0、0.3s（内层容器，不碰槽位变换）。
    private func focusBreathing(on content: CorridorLineView) {
        let inner = content.liveContainer.alpha > 0 ? content.liveContainer : content.imageView
        inner.transform = CGAffineTransform(scaleX: 1.015, y: 1.015)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            inner.transform = .identity
        }
    }

    // MARK: 推进（四槽同支弹簧 + 活字↔快照交接）

    private func transitionToBase(_ newBase: Int, position: TimeInterval) {
        guard let snapshot else { return }
        let lines = snapshot.lines
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let oldBase = baseIndex ?? newBase
        baseIndex = newBase
        springInFlight = true

        // 目标分配：lineIndex → slot。
        var target: [Int: Int] = [:]
        for slot in 0..<4 {
            let lineIndex = newBase + slot - 1
            if lines.indices.contains(lineIndex) { target[lineIndex] = slot }
        }

        // 离任当前行（oldBase）：弹簧头 150ms 内淡化为自身
        // 快照（干净版）。只查缓存、不生成（弹簧期间禁止生成
        // 快照）；缺图则保持活字随行、落位后由槽位档位图接替。
        if let old = contents[oldBase], oldBase != newBase {
            if let clean = cachedSnapshot(line: lines[oldBase], radius: 0, colorRole: "clean") {
                old.imageView.image = clean
                UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
                    old.imageView.alpha = 1
                    old.liveContainer.alpha = 0
                }
            }
            if liveIndex == oldBase { liveIndex = nil }
        }

        // 接任当前行（newBase）：以去模糊快照随行推进；缺图
        // 降级为直接建活字 + 0.3s 交叉淡化。
        var incomingNeedsLiveSwap = false
        var incomingDegraded = false
        if let incoming = contents[newBase] {
            if let clean = cachedSnapshot(line: lines[newBase], radius: 0, colorRole: "clean") {
                incoming.imageView.image = clean
                incoming.imageView.alpha = 1
                incoming.liveContainer.alpha = 0
                incomingNeedsLiveSwap = true
            } else {
                incomingDegraded = true
            }
        }

        // 新进入下二行的行：建内容 + 预烘焙（其快照供后续
        // 推进使用，不供本次弹簧——本次它以 alpha 0 淡入，
        // 烘焙在淡入前同步完成属一次性建行工作）。
        for (lineIndex, slot) in target where contents[lineIndex] == nil {
            guard let content = makeContent(lineIndex: lineIndex) else { continue }
            contents[lineIndex] = content
            let line = lines[lineIndex]
            if slot == 3 { prebake(line: line) }
            if lineIndex == newBase {
                // 切歌后直接落到中段等无预烘焙场景：降级路径。
                incomingDegraded = true
            } else {
                content.showSnapshot(snapshotImage(line: line, slot: slot))
            }
            applyGeometry(to: content, slot: slot,
                          size: fontSize(for: line), reduceMotion: reduceMotion)
            content.alpha = 0
        }

        if incomingDegraded, let incoming = contents[newBase] {
            buildLive(into: incoming, line: lines[newBase], position: position)
            liveIndex = newBase
            UIView.animate(withDuration: 0.3) {
                incoming.liveContainer.alpha = 1
                incoming.imageView.alpha = 0
            }
        }

        // 离场行（不在目标分配内）：随弹簧下沉淡出后回收。
        let leaving = contents.keys.filter { target[$0] == nil }
        for lineIndex in leaving {
            guard let content = contents[lineIndex] else { continue }
            contents[lineIndex] = nil
            UIView.animate(withDuration: reduceMotion ? 0.3 : 0.85, delay: 0,
                           options: [.curveEaseIn]) {
                content.alpha = 0
            } completion: { _ in content.removeFromSuperview() }
        }

        // 四槽同支弹簧：0.85s、damping 0.82、velocity 0.2
        // （Reduce Motion 改为 0.3s 原地交叉淡化口径）。
        let duration = reduceMotion ? 0.3 : 0.85
        UIView.animate(withDuration: duration, delay: 0,
                       usingSpringWithDamping: reduceMotion ? 1 : 0.82,
                       initialSpringVelocity: reduceMotion ? 0 : 0.2,
                       options: [.beginFromCurrentState]) {
            for (lineIndex, slot) in target {
                guard let content = self.contents[lineIndex] else { continue }
                self.applyGeometry(to: content, slot: slot,
                                   size: self.fontSize(for: lines[lineIndex]),
                                   reduceMotion: reduceMotion)
            }
        } completion: { [weak self] _ in
            guard let self else { return }
            self.springInFlight = false
            // 弹簧期间又发生了新推进时，本次落位收尾作废，
            // 交给最新一支弹簧的 completion 处理。
            guard self.baseIndex == newBase else { return }
            // 落位：各行快照切到所在槽位档位（清晰度变化发生
            // 在静止瞬间）；接任行停稳 150ms 后淡化切活字。
            for (lineIndex, slot) in target where lineIndex != newBase {
                guard let content = self.contents[lineIndex] else { continue }
                content.imageView.image = self.snapshotImage(
                    line: lines[lineIndex], slot: slot)
                content.imageView.alpha = 1
                content.liveContainer.alpha = 0
            }
            if incomingNeedsLiveSwap, let incoming = self.contents[newBase] {
                self.buildLive(into: incoming, line: lines[newBase],
                               position: self.context?.positionNow() ?? position)
                self.liveIndex = newBase
                UIView.animate(withDuration: 0.3, delay: 0.15,
                               options: [.curveEaseInOut]) {
                    incoming.liveContainer.alpha = 1
                    incoming.imageView.alpha = 0
                }
                self.focusBreathing(on: incoming)
            } else if self.liveIndex == newBase, let incoming = self.contents[newBase] {
                self.focusBreathing(on: incoming)
            }
        }
    }

    /// 只查缓存、不生成的快照读取（交接协议：弹簧期间禁止
    /// 生成快照，交接图必须来自进入下二行时的预烘焙）。
    private func cachedSnapshot(line: LyricLine, radius: CGFloat,
                                colorRole: String) -> UIImage? {
        snapshotCache.image(forKey: snapshotKey(line: line, radius: radius, colorRole: colorRole))
    }

    // MARK: 布局

    private func performLayout() {
        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        perspectiveView.frame = bounds
        // 灭点：槽位向上收束方向的视觉灭点（舞台中上部）。
        let size: CGFloat = 340
        vanishingGradient.frame = CGRect(
            x: bounds.width / 2 - size / 2,
            y: bounds.height * 0.44 - baseFontSize() * 2.4 - size / 2,
            width: size, height: size)
        // 视口变化：无动画落位（快照按新宽在下次访问时重渲，
        // 缓存 key 含宽度）。
        guard let base = baseIndex, !springInFlight else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        for (lineIndex, content) in contents {
            let slot = lineIndex - base + 1
            guard (0..<4).contains(slot), let snapshot,
                  snapshot.lines.indices.contains(lineIndex) else { continue }
            content.frame.size = contentSize(for: snapshot.lines[lineIndex])
            content.imageView.frame = content.bounds
            content.liveContainer.frame = content.bounds
            applyGeometry(to: content, slot: slot,
                          size: fontSize(for: snapshot.lines[lineIndex]),
                          reduceMotion: reduceMotion)
        }
    }
}
