import UIKit
import QuartzCore

// 绘光 lumiere（3.7 (57) 工作流 B5 全量原生移植）：按 folia-major
// 网页版 lumiere 的核心构成逐项实现。依据文件：scene.ts（七层
// 叠放：光场→背景碎片→星空→线稿→浮尘 / 文字组 / 前景散景、
// resolveLumierePalette 调色盘、LUMIERE_BLOOM）、color.ts
// （CHAMPAGNE 香槟金 [1, 0.86, 0.62]）、lumiereDarkField.ts
// （暗场 = 主题背景 ×0.06、浅色保底 0.94）、overlay.ts（画框：
// 四角括号 + 对位十字 + 顶边虚线、alpha 0.5）、types.ts
// （LumiereSceneTuning / DEFAULT_LUMIERE_SCENE_TUNING）、
// lumiereRuntimeTuning.ts（画质档 graphicsScale / 倍频上限 /
// 浮尘倍率、逐帧现读键表）、text/lyricWindow 口径（窗口邻行
// windowNeighbors、未唱字 unlitOpacity、逐字按光点亮）。
// 管线选型：网页 Pixi/WebGL 的光场着色器（体积光 + fbm 烟雾）
// 与 bloom 后期在原生以 CoreAnimation 矢量图层等价呈现——
// 光束 = 梯形路径掩膜的 CAGradientLayer（叠加感靠图层
// shadow 辉光 + 半透明叠加，不做全屏位图逐帧重绘）、烟雾 =
// 大半径径向渐变层低速漂移、浮尘/散景 = CALayer 圆点池、
// 辉光 = UILabel/CALayer 阴影。零位图、零离屏大纹理，舞台
// 纹理占用远低于 200MB 红线；代价是烟雾无 fbm 细节、光束无
// 着色器级丁达尔散射（见回报档案未移植项）。
// 时钟纪律不变：只消费宿主 frameTick 的锚点位置推进一切
// （浮尘/烟雾/运镜均为 position 的纯函数），不自建时钟源。
final class LumiereStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: false)

    private let rootView = LyricStageRootView()
    /// 暗场底（运行时层，在所有场景之下、不随转场变化）。
    private let darkFieldView = UIView()
    /// 图形组容器（光场/碎片/线稿/浮尘）；textOnly 时整组隐藏。
    private let graphicsView = UIView()
    private let fogLayerA = CAGradientLayer()
    private let fogLayerB = CAGradientLayer()
    /// 三束主光（梯形渐变，掩膜成束形）。
    private var beamLayers: [CAGradientLayer] = []
    private var beamAngles: [CGFloat] = []
    /// 背景歌词碎片（巨大字，echo）。
    private let echoLabel = UILabel()
    /// 线稿层（种子折线 + 圆，strokeEnd 随行进度描出）。
    private let lineArtLayer = CAShapeLayer()
    /// 浮尘池（固定 48 点，数量由 moteAmount × 画质倍率决定显隐）。
    private var moteLayers: [CALayer] = []
    private var moteSeeds: [(x: Double, y: Double, speed: Double, size: CGFloat)] = []
    /// 文字组容器（窗口行）。
    private let textView = UIView()
    private var lineContainer: UIView?
    private var wordViews: [GlowWordView] = []
    private var prevLabel: UILabel?
    private var nextLabel: UILabel?
    /// 前景散景池（6 个大圆，frontBokeh）。
    private var bokehLayers: [CALayer] = []
    /// 画框层（overlay.ts）。
    private let overlayLayer = CAShapeLayer()
    private var overlayBuiltSize: CGSize = .zero

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var activeLineId: Int? = nil
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var lastPosition: TimeInterval = 0

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = .clear
        rootView.addSubview(darkFieldView)
        // 图形组
        graphicsView.isUserInteractionEnabled = false
        for fog in [fogLayerA, fogLayerB] {
            fog.type = .radial
            fog.startPoint = CGPoint(x: 0.5, y: 0.5)
            fog.endPoint = CGPoint(x: 1, y: 1)
            graphicsView.layer.addSublayer(fog)
        }
        for i in 0..<3 {
            let beam = CAGradientLayer()
            beam.startPoint = CGPoint(x: 0.5, y: 0)
            beam.endPoint = CGPoint(x: 0.5, y: 1)
            graphicsView.layer.addSublayer(beam)
            beamLayers.append(beam)
            beamAngles.append(CGFloat(i - 1) * 0.22)
        }
        echoLabel.textAlignment = .center
        echoLabel.numberOfLines = 1
        echoLabel.isUserInteractionEnabled = false
        graphicsView.addSubview(echoLabel)
        lineArtLayer.fillColor = UIColor.clear.cgColor
        lineArtLayer.lineWidth = 1.2
        graphicsView.layer.addSublayer(lineArtLayer)
        for i in 0..<48 {
            let mote = CALayer()
            mote.cornerRadius = 1.5
            graphicsView.layer.addSublayer(mote)
            moteLayers.append(mote)
            moteSeeds.append((
                x: stageSeededRandom(Double(i) * 3.7 + 11),
                y: stageSeededRandom(Double(i) * 5.3 + 29),
                speed: 0.008 + stageSeededRandom(Double(i) * 7.9 + 47) * 0.02,
                size: 2 + CGFloat(stageSeededRandom(Double(i) * 9.1 + 63)) * 2.5))
        }
        rootView.addSubview(graphicsView)
        // 文字组
        textView.isUserInteractionEnabled = false
        rootView.addSubview(textView)
        // 前景散景
        for i in 0..<6 {
            let bokeh = CALayer()
            bokeh.cornerRadius = 30
            rootView.layer.addSublayer(bokeh)
            bokehLayers.append(bokeh)
            _ = i
        }
        overlayLayer.fillColor = UIColor.clear.cgColor
        rootView.layer.addSublayer(overlayLayer)
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
            clearLine()
        }
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        lastPosition = position
        let tuning = LumiereTuningStore.valuesCached(now: CACurrentMediaTime())
        let idx = ClassicStageRenderer.activeIndex(in: snapshot.lines, at: position)
        if idx != activeLineId {
            transitionLine(to: idx, position: position, tuning: tuning)
        }
        for word in wordViews { word.update(position: position) }
        updateAtmosphere(position: position, tuning: tuning, snapshot: snapshot)
    }

    func unmount() {
        isActive = false
        context = nil
        snapshot = nil
        clearLine()
        for mote in moteLayers { mote.removeFromSuperlayer() }
        moteLayers = []
        for bokeh in bokehLayers { bokeh.removeFromSuperlayer() }
        bokehLayers = []
    }

    // MARK: 调色盘（scene.ts resolveLumierePalette）

    /// 香槟金（color.ts CHAMPAGNE，0.86 分量含网页中性偏移 0）。
    private static let champagne = UIColor(red: 1, green: 0.86, blue: 0.62, alpha: 1)
    /// 未唱字偏向的冷灰蓝（scene.ts UNLIT_COOL）。
    private static let unlitCool = UIColor(red: 0.62, green: 0.68, blue: 0.80, alpha: 1)

    private func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                       blue: ab + (bb - ab) * t, alpha: 1)
    }

    /// 按最亮通道拉满（glowOf）：保留色相去掉暗度。
    private func glowOf(_ color: UIColor, fallback: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let peak = max(r, g, b)
        guard peak >= 0.04 else { return fallback }
        return UIColor(red: r / peak, green: g / peak, blue: b / peak, alpha: 1)
    }

    private struct Palette { var light: UIColor; var lit: UIColor; var unlit: UIColor }

    private func palette(tuning: LumiereTuningValues) -> Palette {
        guard let snapshot else {
            return Palette(light: Self.champagne, lit: .white, unlit: Self.unlitCool)
        }
        let p = snapshot.palette
        let mixT = CGFloat(min(max(tuning.themeColorMix, 0), 1))
        // light = mix(mix(CHAMPAGNE, accent, 0.18), glowOf(accent), mix)，再拉满。
        var light = mix(Self.champagne, p.accent, 0.18)
        light = mix(light, glowOf(p.accent, fallback: Self.champagne), mixT)
        light = glowOf(light, fallback: Self.champagne)
        let warmLit = mix(light, .white, 0.2)
        let primaryGlow = glowOf(p.primary, fallback: warmLit)
        let lit = mix(warmLit, mix(primaryGlow, .white, 0.2), mixT)
        let secondaryGlow = glowOf(p.secondary, fallback: primaryGlow)
        let unlit = mix(mix(light, Self.unlitCool, 0.55),
                        mix(secondaryGlow, Self.unlitCool, 0.35), mixT)
        return Palette(light: light, lit: lit, unlit: unlit)
    }

    // MARK: 行切换（窗口：邻行 + 当前行逐词）

    private func clearLine() {
        lineContainer?.removeFromSuperview()
        lineContainer = nil
        wordViews = []
        prevLabel = nil
        nextLabel = nil
        activeLineId = nil
    }

    private func transitionLine(to idx: Int?, position: TimeInterval,
                                tuning: LumiereTuningValues) {
        if let old = lineContainer {
            lineContainer = nil
            wordViews = []
            prevLabel = nil
            nextLabel = nil
            // 出场：seamless 时交叉淡出 0.3s，否则同样淡出（网页
            // 非 seamless 的熄灯/闪白转场未落，见档案）。
            UIView.animate(withDuration: 0.3, delay: 0,
                           options: [.curveEaseInOut]) {
                old.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                old.alpha = 0
            } completion: { _ in old.removeFromSuperview() }
        }
        activeLineId = idx
        guard let idx, let snapshot,
              snapshot.lines.indices.contains(idx) else { return }
        let pal = palette(tuning: tuning)
        let line = snapshot.lines[idx]
        let bounds = rootView.bounds
        let vmin = min(bounds.width, bounds.height)
        // 字号：领头光位 heroSize 口径缺省约画面高 7%（网页各
        // 光位 0.055–0.085），以 vmin clamp(30, 6.5%·vmin, 56) 落。
        let fontSize = vmin > 0 ? max(30, min(vmin * 0.065, 56)) : 40
        let font = StageFonts.bold(size: fontSize)
        let profile = StageLineProfile.profile(for: line)
        let units = StageLyricUnits.units(for: line)

        let container = UIView()
        container.isUserInteractionEnabled = false
        // 当前行：逐词 GlowWord（waiting/active/passed 三态与
        // 辉光由共享引擎驱动；基色 = unlit、激活色 = lit）。
        var words: [GlowWordView] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        let maxRowWidth = max(bounds.width - 64, 120)
        let rowHeight = fontSize * 1.3
        for (i, unit) in units.enumerated() {
            let seed = line.start + Double(i) * 7.13
            let pose = StageWordPose(
                x: CGFloat(stageSeededRandom(seed + 1) - 0.5) * 8,
                y: CGFloat(stageSeededRandom(seed + 2) - 0.5) * 8,
                rotate: CGFloat(stageSeededRandom(seed + 3) - 0.5) * 4,
                scale: 1,
                passedRotate: CGFloat(stageSeededRandom(seed + 8) - 0.5) * 10)
            let word = GlowWordView(
                unit: unit, pose: pose, font: font,
                baseColor: pal.unlit, activeColor: pal.lit, profile: profile)
            if cursorX + word.bounds.width > maxRowWidth, cursorX > 0 {
                cursorX = 0
                cursorY += rowHeight
            }
            word.frame.origin = CGPoint(x: cursorX, y: cursorY)
            cursorX += word.bounds.width + fontSize * 0.18
            container.addSubview(word)
            words.append(word)
        }
        let contentHeight = cursorY + rowHeight
        let contentWidth = maxRowWidth
        container.bounds = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        container.center = CGPoint(x: bounds.width / 2, y: bounds.height * 0.52)
        // 逐词按行内居中：把每行词整体水平居中（按行重排 x）。
        centerWordRows(container: container, words: words, rowHeight: rowHeight)
        lineContainer = container
        wordViews = words
        textView.addSubview(container)
        for word in words { word.snap(position: position) }

        // 邻行（windowNeighbors：1 = 仅上一行；2 = 上 + 下）。
        let neighborFont = StageFonts.light(size: fontSize * 0.52)
        func makeNeighbor(_ lineIndex: Int, above: Bool) -> UILabel? {
            guard snapshot.lines.indices.contains(lineIndex) else { return nil }
            let label = UILabel()
            label.text = snapshot.lines[lineIndex].text
            label.font = neighborFont
            label.textColor = pal.unlit
            // (61) WC：邻行（非当前行）alpha 下限 0.45（调参值低于下限时按下限）。
            label.alpha = max(CGFloat(tuning.unlitOpacity),
                              StagePalette.nonCurrentAlphaFloor)
            label.textAlignment = .center
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.sizeToFit()
            let w = min(label.bounds.width, maxRowWidth)
            label.bounds = CGRect(x: 0, y: 0, width: w, height: label.bounds.height)
            label.center = CGPoint(
                x: bounds.width / 2,
                y: container.center.y + (above ? -1 : 1) * (contentHeight / 2 + fontSize * 0.95))
            textView.addSubview(label)
            return label
        }
        prevLabel = makeNeighbor(idx - 1, above: true)
        if tuning.windowNeighbors == 2 {
            nextLabel = makeNeighbor(idx + 1, above: false)
        }
        // 背景碎片（echo）：当前行文本的巨大空心感字（以大字号
        // 低透明 + 阴影近似网页空心描边字），亮度由 echo 驱动。
        echoLabel.text = line.text
        echoLabel.font = StageFonts.bold(size: max(bounds.height * 0.30, 80))
        echoLabel.textColor = pal.light.withAlphaComponent(
            CGFloat(0.10 * tuning.echo * tuning.lightIntensity))
        // 线稿：按行种子生成折线 + 圆，strokeEnd 在逐帧里推进。
        buildLineArt(line: line, bounds: bounds, color: pal.light,
                     enabled: tuning.lineArt && !tuning.textOnly)
        container.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        container.alpha = 0
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut]) {
            container.transform = .identity
            container.alpha = 1
        }
    }

    private func centerWordRows(container: UIView, words: [GlowWordView], rowHeight: CGFloat) {
        var rows: [CGFloat: [GlowWordView]] = [:]
        for word in words { rows[word.frame.origin.y, default: []].append(word) }
        for (_, row) in rows {
            guard let first = row.first, let last = row.last else { continue }
            let rowWidth = last.frame.maxX - first.frame.minX
            let shift = (container.bounds.width - rowWidth) / 2 - first.frame.minX
            for word in row { word.frame.origin.x += shift }
        }
        _ = rowHeight
    }

    private func buildLineArt(line: LyricLine, bounds: CGRect, color: UIColor, enabled: Bool) {
        lineArtLayer.isHidden = !enabled
        guard enabled else { return }
        // 种子折线：以行 start 为种子，5 个节点横贯画面中带，
        // 外加一个圆（lineart/recipes 的几何线稿近似）。
        let path = UIBezierPath()
        var seed = line.start * 3 + 7
        func rnd() -> Double { let v = stageSeededRandom(seed); seed += 1.37; return v }
        let midY = bounds.height * 0.5
        var points: [CGPoint] = []
        for i in 0..<5 {
            points.append(CGPoint(
                x: bounds.width * (0.12 + 0.19 * CGFloat(i)),
                y: midY + CGFloat(rnd() - 0.5) * bounds.height * 0.36))
        }
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        let circleCenter = CGPoint(x: bounds.width * CGFloat(0.2 + rnd() * 0.6),
                                   y: bounds.height * CGFloat(0.2 + rnd() * 0.25))
        path.addArc(withCenter: circleCenter, radius: 26 + CGFloat(rnd()) * 30,
                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
        lineArtLayer.path = path.cgPath
        lineArtLayer.strokeColor = color.withAlphaComponent(0.35).cgColor
        lineArtLayer.strokeEnd = 0
    }

    // MARK: 逐帧氛围（光束/烟雾/浮尘/散景/暗场/画框/运镜）

    private func updateAtmosphere(position: TimeInterval, tuning: LumiereTuningValues,
                                  snapshot: LyricStageSnapshot) {
        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let pal = palette(tuning: tuning)
        let quality = tuning.renderQuality
        // 画质档（lumiereRuntimeTuning）：浮尘倍率 low ×0.6；
        // 图形降采样在矢量呈现下无对应开销，仅倍频/浮尘落。
        let moteScale: Double = quality == .low ? 0.6 : 1
        let textOnly = tuning.textOnly

        // 暗场（lumiereDarkField）：颜色 = palette.background
        // ×0.06；alpha = darkField，浅色（!isDark）保底 0.94。
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        snapshot.palette.background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        darkFieldView.backgroundColor = UIColor(
            red: br * 0.06, green: bg * 0.06, blue: bb * 0.06, alpha: 1)
        let darkAlpha = snapshot.palette.isDark
            ? tuning.darkField : max(tuning.darkField, 0.94)
        darkFieldView.alpha = CGFloat(darkAlpha)
        // textOnly 只关图形组与画框，暗场底是运行时层照常铺
        // （网页 textOnly 清单不含暗场）。
        darkFieldView.isHidden = false
        overlayLayer.isHidden = !tuning.overlayFrame || textOnly
        if tuning.overlayFrame, !textOnly, overlayBuiltSize != bounds.size {
            buildOverlay(bounds: bounds, color: pal.light)
        }

        graphicsView.isHidden = textOnly
        guard !textOnly else { return }

        // 当前行进度（光束强度与线稿描出共用）。
        var lineProgress: CGFloat = 0
        if let idx = activeLineId, snapshot.lines.indices.contains(idx) {
            let line = snapshot.lines[idx]
            let span = max(line.end - line.start, 0.1)
            lineProgress = CGFloat(min(max((position - line.start) / span, 0), 1))
        }
        // 光强：lightIntensity × 行内呼吸（入 0.6s 渐起，网页
        // intensity = smooth(local/0.6) 口径的单元级近似）；
        // audioResponse 无频谱数据源（协议 requiresSpectrum
        // = false）恒按安静帧处理，不造假。
        let beamBase = CGFloat(tuning.lightIntensity) * (0.55 + 0.45 * sin(lineProgress * .pi))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, beam) in beamLayers.enumerated() {
            let sway = CGFloat(sin(position * 0.11 + Double(i) * 2.1)) * 0.05
            beam.transform = CATransform3DMakeRotation(beamAngles[i] + sway, 0, 0, 1)
            let strength = beamBase * (i == 1 ? 1.0 : 0.62) * CGFloat(tuning.bloom > 0 ? 1 : 0.85)
            beam.colors = [
                pal.light.withAlphaComponent(0.34 * strength).cgColor,
                pal.light.withAlphaComponent(0.10 * strength).cgColor,
                UIColor.clear.cgColor,
            ]
            beam.locations = [0, 0.45, 1]
            beam.opacity = 1
        }
        // 烟雾：两层径向渐变反向漂移，浓度 = fogDensity
        // （倍频数 fogOctaves 只影响网页 fbm 细节，矢量层以
        // 第二层不透明度近似其层次感）。
        let fogAlpha = CGFloat(min(tuning.fogDensity, 2)) * 0.16
        for (i, fog) in [fogLayerA, fogLayerB].enumerated() {
            let drift = CGFloat(sin(position * 0.05 + Double(i) * 2.6)) * 0.06
            fog.transform = CATransform3DMakeTranslation(
                drift * bounds.width, CGFloat(cos(position * 0.04 + Double(i))) * 8, 0)
            let layerFactor: CGFloat = i == 0 ? 1 : (tuning.fogOctaves >= 4 ? 0.7 : 0.4)
            fog.colors = [
                pal.light.withAlphaComponent(fogAlpha * layerFactor).cgColor,
                UIColor.clear.cgColor,
            ]
        }
        // 浮尘：位置为 position 的纯函数（种子基位 + 上浮回绕
        // + 横向正弦），显隐数 = 24 × moteAmount × moteScale。
        let visibleMotes = min(moteLayers.count,
                               Int((24 * tuning.moteAmount * moteScale).rounded()))
        for (i, mote) in moteLayers.enumerated() {
            if i >= visibleMotes { mote.isHidden = true; continue }
            mote.isHidden = false
            let seed = moteSeeds[i]
            let rise = (seed.y + position * seed.speed).truncatingRemainder(dividingBy: 1)
            let x = (seed.x + sin(position * 0.3 + Double(i)) * 0.008) * bounds.width
            let y = (1 - rise) * bounds.height
            mote.bounds = CGRect(x: 0, y: 0, width: seed.size, height: seed.size)
            mote.cornerRadius = seed.size / 2
            mote.position = CGPoint(x: x, y: y)
            mote.backgroundColor = pal.light.withAlphaComponent(0.55).cgColor
            mote.opacity = Float(0.35 + 0.65 * abs(sin(position * 0.8 + Double(i) * 1.7)))
        }
        // 前景散景：6 个大圆低透明，慢漂；关时整组隐藏。
        for (i, bokeh) in bokehLayers.enumerated() {
            bokeh.isHidden = !tuning.frontBokeh
            guard tuning.frontBokeh else { continue }
            let size: CGFloat = 46 + CGFloat(i % 3) * 26
            bokeh.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            bokeh.cornerRadius = size / 2
            let bx = (stageSeededRandom(Double(i) * 13.1 + 5) + sin(position * 0.03 + Double(i)) * 0.02) * bounds.width
            let by = (stageSeededRandom(Double(i) * 17.7 + 9) + cos(position * 0.025 + Double(i) * 2) * 0.02) * bounds.height
            bokeh.position = CGPoint(x: bx, y: by)
            bokeh.backgroundColor = pal.light.withAlphaComponent(0.10).cgColor
        }
        // 线稿描出：strokeEnd 随行进度 0→1（网页每镜头 3.6s
        // 描完的近似：行内进度驱动）。
        lineArtLayer.strokeEnd = lineProgress
        // echo 随光呼吸微缩放（背景碎片沿光漂移的近似）。
        echoLabel.transform = CGAffineTransform(
            translationX: 0, y: CGFloat(sin(position * 0.07)) * 6)
        // 运镜：整组缓慢推近（单元级 push 的近似，行内 3%）。
        let push = 1 + 0.03 * lineProgress
        textView.transform = CGAffineTransform(scaleX: push, y: push)
        // 崩解（decay）：行结束后当前行整体上漂 + 淡出加成
        // （逐词 passed 姿态由 GlowWord 承担，这里只补行级）。
        if let idx = activeLineId, snapshot.lines.indices.contains(idx),
           let container = lineContainer {
            let line = snapshot.lines[idx]
            let over = position - line.end
            if over > 0, tuning.decay > 0 {
                let drift = CGFloat(min(over * 14 * tuning.decay, 18))
                container.transform = CGAffineTransform(translationX: 0, y: -drift)
            }
        }
        CATransaction.commit()
    }

    /// 画框（overlay.ts）：四角括号（臂长 unit×0.045、线宽
    /// max(1.2, unit/600)、alpha 0.5）、左右对位十字（0.8
    /// 倍 alpha）、顶边两组各 4 段虚线（0.55 倍 alpha 以
    /// 分段路径近似）；边距 pad = unit×0.06（网页 frameInsets
    /// 近似）。
    private func buildOverlay(bounds: CGRect, color: UIColor) {
        overlayBuiltSize = bounds.size
        let unit = min(bounds.width, bounds.height)
        let pad = unit * 0.06
        let arm = unit * 0.045
        let path = UIBezierPath()
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (pad, pad, 1, 1),
            (bounds.width - pad, pad, -1, 1),
            (bounds.width - pad, bounds.height - pad, -1, -1),
            (pad, bounds.height - pad, 1, -1),
        ]
        for (x, y, sx, sy) in corners {
            path.move(to: CGPoint(x: x, y: y + sy * arm))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + sx * arm, y: y))
        }
        let mark = unit * 0.012
        for x in [pad, bounds.width - pad] {
            let y = bounds.height / 2
            path.move(to: CGPoint(x: x - mark, y: y))
            path.addLine(to: CGPoint(x: x + mark, y: y))
            path.move(to: CGPoint(x: x, y: y - mark))
            path.addLine(to: CGPoint(x: x, y: y + mark))
            path.addArc(withCenter: CGPoint(x: x, y: y), radius: mark * 0.6,
                        startAngle: 0, endAngle: .pi * 2, clockwise: true)
        }
        for side: CGFloat in [-1, 1] {
            for k in 0..<4 {
                let x = bounds.width / 2 + side * (unit * 0.1 + CGFloat(k) * unit * 0.018)
                path.move(to: CGPoint(x: x, y: pad))
                path.addLine(to: CGPoint(x: x + side * unit * 0.009, y: pad))
            }
        }
        overlayLayer.path = path.cgPath
        overlayLayer.strokeColor = color.withAlphaComponent(0.5).cgColor
        overlayLayer.lineWidth = max(1.2, unit / 600)
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 1)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        darkFieldView.frame = bounds
        graphicsView.frame = bounds
        textView.frame = bounds
        // 光束：自顶部向下贯穿，束宽约屏宽 55%、以屏顶为轴旋转。
        for beam in beamLayers {
            beam.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.55,
                                 height: bounds.height * 1.25)
            beam.position = CGPoint(x: bounds.width / 2, y: -bounds.height * 0.08)
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            // 梯形掩膜：上窄下宽的束形。
            let mask = CAShapeLayer()
            let w = beam.bounds.width, h = beam.bounds.height
            let path = UIBezierPath()
            path.move(to: CGPoint(x: w * 0.32, y: 0))
            path.addLine(to: CGPoint(x: w * 0.68, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.close()
            mask.path = path.cgPath
            mask.fillColor = UIColor.white.cgColor
            beam.mask = mask
        }
        for fog in [fogLayerA, fogLayerB] {
            fog.frame = bounds.insetBy(dx: -bounds.width * 0.15, dy: -bounds.height * 0.15)
        }
        echoLabel.frame = bounds
        lineArtLayer.frame = bounds
        overlayLayer.frame = bounds
        if overlayBuiltSize != bounds.size { overlayBuiltSize = .zero }
        if let container = lineContainer {
            container.center = CGPoint(x: bounds.width / 2, y: bounds.height * 0.52)
        }
    }
}
