import UIKit
import QuartzCore

// 浮名 fume（M2' 最重样式，原生窗口化版）：按 folia-major 网页版
// fume 的展示行为参数级照搬——全曲歌词先排成一篇文章版面
// （多栏纸面、body/hero 块、种子洗牌放置，见 +Layout），相机
// 在版面上空按焦点块/总览镜头移动（弹簧+桥接飞行，见
// +Camera），文字以「等待极淡 → 逐字印出着色+辉光 → 读过
// 留痕」三态呈现（fumeBlockFrame / fumeCanvasText 口径）。
//
// 渲染落法（工程决策）：网页是整曲 canvas 逐帧光栅化 + 静态
// 块快照缓存；原生不做整曲大位图（内存硬线：全应用 ≤450MB、
// 舞台纹理 ≤250MB，整曲纸面在 DPR 2 下位图可达数百 MB）。
// 改用 UIKit 视图窗口化：世界容器（文章坐标）只物化相机视口
// overscan 180pt（网页 isFumeBlockOnScreen 同值）内的块视图，
// 硬上限 48 块；相机移动 = 世界/背景两容器的仿射变换逐帧
// 插值（参数照源码）。静态块用单色标签（网页快照的等价物），
// 只有正在印出的块逐字素重建富文本（每帧 ≤ 数十个字素）。
//
// 时钟纪律：只消费宿主 frameTick(position:)；dt 与漂移相位
// 以 CACurrentMediaTime 与上帧差分（与协议锚点同基准），不
// 自建 CADisplayLink/Timer。inactive/destroyed 停一切推进。
//
// 背景（FumeBackground）：几何图形场景（环/方/十字/星芒）以
// CAShapeLayer 近似——网页的渐变描边以混色实线代（档案注
// 明），音频频段缩放因 requiresSpectrum=false 恒 1。

// MARK: - 调参（DEFAULT_FUME_TUNING；宿主可经快照 ext 覆盖）

struct FumeTuningValues {
    var cameraSpeed: Double = 1        // 0.55…1.85
    var stepped: Bool = false          // cameraTrackingMode 默认 smooth
    var glowIntensity: Double = 1      // 0…1.8
    var heroScale: Double = 1          // 0.82…1.32
    var textHoldRatio: Double = 1      // 1 = 读过不淡出
    var backgroundObjectOpacity: Double = 0.5
    var hidePrintSymbols: Bool = false

    static func from(ext: [String: String]) -> FumeTuningValues {
        var values = FumeTuningValues()
        func number(_ key: String) -> Double? {
            guard let raw = ext[key] else { return nil }
            return Double(raw)
        }
        if let v = number("fume.cameraSpeed") { values.cameraSpeed = fumeClamp(v, 0.55, 1.85) }
        if let v = number("fume.glowIntensity") { values.glowIntensity = fumeClamp(v, 0, 1.8) }
        if let v = number("fume.heroScale") { values.heroScale = fumeClamp(v, 0.82, 1.32) }
        if let v = number("fume.textHoldRatio") { values.textHoldRatio = fumeClamp(v, 0, 1) }
        if let v = number("fume.backgroundObjectOpacity") {
            values.backgroundObjectOpacity = fumeClamp(v, 0, 1)
        }
        if let mode = ext["fume.cameraTrackingMode"] {
            values.stepped = (mode == "stepped")
        }
        if let raw = ext["fume.hidePrintSymbols"] {
            values.hidePrintSymbols = (raw == "true" || raw == "1")
        }
        return values
    }
}

// MARK: - 块时序（fumeBlockFrame.ts / fumeTextStyle.ts 移植）

struct FumePassedStyle {
    var opacity: CGFloat
    var glowMultiplier: CGFloat
    var shadowAlphaBase: CGFloat
    var shadowAlphaTrail: CGFloat
}

/// resolvePassedTextStyle：standard / dimmed 两式。
func fumePassedStyle(isHero: Bool, dimmed: Bool) -> FumePassedStyle {
    if dimmed {
        return FumePassedStyle(opacity: isHero ? 0.11 : 0.075,
                               glowMultiplier: 0, shadowAlphaBase: 0, shadowAlphaTrail: 0)
    }
    return FumePassedStyle(opacity: isHero ? 0.74 : 0.58,
                           glowMultiplier: 1, shadowAlphaBase: 0.1, shadowAlphaTrail: 0.16)
}

struct FumeBlockTiming {
    var waitingOpacity: CGFloat
    var activeOpacity: CGFloat
    var lineEnd: TimeInterval        // renderEndTime
    var passCutoff: TimeInterval     // min(renderEnd, 下行 start)
    var hasRevealCompleted: Bool
    var hasPassCutoffReached: Bool
    var lineDuration: Double
    var colorTrailDuration: Double
    var staticState: Int             // 0 live / 1 waiting / 2 passed
}

/// resolveFumeBlockTiming 的原生复刻。
func fumeBlockTiming(block: FumeBlockData, time: TimeInterval,
                     nextLineStart: TimeInterval?, textHoldRatio: Double) -> FumeBlockTiming {
    let lineEnd = block.renderEnd
    let cutoff = nextLineStart.map { min(lineEnd, $0) } ?? lineEnd
    let lineDuration = max(lineEnd - block.line.start, 0.18)
    let trail = fumeClamp(lineDuration * (block.isHero ? 0.42 : 0.52), 0.45, 1.45)
    let staticState: Int
    if time < block.line.start { staticState = 1 }
    else if time >= lineEnd + trail { staticState = 2 }
    else { staticState = 0 }
    return FumeBlockTiming(
        waitingOpacity: block.isHero ? 0.06 : 0.035,
        activeOpacity: block.isHero ? 0.985 : 0.92,
        lineEnd: lineEnd, passCutoff: cutoff,
        hasRevealCompleted: time >= block.line.end,
        hasPassCutoffReached: time >= cutoff,
        lineDuration: lineDuration, colorTrailDuration: trail,
        staticState: staticState)
}

