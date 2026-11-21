import UIKit
import QuartzCore

// 时计 pendolo（3.7 (57) 工作流 B1 全量原生移植）：按 folia-major
// 网页版 pendolo/ 全目录的展示行为实现。数据通路与网页一致：
// 歌词行/逐词戳经协议快照下发（LyricLine.words 为 YRC 真戳、
// 无戳行由 StageLyricUnits 均分兜底，与网页 buildLineGrapheme-
// Timeline 同口径）；调色板经 PaletteTokens；时间只消费宿主
// frameTick(position)，不自建 Timer/DisplayLink（弹簧与齿轮
// 运动的 dt 取 CACurrentMediaTime 帧间差，与 GlowWordView 的
// 强调弹簧同法，不构成第二时钟源——播放位置恒以入参为准）。
//
// 视觉本体（网页构成 → 原生落点）：
//  - 表盘机芯：PendoloClockworkCanvas 的 WebGL 线框齿轮组按
//    pendoloClockworkDraw2d.ts（Canvas2D 回退路，与 WebGL 同
//    一套锚点/色板 pendoloClockworkScene.ts）逐件翻成
//    CAShapeLayer 矢量层：主擒纵齿轮（36 齿）+辐条轮+玑镂刻
//    线+铆钉、太阳轮（12 齿）、三行星轮、摆轮（20 齿）+游丝
//    螺旋、传动轮（24 齿）+日内瓦纹、秒轮（15 齿）、惰轮、
//    刻度环/分度线、宝石轴承、焦点轴箭头、中心径向渐变。
//    逐帧只改各层 transform/position（锚点公式见
//    resolvePendoloClockworkAnchors），不重建路径。
//  - 歌词弧轨：pendoloGeometry.calculatePendoloWheelLayout
//    逐项对译（窗口 ±8 行、|角| < 90° 门、块高感知角距、
//    alpha/scale 衰减公式）；整轨绕轮心旋转由棘轮弹簧驱动
//    （VisualizerPendolo 的 framer-motion useSpring：
//    stiffness 180×snappiness、damping 18+4/snappiness、
//    mass 0.8，本文件按帧半隐式积分）；行内文字反转
//    -rail×0.65 + 自身角×0.35（网页同式）。
//  - 焦点行扫光：PendoloActiveLyricSweep 的逐字素填充按行
//    复刻（StageTextKit.graphemeTimes/graphemeOffsets/
//    fillWidth 同口径），底色 primary 52%、填充色 =
//    primary 与 accent 按 0.32 混合，柔边以渐变 mask 近似。
//  - 机芯运动：pendoloClockworkMotion.stepPendoloClockwork-
//    Motion 的无节拍分支（相位 = (2.8+bass×3.5)×dt、bass 平
//    滑、秒轮每秒一步 + 刚度 92/衰减 13 的弹簧）。协议无频
//    谱数据源（hostCapabilities.requiresSpectrum=false），
//    bass 恒取网页 PendoloClockworkCanvas 的缺省 0.18；智能
//    动感模式（beatFx）依赖鼓声分离数据，原生无此通路，未落。
//  - 倾斜/视差/轮心视角：网页走 pendoloDialProjection 的
//    3×3 单应矩阵 + WebGL 透视；原生以 CATransform3D 透视
//    旋转近似（同倾斜角/轴、视距 1.2×长边；轮心视角视距
//    0.75×长边 + 俯角 atan2(H, D')），歌词层以 translateZ
//    承接 PENDOLO_LYRIC_LAYER_HEIGHT=0.1 的分层视差。轮心
//    视角下歌词逐句「立起」（preserve-3d rotateX）未落，
//    以平躺 + 近焦点句 alpha 压暗（网页 standSideLineAlpha
//    公式）+ 弧端 65°–75° 淡出近似，见文末未落清单。
// 参数全部经 PendoloTuningStore 读（逐帧走 0.25s 缓存）。

/// 弧轨一行布局（pendoloGeometry.PendoloLineItem 的原生形状）。
private struct PendoloWheelItem {
    var index: Int
    var angleRad: Double
    var angleDeg: Double
    var x: CGFloat
    var y: CGFloat
    var isActive: Bool
    var distance: Double
    var alpha: CGFloat
    var scale: CGFloat
}

/// 焦点行的一行扫光（网页 PendoloSweepLine 的单行等价）。
private final class PendoloSweepRowView: UIView {

    private let fillClip = UIView()
    private let fillLabel = UILabel()
    private let maskGradient = CAGradientLayer()
    private let timings: [(start: TimeInterval, end: TimeInterval)]
    private let offsets: [CGFloat]
    private let rowWidth: CGFloat
    private let softness: CGFloat