/// resolveVisualProgressWithCutoff：名义时长被 cutoff 截短的进度。
func fumeProgressWithCutoff(start: TimeInterval, duration: Double,
                            time: TimeInterval, cutoff: TimeInterval) -> Double {
    let nominalEnd = start + max(duration, 0.001)
    let effectiveEnd = max(start + 0.001, min(nominalEnd, cutoff))
    return fumeClamp((time - start) / max(effectiveEnd - start, 0.001), 0, 1)
}

/// resolveFumePassedFadeDuration：dimmed 淡出总时长（ratio=1 时 ∞）。
func fumePassedFadeDuration(lines: [LyricLine], textHoldRatio: Double) -> Double {
    if textHoldRatio >= 1 { return .infinity }
    let timed = lines.map { (start: $0.start, end: fumeLineTiming(for: $0).renderEnd) }
        .sorted { $0.start < $1.start }
    if timed.count <= 1 { return fumeClamp(8 * textHoldRatio, 2.4, 130) }
    guard let first = timed.first, let last = timed.last else { return 130 }
    return fumeClamp(max(last.end - first.start, 0) * textHoldRatio, 2.4, 130)
}

// MARK: - 背景场景（FumeBackground.ts 移植，形状数据）

struct FumeBgShape {
    var kind: Int        // 0 ring / 1 square / 2 cross / 3 spark
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var rotation: Double
    var rotationSpeed: Double
    var strokeWidth: CGFloat
    var opacity: Double
    var useAccent: Bool
    var depth: Double
    var ringGapStart: Double = 0
    var ringGapSize: Double = 0
}

/// choosePaperHaloAnchor：22% 概率落在纸内，否则贴纸边外溢。
private func fumeHaloAnchor(paperLeft: CGFloat, paperTop: CGFloat,
                            paperRight: CGFloat, paperBottom: CGFloat,
                            worldWidth: CGFloat, worldHeight: CGFloat,
                            width: CGFloat, height: CGFloat,
                            seedKey: String) -> (x: CGFloat, y: CGFloat) {
    if fumeSeeded("\(seedKey):inside-chance") < 0.22 {
        return (
            x: fumeClampF(fumeMixF(paperLeft + width * 0.12, paperRight - width * 0.12,
                                   CGFloat(fumeSeeded("\(seedKey):inside-x"))), 0, worldWidth),
            y: fumeClampF(fumeMixF(paperTop + height * 0.12, paperBottom - height * 0.12,
                                   CGFloat(fumeSeeded("\(seedKey):inside-y"))), 0, worldHeight))
    }
    let side = Int(fumeSeeded("\(seedKey):side") * 4) % 4
    let overflowX = width * fumeMixF(0.16, 0.24, CGFloat(fumeSeeded("\(seedKey):overflow-x")))
    let overflowY = height * fumeMixF(0.16, 0.24, CGFloat(fumeSeeded("\(seedKey):overflow-y")))
    let jitterX = width * fumeMixF(-0.18, 0.18, CGFloat(fumeSeeded("\(seedKey):span-jitter-x")))
    let jitterY = height * fumeMixF(-0.18, 0.18, CGFloat(fumeSeeded("\(seedKey):span-jitter-y")))
    switch side {
    case 0:
        return (x: fumeClampF(paperLeft - overflowX, 0, worldWidth),
                y: fumeClampF(fumeMixF(paperTop - height * 0.12, paperBottom + height * 0.12,
                                       CGFloat(fumeSeeded("\(seedKey):y"))) + jitterY, 0, worldHeight))
    case 1:
        return (x: fumeClampF(paperRight + overflowX, 0, worldWidth),
                y: fumeClampF(fumeMixF(paperTop - height * 0.12, paperBottom + height * 0.12,
                                       CGFloat(fumeSeeded("\(seedKey):y"))) + jitterY, 0, worldHeight))
    case 2:
        return (x: fumeClampF(fumeMixF(paperLeft - width * 0.12, paperRight + width * 0.12,
                                       CGFloat(fumeSeeded("\(seedKey):x"))) + jitterX, 0, worldWidth),
                y: fumeClampF(paperTop - overflowY, 0, worldHeight))
    default:
        return (x: fumeClampF(fumeMixF(paperLeft - width * 0.12, paperRight + width * 0.12,
                                       CGFloat(fumeSeeded("\(seedKey):x"))) + jitterX, 0, worldWidth),
                y: fumeClampF(paperBottom + overflowY, 0, worldHeight))
    }
}

/// buildFumeBackgroundScene：世界 = 文章尺寸；seed 的主题名
/// 分量原生以 "fume" 代（与版面 seedKey 同口径，档案注明）。
func fumeBuildBackgroundScene(viewport: CGSize, worldWidth: CGFloat, worldHeight: CGFloat,
                              paper: (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat)?)
    -> (width: CGFloat, height: CGFloat, shapes: [FumeBgShape]) {
    let resolvedWorldWidth = max(worldWidth, viewport.width * 1.2)
    let resolvedWorldHeight = max(worldHeight, viewport.height * 1.2)
    guard viewport.width > 0, viewport.height > 0 else {
        return (max(resolvedWorldWidth, 1), max(resolvedWorldHeight, 1), [])
    }
    let baseUnit = fumeClampF(min(viewport.width, viewport.height) * 0.72, 320, 760)
    let paperLeft = paper?.left ?? resolvedWorldWidth * 0.24
    let paperTop = paper?.top ?? resolvedWorldHeight * 0.18
    let paperRight = paper?.right ?? resolvedWorldWidth * 0.76
    let paperBottom = paper?.bottom ?? resolvedWorldHeight * 0.82
    let kinds = [0, 1, 2, 0, 1, 2]
    let landscape = resolvedWorldWidth > resolvedWorldHeight
    let shapeCount = landscape ? 8 : 7
    let sparkCount = landscape ? 12 : 9
    var shapes: [FumeBgShape] = []

    for index in 0..<shapeCount {
        let seed = "fume:fume:\(fumeJSNumber(Double(resolvedWorldWidth))):\(fumeJSNumber(Double(resolvedWorldHeight))):\(index)"
        let kind = kinds[index % kinds.count]
        let width = baseUnit * fumeMixF(0.82, 1.36, CGFloat(fumeSeeded("\(seed):size")))
        let anchor = fumeHaloAnchor(
            paperLeft: paperLeft, paperTop: paperTop, paperRight: paperRight, paperBottom: paperBottom,
            worldWidth: resolvedWorldWidth, worldHeight: resolvedWorldHeight,
            width: width, height: width, seedKey: seed)
        shapes.append(FumeBgShape(
            kind: kind, x: anchor.x, y: anchor.y, width: width,
            rotation: fumeMix(-Double.pi * 0.2, Double.pi * 0.2, fumeSeeded("\(seed):rotation")),
            rotationSpeed: fumeMix(-0.045, 0.045, fumeSeeded("\(seed):rotation-speed")),
            strokeWidth: fumeMixF(0.25, 2.1, CGFloat(fumeSeeded("\(seed):stroke-width"))),
            opacity: fumeMix(0.01, 0.16, fumeSeeded("\(seed):opacity")),
            useAccent: fumeSeeded("\(seed):color") > 0.5,
            depth: fumeSeeded("\(seed):depth"),
            ringGapStart: kind == 0 ? fumeMix(-Double.pi, Double.pi, fumeSeeded("\(seed):gap-start")) : 0,
            ringGapSize: kind == 0 ? fumeMix(Double.pi * 0.12, Double.pi * 0.24, fumeSeeded("\(seed):gap-size")) : 0))
    }

    let sparkLeft = resolvedWorldWidth * 0.2
    let sparkRight = resolvedWorldWidth * 0.8
    let sparkTop = resolvedWorldHeight * 0.18
    let sparkBottom = resolvedWorldHeight * 0.82
    let sparkColumns = max(Int(ceil(sqrt(Double(sparkCount) * Double(resolvedWorldWidth / max(resolvedWorldHeight, 1))))), 1)
    let sparkRows = max(Int(ceil(Double(sparkCount) / Double(sparkColumns))), 1)
    let cellWidth = (sparkRight - sparkLeft) / CGFloat(sparkColumns)
    let cellHeight = (sparkBottom - sparkTop) / CGFloat(sparkRows)
    for index in 0..<sparkCount {
        let seed = "fume:fume:\(fumeJSNumber(Double(resolvedWorldWidth))):\(fumeJSNumber(Double(resolvedWorldHeight))):spark:\(index)"
        let width = baseUnit * fumeMixF(0.1, 0.24, CGFloat(fumeSeeded("\(seed):size")))
        let column = index % sparkColumns
        let row = index / sparkColumns
        let jitterX = fumeMixF(-0.32, 0.32, CGFloat(fumeSeeded("\(seed):jitter-x"))) * cellWidth
        let jitterY = fumeMixF(-0.32, 0.32, CGFloat(fumeSeeded("\(seed):jitter-y"))) * cellHeight
        shapes.append(FumeBgShape(
            kind: 3,
            x: fumeClampF(sparkLeft + (CGFloat(column) + 0.5) * cellWidth + jitterX, sparkLeft, sparkRight),
            y: fumeClampF(sparkTop + (CGFloat(row) + 0.5) * cellHeight + jitterY, sparkTop, sparkBottom),
            width: width,
            rotation: fumeMix(-Double.pi, Double.pi, fumeSeeded("\(seed):rotation")),
            rotationSpeed: fumeMix(-0.18, 0.18, fumeSeeded("\(seed):rotation-speed")),
            strokeWidth: fumeMixF(0.75, 1.7, CGFloat(fumeSeeded("\(seed):stroke-width"))),
            opacity: fumeMix(0.08, 0.22, fumeSeeded("\(seed):opacity")),
            useAccent: fumeSeeded("\(seed):color") > 0.5,
            depth: fumeSeeded("\(seed):depth")))
    }
    shapes.sort { $0.depth < $1.depth }
    return (resolvedWorldWidth, resolvedWorldHeight, shapes)
}

/// 背景形状路径（buildShapePath 的 UIBezierPath 版，局部坐标）。
private func fumeShapePath(_ shape: FumeBgShape) -> UIBezierPath {
    let size = shape.width
    let half = size * 0.5
    let path = UIBezierPath()
    switch shape.kind {
    case 0:  // ring：带缺口的圆弧
        let gapStart = shape.ringGapStart == 0 ? -Double.pi * 0.18 : shape.ringGapStart
        let gapSize = fumeClamp(shape.ringGapSize == 0 ? Double.pi * 0.2 : shape.ringGapSize,
                                0.18, Double.pi * 0.6)
        path.addArc(withCenter: CGPoint(x: half, y: half), radius: half,
                    startAngle: CGFloat(gapStart + gapSize),
                    endAngle: CGFloat(gapStart + Double.pi * 2), clockwise: true)
    case 1:  // square
        path.append(UIBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)))
    case 2:  // cross：十字多边形（arm = size×0.3）
        let arm = size * 0.3
        let points: [(CGFloat, CGFloat)] = [
            (half - arm, 0), (half + arm, 0), (half + arm, half - arm), (size, half - arm),
            (size, half + arm), (half + arm, half + arm), (half + arm, size), (half - arm, size),
            (half - arm, half + arm), (0, half + arm), (0, half - arm), (half - arm, half - arm),
        ]
        for (i, point) in points.enumerated() {
            if i == 0 { path.move(to: CGPoint(x: point.0, y: point.1)) }
            else { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        }
        path.close()
    default:  // spark：八角星芒（outer 0.5 / inner 0.13）
        let outer = half
        let inner = size * 0.13
        let points: [(CGFloat, CGFloat)] = [
            (half, half - outer), (half + inner, half - inner), (half + outer, half),
            (half + inner, half + inner), (half, half + outer), (half - inner, half + inner),
            (half - outer, half), (half - inner, half - inner),
        ]
        for (i, point) in points.enumerated() {
            if i == 0 { path.move(to: CGPoint(x: point.0, y: point.1)) }
            else { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        }
        path.close()
    }
    return path
}