    init(text: String, font: UIFont, baseColor: UIColor, fillColor: UIColor,
         timings: [(start: TimeInterval, end: TimeInterval)],
         offsets: [CGFloat], lineHeight: CGFloat) {
        self.timings = timings
        self.offsets = offsets
        self.rowWidth = offsets.last ?? 0
        self.softness = min(max(font.pointSize * 0.42, 8), 16)
        super.init(frame: CGRect(x: 0, y: 0, width: rowWidth, height: lineHeight))
        isUserInteractionEnabled = false
        let baseLabel = UILabel()
        baseLabel.text = text
        baseLabel.font = font
        baseLabel.textColor = baseColor
        baseLabel.frame = CGRect(x: 0, y: 0, width: rowWidth, height: lineHeight)
        addSubview(baseLabel)
        fillClip.clipsToBounds = true
        fillClip.frame = CGRect(x: 0, y: 0, width: 0, height: lineHeight)
        fillLabel.text = text
        fillLabel.font = font
        fillLabel.textColor = fillColor
        fillLabel.frame = CGRect(x: 0, y: 0, width: rowWidth, height: lineHeight)
        fillClip.addSubview(fillLabel)
        maskGradient.startPoint = CGPoint(x: 0, y: 0.5)
        maskGradient.endPoint = CGPoint(x: 1, y: 0.5)
        maskGradient.colors = [
            UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor,
        ]
        fillClip.layer.mask = maskGradient
        addSubview(fillClip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func update(position: TimeInterval) {
        let start = timings.first?.start ?? 0
        let end = timings.last?.end ?? start
        let filled = StageTextKit.fillWidth(
            position: position, start: start, end: end,
            offsets: offsets, timings: timings)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillClip.frame.size.width = filled
        let maskWidth = filled + softness
        maskGradient.frame = CGRect(
            x: 0, y: 0, width: max(maskWidth, 0.001), height: bounds.height)
        let solid = maskWidth > 0 ? Double(filled / maskWidth) : 0
        maskGradient.locations = [
            NSNumber(value: 0), NSNumber(value: solid), NSNumber(value: 1),
        ]
        CATransaction.commit()
    }
}

/// 触摸穿透容器：自身不接手势，只把点击交给子视图（行项）。
/// 网页口径同构：根层 pointer-events-none、只有歌词轨
/// pointer-events-auto；原生若关掉中间层交互会连带禁掉子
/// 视图，故用 hitTest 穿透代替关闭。
private final class PendoloPassthroughView: UIView {
    override func hitTest(_ point: CGPoint,
                          with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// 弧轨上的一行歌词视图：锚点在弧上 (x, y)，内容绕锚点侧
/// 中心旋转/缩放（网页 PendoloRotatingLine + 内层 motion.div）。
private final class PendoloLineItemView: UIView {

    let item: PendoloWheelItem
    let contentView = UIView()
    var sweepRows: [PendoloSweepRowView] = []

    init(item: PendoloWheelItem, width: CGFloat, height: CGFloat,
         mirrored: Bool) {
        self.item = item
        super.init(frame: CGRect(
            x: mirrored ? item.x - width : item.x,
            y: item.y - height / 2, width: width, height: height))
        isUserInteractionEnabled = true
        contentView.isUserInteractionEnabled = false
        contentView.frame = bounds
        // 变换原点 = 锚点侧中点（网页 transform-origin:
        // left/right center），内容绕它旋转缩放不漂移。
        contentView.layer.anchorPoint = CGPoint(x: mirrored ? 1 : 0, y: 0.5)
        contentView.layer.position = CGPoint(
            x: mirrored ? width : 0, y: height / 2)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

final class PendoloStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = LyricStageRootView()
    /// 透视空间层（倾斜/轮心视角的作用面，锚点在轮心）。
    private let spaceView = PendoloPassthroughView()
    /// 表盘机芯层（spaceView 子层，平面 z=0）。
    private let dialView = UIView()
    /// 歌词弧轨层（绕轮心旋转；锚点在轮心以便纯旋转变换）。
    private let railView = PendoloPassthroughView()

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    /// chrome 占用（3.7 (60) 第 4 条）：宿主 layoutStage 下发；
    /// 表盘构图重心在下部，轮心按 bottom inset 的一半上移避让
    /// 点播台浮压。变更时重建结构（逐帧路径不读本值）。
    private var chromeInsets: UIEdgeInsets = .zero

    // 几何缓存（布局/调参/调色板变化时重建，逐帧不重建）。
    private var builtSize: CGSize = .zero
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var builtPalette: PaletteTokens? = nil
    private var builtTuning: PendoloTuningValues? = nil
    private var hub = CGPoint.zero
    private var baseRadius: CGFloat = 0
    private var ringRadius: CGFloat = 0
    private var availableTextWidth: CGFloat = 140

    // 机芯层组（buildDial 填充，frameTick 只改变换）。
    private var gradientLayer: CAGradientLayer?
    private var coverLayer: CAShapeLayer?
    private var ticksLayer: CAShapeLayer?
    private var mainGearLayers: [CAShapeLayer] = []
    private var sunLayer: CAShapeLayer?
    private var planetLayers: [CAShapeLayer] = []
    private var planetJewelLayers: [CAShapeLayer] = []
    private var balanceLayer: CAShapeLayer?
    private var hairspringLayer: CAShapeLayer?
    private var transLayers: [CAShapeLayer] = []
    private var secondGearLayer: CAShapeLayer?
    private var secondSpokeLayer: CAShapeLayer?
    private var idlerLayer: CAShapeLayer?
    private var allDialLayers: [CALayer] = []

    // 弧轨与行项。
    private var itemViews: [PendoloLineItemView] = []
    private var blockHeightCache: [Int: CGFloat] = [:]

    // 棘轮弹簧（framer-motion useSpring 的半隐式积分复刻）。
    private var springValue: Double = 0
    /// §0 量测（3.7 (67) B 组）：待收敛的行（flip.up 记账）。
    private var probeUpPending67: Int? = nil
    private var springVelocity: Double = 0
    private var springSnapped = false
    private var currentTarget: Double = 0
    private var builtTarget: Double? = nil

    // 焦点锚定（pendoloTimeline.resolvePendoloFallbackAnchorIndex）。
    private var lastValidIndex = 0
    private var hasObservedLine = false

    // 机芯运动（pendoloClockworkMotion 无节拍分支）。
    private var phase: Double = 0
    private var smoothedBass: Double = 0.15
    private var secondElapsed: Double = 0
    private var secondStep: Double = 0
    private var secondAngle: Double = 0
    private var secondVelocity: Double = 0
    private var lastTickWall: CFTimeInterval = -1
    private var lastPosition: TimeInterval = 0

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        dialView.isUserInteractionEnabled = false
        rootView.addSubview(spaceView)
        spaceView.addSubview(dialView)
        spaceView.addSubview(railView)
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    /// chrome 内缩（3.7 (60) 第 4 条）：bottom inset 变化即重建
    /// 结构让轮心上移 bottom/2；无快照时只存值，首帧重建自取。
    func applyChromeInsets(_ insets: UIEdgeInsets) {
        guard insets != chromeInsets else { return }
        chromeInsets = insets
        guard snapshot != nil else { return }
        rebuildStructure(tuning: PendoloTuningStore.valuesCached(
            now: CACurrentMediaTime()))
        builtTarget = nil
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        // (61) WC：入口统一过对比钳制——下游 palette.* 全走保护副本。
        var snapshot = snapshot
        snapshot.palette = snapshot.palette.contrastProtected()
        let trackChanged = snapshot.track?.id != builtTrackId
            || snapshot.lines.count != builtLineCount
        self.snapshot = snapshot
        if trackChanged {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
            blockHeightCache.removeAll()
            lastValidIndex = 0
            hasObservedLine = false
            springSnapped = false
            builtTarget = nil
            phase = 0
            secondElapsed = 0
            secondStep = 0
            secondAngle = 0
            secondVelocity = 0
        }
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive { lastTickWall = -1 }
    }

    func frameTick(position: TimeInterval) {
        position62 = position
        guard isActive, let snapshot else { return }
        lastPosition = position
        let now = CACurrentMediaTime()
        let dt = lastTickWall < 0
            ? 1.0 / 60 : min(max(now - lastTickWall, 0), 0.05)
        lastTickWall = now
        let tuning = PendoloTuningStore.valuesCached(now: now)

        // 结构重建（尺寸/调色板/调参变化时才走，逐帧零重建）。
        if builtSize != rootView.bounds.size
            || builtPalette != snapshot.palette
            || builtTuning != tuning {
            rebuildStructure(tuning: tuning)
        }

        // 焦点目标（网页 targetLineIndex：有效行直取；无有效
        // 行走 fallback 锚：未观察过 → -1（纯机芯画面）、末行
        // 唱完 → lines.count、其余 lastValid+0.5）。
        let rawIndex = LyricParser.currentIndex(in: snapshot.lines, at: position)
        if let rawIndex {
            lastValidIndex = rawIndex
            hasObservedLine = true
        }
        let target = fallbackAnchor(position: position, rawIndex: rawIndex)
        if target != currentTarget || builtTarget == nil {
            // §0 呈现侧（3.7 (67) B 组）：焦点目标提交点；收敛
            // 看表盘弹簧 springValue 首次进入目标 ε 内。
            if target != currentTarget, let rawIndex {
                Breadcrumbs.log("flip.cmt style=pendolo idx=\(rawIndex) judge=\(SyncProbe67.fmt(position)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
                probeUpPending67 = rawIndex
            }
            currentTarget = target
            rebuildItems(tuning: tuning)
        }
        if !springSnapped {
            springValue = target
            springVelocity = 0
            springSnapped = true
        }

        stepSpring(dt: dt, tuning: tuning)
        // §0 呈现侧（3.7 (67) B 组）：表盘弹簧收敛点，每行一次。
        if let pending = probeUpPending67,
           abs(springValue - currentTarget) < 0.01 {
            probeUpPending67 = nil
            Breadcrumbs.log("flip.up style=pendolo idx=\(pending) judge=\(SyncProbe67.fmt(position)) wall=\(SyncProbe67.fmt(CACurrentMediaTime()))")
        }
        stepClockwork(dt: dt, paused: context.map { $0.currentAnchor().rate == 0 } ?? false)
        applyFrameTransforms(position: position, tuning: tuning)
    }

    func unmount() {
        isActive = false
        context = nil
        snapshot = nil
        for item in itemViews { item.removeFromSuperview() }
        itemViews = []
        for layer in allDialLayers { layer.removeFromSuperlayer() }
        allDialLayers = []
        mainGearLayers = []
        planetLayers = []
        planetJewelLayers = []
        transLayers = []
        gradientLayer = nil
        coverLayer = nil
        ticksLayer = nil
        sunLayer = nil
        balanceLayer = nil
        hairspringLayer = nil
        secondGearLayer = nil
        secondSpokeLayer = nil
        idlerLayer = nil
        blockHeightCache.removeAll()
        lastTickWall = -1
    }

    // MARK: 焦点锚（pendoloTimeline 对译）

    private func fallbackAnchor(position: TimeInterval,
                                rawIndex: Int?) -> Double {
        guard let snapshot, !snapshot.lines.isEmpty else { return 0 }
        if let rawIndex { return Double(rawIndex) }
        if !hasObservedLine { return -1 }
        if let last = snapshot.lines.last, position > last.end {
            return Double(snapshot.lines.count)
        }
        return Double(lastValidIndex) + 0.5
    }

    // MARK: 棘轮弹簧（framer-motion useSpring 对译）

    /// stiffness = 180 × snappiness × escapementSpringMultiplier
    /// （normal 档 = 1）；damping = (18 + 4/max(0.5, snappiness))
    /// × escapementDampingMultiplier（normal 档 = 1）；mass 0.8。
    /// 半隐式欧拉积分，dt 上限 0.05（网页 RAF 口径一致）。
    private func stepSpring(dt: Double, tuning: PendoloTuningValues) {
        let snappiness = tuning.tickSnappiness
        let stiffness = 180 * snappiness
        let damping = 18 + 4 / max(0.5, snappiness)
        let accel = (-stiffness * (springValue - currentTarget)
            - damping * springVelocity) / 0.8
        springVelocity += accel * dt
        springValue += springVelocity * dt
    }

    /// 擒纵角（rad）= springValue × angleStep（网页
    /// gearRotationAngleRad = tickSpring × angleStepRad）。
    private var escapementAngle: Double {
        guard let tuning = builtTuning else { return 0 }
        let totalArc = tuning.arcAngleDeg * .pi / 180
        return springValue * (totalArc / 8)
    }

    /// 轨道旋转（deg）：wheel = -(spring - target) × stepDeg，
    /// rail = wheel × sideSign（镜像时轨道反转，网页同式）。
    private func railRotationDeg(tuning: PendoloTuningValues) -> Double {
        let stepDeg = tuning.arcAngleDeg / 8
        let wheel = -(springValue - currentTarget) * stepDeg
        return wheel * (tuning.mirrorLayout ? -1 : 1)
    }

    // MARK: 机芯运动（pendoloClockworkMotion 无节拍分支对译）

    private var position62: TimeInterval = 0

    private func stepClockwork(dt: Double, paused: Bool) {
        // bass 无频谱数据源：(62) 以伪能量低频近似替代恒值——
        // StageEnergy62.bass（确定性慢包络）围绕网页缺省 0.18
        // 摆动（±0.10），平滑公式 min(0.24, 0.12×bassResponse)
        // 中 normal 档 = 0.12 不变。beatFx 的鼓点分离仍无数据
        // 源，未落（见报告）。
        let bassTarget = 0.18 + (StageEnergy62.bass(at: position62) - 0.5) * 0.2
        smoothedBass += (bassTarget - smoothedBass) * 0.12
        guard !paused else { return }
        phase += dt * (2.8 + smoothedBass * 3.5)
        secondElapsed += dt
        let completed = floor(secondElapsed)
        if completed > 0 {
            secondStep += completed
            secondElapsed -= completed
        }
        let target = secondStep * (2 * Double.pi / 15)
        secondVelocity += (target - secondAngle) * 92 * dt
        secondVelocity *= exp(-13 * dt)
        secondAngle += secondVelocity * dt
    }

    private var bassOscillation: Double {
        sin(phase) * (0.15 + smoothedBass * 0.70)
    }

    // MARK: 结构重建（几何 + 表盘 + 空间变换）

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        guard rootView.bounds.width > 0 else { return }
        if builtSize != rootView.bounds.size, snapshot != nil {
            rebuildStructure(tuning: PendoloTuningStore.valuesCached(
                now: CACurrentMediaTime()))
            builtTarget = nil
        }
    }

    private func rebuildStructure(tuning: PendoloTuningValues) {
        guard let snapshot else { return }
        let size = rootView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        builtSize = size
        builtPalette = snapshot.palette
        builtTuning = tuning
        spaceView.frame = CGRect(origin: .zero, size: size)
        dialView.frame = CGRect(origin: .zero, size: size)
        railView.frame = CGRect(origin: .zero, size: size)

        let mirrored = tuning.mirrorLayout
        let centerX = mirrored
            ? size.width * CGFloat(1 - tuning.wheelCenterX)
            : size.width * CGFloat(tuning.wheelCenterX)
        // (60) 第 4 条：轮心上移 bottom chrome inset 的一半，
        // 让表盘焦点避开点播台浮压区（全幅容器下 chrome 不再
        // 靠宿主带状容器天然避让，改由本内缩口径承担）。
        hub = CGPoint(x: centerX,
                      y: size.height * CGFloat(tuning.wheelCenterY)
                        - chromeInsets.bottom / 2)
        let shortSide = min(size.width, size.height)
        baseRadius = shortSide * CGFloat(tuning.arcRadius)
        ringRadius = baseRadius + shortSide * 0.06
        let maxItemX = hub.x + baseRadius
        availableTextWidth = max(140, min(
            size.width * 0.46,
            mirrored ? hub.x - baseRadius - 48
                : size.width - maxItemX - 48))

        // 空间层锚点落轮心（倾斜/旋转绕轮心，网页 transform-
        // origin 同为轮心）；轨道层锚点同理，纯旋转变换即可。
        spaceView.layer.anchorPoint = CGPoint(
            x: size.width > 0 ? hub.x / size.width : 0.5,
            y: size.height > 0 ? hub.y / size.height : 0.5)
        spaceView.layer.position = hub
        railView.layer.anchorPoint = spaceView.layer.anchorPoint
        railView.layer.position = hub
        spaceView.layer.transform = spaceTransform(tuning: tuning, size: size)

        buildDial(tuning: tuning, palette: snapshot.palette)
        builtTarget = nil
    }

    /// 倾斜/轮心视角的透视变换（pendoloDialProjection 的
    /// CATransform3D 近似）：平放（倾斜 0 且非轮心视角）恒等。
    private func spaceTransform(tuning: PendoloTuningValues,
                                  size: CGSize) -> CATransform3D {
        let maxDim = max(size.width, size.height)
        guard maxDim > 0 else { return CATransform3DIdentity }
        if tuning.hubView {
            // 相机高 H = R×hubViewHeight（下限须高于摆轮层，
            // 网页同式 max(hubViewHeight, 0.2×parallax+0.15)）、
            // 后退 B = R×hubViewBack、D' = ringR + B；俯角 =
            // atan2(H, D')，视距 0.75×长边；焦点句落点向
            // (0.5w, 0.42h) 拉近 60%（网页为精确投影，原生
            // 近似，见未落清单）。
            let heightRatio = max(tuning.hubViewHeight,
                                  0.2 * tuning.parallaxDepth + 0.15)
            let h = Double(baseRadius) * heightRatio
            let back = Double(baseRadius) * tuning.hubViewBack
            let dPrime = Double(ringRadius) + back
            let pitch = atan2(h, dPrime)
            var t = CATransform3DIdentity
            t.m34 = -1 / (0.75 * maxDim)
            let side: CGFloat = tuning.mirrorLayout ? -1 : 1
            let focal = CGPoint(x: hub.x + side * ringRadius, y: hub.y)
            let target = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            t = CATransform3DTranslate(
                t, (target.x - focal.x) * 0.6, (target.y - focal.y) * 0.6, 0)
            t = CATransform3DRotate(t, CGFloat(pitch), 1, 0, 0)
            return t
        }
        guard tuning.tiltDeg != 0 else { return CATransform3DIdentity }
        var t = CATransform3DIdentity
        t.m34 = -1 / (1.2 * maxDim)
        let axisRad = CGFloat(tuning.tiltAxisDeg * .pi / 180)
        t = CATransform3DRotate(
            t, CGFloat(tuning.tiltDeg * .pi / 180),
            cos(axisRad), sin(axisRad), 0)
        return t
    }

    // MARK: 表盘构建（pendoloClockworkDraw2d + Scene 对译）

    /// 色板（buildPendoloClockworkPalette 对译）：m = full
    /// 时 1.0、subtle 时 0.6；none 时齿轮层全不建（渐变与
    /// 封面层仍在，网页画布同逻辑）。
    private func buildDial(tuning: PendoloTuningValues,
                           palette: PaletteTokens) {
        for layer in allDialLayers { layer.removeFromSuperlayer() }
        allDialLayers = []
        mainGearLayers = []
        planetLayers = []
        planetJewelLayers = []
        transLayers = []
        gradientLayer = nil
        coverLayer = nil
        ticksLayer = nil
        sunLayer = nil
        balanceLayer = nil
        hairspringLayer = nil
        secondGearLayer = nil
        secondSpokeLayer = nil
        idlerLayer = nil

        let primary = palette.primary
        let accent = palette.accent
        let isFull = tuning.showGearDecor == .full
        let m: CGFloat = isFull ? 1.0 : 0.6
        let glow = tuning.enableLineGlow
        dialView.layer.shadowColor = glow ? accent.cgColor : nil
        dialView.layer.shadowOpacity = glow ? 0.55 : 0
        dialView.layer.shadowRadius = glow ? 8 : 0
        dialView.layer.shadowOffset = .zero

        let anchors = clockworkAnchors()
        // 中心径向渐变（网页 stops 0/0.35/0.7/1 → alpha
        // 0.72/0.52/0.20/0，底色 = palette.background）。
        if tuning.showCenterGradient {
            let gradient = CAGradientLayer()
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            let bg = palette.background
            gradient.colors = [
                bg.withAlphaComponent(0.72).cgColor,
                bg.withAlphaComponent(0.52).cgColor,
                bg.withAlphaComponent(0.20).cgColor,
                bg.withAlphaComponent(0).cgColor,
            ]
            gradient.locations = [0, 0.35, 0.7, 1]
            let r = anchors.gradientR
            gradient.frame = CGRect(
                x: hub.x - r, y: hub.y - r, width: r * 2, height: r * 2)
            dialView.layer.addSublayer(gradient)
            gradientLayer = gradient
            allDialLayers.append(gradient)
        }
        // 表盘封面：协议不下发封面位图（只有 TrackMeta
        // .artworkURL 字符串、无渲染器侧位图通路），以调色
        // 板底色盘 + accent 描边占位，alpha 与网页同式
        // 0.42×(full 1.0 / subtle 0.6)。见未落清单。
        if tuning.showCoverOnWatchFace {
            let cover = CAShapeLayer()
            cover.path = Self.circlePath(radius: anchors.coverR).cgPath
            cover.fillColor = palette.background.cgColor
            cover.strokeColor = accent.withAlphaComponent(0.35 * m).cgColor
            cover.lineWidth = 1
            cover.opacity = Float(0.42 * (isFull ? 1.0 : 0.6))
            place(cover, at: hub, radius: anchors.coverR)
            coverLayer = cover
        }
        guard tuning.showGearDecor != .none else { return }

        func strokeLayer(_ path: UIBezierPath, color: UIColor,
                         width: CGFloat, fill: UIColor? = nil,
                         at center: CGPoint, radius: CGFloat) -> CAShapeLayer {
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.strokeColor = color.cgColor
            layer.lineWidth = width
            layer.fillColor = fill?.cgColor
            layer.lineJoin = .round
            // place 的内联版（嵌套函数不隐式调实例方法）。
            layer.bounds = CGRect(x: -radius, y: -radius,
                                  width: radius * 2, height: radius * 2)
            layer.position = center
            dialView.layer.addSublayer(layer)
            allDialLayers.append(layer)
            return layer
        }

        let r = baseRadius
        // 静态圈：导引环（0.3/0.6/0.85/1.15/1.4 R）+ 斜面双环。
        var ringsPath = UIBezierPath()
        for factor: CGFloat in [0.3, 0.6, 0.85, 1.15, 1.4] {
            ringsPath.append(Self.circlePath(radius: r * factor))
        }
        _ = strokeLayer(ringsPath,
                        color: primary.withAlphaComponent(0.15 * m), width: 1,
                        at: hub, radius: r * 1.4)
        var bevelPath = UIBezierPath()
        bevelPath.append(Self.circlePath(radius: r * 0.88))
        bevelPath.append(Self.circlePath(radius: r * 0.92))
        _ = strokeLayer(bevelPath,
                        color: primary.withAlphaComponent(0.18 * m), width: 0.8,
                        at: hub, radius: r * 0.92)
        // 分度线（60 刻度、每 5 大刻度；随 escapement×0.2 转）。
        ticksLayer = strokeLayer(
            Self.ticksPath(radius: r * 1.15),
            color: primary.withAlphaComponent(0.15 * m), width: 1,
            at: hub, radius: r * 1.15 + 12)
        // 主擒纵齿轮组（同转 escapement）：齿形（填 accent
        // 8%）/辐条轮/玑镂/铆钉分层不同色宽。
        let gearFill = accent.withAlphaComponent(0.08 * m)
        mainGearLayers.append(strokeLayer(
            Self.gearPath(radius: r + 8, teeth: 36, depth: 10),
            color: accent.withAlphaComponent(0.58 * m), width: 2.2,
            fill: gearFill, at: hub, radius: r + 8))
        mainGearLayers.append(strokeLayer(
            Self.spokedPath(hubR: r * 0.2, rimR: r * 0.85, spokes: 6),
            color: primary.withAlphaComponent(0.42 * m), width: 1.8,
            at: hub, radius: r * 0.85))
        mainGearLayers.append(strokeLayer(
            Self.guillochePath(inner: r * 0.62, outer: r * 0.83),
            color: primary.withAlphaComponent(0.10 * m), width: 0.7,
            at: hub, radius: r * 0.83))
        mainGearLayers.append(strokeLayer(
            Self.rivetsPath(radius: r * 0.96, rivetR: 2.2, count: 12),
            color: primary.withAlphaComponent(0.25 * m), width: 0.8,
            at: hub, radius: r * 0.96 + 2.2))
        // 太阳轮（反转 ×-2.5）。
        sunLayer = strokeLayer(
            Self.gearPath(radius: r * 0.22, teeth: 12, depth: 6),
            color: accent.withAlphaComponent(0.72 * m), width: 2.1,
            at: hub, radius: r * 0.22)
        // 中心宝石。
        _ = strokeLayer(Self.jewelPath(outer: 4.5, inner: 2.5),
                        color: accent.withAlphaComponent(0.65 * m), width: 1.2,
                        at: hub, radius: 4.5)
        // 三行星轮（轨道 escapement×0.4、自转 ×-3+idx×0.5）。
        for idx in 0..<3 {
            planetLayers.append(strokeLayer(
                Self.gearPath(radius: anchors.planetR, teeth: 14, depth: 5),
                color: primary.withAlphaComponent(0.24 * m), width: 1.7,
                at: hub, radius: anchors.planetR))
            planetJewelLayers.append(strokeLayer(
                Self.jewelPath(outer: 3.5, inner: 1.8),
                color: accent.withAlphaComponent(0.65 * m), width: 1,
                at: hub, radius: 3.5))
            _ = idx
        }
        // 摆轮组：齿轮（phase×0.1）+ 内圈静环 + 游丝 + 宝石。
        balanceLayer = strokeLayer(
            Self.gearPath(radius: anchors.balanceR, teeth: 20, depth: 7),
            color: accent.withAlphaComponent(0.72 * m), width: 2.1,
            fill: accent.withAlphaComponent(0.10 * m),
            at: anchors.balance, radius: anchors.balanceR)
        _ = strokeLayer(Self.circlePath(radius: anchors.balanceR * 0.52),
                        color: primary.withAlphaComponent(0.32 * m), width: 1.8,
                        at: anchors.balance, radius: anchors.balanceR * 0.52)
        hairspringLayer = strokeLayer(
            Self.hairspringPath(start: anchors.balanceR * 0.56,
                                end: anchors.balanceR * 0.88, coils: 3.5),
            color: accent.withAlphaComponent(0.30 * m), width: 0.8,
            at: anchors.balance, radius: anchors.balanceR * 0.88)
        _ = strokeLayer(Self.jewelPath(outer: 3.5, inner: 1.8),
                        color: accent.withAlphaComponent(0.65 * m), width: 1,
                        at: anchors.balance, radius: 3.5)
        // 主题图标（网页摆轮上方的 lucide 图标）：协议无图标
        // 字段，以 accent 星点圆点近似占位（decor≠none 才画）。
        let iconDot = CAShapeLayer()
        iconDot.path = Self.circlePath(radius: max(3, r * 0.03)).cgPath
        iconDot.fillColor = accent.withAlphaComponent(0.62).cgColor
        iconDot.strokeColor = nil
        place(iconDot, at: anchors.balance, radius: max(3, r * 0.03))
        // 传动轮组（转 -escapement×1.4）：齿+辐条+日内瓦纹。
        transLayers.append(strokeLayer(
            Self.gearPath(radius: anchors.transR, teeth: 24, depth: 7),
            color: primary.withAlphaComponent(0.42 * m), width: 1.8,
            at: anchors.trans, radius: anchors.transR))
        var transInner = Self.spokedPath(
            hubR: anchors.transR * 0.25, rimR: anchors.transR * 0.85, spokes: 5)
        transInner.append(Self.genevaPath(radius: anchors.transR))
        transLayers.append(strokeLayer(
            transInner,
            color: primary.withAlphaComponent(0.32 * m), width: 1.5,
            at: anchors.trans, radius: anchors.transR * 0.85))
        _ = strokeLayer(Self.jewelPath(outer: 3.5, inner: 1.8),
                        color: accent.withAlphaComponent(0.65 * m), width: 1,
                        at: anchors.trans, radius: 3.5)
        // 秒轮组：齿轮随 secondAngle、辐条反向同角。
        secondGearLayer = strokeLayer(
            Self.gearPath(radius: anchors.secondR, teeth: 15, depth: 5),
            color: accent.withAlphaComponent(0.58 * m), width: 1.8,
            fill: accent.withAlphaComponent(0.06 * m),
            at: anchors.second, radius: anchors.secondR)
        secondSpokeLayer = strokeLayer(
            Self.spokedPath(hubR: anchors.secondR * 0.28,
                            rimR: anchors.secondR * 0.76, spokes: 4),
            color: primary.withAlphaComponent(0.32 * m), width: 1.3,
            at: anchors.second, radius: anchors.secondR * 0.76)
        _ = strokeLayer(Self.jewelPath(outer: 2.8, inner: 1.5),
                        color: accent.withAlphaComponent(0.65 * m), width: 0.8,
                        at: anchors.second, radius: 2.8)
        // 惰轮（转 escapement×2.2）+ 内环 + 宝石。
        idlerLayer = strokeLayer(
            Self.gearPath(radius: anchors.idlerR, teeth: 10, depth: 3.5),
            color: primary.withAlphaComponent(0.28 * m), width: 1.3,
            at: anchors.idler, radius: anchors.idlerR)
        _ = strokeLayer(Self.circlePath(radius: anchors.idlerR * 0.45),
                        color: primary.withAlphaComponent(0.18 * m), width: 0.8,
                        at: anchors.idler, radius: anchors.idlerR * 0.45)
        _ = strokeLayer(Self.jewelPath(outer: 2.2, inner: 1.2),
                        color: accent.withAlphaComponent(0.65 * m), width: 0.7,
                        at: anchors.idler, radius: 2.2)
        // 焦点轴（镜像时朝左，网页经投影镜像同义）+ 箭头。
        let side: CGFloat = tuning.mirrorLayout ? -1 : 1
        let axisPath = UIBezierPath()
        let axisStart = hub.x + side * r * 0.8
        let axisEnd = hub.x + side * anchors.focalEnd
        axisPath.move(to: CGPoint(x: axisStart, y: hub.y))
        axisPath.addLine(to: CGPoint(x: axisEnd, y: hub.y))
        axisPath.move(to: CGPoint(x: axisEnd, y: hub.y - 4))
        axisPath.addLine(to: CGPoint(x: axisEnd + side * 8, y: hub.y))
        axisPath.addLine(to: CGPoint(x: axisEnd, y: hub.y + 4))
        axisPath.close()
        let axisLayer = CAShapeLayer()
        axisLayer.path = axisPath.cgPath
        axisLayer.strokeColor = accent.withAlphaComponent(0.72 * m).cgColor
        axisLayer.lineWidth = 2
        axisLayer.fillColor = accent.withAlphaComponent(0.72 * m).cgColor
        axisLayer.frame = dialView.bounds
        dialView.layer.addSublayer(axisLayer)
        allDialLayers.append(axisLayer)
    }

    /// 把以原点为中心画路径的层放到 center 处：bounds 取负
    /// 原点使路径原点正对 position，旋转绕路径原点生效。
    private func place(_ layer: CAShapeLayer, at center: CGPoint,
                       radius: CGFloat) {
        layer.bounds = CGRect(x: -radius, y: -radius,
                              width: radius * 2, height: radius * 2)
        layer.position = center
        dialView.layer.addSublayer(layer)
        allDialLayers.append(layer)
    }

    /// 机芯锚点（resolvePendoloClockworkAnchors 对译；镜像
    /// 时整体经 spaceView 的投影语义翻转——原生以 sideSign
    /// 只翻焦点轴，齿轮组相对轮心位置与网页镜像前一致，
    /// 镜像差异见未落清单）。
    private struct ClockworkAnchors {
        var balance: CGPoint
        var balanceR: CGFloat
        var trans: CGPoint
        var transR: CGFloat
        var second: CGPoint
        var secondR: CGFloat
        var idler: CGPoint
        var idlerR: CGFloat
        var orbitR: CGFloat
        var planetR: CGFloat
        var coverR: CGFloat
        var gradientR: CGFloat
        var focalEnd: CGFloat
    }

    private func clockworkAnchors() -> ClockworkAnchors {
        let r = baseRadius
        let balance = CGPoint(x: hub.x + r * 0.2, y: hub.y - r * 0.75)
        let trans = CGPoint(x: hub.x + r * 0.32, y: hub.y + r * 0.78)
        let second = CGPoint(x: hub.x + r * 0.68, y: hub.y + r * 0.76)
        let idler = CGPoint(
            x: (trans.x + second.x) / 2 + r * 0.04,
            y: (trans.y + second.y) / 2 - r * 0.02)
        return ClockworkAnchors(
            balance: balance, balanceR: r * 0.28,
            trans: trans, transR: r * 0.34,
            second: second, secondR: r * 0.16,
            idler: idler, idlerR: r * 0.08,
            orbitR: r * 0.52, planetR: r * 0.16,
            coverR: r * 0.88, gradientR: r * 1.65,
            focalEnd: ringRadius - max(14, r * 0.025))
    }

    // MARK: 路径工厂（pendoloClockworkDraw2d 逐件对译，原点中心）

    private static func circlePath(radius: CGFloat) -> UIBezierPath {
        UIBezierPath(arcCenter: .zero, radius: radius,
                     startAngle: 0, endAngle: .pi * 2, clockwise: true)
    }

    private static func gearPath(radius: CGFloat, teeth: Int,
                                 depth: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let inner = radius - depth
        let per = 2 * Double.pi / Double(teeth)
        for i in 0..<teeth {
            let base = Double(i) * per
            let angles = [base - per * 0.22, base - per * 0.12,
                          base + per * 0.12, base + per * 0.22]
            let radii = [inner, radius, radius, inner]
            for k in 0..<4 {
                let point = CGPoint(
                    x: radii[k] * CGFloat(cos(angles[k])),
                    y: radii[k] * CGFloat(sin(angles[k])))
                if i == 0 && k == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
        }
        path.close()
        return path
    }

    private static func spokedPath(hubR: CGFloat, rimR: CGFloat,
                                   spokes: Int) -> UIBezierPath {
        let path = UIBezierPath()
        path.append(circlePath(radius: hubR))
        path.append(circlePath(radius: rimR))
        let step = 2 * Double.pi / Double(spokes)
        for i in 0..<spokes {
            let a = Double(i) * step
            path.move(to: CGPoint(x: hubR * CGFloat(cos(a)),
                                  y: hubR * CGFloat(sin(a))))
            path.addLine(to: CGPoint(x: rimR * CGFloat(cos(a)),
                                     y: rimR * CGFloat(sin(a))))
        }
        let midR = (hubR + rimR) / 2
        let holeR = (rimR - hubR) * 0.22
        for i in 0..<spokes {
            let a = Double(i) * step + step / 2
            path.append(UIBezierPath(
                arcCenter: CGPoint(x: midR * CGFloat(cos(a)),
                                   y: midR * CGFloat(sin(a))),
                radius: holeR, startAngle: 0,
                endAngle: .pi * 2, clockwise: true))
        }
        return path
    }

    private static func ticksPath(radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0..<60 {
            let a = Double(i) * 2 * Double.pi / 60
            let len: CGFloat = i % 5 == 0 ? 12 : 6
            path.move(to: CGPoint(x: radius * CGFloat(cos(a)),
                                  y: radius * CGFloat(sin(a))))
            path.addLine(to: CGPoint(x: (radius + len) * CGFloat(cos(a)),
                                     y: (radius + len) * CGFloat(sin(a))))
        }
        return path
    }

    private static func guillochePath(inner: CGFloat,
                                      outer: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0..<48 {
            let a = Double(i) * 2 * Double.pi / 48
            let start = i % 2 == 0 ? inner : inner + (outer - inner) * 0.3
            path.move(to: CGPoint(x: start * CGFloat(cos(a)),
                                  y: start * CGFloat(sin(a))))
            path.addLine(to: CGPoint(x: outer * CGFloat(cos(a)),
                                     y: outer * CGFloat(sin(a))))
        }
        return path
    }

    private static func rivetsPath(radius: CGFloat, rivetR: CGFloat,
                                   count: Int) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0..<count {
            let a = Double(i) * 2 * Double.pi / Double(count)
            path.append(UIBezierPath(
                arcCenter: CGPoint(x: radius * CGFloat(cos(a)),
                                   y: radius * CGFloat(sin(a))),
                radius: rivetR, startAngle: 0,
                endAngle: .pi * 2, clockwise: true))
        }
        return path
    }

    private static func jewelPath(outer: CGFloat,
                                  inner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.append(circlePath(radius: outer))
        path.append(circlePath(radius: inner))
        return path
    }

    private static func hairspringPath(start: CGFloat, end: CGFloat,
                                       coils: Double) -> UIBezierPath {
        let path = UIBezierPath()
        let steps = Int(coils * 60)
        let total = coils * 2 * Double.pi
        for i in 0...steps {
            let t = Double(i) / Double(max(steps, 1))
            let angle = t * total
            let radius = start + (end - start) * CGFloat(pow(t, 0.9))
            let point = CGPoint(x: radius * CGFloat(cos(angle)),
                                y: radius * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private static func genevaPath(radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let span = radius * 1.6
        let step = span / 10
        let clipR = radius * 0.80
        for i in 1...9 {
            let yOff = -span / 2 + CGFloat(i) * step
            let half = sqrt(max(0, clipR * clipR - yOff * yOff))
            guard half >= 0.5 else { continue }
            path.move(to: CGPoint(x: -half, y: yOff))
            path.addLine(to: CGPoint(x: half, y: yOff))
        }
        return path
    }

    // MARK: 弧轨布局（pendoloGeometry 对译）

    /// 焦点行块高（网页 lineBlockHeights 的主行部分）：以
    /// 焦点字号 28、行高 34 在 measureWidth = avail/activeScale
    /// 下折行，块高 = 折行高 × activeScale。副字幕行在原生
    /// 无数据源（LyricLine 无译文字段），不计入。
    private func blockHeight(for line: LyricLine,
                             tuning: PendoloTuningValues) -> CGFloat {
        if let cached = blockHeightCache[line.id] { return cached }
        let font = StageFonts.serifRegular(size: 28)
        let measureWidth = availableTextWidth / CGFloat(tuning.activeScale)
        let wrapped = StageTextKit.wrap(
            text: line.text, font: font, maxWidth: measureWidth,
            maxLines: 6, fontPx: 28)
        let height = CGFloat(max(wrapped.rows.count, 1)) * 34
            * CGFloat(tuning.activeScale)
        blockHeightCache[line.id] = height
        return height
    }

    private func wheelLayout(anchor: Double,
                             tuning: PendoloTuningValues) -> [PendoloWheelItem] {
        guard let snapshot else { return [] }
        let lines = snapshot.lines
        guard !lines.isEmpty else { return [] }
        let totalArc = tuning.arcAngleDeg * .pi / 180
        let angleStep = totalArc / 8
        let side: CGFloat = tuning.mirrorLayout ? -1 : 1
        let centerRef = max(0, min(lines.count - 1,
                                   Int(floor(anchor >= 0 ? anchor : 0))))
        let windowStart = max(0, centerRef - 8)
        let windowEnd = min(lines.count - 1, centerRef + 8)
        var visualAngles: [Int: Double] = [:]
        let isInteger = anchor == floor(anchor)
        if isInteger, Int(anchor) >= windowStart, Int(anchor) <= windowEnd {
            let active = Int(anchor)
            visualAngles[active] = 0
            var idx = active + 1
            while idx <= windowEnd {
                let prevH = blockHeight(for: lines[idx - 1], tuning: tuning)
                let curH = blockHeight(for: lines[idx], tuning: tuning)
                let spacing = max(angleStep,
                                  Double((prevH + curH + 24) / (2 * ringRadius)))
                visualAngles[idx] = (visualAngles[idx - 1] ?? 0) + spacing
                idx += 1
            }
            idx = active - 1
            while idx >= windowStart {
                let nextH = blockHeight(for: lines[idx + 1], tuning: tuning)
                let curH = blockHeight(for: lines[idx], tuning: tuning)
                let spacing = max(angleStep,
                                  Double((nextH + curH + 24) / (2 * ringRadius)))
                visualAngles[idx] = (visualAngles[idx + 1] ?? 0) - spacing
                idx -= 1
            }
        }
        var items: [PendoloWheelItem] = []
        for i in windowStart...windowEnd {
            let distance = Double(i) - anchor
            let angle = (visualAngles[i] ?? distance * angleStep)
            guard abs(angle) < Double.pi / 2 else { continue }
            let isActive = isInteger && Int(anchor) == i
                && anchor >= 0 && Int(anchor) < lines.count
            let absDistance = abs(distance)
            let alpha = max(0.12, pow(cos(angle * 0.75), 2.5)
                * (1 - absDistance * 0.18))
            let scale = isActive ? tuning.activeScale
                : max(0.7, 1 - absDistance * 0.08)
            items.append(PendoloWheelItem(
                index: i, angleRad: angle,
                angleDeg: angle * 180 / .pi,
                x: hub.x + side * ringRadius * CGFloat(cos(angle)),
                y: hub.y + ringRadius * CGFloat(sin(angle)),
                isActive: isActive, distance: absDistance,
                alpha: CGFloat(alpha), scale: CGFloat(scale)))
        }
        return items
    }

    private func rebuildItems(tuning: PendoloTuningValues) {
        guard let snapshot else { return }
        builtTarget = currentTarget
        for item in itemViews {
            item.gestureRecognizers?.forEach { item.removeGestureRecognizer($0) }
            item.removeFromSuperview()
        }
        itemViews = []
        let layout = wheelLayout(anchor: currentTarget, tuning: tuning)
        let mirrored = tuning.mirrorLayout
        for entry in layout {
            let line = snapshot.lines[entry.index]
            let isFocal = entry.isActive
            let fontPx: CGFloat = isFocal ? 28 : 22
            let font = StageFonts.serifRegular(size: fontPx)
            let maxTextWidth = availableTextWidth / entry.scale
            let itemView: PendoloLineItemView
            if isFocal {
                itemView = buildFocalItem(
                    entry: entry, line: line, font: font,
                    maxTextWidth: maxTextWidth, mirrored: mirrored,
                    palette: snapshot.palette)
            } else {
                let wrapped = StageTextKit.wrap(
                    text: line.text, font: font, maxWidth: maxTextWidth,
                    maxLines: 6, fontPx: fontPx)
                let height = CGFloat(max(wrapped.rows.count, 1))
                    * wrapped.lineHeight
                itemView = PendoloLineItemView(
                    item: entry, width: maxTextWidth, height: height,
                    mirrored: mirrored)
                let label = UILabel()
                label.text = line.text
                label.font = font
                label.numberOfLines = 0
                label.textAlignment = mirrored ? .right : .left
                label.textColor = snapshot.palette.primary
                    .withAlphaComponent(0.75)
                label.frame = CGRect(x: 0, y: 0,
                                     width: maxTextWidth, height: height)
                itemView.contentView.addSubview(label)
            }
            let tap = UITapGestureRecognizer(
                target: self, action: #selector(lineTapped(_:)))
            itemView.addGestureRecognizer(tap)
            railView.addSubview(itemView)
            itemViews.append(itemView)
        }
    }

    private func buildFocalItem(entry: PendoloWheelItem, line: LyricLine,
                                font: UIFont, maxTextWidth: CGFloat,
                                mirrored: Bool,
                                palette: PaletteTokens) -> PendoloLineItemView {
        let units = StageLyricUnits.units(for: line)
        let graphemeTimes = StageTextKit.graphemeTimes(line: line, words: units)
        let wrapped = StageTextKit.wrap(
            text: line.text, font: font, maxWidth: maxTextWidth,
            maxLines: 6, fontPx: 28)
        let lineHeight = wrapped.lineHeight
        let height = CGFloat(max(wrapped.rows.count, 1)) * lineHeight
        let itemView = PendoloLineItemView(
            item: entry, width: maxTextWidth, height: height,
            mirrored: mirrored)
        let graphemes = line.text.map { String($0) }
        let fillColor = Self.mix(palette.primary, palette.accent, 0.32)
        let baseColor = palette.primary.withAlphaComponent(0.52)
        for (rowIndex, row) in wrapped.rows.enumerated() {
            let rowText = graphemes[row.graphemeRange].joined()
            guard !rowText.isEmpty else { continue }
            let rowTimings = Array(graphemeTimes[row.graphemeRange])
            let rowOffsets = StageTextKit.graphemeOffsets(
                text: rowText, font: font)
            let rowView = PendoloSweepRowView(
                text: rowText, font: font, baseColor: baseColor,
                fillColor: fillColor, timings: rowTimings,
                offsets: rowOffsets, lineHeight: lineHeight)
            let rowWidth = rowOffsets.last ?? 0
            rowView.frame = CGRect(
                x: mirrored ? maxTextWidth - rowWidth : 0,
                y: CGFloat(rowIndex) * lineHeight,
                width: rowWidth, height: lineHeight)
            itemView.contentView.addSubview(rowView)
            itemView.sweepRows.append(rowView)
        }
        return itemView
    }

    @objc private func lineTapped(_ gesture: UITapGestureRecognizer) {
        guard let itemView = gesture.view as? PendoloLineItemView,
              let snapshot,
              snapshot.lines.indices.contains(itemView.item.index)
        else { return }
        let line = snapshot.lines[itemView.item.index]
        context?.sendCommand(LyricStageCommand(
            kind: .seek(to: line.start), source: "stage.pendolo"))
    }

    // MARK: 逐帧变换

    private func applyFrameTransforms(position: TimeInterval,
                                      tuning: PendoloTuningValues) {
        let esc = escapementAngle
        let anchors = clockworkAnchors()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ticksLayer?.transform = CATransform3DMakeRotation(
            CGFloat(esc * 0.2), 0, 0, 1)
        for layer in mainGearLayers {
            layer.transform = CATransform3DMakeRotation(CGFloat(esc), 0, 0, 1)
        }
        sunLayer?.transform = CATransform3DMakeRotation(
            CGFloat(-esc * 2.5), 0, 0, 1)
        for (idx, layer) in planetLayers.enumerated() {
            let orbit = esc * 0.4 + Double(idx) * 2 * Double.pi / 3
            let center = CGPoint(
                x: hub.x + anchors.orbitR * CGFloat(cos(orbit)),
                y: hub.y + anchors.orbitR * CGFloat(sin(orbit)))
            layer.position = center
            layer.transform = CATransform3DMakeRotation(
                CGFloat(-esc * 3 + Double(idx) * 0.5), 0, 0, 1)
            if planetJewelLayers.indices.contains(idx) {
                planetJewelLayers[idx].position = center
            }
        }
        balanceLayer?.transform = CATransform3DMakeRotation(
            CGFloat(phase * 0.1), 0, 0, 1)
        hairspringLayer?.transform = CATransform3DMakeRotation(
            CGFloat(bassOscillation * 0.6 + phase * 0.03), 0, 0, 1)
        for layer in transLayers {
            layer.transform = CATransform3DMakeRotation(
                CGFloat(-esc * 1.4), 0, 0, 1)
        }
        secondGearLayer?.transform = CATransform3DMakeRotation(
            CGFloat(secondAngle), 0, 0, 1)
        secondSpokeLayer?.transform = CATransform3DMakeRotation(
            CGFloat(-secondAngle), 0, 0, 1)
        idlerLayer?.transform = CATransform3DMakeRotation(
            CGFloat(esc * 2.2), 0, 0, 1)
        // 轨道整体旋转（锚点已落轮心，纯 z 旋转）+ 分层视差
        // 的 z 抬升（倾斜/轮心视角时才有透视可感，平放恒等
        // 变换下 translateZ 无视觉变化，与网页 flat 口径同）。
        var railTransform = CATransform3DMakeRotation(
            CGFloat(railRotationDeg(tuning: tuning) * .pi / 180), 0, 0, 1)
        if tuning.tiltDeg != 0 || tuning.hubView {
            let lift = 0.1 * CGFloat(tuning.parallaxDepth) * baseRadius
            railTransform = CATransform3DTranslate(railTransform, 0, 0, lift)
        }
        railView.layer.transform = railTransform
        CATransaction.commit()

        // 行项不透明度（PendoloRotatingLine 的可见弧淡出：
        // |自身角 + 轮转角| ≥ 110° → 0，末 28° 线性淡出；
        // 轮心视角下非焦点句再乘 standSideLineAlpha）与内容
        // 反转/缩放。逐帧只改 alpha 与 transform，不重排版。
        let wheelDeg = railRotationDeg(tuning: tuning)
            * (tuning.mirrorLayout ? -1 : 1)
        for itemView in itemViews {
            let entry = itemView.item
            let visible = abs(entry.angleDeg + wheelDeg)
            var alpha = entry.alpha
            if visible >= 110 {
                alpha = 0
            } else {
                alpha *= CGFloat(min(1, (110 - visible) / 28))
            }
            if tuning.hubView, !entry.isActive {
                let d = max(1, entry.distance)
                // (61) WC：轮心视角非焦点行 alpha 基线 0.18→0.45 下限。
                let stand = 0.45 + (1 - 0.45) * (d - 1) / 3
                alpha *= CGFloat(min(1, stand))
                let edge = max(0, min(1, (75 - abs(entry.angleDeg + wheelDeg)) / 10))
                alpha *= CGFloat(edge)
            }
            itemView.alpha = alpha
            let contentDeg = -railRotationDeg(tuning: tuning) * 0.65
                + (tuning.mirrorLayout ? -1 : 1) * entry.angleDeg * 0.35
            itemView.contentView.transform = CGAffineTransform(
                rotationAngle: CGFloat(contentDeg * .pi / 180))
                .scaledBy(x: entry.scale, y: entry.scale)
            for row in itemView.sweepRows {
                row.update(position: position)
            }
        }
    }

    /// 两色线性混合（网页 mixColors 口径，sRGB 分量插值）。
    private static func mix(_ a: UIColor, _ b: UIColor,
                            _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t,
                       green: ag + (bg - ag) * t,
                       blue: ab + (bb - ab) * t,
                       alpha: aa + (ba - aa) * t)
    }
}