// MARK: - 块视图（窗口化物化单位）

final class FumeBlockView: UIView {
    let block: FumeBlockData
    private(set) var labels: [UILabel] = []
    let stampView = UIView()
    /// 字素 → 词区间下标（-1 无），init 时按 wordRanges 铺满。
    let rangeIndexByOffset: [Int]
    var lastStaticKey: String? = nil

    init(block: FumeBlockData, font: UIFont) {
        self.block = block
        var indexByOffset = [Int](repeating: -1, count: block.graphemes.count)
        for (rangeIndex, range) in block.wordRanges.enumerated() {
            for offset in range.start..<min(range.end, block.graphemes.count) {
                indexByOffset[offset] = rangeIndex
            }
        }
        self.rangeIndexByOffset = indexByOffset
        super.init(frame: CGRect(x: block.x, y: block.y, width: block.width, height: block.height))
        isUserInteractionEnabled = false
        for renderLine in block.renderLines {
            let label = UILabel()
            label.text = renderLine.text
            label.font = font
            label.numberOfLines = 1
            label.frame = CGRect(x: renderLine.left, y: renderLine.top,
                                 width: max(renderLine.width + 2, 1), height: block.lineHeight)
            label.layer.shadowOffset = .zero
            labels.append(label)
            addSubview(label)
        }
        stampView.isHidden = true
        stampView.layer.shadowOffset = .zero
        addSubview(stampView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 静态样式（等待/读过）：单色 + 可选辉光阴影（网页快照等价）。
    /// 重设 text 以清除 live 期写过的富文本逐字颜色。
    func applyStatic(textColor: UIColor, shadowColor: UIColor?, shadowRadius: CGFloat) {
        for (index, label) in labels.enumerated() {
            if index < block.renderLines.count {
                label.text = block.renderLines[index].text
            }
            label.textColor = textColor
            if let shadowColor {
                label.layer.shadowColor = shadowColor.cgColor
                label.layer.shadowRadius = shadowRadius
                label.layer.shadowOpacity = 1
            } else {
                label.layer.shadowOpacity = 0
            }
        }
        stampView.isHidden = true
    }
}

// MARK: - 渲染方

final class FumeStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    /// 窗口化硬上限：同时物化的块视图数（视口+overscan 内按
    /// 距相机中心近者优先），档案内存审计据此计。
    private static let maxMaterializedBlocks = 48

    private let rootView = LyricStageRootView()
    private let bgWorldView = UIView()
    private let worldView = UIView()
    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    private var isActive = false

    private let builder = FumeArticleBuilder()
    var article: FumeArticleData?
    private var builtKey: String? = nil
    private var tuning = FumeTuningValues()
    private var passedFadeDuration: Double = .infinity
    private var overviewCamera: FumeViewTarget?
    var overviewStart: TimeInterval = .infinity
    private var cameraState = FumeCameraState()
    private var blockViews: [Int: FumeBlockView] = [:]
    private var bgScene: (width: CGFloat, height: CGFloat, shapes: [FumeBgShape])?
    private var bgLayers: [CAShapeLayer] = []
    private var lastTickWall: TimeInterval? = nil
    private var lastOverviewRestore: Double = 0

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = true
        for container in [bgWorldView, worldView] {
            container.layer.anchorPoint = .zero
            container.layer.position = .zero
            container.isUserInteractionEnabled = false
            rootView.addSubview(container)
        }
        rootView.onLayout = { [weak self] in self?.performLayout() }
    }

    // MARK: LyricStageRenderer

    func mount(context: LyricStageContext) {
        self.context = context
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        self.snapshot = snapshot
        tuning = FumeTuningValues.from(ext: snapshot.ext)
        rootView.backgroundColor = snapshot.palette.background
        rebuildIfNeeded()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        if !isActive { lastTickWall = nil }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot, let article else { return }
        let viewport = snapshot.viewport.size
        guard viewport.width > 0, viewport.height > 0 else { return }

        // dt：与上帧墙钟差分并按网页钳制 [1/240, 0.05]。
        let wall = CACurrentMediaTime()
        let dt = lastTickWall.map { fumeClamp(wall - $0, 1.0 / 240.0, 0.05) } ?? (1.0 / 60.0)
        lastTickWall = wall

        var lineIndex = -1
        for (index, line) in snapshot.lines.enumerated() {
            if line.start <= position { lineIndex = index } else { break }
        }

        lastOverviewRestore = cameraState.step(
            article: article, time: position, nowMs: wall * 1000, dt: dt,
            lineIndex: lineIndex, viewport: viewport,
            overview: overviewCamera, overviewStart: overviewStart,
            cameraSpeed: tuning.cameraSpeed, stepped: tuning.stepped,
            staticMode: false)
        let camera = cameraState.camera

        // 世界变换：p' = (p − camera) × scale + 视口中心（网页
        // canvas translate/scale/translate 的仿射等价式）。
        let scale = CGFloat(camera.scale)
        worldView.transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: viewport.width / 2 - scale * CGFloat(camera.x),
            ty: viewport.height / 2 - scale * CGFloat(camera.y))

        updateBackground(camera: camera, viewport: viewport, position: position)
        syncWindow(article: article, camera: camera, viewport: viewport)
        for (blockIndex, blockView) in blockViews {
            updateBlockView(blockView, blockIndex: blockIndex,
                            article: article, time: position, snapshot: snapshot)
        }
    }

    func unmount() {
        isActive = false
        lastTickWall = nil
        clearBlocks()
        clearBackground()
        article = nil
        builtKey = nil
        cameraState = FumeCameraState()
        context = nil
    }

    // MARK: 构建

    private func rebuildIfNeeded() {
        guard let snapshot else { return }
        let viewport = snapshot.viewport.size
        let key = "\(snapshot.track?.id ?? "")|\(snapshot.lines.count)|"
            + "\(Int(viewport.width))x\(Int(viewport.height))|\(tuning.heroScale)"
        guard key != builtKey else { return }
        builtKey = key
        clearBlocks()
        clearBackground()
        cameraState = FumeCameraState()
        guard viewport.width > 0, viewport.height > 0, !snapshot.lines.isEmpty,
              let built = builder.build(lines: snapshot.lines, viewport: viewport,
                                        heroScale: tuning.heroScale) else {
            article = nil
            overviewCamera = nil
            overviewStart = .infinity
            return
        }
        article = built
        worldView.bounds = CGRect(x: 0, y: 0, width: built.width, height: built.height)
        cameraState.syncToArticle(built)
        overviewCamera = fumeOverviewCamera(article: built, viewport: viewport)
        // 总览起点：末个可渲染行 start + 其渲染时长 ×0.5。
        overviewStart = .infinity
        for line in snapshot.lines.reversed() {
            if !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let renderEnd = fumeLineTiming(for: line).renderEnd
                overviewStart = line.start + max(renderEnd - line.start, 0) * 0.5
                break
            }
        }
        passedFadeDuration = fumePassedFadeDuration(lines: snapshot.lines,
                                                    textHoldRatio: tuning.textHoldRatio)
        buildBackground(article: built, viewport: viewport, palette: snapshot.palette)
    }

    private func buildBackground(article: FumeArticleData, viewport: CGSize, palette: PaletteTokens) {
        let scene = fumeBuildBackgroundScene(
            viewport: viewport, worldWidth: article.width, worldHeight: article.height,
            paper: (article.paperLeft, article.paperTop, article.paperRight, article.paperBottom))
        bgScene = scene
        bgWorldView.bounds = CGRect(x: 0, y: 0, width: scene.width, height: scene.height)
        // 渐变描边近似色：secondary 与 accent 以 0.62 混合（网页
        // 渐变 0.54 停点色），透明度即形状自身 opacity×倍率。
        let gradientApprox = fumeMixColor(palette.secondary, palette.accent, 0.62, alpha: 1)
        let multiplier = tuning.backgroundObjectOpacity * 2
        for shape in scene.shapes {
            let layer = CAShapeLayer()
            layer.path = fumeShapePath(shape).cgPath
            layer.fillColor = nil
            let shapeColor = shape.useAccent ? palette.accent : palette.secondary
            let opacity = fumeClamp(shape.opacity * multiplier, 0, 0.42)
            if shape.kind == 3 {
                layer.strokeColor = shapeColor.withAlphaComponent(CGFloat(opacity)).cgColor
                layer.lineWidth = shape.strokeWidth
                layer.shadowColor = shapeColor.cgColor
                layer.shadowOpacity = Float(fumeClamp(shape.opacity * 0.75 * multiplier, 0, 1))
                layer.shadowRadius = 10
                layer.shadowOffset = .zero
            } else {
                layer.strokeColor = gradientApprox.withAlphaComponent(CGFloat(opacity)).cgColor
                layer.lineWidth = max(shape.strokeWidth * 0.92, 0.78)
            }
            layer.frame = CGRect(x: 0, y: 0, width: shape.width, height: shape.width)
            bgWorldView.layer.addSublayer(layer)
            bgLayers.append(layer)
        }
    }

    private func clearBackground() {
        for layer in bgLayers { layer.removeFromSuperlayer() }
        bgLayers = []
        bgScene = nil
    }

    private func updateBackground(camera: FumeCameraTarget, viewport: CGSize, position: TimeInterval) {
        guard let scene = bgScene else { return }
        let bg = fumeBackgroundView(sceneWidth: scene.width, sceneHeight: scene.height,
                                    camera: camera, viewport: viewport)
        let bgScale = CGFloat(bg.scale)
        bgWorldView.transform = CGAffineTransform(
            a: bgScale, b: 0, c: 0, d: bgScale,
            tx: viewport.width / 2 - bgScale * CGFloat(bg.cameraX),
            ty: viewport.height / 2 - bgScale * CGFloat(bg.cameraY))
        for (index, shape) in scene.shapes.enumerated() {
            guard index < bgLayers.count else { break }
            let layer = bgLayers[index]
            // 层视差：response = mix(0.58, 1.16, depth)，strength 0.72。
            // CAShapeLayer 默认 anchorPoint (0.5, 0.5)：position 即
            // 形状中心，路径在 frame 内以 (w/2, w/2) 为心绘制。
            let response = fumeMix(0.58, 1.16, shape.depth)
            let offsetX = (bg.cameraX - bg.centerX) * (1 - response) * 0.72
            let offsetY = (bg.cameraY - bg.centerY) * (1 - response) * 0.72
            layer.position = CGPoint(x: shape.x + CGFloat(offsetX),
                                     y: shape.y + CGFloat(offsetY))
            layer.setAffineTransform(CGAffineTransform(
                rotationAngle: CGFloat(shape.rotation + position * shape.rotationSpeed)))
        }
    }

    // MARK: 窗口化

    /// isFumeBlockOnScreen（overscan 180）+ 48 块上限（近者优先）。
    private func syncWindow(article: FumeArticleData, camera: FumeCameraTarget, viewport: CGSize) {
        let scale = camera.scale
        var visible: [(index: Int, distance: Double)] = []
        for (index, block) in article.blocks.enumerated() {
            let screenLeft = Double(viewport.width) * 0.5 + (Double(block.x) - camera.x) * scale
            let screenTop = Double(viewport.height) * 0.5 + (Double(block.y) - camera.y) * scale
            let screenRight = screenLeft + Double(block.width) * scale
            let screenBottom = screenTop + Double(block.height) * scale
            if screenRight < -180 || screenLeft > Double(viewport.width) + 180
                || screenBottom < -180 || screenTop > Double(viewport.height) + 180 {
                continue
            }
            let distance = hypot(Double(block.x + block.width / 2) - camera.x,
                                 Double(block.y + block.height / 2) - camera.y)
            visible.append((index, distance))
        }
        if visible.count > Self.maxMaterializedBlocks {
            visible.sort { $0.distance < $1.distance }
            visible = Array(visible.prefix(Self.maxMaterializedBlocks))
        }
        let wanted = Set(visible.map { $0.index })
        for index in Array(blockViews.keys) where !wanted.contains(index) {
            blockViews[index]?.removeFromSuperview()
            blockViews[index] = nil
        }
        for entry in visible where blockViews[entry.index] == nil {
            let block = article.blocks[entry.index]
            let blockView = FumeBlockView(
                block: block,
                font: builder.font(fontPx: block.fontPx, isHero: block.isHero))
            worldView.addSubview(blockView)
            blockViews[entry.index] = blockView
        }
    }

    private func clearBlocks() {
        for (_, blockView) in blockViews { blockView.removeFromSuperview() }
        blockViews = [:]
    }

    // MARK: 块样式推进

    private func updateBlockView(_ blockView: FumeBlockView, blockIndex: Int,
                                 article: FumeArticleData, time: TimeInterval,
                                 snapshot: LyricStageSnapshot) {
        let block = blockView.block
        let nextStart = snapshot.lines.indices.contains(block.sourceLineIndex + 1)
            ? snapshot.lines[block.sourceLineIndex + 1].start : nil
        let timing = fumeBlockTiming(block: block, time: time,
                                     nextLineStart: nextStart,
                                     textHoldRatio: tuning.textHoldRatio)
        let palette = snapshot.palette
        // 辉光基数（normal 强度档）：active 0.92 / passed 0.62 × glowIntensity。
        let activeGlowBoost = 0.92 * tuning.glowIntensity
        let passedGlowBase = 0.62 * tuning.glowIntensity

        if timing.staticState == 1 {
            let key = "waiting"
            if blockView.lastStaticKey != key {
                blockView.lastStaticKey = key
                blockView.applyStatic(
                    textColor: palette.primary.withAlphaComponent(timing.waitingOpacity),
                    shadowColor: nil, shadowRadius: 0)
            }
            return
        }
        if timing.staticState == 2 {
            // 读过留痕：standard 恒定；ratio<1 时按 dimmed 交叉
            // 淡入（总览恢复进度抵消 dim），以参数混合近似双快照。
            var opacity = fumePassedStyle(isHero: block.isHero, dimmed: false).opacity
            var glowMultiplier: CGFloat = 1
            var shadowBase = fumePassedStyle(isHero: block.isHero, dimmed: false).shadowAlphaBase
            var dimBucket = 0
            if tuning.textHoldRatio < 1 {
                let passedAt = timing.lineEnd + timing.colorTrailDuration
                let age = max(time - passedAt, 0)
                let rawDim = passedFadeDuration.isFinite
                    ? fumeEaseInCubic(fumeClamp(age / passedFadeDuration, 0, 1)) : 1
                let dim = rawDim * (1 - lastOverviewRestore)
                let dimmed = fumePassedStyle(isHero: block.isHero, dimmed: true)
                let standard = fumePassedStyle(isHero: block.isHero, dimmed: false)
                opacity = fumeMixF(standard.opacity, dimmed.opacity, CGFloat(dim))
                glowMultiplier = fumeMixF(1, 0, CGFloat(dim))
                shadowBase = fumeMixF(standard.shadowAlphaBase, 0, CGFloat(dim))
                dimBucket = Int((dim * 20).rounded())
            }
            let key = "passed|\(dimBucket)"
            if blockView.lastStaticKey != key {
                blockView.lastStaticKey = key
                let shadowBlur = (2 + block.fontPx * 0.1) * 0.65 * CGFloat(passedGlowBase) * glowMultiplier
                blockView.applyStatic(
                    textColor: palette.primary.withAlphaComponent(opacity),
                    shadowColor: shadowBase > 0
                        ? palette.primary.withAlphaComponent(shadowBase) : nil,
                    shadowRadius: shadowBlur)
            }
            return
        }

        // Live：正在印出或色彩尾迹期，逐字素重建富文本。
        blockView.lastStaticKey = nil
        updateLiveBlock(blockView, timing: timing, time: time, palette: palette,
                        activeGlowBoost: activeGlowBoost, passedGlowBase: passedGlowBase)
    }

    /// drawFumeLiveBlock 的标签版：逐字素颜色/透明度 + 行辉光
    /// （标签层阴影近似）+ 印字戳（frontier 单枚近似）。
    private func updateLiveBlock(_ blockView: FumeBlockView, timing: FumeBlockTiming,
                                 time: TimeInterval, palette: PaletteTokens,
                                 activeGlowBoost: Double, passedGlowBase: Double) {
        let block = blockView.block
        let printed = fumePrintedCount(line: block.line, ranges: block.wordRanges,
                                       graphemeCount: block.graphemes.count, at: time)
        let transitionPassed = fumePassedStyle(isHero: block.isHero, dimmed: false)

        // 行辉光（isLineActive 段）：包络峰值 0.8 的延迟辉光。
        let isLineActive = time >= block.line.start && time <= timing.passCutoff
        var lineGlowAlpha: CGFloat = 0
        var lineGlowBlur: CGFloat = 0
        if isLineActive {
            let progress = fumeProgressWithCutoff(
                start: block.line.start, duration: timing.lineDuration,
                time: time, cutoff: timing.passCutoff)
            let envelope = fumeDelayedGlowEnvelope(progress, peakProgress: 0.8)
            lineGlowAlpha = CGFloat(((block.isHero ? 0.16 : 0.12)
                + envelope * (block.isHero ? 0.26 : 0.2)) * tuning.glowIntensity)
            lineGlowBlur = CGFloat(((block.isHero ? 12 : 8)
                + envelope * Double(block.fontPx) * (block.isHero ? 0.7 : 0.52)) * tuning.glowIntensity)
        }

        for (lineIdx, renderLine) in block.renderLines.enumerated() {
            guard lineIdx < blockView.labels.count else { break }
            let label = blockView.labels[lineIdx]
            let attributed = NSMutableAttributedString(string: renderLine.text)
            // 按字素序号逐个着色（NSRange 以 UTF-16 计）。
            var utf16Cursor = 0
            for (graphemeIndex, grapheme) in renderLine.graphemes.enumerated() {
                let globalOffset = renderLine.start + graphemeIndex
                let length = grapheme.utf16.count
                let color = glyphColor(
                    block: block, blockView: blockView, globalOffset: globalOffset,
                    grapheme: grapheme, printed: printed, timing: timing,
                    time: time, palette: palette, transitionPassed: transitionPassed,
                    activeGlowBoost: activeGlowBoost, passedGlowBase: passedGlowBase)
                attributed.addAttribute(.foregroundColor, value: color,
                                        range: NSRange(location: utf16Cursor, length: length))
                utf16Cursor += length
            }
            label.attributedText = attributed
            if lineGlowAlpha > 0 {
                label.layer.shadowColor = palette.accent
                    .withAlphaComponent(min(lineGlowAlpha * 1.35, 1)).cgColor
                label.layer.shadowRadius = max(lineGlowBlur.rounded(), 0)
                label.layer.shadowOpacity = 1
            } else {
                label.layer.shadowOpacity = 0
            }
        }
        updateStamp(blockView, timing: timing, printed: printed, time: time,
                    palette: palette, activeGlowBoost: activeGlowBoost)
    }

    /// 单字素颜色（drawFumeLiveBlock 的逐字素分支移植；
    /// active 色：网页按词色表取色，协议无词色表 → accent，
    /// 与网页无命中时的回退一致）。
    private func glyphColor(block: FumeBlockData, blockView: FumeBlockView,
                            globalOffset: Int, grapheme: String, printed: Int,
                            timing: FumeBlockTiming, time: TimeInterval,
                            palette: PaletteTokens, transitionPassed: FumePassedStyle,
                            activeGlowBoost: Double, passedGlowBase: Double) -> UIColor {
        let rangeIndex = (globalOffset >= 0 && globalOffset < blockView.rangeIndexByOffset.count)
            ? blockView.rangeIndexByOffset[globalOffset] : -1
        guard rangeIndex >= 0, rangeIndex < block.wordRanges.count else {
            // 无词区间：已印 = activeOpacity 主色，前沿字 0.82，其余等待色。
            if timing.hasRevealCompleted || globalOffset < printed {
                return palette.primary.withAlphaComponent(timing.activeOpacity)
            }
            if printed > 0 && globalOffset == printed && !timing.hasPassCutoffReached {
                return palette.primary.withAlphaComponent(0.82)
            }
            return palette.primary.withAlphaComponent(timing.waitingOpacity)
        }
        let range = block.wordRanges[rangeIndex]
        let wordDuration = max(range.wordEnd - range.wordStart, 0.08)
        let wordProgress = fumeClamp((time - range.wordStart) / wordDuration, 0, 1)
        let glyphCount = max(range.end - range.start, 1)
        let glyphIndex = globalOffset - range.start
        let glyphStart = range.wordStart + Double(glyphIndex) / Double(glyphCount) * wordDuration
        let glyphEnd = range.wordStart + Double(glyphIndex + 1) / Double(glyphCount) * wordDuration
        let glyphDuration = max(glyphEnd - glyphStart, 0.001)
        let glyphProgress = fumeClamp(wordProgress * Double(glyphCount) - Double(glyphIndex) + 0.16, 0, 1)
        let eased = fumeEaseOutCubic(glyphProgress)
        let activeColor = palette.accent
        let trailStart = glyphStart + glyphDuration * 0.18
        let trailPhase = fumeProgressWithCutoff(
            start: trailStart, duration: timing.colorTrailDuration,
            time: time, cutoff: timing.passCutoff)
        let trailProgress = pow(trailPhase, 1.35)

        if timing.hasPassCutoffReached {
            let alpha = fumeMixF(timing.activeOpacity, transitionPassed.opacity, CGFloat(trailProgress))
            return fumeMixColor(activeColor, palette.primary,
                                0.18 + CGFloat(trailProgress) * 0.82, alpha: alpha)
        }
        if time < range.wordStart {
            return palette.primary.withAlphaComponent(timing.waitingOpacity)
        }
        if time <= trailStart {
            let alpha = fumeMixF(timing.waitingOpacity, timing.activeOpacity, CGFloat(eased))
            return fumeMixColor(palette.primary, activeColor,
                                0.22 + CGFloat(eased) * 0.78, alpha: alpha)
        }
        let alpha = fumeMixF(timing.activeOpacity, transitionPassed.opacity, CGFloat(trailProgress))
        return fumeMixColor(activeColor, palette.primary,
                            0.18 + CGFloat(trailProgress) * 0.82, alpha: alpha)
    }

    /// 印字戳（showPrintStamp）：网页逐字素盖戳，原生只呈现
    /// 当前 frontier 字素一枚（尺寸/落点/脉冲公式照搬）。
    private func updateStamp(_ blockView: FumeBlockView, timing: FumeBlockTiming,
                             printed: Int, time: TimeInterval,
                             palette: PaletteTokens, activeGlowBoost: Double) {
        let block = blockView.block
        let stamp = blockView.stampView
        guard !tuning.hidePrintSymbols, printed > 0, printed < block.graphemes.count,
              !timing.hasRevealCompleted, !timing.hasPassCutoffReached else {
            stamp.isHidden = true
            return
        }
        let rangeIndex = (printed < blockView.rangeIndexByOffset.count)
            ? blockView.rangeIndexByOffset[printed] : -1
        guard rangeIndex >= 0, rangeIndex < block.wordRanges.count,
              let renderLine = block.renderLines.first(where: { printed >= $0.start && printed < $0.end })
                ?? block.renderLines.last(where: { printed >= $0.start }) else {
            stamp.isHidden = true
            return
        }
        let range = block.wordRanges[rangeIndex]
        let wordDuration = max(range.wordEnd - range.wordStart, 0.08)
        let glyphCount = max(range.end - range.start, 1)
        let glyphIndex = printed - range.start
        let glyphStart = range.wordStart + Double(glyphIndex) / Double(glyphCount) * wordDuration
        let glyphDuration = max(wordDuration / Double(glyphCount), 0.001)
        let trailStart = glyphStart + glyphDuration * 0.18
        let glyphWindow = max(wordDuration / Double(glyphCount), 0.04)
        let lead = fumeClamp(min(glyphWindow * 0.86, timing.lineDuration * 0.16),
                             0.055, block.isHero ? 0.2 : 0.16)
        let windowStart = trailStart - lead
        let windowEnd = trailStart + lead * 0.42
        let stampProgress = fumeProgressWithCutoff(
            start: windowStart, duration: windowEnd - windowStart,
            time: time, cutoff: timing.passCutoff)
        guard stampProgress > 0, stampProgress < 1 else {
            stamp.isHidden = true
            return
        }
        let trailPhase = fumeProgressWithCutoff(
            start: trailStart, duration: max(windowEnd - trailStart, 0.001),
            time: time, cutoff: timing.passCutoff)
        let isDropping = trailPhase <= 0
        let dropProgress = isDropping
            ? fumeEaseOutCubic(fumeProgressWithCutoff(
                start: windowStart, duration: max(trailStart - windowStart, 0.001),
                time: time, cutoff: timing.passCutoff))
            : 1
        let fadeProgress = isDropping ? 0 : fumeEaseInOutCubic(trailPhase)
        let pulse = isDropping
            ? fumeMix(0.18, 1, pow(dropProgress, 0.78))
            : pow(1 - fadeProgress, 1.2)

        let localIndex = printed - renderLine.start
        let glyphOffset: CGFloat = (localIndex >= 0 && localIndex < renderLine.glyphOffsets.count)
            ? renderLine.glyphOffsets[localIndex] : renderLine.width
        let nextOffset: CGFloat = (localIndex + 1 < renderLine.glyphOffsets.count)
            ? renderLine.glyphOffsets[localIndex + 1] : renderLine.width
        let advance = max(nextOffset - glyphOffset, 0)
        let grapheme = (localIndex >= 0 && localIndex < renderLine.graphemes.count)
            ? renderLine.graphemes[localIndex] : ""
        let visualWidth = max(advance * 0.88,
                              fumeIsCJK(grapheme) ? block.fontPx * 0.56 : block.fontPx * 0.38)
        let stampWidth = visualWidth + block.fontPx * (block.isHero ? 0.18 : 0.12)
        let stampHeight = block.fontPx * (block.isHero ? 0.72 : 0.62)
        let dropDistance = Double(block.lineHeight) * (block.isHero ? 0.24 : 0.2)
        let centerX = renderLine.left + glyphOffset + advance * 0.5
        let centerY = renderLine.top + block.lineHeight * 0.5
            - block.fontPx * 0.38 - CGFloat(fumeMix(dropDistance, 0, dropProgress))
        stamp.frame = CGRect(x: centerX - stampWidth / 2, y: centerY - stampHeight / 2,
                             width: stampWidth, height: stampHeight)
        stamp.backgroundColor = palette.accent
        stamp.alpha = CGFloat(pulse) * (block.isHero ? 0.82 : 0.72)
        stamp.layer.shadowColor = palette.accent
            .withAlphaComponent(CGFloat(0.56 * pulse)).cgColor
        stamp.layer.shadowRadius = CGFloat((8 + Double(block.fontPx) * 0.24) * pulse * activeGlowBoost)
        stamp.layer.shadowOpacity = 1
        stamp.isHidden = false
    }

    // MARK: 布局

    private func performLayout() {
        // 世界/背景容器的 bounds 在构建时按文章尺寸设定，变换
        // 每帧由 frameTick 写；根视图尺寸变化只影响快照视口
        // （宿主会重发快照触发重建），此处无额外排版。
    }
}
