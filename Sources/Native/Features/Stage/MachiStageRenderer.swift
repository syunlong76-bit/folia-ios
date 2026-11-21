import UIKit
import SceneKit
import QuartzCore

// 町景 machi 全量原生移植（3.7 (57) 工作流 B7）：网页版
// folia-major/src/components/visualizer/machi/ 是 Three.js
// WebGL 的程序化微缩町景（三场景便利店/加油站/城寨酒吧，
// 歌词逐字点亮在场景里的 LED 屏上）。原生终局 100% 原生、
// 无 WebGL 例外：本文件以 SceneKit 等价重写，不用 WKWebView。
//
// 网页构成 → 原生实现对照（细节数值见各节注释）：
//  - 运行时 createMachiRuntime（渲染器/镜头/天光/天气/湿地
//    面/倒影/后处理/时钟/编排）→ 本类：SCNView + 环境状态机
//    （engine/environment.ts 逐常数移植）+ 编排（director.ts
//    的牌面目标/跑马灯/闪烁逐函数移植）。湿地面/倒影/后处理
//    无 SceneKit 等价通路，以材质高光近似（见未移植清单）。
//  - 场景 scenes/{konbini,station,kowloon}（layout.ts 尺寸
//    表逐值）→ 程序化 SCNBox/SCNPlane/SCNCylinder 体块：
//    底座 12m 见方、街道、町屋/店铺体块、招牌面（文字贴图）、
//    灯笼（发光球/柱）、电线杆/路灯/贩卖机/车辆。几何定额：
//    全场景节点 ≤ ~420、几何体按尺寸复用、材质按角色共享。
//  - 歌词屏 engine/lyricScreen.ts（着色器 LED 屏：像素格/
//    子像素条/逐行点亮）→ 广告塔/货厢/大屏平面 + 一张
//    1024×440 文字贴图：未唱/已唱两色在 CPU 侧按行点亮位
//    置裁切合成（逐字时刻来自 StageLyricUnits，与网页
//    buildLineGraphemeTimeline 同数据源口径）；LED 像素格
//    与刷新带等着色器细节未移植（见清单）。
//  - 镜头 engine/camera.ts（正交斜俯视、构图拟合、运镜
//    resolveMachiDrift 慢正弦、自定义视角、闲置回正）→
//    SCNCamera 正交投影 + 同公式拟合与漂移；拖拽 OrbitControls
//    无原生对应且会与宿主手势打架，改由渲染器自带取景控制
//    条（下方 MachiCameraBarView，对应网页命令
//    visualizer-machi-camera-bar / MachiCameraBar.tsx 的
//    视角/镜头/运镜三页）以滑块调同一套 tuning 视角值。
//  - 环境 engine/environment.ts + sky.ts + palette.ts 的
//    ART 天空色 → 环境状态阻尼追目标（TAU 逐值），天空色
//    按 daylight 在夜/黄昏/白天三套 ART 色之间插值；主题
//    色只经协议 PaletteTokens 进场（brand/屏字/霓虹取
//    accent/primary 近似，网页按完整 Theme 推导，见清单）。
//  - 天气 fx/weather.ts（雨/雪/雾）→ 雨丝/雪片节点池在
//    SCNView 渲染循环里回收推进（氛围时钟，暂停即停，与
//    网页 MachiClock 同纪律：单步钳 0.1s）；雾走场景 fog。
//  - 景深 engine/lens.ts → SCNCamera 的 wantsDepthOfField/
//    focalDistance/focalSize/fStop（focusBand/focusFalloff
//    公式逐值算 focalSize）；移轴无 SceneKit 通路，只存不用。
//  - 节拍 engine/beatFx.ts：协议无音频/鼓点数据源，智能
//    动感三件（霓虹脉冲/涟漪/闪拍）未移植；simulatedBeat
//    开时以 MACHI_BEAT.steady（period 0.75s）驱动霓虹与
//    屏面亮度的固定节拍近似（见 frameTick/渲染循环）。
//
// 时钟纪律：歌词同步元素（牌面目标、逐字点亮、跑马灯文本）
// 只挂宿主 frameTick(position)；环境运镜/天气/闪烁/车辆由
// SCNView 渲染循环驱动（氛围时间，生命周期 paused 时停），
// 路径与速度参数照搬网页 tuning（drift 周期表、TAU、
// flicker 窗口 6.5s、steady 0.75s）。
// 数据只从 snapshot/context 取：曲目/歌词/调色板/视口来自
// 快照，封面经 NativeCoverLoader 按 artworkURL 取一张贴图
// （全舞台封面贴图上限 1 张；文字贴图为程序化小图，合计
// 估算 < 12MB，远低于舞台纹理 200MB 红线）；不预载资源包。
// 场景按 seed 选（auto 时 FNV-1a 哈希与网页 resolveMachiSceneId
// 同公式），同曲恒同场景。

// MARK: - 网页纯函数移植（哈希 / 环境 / 运镜 / 编排）

/// FNV-1a 32 位（visualizerSeedHash.hashVisualizerSeed，
/// 按 UTF-16 码元，与 JS charCodeAt 同序）。
private func machiHashSeed(_ value: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for unit in value.utf16 {
        hash ^= UInt32(unit)
        hash = hash &* 16_777_619
    }
    return hash
}

/// visualizerHash01：mixVisualizerSeed(seed + (index+1)*97, salt) / 2^32。
private func machiHash01(seed: UInt32, index: Int, salt: UInt32) -> Double {
    let mixedSeed = seed &+ UInt32(truncatingIfNeeded: (index + 1) &* 97)
    let mixed = (mixedSeed ^ salt) &* 2_654_435_761
    return Double(mixed) / 4_294_967_296
}

/// 场景 auto 解析（machiTuning.resolveMachiSceneId）。
private func machiResolveScene(tuningScene: MachiSceneChoice, seed: String) -> MachiSceneId {
    if tuningScene != .auto, let id = MachiSceneId(rawValue: tuningScene.rawValue) {
        return id
    }
    let ids = MachiSceneId.allCases
    let index = Int(machiHashSeed("machi-scene:\(seed)") % UInt32(ids.count))
    return ids[index]
}

/// 天气 auto 解析（environment.resolveMachiWeatherKind：
/// 雨 35% / 晴 30% / 雾 20% / 雪 15%）。
private func machiResolveWeatherKind(tuningWeather: MachiWeatherChoice, seed: String) -> MachiWeatherChoice {
    if tuningWeather != .auto { return tuningWeather }
    var roll = machiHash01(seed: machiHashSeed("machi-weather:\(seed)"), index: 0, salt: 0x3d)
    for (kind, weight) in [(MachiWeatherChoice.rain, 0.35), (.clear, 0.30), (.fog, 0.20), (.snow, 0.15)] {
        if roll < weight { return kind }
        roll -= weight
    }
    return .rain
}

private func machiSmoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

/// 本地时钟 → 白天程度（environment.resolveMachiDaylightAt：
/// 05:00–06:30 天亮、06:30–16:30 白天、16:30–17:30 落黄昏
/// 0.45、17:30–18:30 入夜）。
private func machiDaylightAt(hour: Double) -> Double {
    let h = ((hour.truncatingRemainder(dividingBy: 24)) + 24)
        .truncatingRemainder(dividingBy: 24)
    if h >= 5, h < 6.5 { return machiSmoothstep(5, 6.5, h) }
    if h >= 6.5, h < 16.5 { return 1 }
    if h >= 16.5, h < 17.5 { return 1 - (1 - 0.45) * machiSmoothstep(16.5, 17.5, h) }
    if h >= 17.5, h < 18.5 { return 0.45 * (1 - machiSmoothstep(17.5, 18.5, h)) }
    return 0
}

private func machiDaylight(timeOfDay: MachiTimeChoice, now: Date) -> Double {
    switch timeOfDay {
    case .day: return 1
    case .dusk: return 0.45
    case .night: return 0
    case .auto:
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: now))
            + Double(calendar.component(.minute, from: now)) / 60
            + Double(calendar.component(.second, from: now)) / 3600
        return machiDaylightAt(hour: hour)
    }
}

/// 环境状态（environment.MachiEnvironmentState/Target/TAU 逐值）。
private struct MachiEnvironmentState {
    var daylight: Double
    var rain: Double
    var snow: Double
    var fog: Double
    var wetness: Double
    var snowCover: Double

    static func target(daylight: Double, kind: MachiWeatherChoice) -> MachiEnvironmentState {
        MachiEnvironmentState(
            daylight: daylight,
            rain: kind == .rain ? 1 : 0,
            snow: kind == .snow ? 1 : 0,
            fog: kind == .fog ? 1 : 0,
            wetness: kind == .rain ? 1 : (kind == .fog ? 0.35 : 0),
            snowCover: kind == .snow ? 1 : 0)
    }

    mutating func step(toward target: MachiEnvironmentState, delta: Double) {
        guard delta > 0 else { return }
        func approach(_ value: Double, _ goal: Double, _ tau: Double) -> Double {
            let next = value + (goal - value) * (1 - exp(-delta / tau))
            return abs(next - goal) < 1e-3 ? goal : next
        }
        rain = approach(rain, target.rain, 1.4)
        snow = approach(snow, target.snow, 1.4)
        fog = approach(fog, target.fog, 2.2)
        let wetTarget = max(target.rain, target.fog * 0.35)
        wetness = approach(wetness, wetTarget, wetTarget > wetness ? 3 : 20)
        snowCover = approach(snowCover, snow, snow > snowCover ? 8 : 12)
        daylight = approach(daylight, target.daylight, 1.6)
    }
}

/// 运镜偏移（camera.resolveMachiDrift 逐周期/相位移植：
/// 转角/俯仰度、缩放倍数、平移米）。
private func machiDrift(at time: Double)
    -> (azimuth: Double, elevation: Double, zoom: Double, panX: Double, panZ: Double) {
    func wave(_ period: Double, _ phase: Double) -> Double {
        sin((time / period) * Double.pi * 2 + phase)
    }
    return (
        azimuth: 15 * wave(67, 0) + 5 * wave(29, 1.3),
        elevation: 4 * wave(47, 0.7),
        zoom: exp(0.08 * wave(41, 2.1)),
        panX: 0.45 * wave(53, 0.4),
        panZ: 0.3 * wave(71, 2.6))
}

/// 招牌闪烁（director.resolveMachiFlicker：6.5s 窗口、哈希
/// 决定窗口内三下明暗，返回亮度倍数 0.5…1）。
private func machiFlicker(at time: Double, seed: String) -> Double {
    let window = 6.5
    let index = Int(floor(time / window))
    let key = machiHashSeed("flicker:\(seed)")
    if machiHash01(seed: key, index: index, salt: 0x51) > 0.42 { return 1 }
    let offset = machiHash01(seed: key, index: index, salt: 0x7a) * (window - 0.6)
    let local = time - Double(index) * window - offset
    if local < 0 || local > 0.46 { return 1 }
    for (from, to, depth) in [(0.0, 0.07, 0.5), (0.15, 0.20, 0.68), (0.32, 0.36, 0.8)] {
        if local >= from, local <= to { return depth }
    }
    return 1
}

/// 牌面目标（director.resolveMachiBoardTarget：BOARD_LEAD
/// 0.12s 提前亮、行后 BOARD_HOLD 2.6s 留牌，空档回曲名卡；
/// 协议无间奏标记，空行文本近似 interlude 判定）。
private enum MachiBoardTarget: Equatable {
    case card
    case line(Int)
}

private func machiBoardTarget(lines: [LyricLine], time: TimeInterval) -> MachiBoardTarget {
    var index = -1
    for (i, line) in lines.enumerated() {
        if line.start <= time + 0.12 { index = i } else { break }
    }
    guard index >= 0 else { return .card }
    let line = lines[index]
    if line.text.trimmingCharacters(in: .whitespaces).isEmpty { return .card }
    let hold = line.end + 2.6
    if time > hold {
        let next = index + 1 < lines.count ? lines[index + 1] : nil
        if next == nil || next!.start - 0.12 > time { return .card }
    }
    return .line(index)
}

/// 跑马灯文本（director.resolveMachiTickerText 逐分支移植；
/// 协议无译文字段，译文分支恒不触发）。
private func machiTickerText(target: MachiBoardTarget, lines: [LyricLine],
                             title: String, artist: String) -> String {
    switch target {
    case .card:
        return "♪ \(title)\(artist.isEmpty ? "" : " — \(artist)")   ◆   OPEN 24H   ◆   "
    case .line(let index):
        let next = lines.dropFirst(index + 1).first {
            !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if let next { return "NEXT ▸ \(next.text)   " }
        return "♪ \(title)   ◆   "
    }
}

// MARK: - 颜色与向量小工具

private func machiColor(hex: String) -> UIColor {
    var value: UInt64 = 0
    var text = hex
    if text.hasPrefix("#") { text.removeFirst() }
    Scanner(string: text).scanHexInt64(&value)
    return UIColor(red: CGFloat((value >> 16) & 0xff) / 255,
                   green: CGFloat((value >> 8) & 0xff) / 255,
                   blue: CGFloat(value & 0xff) / 255, alpha: 1)
}

private func machiMix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                   blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
}

/// 天空色按 daylight 在夜/黄昏/白天之间插值（palette ART 三套）。
private func machiSkyColor(daylight: Double, night: UIColor, dusk: UIColor, day: UIColor) -> UIColor {
    if daylight <= 0.45 {
        return machiMix(night, dusk, CGFloat(daylight / 0.45))
    }
    return machiMix(dusk, day, CGFloat((daylight - 0.45) / 0.55))
}

private func machiCross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func machiNormalized(_ v: SCNVector3) -> SCNVector3 {
    let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    guard length > 1e-6 else { return v }
    return SCNVector3(v.x / length, v.y / length, v.z / length)
}

private func machiDot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
    a.x * b.x + a.y * b.y + a.z * b.z
}

// MARK: - 文字贴图

/// 程序化文字贴图（signRaster 的原生落点：UIGraphics 绘制，
/// 不加载任何字体/图片资源包）。
private enum MachiTextTexture {
    static func image(size: CGSize, draw: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, size)
        }
    }

    /// 单行居中文字图（招牌用）。
    static func sign(text: String, size: CGSize, background: UIColor,
                     foreground: UIColor, fontSize: CGFloat) -> UIImage {
        image(size: size) { context, canvas in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let font = UIFont(name: "STSongti-SC-Bold", size: fontSize)
                ?? .boldSystemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: foreground,
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let textSize = string.size()
            string.draw(at: CGPoint(x: (canvas.width - textSize.width) / 2,
                                    y: (canvas.height - textSize.height) / 2))
        }
    }
}

// MARK: - 渲染器

final class MachiStageRenderer: NSObject, LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    private let rootView = LyricStageRootView()
    private let sceneView = SCNView()
    private let cameraBar = MachiCameraBarView()
    private let cameraBarToggle = UIButton(type: .system)

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false
    private var lifecycleState: LyricStageLifecycleState = .created

    // 场景状态
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let sceneRoot = SCNNode()
    private var builtSceneId: MachiSceneId?
    private var builtTrackId: String?
    private var builtPalette: PaletteTokens?
    private var focusPoint = SCNVector3(0, 4, 0)
    private var framingPoints: [SCNVector3] = []
    private var framingView = (azimuth: 45.0, elevation: 31.0, zoom: 1.58)
    private var fitCenter = SCNVector3()
    private var fitUp = SCNVector3(0, 1, 0)
    private var fitHalf = (width: 9.0, height: 7.0)

    // 动态节点（渲染循环驱动）
    private var sunLight: SCNLight?
    private var sunNode: SCNNode?
    private var ambientLight: SCNLight?
    private var warmLight: SCNLight?
    private var lampMaterials: [SCNMaterial] = []
    private var neonMaterials: [SCNMaterial] = []
    private var boardMaterial: SCNMaterial?
    private var tickerMaterial: SCNMaterial?
    private var coverMaterial: SCNMaterial?
    private var rainNodes: [SCNNode] = []
    private var snowNodes: [SCNNode] = []
    private var carNodes: [SCNNode] = []
    private var rainMaterial: SCNMaterial?
    private var snowMaterial: SCNMaterial?
    /// 辉光开关的发光强度系数（applyQuality 写、渲染循环读：
    /// SceneKit 无 bloom 通路，开关以发光强度承载）。
    private var glowScale: CGFloat = 1

    // 环境与氛围时钟（environment/clock 移植）
    private var environment = MachiEnvironmentState.target(daylight: 0, kind: .rain)
    private var environmentTarget = MachiEnvironmentState.target(daylight: 0, kind: .rain)
    private var ambientTime: Double = 0
    private var lastRenderTime: TimeInterval = -1
    private var motionTime: Double = 0
    private var motionWeight: Double = 0
    private var cameraDirty = true
    private var lastTuning: MachiTuningValues?

    // 歌词牌面（frameTick 驱动）
    private var boardTarget: MachiBoardTarget?
    private var boardRevealBucket: Int = -1
    private var boardTextureSize = CGSize(width: 1024, height: 440)
    private var coverTask: Task<Void, Never>?
    private var coverTrackId: String?

    override init() {
        view = rootView
        super.init()
        rootView.backgroundColor = machiColor(hex: "#0e1524")
        sceneView.scene = scene
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.isPlaying = false
        sceneView.rendersContinuously = false
        sceneView.delegate = self
        scene.rootNode.addChildNode(sceneRoot)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 200
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
        rootView.addSubview(sceneView)

        // 取景控制条开关（对应网页命令 visualizer-machi-camera-bar
        // 与控制面板的摄影机按钮：打开取景条、再点收起）。
        cameraBarToggle.setTitle("取景", for: .normal)
        cameraBarToggle.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        cameraBarToggle.setTitleColor(.white, for: .normal)
        cameraBarToggle.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        cameraBarToggle.layer.cornerRadius = 15
        cameraBarToggle.addTarget(self, action: #selector(toggleCameraBar), for: .touchUpInside)
        rootView.addSubview(cameraBarToggle)

        cameraBar.isHidden = true
        cameraBar.onClose = { [weak self] in self?.setCameraBar(open: false) }
        rootView.addSubview(cameraBar)
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
        let tuning = MachiTuningStore.valuesCached(now: CACurrentMediaTime())
        let seed = snapshot.track?.id ?? "machi"
        let sceneId = machiResolveScene(tuningScene: tuning.scene, seed: seed)
        let trackChanged = snapshot.track?.id != builtTrackId
        let paletteChanged = snapshot.palette != builtPalette
        if sceneId != builtSceneId || trackChanged {
            buildScene(id: sceneId, snapshot: snapshot)
        } else if paletteChanged {
            builtPalette = snapshot.palette
            refreshSignTextures()
            redrawBoard()
        }
        retargetEnvironment(tuning: tuning, seed: seed)
        if trackChanged {
            boardTarget = nil
            boardRevealBucket = -1
            loadCover(for: snapshot)
        }
        cameraDirty = true
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        lifecycleState = state
        isActive = active && state != .destroyed
        sceneView.isPlaying = isActive
        sceneView.rendersContinuously = isActive
        if !isActive { lastRenderTime = -1 }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let tuning = MachiTuningStore.valuesCached(now: CACurrentMediaTime())
        if tuning != lastTuning {
            let previous = lastTuning
            lastTuning = tuning
            applyTuningChange(tuning, previous: previous, snapshot: snapshot)
        }
        // 牌面目标与逐字点亮只在此推进（时钟纪律）。
        let target = machiBoardTarget(lines: snapshot.lines, time: position)
        if target != boardTarget {
            boardTarget = target
            boardRevealBucket = -1
            refreshTicker()
            redrawBoard()
        } else if case .line(let index) = target {
            let bucket = revealBucket(line: snapshot.lines[index], position: position)
            if bucket != boardRevealBucket {
                boardRevealBucket = bucket
                redrawBoard()
            }
        }
        updateLens(tuning: tuning)
    }

    func unmount() {
        isActive = false
        sceneView.isPlaying = false
        sceneView.rendersContinuously = false
        sceneView.delegate = nil
        coverTask?.cancel()
        coverTask = nil
        coverMaterial?.diffuse.contents = nil
        sceneRoot.childNodes.forEach { $0.removeFromParentNode() }
        builtSceneId = nil
        context = nil
        snapshot = nil
    }

    // MARK: 调参变化落点

    private func applyTuningChange(_ tuning: MachiTuningValues,
                                   previous: MachiTuningValues?,
                                   snapshot: LyricStageSnapshot) {
        let seed = snapshot.track?.id ?? "machi"
        let sceneId = machiResolveScene(tuningScene: tuning.scene, seed: seed)
        if sceneId != builtSceneId {
            buildScene(id: sceneId, snapshot: snapshot)
        }
        retargetEnvironment(tuning: tuning, seed: seed)
        applyQuality(tuning.quality)
        cameraDirty = true
    }

    private func retargetEnvironment(tuning: MachiTuningValues, seed: String) {
        let kind = machiResolveWeatherKind(tuningWeather: tuning.weather, seed: seed)
        let daylight = machiDaylight(timeOfDay: tuning.timeOfDay, now: Date())
        environmentTarget = MachiEnvironmentState.target(daylight: daylight, kind: kind)
        if builtSceneId == nil {
            environment = environmentTarget
        }
    }

    private func applyQuality(_ quality: MachiQualityValues) {
        // 抗锯齿（网页 antialias 档 → SCNView 口径）：global/smaa
        // → MSAA 4×；fxaa 近似 MSAA 4×（SceneKit 无 FXAA 开关）；
        // ssaa → 渲染倍率 2 由 contentScale 近似不到，退 MSAA 4×；
        // off → 无。
        switch quality.antialias {
        case "off": sceneView.antialiasingMode = .none
        default: sceneView.antialiasingMode = .multisampling4X
        }
        // 阴影：off 关方向光投影；low/high 只差影图尺寸，SCNView
        // 无逐光尺寸外的画质差，统一以 castsShadow 承载。
        sunLight?.castsShadow = quality.shadows != .off
        // 辉光：无 bloom 后处理通路，以发光材质强度承载开关
        // （渲染循环逐帧写 emission.intensity 时乘此系数）。
        glowScale = quality.glow ? 1 : 0.35
    }

    // MARK: 景深（lens.ts 移植）

    /// resolveMachiLens：open = 8/aperture；depth = dofRange/zoom；
    /// focusBand = 3.4·depth/open；focusFalloff = 7.5·depth/√open；
    /// coc = 0.012·dof·open（SceneKit 无 coc 直通量，focalSize
    /// 取 focusBand、离焦强度由 fStop 承载，为近似落点）。
    private func updateLens(tuning: MachiTuningValues) {
        guard let camera = cameraNode.camera else { return }
        let zoom = currentRestZoom(tuning: tuning)
        let open = 8 / max(tuning.aperture, 0.1)
        let depth = tuning.dofRange / max(zoom, 1e-3)
        let focusBand = 3.4 * depth / open
        camera.wantsDepthOfField = tuning.dof > 0
        guard tuning.dof > 0 else { return }
        let centerDistance = Double(cameraNode.position.x * cameraNode.position.x
            + cameraNode.position.y * cameraNode.position.y
            + cameraNode.position.z * cameraNode.position.z).squareRoot()
        // 对焦距离：center = 相机到目标点（构图中心近似取相机
        // 距原点距离的投影，运行时以 focusPoint 深度为准）；
        // lyrics = 歌词屏中心深度；manual = center + focusOffset。
        let lyricsDepth = depthOf(point: focusPoint)
        switch tuning.focus {
        case .center:
            camera.focalDistance = CGFloat(max(centerDistance, 1))
        case .lyrics:
            camera.focalDistance = CGFloat(max(lyricsDepth, 1))
        case .manual:
            camera.focalDistance = CGFloat(max(centerDistance + tuning.focusOffset, 1))
        }
        camera.focalSize = CGFloat(max(focusBand, 0.1))
        camera.fStop = CGFloat(tuning.aperture)
        _ = open
    }

    /// 某点沿视线深度（camera.depthOf 移植）。
    private func depthOf(point: SCNVector3) -> Double {
        let target = currentTarget ?? fitCenter
        let forward = machiNormalized(SCNVector3(
            target.x - cameraNode.position.x,
            target.y - cameraNode.position.y,
            target.z - cameraNode.position.z))
        let delta = SCNVector3(point.x - cameraNode.position.x,
                               point.y - cameraNode.position.y,
                               point.z - cameraNode.position.z)
        return Double(machiDot(delta, forward))
    }

    private var currentTarget: SCNVector3?

    private func currentRestZoom(tuning: MachiTuningValues) -> Double {
        var zoom = framingView.zoom
        if tuning.camera == .custom, let sceneId = builtSceneId {
            zoom *= tuning.view(for: sceneId).zoom
        }
        return min(3.6, max(0.75, zoom))
    }
}

// MARK: - 场景构建（scenes/ 布局表逐值）

extension MachiStageRenderer {

    /// 材质工厂（按角色共享，不逐节点新建）。
    private func material(color: UIColor, emission: UIColor? = nil,
                          emissionIntensity: CGFloat = 1,
                          roughness: CGFloat = 0.9) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = roughness
        if let emission {
            material.emission.contents = emission
            material.emission.intensity = emissionIntensity
        }
        return material
    }

    private func box(size: SCNVector3, position: SCNVector3,
                     material: SCNMaterial, name: String) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y),
                              length: CGFloat(size.z), chamferRadius: 0)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.name = name
        return node
    }

    private func plane(width: CGFloat, height: CGFloat, position: SCNVector3,
                       rotationY: CGFloat = 0, material: SCNMaterial,
                       name: String) -> SCNNode {
        let geometry = SCNPlane(width: width, height: height)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.eulerAngles.y = Float(rotationY)
        node.name = name
        return node
    }

    private func pole(position: SCNVector3, height: CGFloat, radius: CGFloat,
                      material: SCNMaterial, name: String) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(position.x, position.y + Float(height / 2), position.z)
        node.name = name
        return node
    }

    /// 场景重建：拆旧建新（引擎换场景同纪律：上下文留着）。
    /// 布局数值逐值取自三场景 layout.ts（原点底座中心、y 上、
    /// +z 前、+x 右，单位米）。
    func buildScene(id: MachiSceneId, snapshot: LyricStageSnapshot) {
        sceneRoot.childNodes.forEach { $0.removeFromParentNode() }
        lampMaterials = []
        neonMaterials = []
        rainNodes = []
        snowNodes = []
        carNodes = []
        builtSceneId = id
        builtTrackId = snapshot.track?.id
        builtPalette = snapshot.palette
        let palette = snapshot.palette

        // 灯光组：环境（半球光近似）+ 方向光（日/月）+ 暖点光。
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 0.7
        ambientLight = ambient
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        sceneRoot.addChildNode(ambientNode)
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1.4
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sunLight = sun
        let sunHolder = SCNNode()
        sunHolder.light = sun
        sunHolder.position = SCNVector3(18, 26, 12)
        sunHolder.look(at: SCNVector3(0, 0, 0))
        sunNode = sunHolder
        sceneRoot.addChildNode(sunHolder)
        let warm = SCNLight()
        warm.type = .omni
        warm.intensity = 40
        warm.attenuationStartDistance = 2
        warm.attenuationEndDistance = 16
        warmLight = warm
        let warmNode = SCNNode()
        warmNode.light = warm
        warmNode.position = SCNVector3(0, 3, 0)
        sceneRoot.addChildNode(warmNode)

        // 底座（BASE：12m 见方、0.6 厚、顶面 y=0）。
        let plinthMaterial = material(color: machiColor(hex: "#20242c"))
        sceneRoot.addChildNode(box(
            size: SCNVector3(12, 0.6, 12), position: SCNVector3(0, -0.3, 0),
            material: plinthMaterial, name: "plinth"))
        let asphalt = material(color: machiColor(hex: "#2a303c"), roughness: 0.6)
        let concrete = material(color: machiColor(hex: "#4b5363"))
        let roadPaint = material(color: machiColor(hex: "#c9d1dc"))
        _ = roadPaint

        // 牌面/跑马灯/封面材质（贴图在 refresh/redraw 时灌入）。
        let board = SCNMaterial()
        board.diffuse.contents = machiColor(hex: "#101623")
        board.emission.contents = UIColor.white
        board.emission.intensity = 0.85
        boardMaterial = board
        let ticker = SCNMaterial()
        ticker.diffuse.contents = machiColor(hex: "#0a0d14")
        ticker.emission.contents = UIColor.white
        ticker.emission.intensity = 0.9
        ticker.diffuse.wrapS = .repeat
        tickerMaterial = ticker
        let cover = SCNMaterial()
        cover.diffuse.contents = palette.background
        coverMaterial = cover

        switch id {
        case .konbini: buildKonbini(palette: palette, asphalt: asphalt, concrete: concrete)
        case .station: buildStation(palette: palette, asphalt: asphalt, concrete: concrete)
        case .kowloon: buildKowloon(palette: palette, asphalt: asphalt, concrete: concrete)
        }
        buildWeatherNodes()
        computeFraming(id: id)
        refreshSignTextures()
        redrawBoard()
        refreshTicker()
        let tuning = MachiTuningStore.valuesCached(now: CACurrentMediaTime())
        applyQuality(tuning.quality)
        cameraDirty = true
        cameraBar.setScene(id, tuning: tuning)
    }

    // MARK: 便利店 konbini（layout.ts：STORE/ROAD/BOARD/PROPS）

    private func buildKonbini(palette: PaletteTokens, asphalt: SCNMaterial, concrete: SCNMaterial) {
        framingView = (azimuth: 45 * .pi / 180, elevation: 31 * .pi / 180, zoom: 1.58)
        // 两条路：前（+z）沿 x、右（+x）沿 z，内 2.2 外 5.5。
        let roadFront = plane(width: 12, height: 3.3,
            position: SCNVector3(0, 0.01, 3.85), material: asphalt, name: "roadFront")
        roadFront.rotation.x = -.pi / 2
        sceneRoot.addChildNode(roadFront)
        let roadSide = plane(width: 3.3, height: 12,
            position: SCNVector3(3.85, 0.01, 0), material: asphalt, name: "roadSide")
        roadSide.rotation.x = -.pi / 2
        sceneRoot.addChildNode(roadSide)
        // 店体：x[−5.4, 0.8]、z[−5.4, 0.4]、墙高 3.2。
        let wallMaterial = material(color: machiColor(hex: "#d8d3c8"))
        sceneRoot.addChildNode(box(
            size: SCNVector3(6.2, 3.2, 5.8), position: SCNVector3(-2.3, 1.6 + 0.16, -2.5),
            material: wallMaterial, name: "store"))
        // 落地玻璃（前面 + 右面前段）与自动门。
        let glass = material(color: machiColor(hex: "#9cc3e6"), roughness: 0.15)
        glass.transparency = 0.55
        sceneRoot.addChildNode(plane(width: 5.4, height: 2.26,
            position: SCNVector3(-2.5, 0.24 + 1.13 + 0.16, 0.42),
            material: glass, name: "glassFront"))
        let doorMaterial = material(color: palette.accent, emission: palette.accent, emissionIntensity: 0.25)
        sceneRoot.addChildNode(plane(width: 0.92, height: 2.2,
            position: SCNVector3(-0.86, 1.1 + 0.16, 0.44), material: doorMaterial, name: "doorL"))
        sceneRoot.addChildNode(plane(width: 0.92, height: 2.2,
            position: SCNVector3(0.06, 1.1 + 0.16, 0.44), material: doorMaterial, name: "doorR"))
        // 店招带 FASCIA y[2.6, 3.28]：品牌三色条（主题色近似）+ 店名牌。
        let brandColors = [palette.accent, machiColor(hex: "#f4f1ea"), palette.secondary]
        for (index, color) in brandColors.enumerated() {
            let stripe = material(color: color, emission: color, emissionIntensity: 0.35)
            neonMaterials.append(stripe)
            sceneRoot.addChildNode(box(
                size: SCNVector3(6.44, 0.2, 0.16),
                position: SCNVector3(-2.3, Float(3.18 - CGFloat(index) * 0.21) + 0.16, 0.48),
                material: stripe, name: "fascia\(index)"))
        }
        // 屋顶广告塔 BOARD：中心 (−2.2, −2.65)、面 5.6×2.3、
        // y0 4.0、法线方位 45°；正面为歌词屏，另两面同材质近似
        // （网页三角柱三面共用同一着色器材质）。
        let boardAngle = Float(45 * Double.pi / 180)
        let boardCenter = SCNVector3(-2.2, 4.0 + 1.15, -2.65)
        let towerMaterial = material(color: machiColor(hex: "#232833"))
        let tower = box(size: SCNVector3(5.6, 2.3, 0.35), position: boardCenter,
                        material: towerMaterial, name: "boardTower")
        tower.eulerAngles.y = boardAngle
        sceneRoot.addChildNode(tower)
        let boardFace = plane(width: 5.6, height: 2.3, position: SCNVector3(
                boardCenter.x + sin(boardAngle) * 0.19, boardCenter.y,
                boardCenter.z + cos(boardAngle) * 0.19),
            rotationY: CGFloat(boardAngle), material: boardMaterial!, name: "boardFace")
        sceneRoot.addChildNode(boardFace)
        focusPoint = boardCenter
        // 封面海报：店面玻璃一角（全舞台唯一封面贴图落点）。
        sceneRoot.addChildNode(plane(width: 1.1, height: 1.1,
            position: SCNVector3(-4.6, 1.35, 0.45), material: coverMaterial!,
            name: "coverPoster"))
        // 道具：电线杆（−5.3, 1.96, 高 7.6）、路灯（5.74, −1.2,
        // 高 5.2）、贩卖机两台（x 0.82、z −3.25/−4.3）。
        let poleMaterial = material(color: machiColor(hex: "#979ca4"))
        sceneRoot.addChildNode(pole(position: SCNVector3(-5.3, 0, 1.96), height: 7.6,
            radius: 0.09, material: poleMaterial, name: "utilityPole"))
        sceneRoot.addChildNode(pole(position: SCNVector3(5.74, 0, -1.2), height: 5.2,
            radius: 0.07, material: poleMaterial, name: "streetLampPole"))
        addLamp(at: SCNVector3(5.0, 5.2, -1.2), palette: palette)
        let vendingMaterial = material(color: palette.secondary,
                                       emission: machiColor(hex: "#d4ebff"), emissionIntensity: 0.5)
        lampMaterials.append(vendingMaterial)
        for z in [-3.25, -4.3] {
            sceneRoot.addChildNode(box(
                size: SCNVector3(1.0, 1.83, 0.74),
                position: SCNVector3(0.82 + 0.6, Float(1.83 / 2), Float(z)),
                material: vendingMaterial, name: "vending"))
        }
        // 灯笼串：招带下沿一排发光小球（町景氛围件）。
        for index in 0..<6 {
            addLamp(at: SCNVector3(Float(-5.0 + CGFloat(index) * 1.05), 2.5, 0.62),
                    palette: palette, radius: 0.11)
        }
        // 一辆过路车（actors/traffic 的简化：沿前路往复）。
        let car = makeCar(color: palette.primary)
        car.position = SCNVector3(-7, 0, 3.4)
        sceneRoot.addChildNode(car)
        carNodes.append(car)
    }

    // MARK: 加油站 station（layout.ts：CANOPY/TRUCK/STALLS）

    private func buildStation(palette: PaletteTokens, asphalt: SCNMaterial, concrete: SCNMaterial) {
        framingView = (azimuth: 25 * .pi / 180, elevation: 30 * .pi / 180, zoom: 1.48)
        let road = plane(width: 12, height: 3.65, position: SCNVector3(0, 0.01, 4.17),
                         material: asphalt, name: "road")
        road.rotation.x = -.pi / 2
        sceneRoot.addChildNode(road)
        let apron = plane(width: 4.8, height: 6.4, position: SCNVector3(3.6, 0.06, -2.8),
                          material: concrete, name: "apron")
        apron.rotation.x = -.pi / 2
        sceneRoot.addChildNode(apron)
        // 罩棚：x[1.4, 5.9]、z[−5.6, −1.4]、底 3.85 顶 4.3、四柱。
        let canopyMaterial = material(color: machiColor(hex: "#e8e4da"))
        sceneRoot.addChildNode(box(
            size: SCNVector3(4.5, 0.45, 4.2), position: SCNVector3(3.65, (3.85 + 4.3) / 2, -3.5),
            material: canopyMaterial, name: "canopy"))
        let brandStripe = material(color: palette.accent, emission: palette.accent,
                                    emissionIntensity: 0.4)
        neonMaterials.append(brandStripe)
        sceneRoot.addChildNode(box(
            size: SCNVector3(4.5, 0.3, 0.1), position: SCNVector3(3.65, 4.0, -1.36),
            material: brandStripe, name: "canopyBrand"))
        let columnMaterial = material(color: machiColor(hex: "#8a94a1"))
        for (x, z) in [(2.05, -2.1), (5.25, -2.1), (2.05, -4.9), (5.25, -4.9)] {
            sceneRoot.addChildNode(pole(position: SCNVector3(Float(x), 0, Float(z)),
                height: 3.85, radius: 0.12, material: columnMaterial, name: "column"))
        }
        // 加油岛两座、各两台加油机。
        let pumpMaterial = material(color: machiColor(hex: "#c7302b"),
                                    emission: palette.accent, emissionIntensity: 0.2)
        for z in [-4.35, -2.75] {
            sceneRoot.addChildNode(box(
                size: SCNVector3(2.4, 0.16, 0.5), position: SCNVector3(3.65, 0.08, Float(z)),
                material: concrete, name: "island"))
            for x in [3.05, 4.25] {
                sceneRoot.addChildNode(box(
                    size: SCNVector3(0.5, 1.1, 0.4), position: SCNVector3(Float(x), 0.55, Float(z)),
                    material: pumpMaterial, name: "pump"))
            }
        }
        // 货车：厢 x[−5.85, −0.7]、z[−5.7, −3.6]、顶 3.4；
        // 侧面屏 TRUCK_SCREEN（中心 y≈2.19、4.79×2.02）为歌词屏。
        let truckMaterial = material(color: machiColor(hex: "#3d4657"))
        sceneRoot.addChildNode(box(
            size: SCNVector3(5.15, 2.4, 2.1), position: SCNVector3(-3.27, 1.0 + 1.2, -4.65),
            material: truckMaterial, name: "truckBox"))
        sceneRoot.addChildNode(plane(
            width: 4.79, height: 2.02,
            position: SCNVector3(-3.27, 2.19, -3.57),
            material: boardMaterial!, name: "truckScreen"))
        focusPoint = SCNVector3(-3.27, 2.19, -3.57)
        sceneRoot.addChildNode(box(
            size: SCNVector3(1.65, 1.75, 1.9), position: SCNVector3(0.27, 0.87, -4.65),
            material: truckMaterial, name: "truckCab"))
        // 价格立柱（5.35, 1.75, 高 4.1）挂封面、旅馆高牌（−5.25, 1.85, 高 6.4）。
        sceneRoot.addChildNode(pole(position: SCNVector3(5.35, 0, 1.75), height: 4.1,
            radius: 0.09, material: columnMaterial, name: "pylon"))
        sceneRoot.addChildNode(plane(width: 1.0, height: 1.0,
            position: SCNVector3(5.35, 3.6, 1.86), material: coverMaterial!, name: "coverPoster"))
        sceneRoot.addChildNode(pole(position: SCNVector3(-5.25, 0, 1.85), height: 6.4,
            radius: 0.09, material: columnMaterial, name: "motelPole"))
        let motelMaterial = material(color: palette.secondary, emission: palette.secondary,
                                     emissionIntensity: 0.5)
        neonMaterials.append(motelMaterial)
        sceneRoot.addChildNode(plane(width: 1.6, height: 0.9,
            position: SCNVector3(-5.25, 5.9, 1.96), material: motelMaterial, name: "motelSign"))
        // 前排三辆停车 + 加油区一辆 + 过路车一辆。
        for x in [-4.75, -2.85, -0.95] {
            let car = makeCar(color: palette.primary)
            car.position = SCNVector3(Float(x), 0, -0.3)
            car.eulerAngles.y = .pi
            sceneRoot.addChildNode(car)
        }
        let pumpCar = makeCar(color: palette.accent)
        pumpCar.position = SCNVector3(3.65, 0, -0.95)
        pumpCar.eulerAngles.y = .pi / 2
        sceneRoot.addChildNode(pumpCar)
        let traffic = makeCar(color: palette.secondary)
        traffic.position = SCNVector3(-7, 0, 3.36)
        sceneRoot.addChildNode(traffic)
        carNodes.append(traffic)
        addLamp(at: SCNVector3(0.9, 5.0, 1.85), palette: palette)
        for index in 0..<4 {
            addLamp(at: SCNVector3(Float(1.8 + CGFloat(index) * 1.2), 3.7, -1.2),
                    palette: palette, radius: 0.1)
        }
    }

    // MARK: 城寨酒吧 kowloon（layout.ts：BLOCKS/BAR/SCREEN）

    private func buildKowloon(palette: PaletteTokens, asphalt: SCNMaterial, concrete: SCNMaterial) {
        framingView = (azimuth: 30 * .pi / 180, elevation: 30 * .pi / 180, zoom: 1.55)
        let ground = plane(width: 12, height: 12, position: SCNVector3(0, 0.02, 0),
                           material: asphalt, name: "alley")
        ground.rotation.x = -.pi / 2
        sceneRoot.addChildNode(ground)
        // 十栋楼（BLOCKS 逐值：左排 L0–L5 + 后排 B0/B0b/B1/B2）。
        let blocks: [(String, Double, Double, Double, Double, Double, String)] = [
            ("L0", -6, -3.0, -6, -1.8, 6.9, "#6b5a4e"), ("L1", -6, -3.35, -1.8, -0.2, 7.3, "#5d6a72"),
            ("L2", -6, -3.6, -0.2, 1.3, 6.6, "#71624f"), ("L3", -6, -3.2, 1.3, 2.9, 6.2, "#4f5d68"),
            ("L4", -6, -3.45, 2.9, 4.5, 5.2, "#65584c"), ("L5", -6, -3.75, 4.5, 6, 4.0, "#71624f"),
            ("B0", -3.0, -1.6, -6, -1.8, 6.4, "#65584c"), ("B0b", -1.6, -0.3, -6, -2.05, 7.0, "#4f5d68"),
            ("B1", -0.3, 4.5, -6, -1.5, 6.2, "#6b5a4e"), ("B2", 4.5, 6, -6, -2.3, 5.4, "#5d6a72"),
        ]
        let windowMaterial = material(color: machiColor(hex: "#ffc887"),
                                      emission: machiColor(hex: "#ffc887"), emissionIntensity: 0.55)
        lampMaterials.append(windowMaterial)
        for (name, x0, x1, z0, z1, height, hex) in blocks {
            let wallMaterial = material(color: machiColor(hex: hex))
            sceneRoot.addChildNode(box(
                size: SCNVector3(Float(x1 - x0), Float(height), Float(z1 - z0)),
                position: SCNVector3(Float((x0 + x1) / 2), Float(height / 2), Float((z0 + z1) / 2)),
                material: wallMaterial, name: name))
            // 楼面窗格（朝巷子一面贴小发光面，密度按楼高取整）。
            let faceX = Float(x1)
            let rows = max(1, Int(height) - 2)
            for row in 0..<rows {
                let window = plane(width: 0.34, height: 0.4,
                    position: SCNVector3(faceX + 0.02, Float(1.2 + Double(row) * 1.0),
                                         Float((z0 + z1) / 2)),
                    rotationY: .pi / 2, material: windowMaterial, name: "window")
                if name.hasPrefix("B") {
                    window.position = SCNVector3(Float((x0 + x1) / 2),
                                                 Float(1.2 + Double(row) * 1.0), Float(z1) + 0.02)
                    window.eulerAngles.y = 0
                }
                sceneRoot.addChildNode(window)
            }
        }
        // 酒吧 B1 一楼：玻璃门面（z −1.62）+ 暖内光 + 吧台。
        let glass = material(color: machiColor(hex: "#9cc3e6"), roughness: 0.15)
        glass.transparency = 0.45
        sceneRoot.addChildNode(plane(width: 4.4, height: 2.95,
            position: SCNVector3(2.1, 1.47, -1.6), material: glass, name: "barGlass"))
        let interior = material(color: machiColor(hex: "#ffc887"),
                                emission: machiColor(hex: "#ffc887"), emissionIntensity: 0.7)
        lampMaterials.append(interior)
        sceneRoot.addChildNode(plane(width: 4.4, height: 2.95,
            position: SCNVector3(2.1, 1.47, -4.15), material: interior, name: "barInterior"))
        // 门头霓虹（曲名牌，贴图在 refreshSignTextures 灌入）、
        // 跑马灯 TICKER（2.1, 3.09, 4.2×0.17）、大屏 SCREEN
        // （2.1, 4.22, 4.2×1.8）为歌词屏。
        let barSignMaterial = SCNMaterial()
        barSignMaterial.emission.contents = UIColor.white
        barSignMaterial.emission.intensity = 0.9
        barSignMaterial.diffuse.contents = machiColor(hex: "#1a0f14")
        neonMaterials.append(barSignMaterial)
        barSignMaterial.name = "barSign"
        sceneRoot.addChildNode(plane(width: 3.9, height: 0.46,
            position: SCNVector3(2.1, 2.68, -1.38), material: barSignMaterial, name: "barSign"))
        sceneRoot.addChildNode(plane(width: 4.2, height: 0.17,
            position: SCNVector3(2.1, 3.09, -1.41), material: tickerMaterial!, name: "ticker"))
        sceneRoot.addChildNode(plane(width: 4.2, height: 1.8,
            position: SCNVector3(2.1, 4.22, -1.38), material: boardMaterial!, name: "screen"))
        focusPoint = SCNVector3(2.1, 4.22, -1.38)
        // 伸出招牌 HANGING_SIGNS：8 块（轴/墙/尖/y/位逐值），
        // artist 牌写歌手、其余写店名占位字（贴图刷新时灌入）。
        let hanging: [(String, Double, Double, Double, Double, Double, Bool)] = [
            ("x", -3.45, -2.65, 2.95, 4.75, 3.65, true), ("x", -3.6, -1.35, 5.15, 5.95, 0.55, false),
            ("x", -3.35, -2.67, 3.3, 5.5, -0.85, true), ("x", -3.2, -1.45, 3.45, 4.2, 2.25, false),
            ("x", -3.2, -1.95, 4.45, 5.05, 1.5, false), ("x", -3.75, -3.1, 2.6, 3.75, 5.25, true),
            ("z", -2.05, -1.3, 3.4, 5.7, -0.72, true), ("z", -1.8, -1.25, 4.0, 5.5, -2.2, true),
        ]
        for (index, sign) in hanging.enumerated() {
            let signMaterial = SCNMaterial()
            signMaterial.emission.contents = UIColor.white
            signMaterial.emission.intensity = 0.8
            signMaterial.diffuse.contents = machiColor(hex: "#14100e")
            signMaterial.name = "hanging\(index)"
            neonMaterials.append(signMaterial)
            let depth = abs(sign.2 - sign.1)
            let center = (sign.1 + sign.2) / 2
            let height = sign.4 - sign.3
            let node: SCNNode
            if sign.0 == "x" {
                node = plane(width: CGFloat(depth), height: CGFloat(height),
                             position: SCNVector3(Float(center), Float((sign.3 + sign.4) / 2), Float(sign.5)),
                             rotationY: .pi / 2, material: signMaterial, name: "hanging\(index)")
            } else {
                node = plane(width: CGFloat(depth), height: CGFloat(height),
                             position: SCNVector3(Float(sign.5), Float((sign.3 + sign.4) / 2), Float(center)),
                             material: signMaterial, name: "hanging\(index)")
            }
            sceneRoot.addChildNode(node)
        }
        // 楼顶广告架 ROOF_BILLBOARD（「九龍城寨」字牌）。
        let roofMaterial = SCNMaterial()
        roofMaterial.emission.contents = UIColor.white
        roofMaterial.emission.intensity = 0.85
        roofMaterial.diffuse.contents = machiColor(hex: "#160b10")
        roofMaterial.name = "roofBillboard"
        neonMaterials.append(roofMaterial)
        sceneRoot.addChildNode(plane(width: 2.5, height: 0.9,
            position: SCNVector3(1.2, 7.05, -2.13), material: roofMaterial, name: "roofBillboard"))
        // 全息面板（下一句，hologram.ts 的简化：半透明牌面）。
        let holoMaterial = SCNMaterial()
        holoMaterial.diffuse.contents = palette.accent.withAlphaComponent(0.25)
        holoMaterial.emission.contents = palette.accent
        holoMaterial.emission.intensity = 0.5
        holoMaterial.transparency = 0.75
        holoMaterial.name = "hologram"
        neonMaterials.append(holoMaterial)
        let holo = plane(width: 3.0, height: 1.1, position: SCNVector3(0.9, 3.0, 2.3),
                         rotationY: CGFloat(30 * Double.pi / 180),
                         material: holoMaterial, name: "hologram")
        sceneRoot.addChildNode(holo)
        // 大排档 + 电线杆 + 红灯笼串（巷子氛围）。
        sceneRoot.addChildNode(box(
            size: SCNVector3(1.75, 1.0, 0.95), position: SCNVector3(4.97, 0.5, 1.77),
            material: material(color: machiColor(hex: "#3f6212")), name: "stall"))
        sceneRoot.addChildNode(pole(position: SCNVector3(5.55, 0, -1.15), height: 7.0,
            radius: 0.08, material: material(color: machiColor(hex: "#383e49")), name: "pole"))
        addLamp(at: SCNVector3(4.6, 5.05, -1.15), palette: palette)
        for index in 0..<5 {
            addLamp(at: SCNVector3(Float(-2.6 + CGFloat(index) * 1.3), 3.4, 0.6),
                    palette: palette, radius: 0.13, color: machiColor(hex: "#e2402f"))
        }
        // 封面：酒吧玻璃内侧海报。
        sceneRoot.addChildNode(plane(width: 0.9, height: 0.9,
            position: SCNVector3(0.4, 1.6, -1.58), material: coverMaterial!, name: "coverPoster"))
    }

    // MARK: 共用小件

    private func addLamp(at position: SCNVector3, palette: PaletteTokens,
                         radius: CGFloat = 0.14, color: UIColor? = nil) {
        let lampColor = color ?? machiColor(hex: "#ffe4b8")
        let lampMaterial = material(color: lampColor, emission: lampColor, emissionIntensity: 1)
        lampMaterials.append(lampMaterial)
        let geometry = SCNSphere(radius: radius)
        geometry.materials = [lampMaterial]
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.name = "lamp"
        sceneRoot.addChildNode(node)
    }

    private func makeCar(color: UIColor) -> SCNNode {
        let car = SCNNode()
        car.name = "car"
        let bodyMaterial = material(color: color, roughness: 0.35)
        let body = box(size: SCNVector3(1.42, 0.55, 3.2), position: SCNVector3(0, 0.45, 0),
                       material: bodyMaterial, name: "carBody")
        let cabin = box(size: SCNVector3(1.3, 0.5, 1.7), position: SCNVector3(0, 0.95, -0.1),
                        material: material(color: machiColor(hex: "#1c2733"), roughness: 0.2),
                        name: "carCabin")
        car.addChildNode(body)
        car.addChildNode(cabin)
        return car
    }

    /// 雨丝/雪片节点池（weather 的简化实现：定额回收，
    /// 雨 90 根细条、雪 60 片，位置按 seed 确定性散布）。
    private func buildWeatherNodes() {
        let rain = SCNMaterial()
        rain.diffuse.contents = machiColor(hex: "#9cc3e6")
        rain.transparency = 0
        rainMaterial = rain
        let rainGeometry = SCNBox(width: 0.012, height: 0.55, length: 0.012, chamferRadius: 0)
        rainGeometry.materials = [rain]
        for index in 0..<90 {
            let node = SCNNode(geometry: rainGeometry)
            let rx = machiHash01(seed: 0xA17, index: index, salt: 0x11)
            let rz = machiHash01(seed: 0xA17, index: index, salt: 0x22)
            node.position = SCNVector3(Float(rx * 12 - 6), Float((Double(index % 10)) * 0.9), Float(rz * 12 - 6))
            node.name = "rain"
            sceneRoot.addChildNode(node)
            rainNodes.append(node)
        }
        let snow = SCNMaterial()
        snow.diffuse.contents = UIColor.white
        snow.transparency = 0
        snowMaterial = snow
        let snowGeometry = SCNPlane(width: 0.09, height: 0.09)
        snowGeometry.materials = [snow]
        for index in 0..<60 {
            let node = SCNNode(geometry: snowGeometry)
            let rx = machiHash01(seed: 0x5EED, index: index, salt: 0x33)
            let rz = machiHash01(seed: 0x5EED, index: index, salt: 0x44)
            node.position = SCNVector3(Float(rx * 12 - 6), Float((Double(index % 8)) * 1.1), Float(rz * 12 - 6))
            node.name = "snow"
            sceneRoot.addChildNode(node)
            snowNodes.append(node)
        }
    }

    /// 构图拟合（camera.fitDefault 移植：构图点投到默认视角
    /// 的镜头平面求包围盒中心与半宽/半高）。
    private func computeFraming(id: MachiSceneId) {
        let points: [SCNVector3]
        switch id {
        case .konbini:
            points = [SCNVector3(-6, 0, -6), SCNVector3(6, 0, 6), SCNVector3(-2.2, 6.3, -2.65),
                      SCNVector3(-5.3, 7.6, 1.96), SCNVector3(6, 0, -6), SCNVector3(-6, 0, 6)]
            framingPoints = points
        case .station:
            points = [SCNVector3(-6, 0, -6), SCNVector3(6, 0, 6), SCNVector3(-5.25, 6.4, 1.85),
                      SCNVector3(5.9, 4.3, -3.5), SCNVector3(-5.85, 3.4, -4.65)]
            framingPoints = points
        case .kowloon:
            points = [SCNVector3(-6, 0, -6), SCNVector3(6, 0, 6), SCNVector3(-6, 7.3, -1),
                      SCNVector3(1.2, 7.5, -2.15), SCNVector3(5.55, 7.0, -1.15)]
            framingPoints = points
        }
        let azimuth = framingView.azimuth
        let elevation = framingView.elevation
        let direction = SCNVector3(
            Float(sin(azimuth) * cos(elevation)), Float(sin(elevation)),
            Float(cos(azimuth) * cos(elevation)))
        let forward = SCNVector3(-direction.x, -direction.y, -direction.z)
        let right = machiNormalized(machiCross(forward, SCNVector3(0, 1, 0)))
        let up = machiNormalized(machiCross(right, forward))
        var minR = Float.greatestFiniteMagnitude, maxR = -Float.greatestFiniteMagnitude
        var minU = Float.greatestFiniteMagnitude, maxU = -Float.greatestFiniteMagnitude
        for point in points {
            let r = machiDot(point, right)
            let u = machiDot(point, up)
            minR = min(minR, r); maxR = max(maxR, r)
            minU = min(minU, u); maxU = max(maxU, u)
        }
        let centerR = (minR + maxR) / 2
        let centerU = (minU + maxU) / 2
        fitUp = up
        fitCenter = SCNVector3(right.x * centerR + up.x * centerU,
                               right.y * centerR + up.y * centerU,
                               right.z * centerR + up.z * centerU)
        fitHalf = (width: Double((maxR - minR) / 2), height: Double((maxU - minU) / 2))
        cameraDirty = true
    }
}

// MARK: - 镜头（camera.ts 移植）

extension MachiStageRenderer {

    /// 静止视角 + 运镜偏移 → 摆相机（camera.settle/place 移植：
    /// 限角 azimuth ±75°、俯角 20°–70°、缩放 0.75–3.6、平移
    /// ±5m 与网页 MACHI_CAMERA_LIMITS 逐值；构图留白 MARGIN
    /// 0.02、字幕预留 SUBTITLE_RESERVE 0.05、下沿裁切
    /// CROP_FROM_BOTTOM 0.85 同值）。
    func applyCamera(tuning: MachiTuningValues) {
        guard let camera = cameraNode.camera, builtSceneId != nil else { return }
        let bounds = sceneView.bounds
        let aspect = bounds.width > 0 && bounds.height > 0
            ? Double(bounds.width / bounds.height)
            : Double(snapshot?.viewport.size.width ?? 16) / Double(max(snapshot?.viewport.size.height ?? 9, 1))
        let usable = 1 - 0.02 * 2 - 0.05
        let halfHeight = max(fitHalf.height, fitHalf.width / max(aspect, 0.2)) / usable
        // 静止视角：默认构图 + 自定义偏移（camera=custom 时）。
        var restAzimuth = framingView.azimuth
        var restElevation = framingView.elevation
        var restZoom = framingView.zoom
        var panX = 0.0, panZ = 0.0
        if tuning.camera == .custom, let sceneId = builtSceneId {
            let custom = tuning.view(for: sceneId)
            restAzimuth += custom.azimuth * .pi / 180
            restElevation = min(70 * Double.pi / 180,
                                max(20 * Double.pi / 180,
                                    restElevation + custom.elevation * .pi / 180))
            restZoom = min(3.6, max(0.75, restZoom * custom.zoom))
            panX = custom.panX
            panZ = custom.panZ
        }
        // 运镜偏移（幅度按 smoothstep 缓起缓停，DRIFT_RAMP 4s）。
        let weight = motionWeight * motionWeight * (3 - 2 * motionWeight)
        var azimuth = restAzimuth
        var elevation = restElevation
        var zoom = restZoom
        if weight > 0 {
            let drift = machiDrift(at: motionTime)
            let home = framingView.azimuth
            let range = 75 * Double.pi / 180
            azimuth = min(home + range, max(home - range,
                                            restAzimuth + drift.azimuth * .pi / 180 * weight))
            elevation = min(70 * Double.pi / 180,
                            max(20 * Double.pi / 180,
                                restElevation + drift.elevation * .pi / 180 * weight))
            zoom = min(3.6, max(0.75, restZoom * pow(drift.zoom, weight)))
            let panScale = weight * min(1, framingView.zoom / restZoom)
            panX = min(5, max(-5, panX + drift.panX * panScale))
            panZ = min(5, max(-5, panZ + drift.panZ * panScale))
        }
        // 目标点：拟合中心 + 下沿裁切上移 + 平移（按默认朝向轴）。
        let overflow = max(0, fitHalf.height / usable - halfHeight / restZoom)
        var target = SCNVector3(
            fitCenter.x + fitUp.x * Float(overflow * (0.85 - 0.5) * 2),
            fitCenter.y + fitUp.y * Float(overflow * (0.85 - 0.5) * 2),
            fitCenter.z + fitUp.z * Float(overflow * (0.85 - 0.5) * 2))
        let homeAzimuth = framingView.azimuth
        let right = SCNVector3(Float(cos(homeAzimuth)), 0, Float(-sin(homeAzimuth)))
        let back = SCNVector3(Float(-sin(homeAzimuth)), 0, Float(-cos(homeAzimuth)))
        target = SCNVector3(
            target.x + right.x * Float(panX) + back.x * Float(panZ),
            target.y,
            target.z + right.z * Float(panX) + back.z * Float(panZ))
        currentTarget = target
        let direction = SCNVector3(
            Float(sin(azimuth) * cos(elevation)), Float(sin(elevation)),
            Float(cos(azimuth) * cos(elevation)))
        cameraNode.position = SCNVector3(
            target.x + direction.x * 60, target.y + direction.y * 60,
            target.z + direction.z * 60)
        cameraNode.look(at: target)
        camera.orthographicScale = halfHeight / zoom
        cameraDirty = false
    }

    /// 取景条开关（弹簧动效守 iOS 系统口径：spring + 自然减速）。
    @objc func toggleCameraBar() {
        setCameraBar(open: cameraBar.isHidden)
    }

    func setCameraBar(open: Bool) {
        if open {
            if let tuning = lastTuning ?? Optional(MachiTuningStore.valuesCached(now: CACurrentMediaTime())),
               let sceneId = builtSceneId {
                cameraBar.setScene(sceneId, tuning: tuning)
            }
            cameraBar.isHidden = false
            cameraBar.alpha = 0
            cameraBar.transform = CGAffineTransform(translationX: 0, y: 16)
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState]) {
                self.cameraBar.alpha = 1
                self.cameraBar.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn]) {
                self.cameraBar.alpha = 0
                self.cameraBar.transform = CGAffineTransform(translationX: 0, y: 16)
            } completion: { _ in
                self.cameraBar.isHidden = true
            }
        }
    }

    // MARK: 布局（横竖屏自适应：相机按 bounds 宽高比重拟合）

    func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        let bounds = rootView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        sceneView.frame = bounds
        let safe = rootView.safeAreaInsets
        cameraBarToggle.frame = CGRect(
            x: bounds.width - safe.right - 64, y: safe.top + 10,
            width: 54, height: 30)
        let barHeight: CGFloat = 248
        cameraBar.frame = CGRect(
            x: max(safe.left, 10), y: bounds.height - safe.bottom - barHeight - 8,
            width: bounds.width - max(safe.left, 10) - max(safe.right, 10),
            height: barHeight)
        cameraDirty = true
        if let tuning = lastTuning {
            applyCamera(tuning: tuning)
        } else {
            applyCamera(tuning: MachiTuningStore.valuesCached(now: CACurrentMediaTime()))
        }
    }
}

// MARK: - 牌面与贴图（lyricScreen / signRaster 的 CPU 落点）

extension MachiStageRenderer {

    /// 当前行的点亮分桶（0…100）：按 StageLyricUnits 的字
    /// 单元时刻算整行已唱占比，量化后决定是否重绘贴图
    /// （每行至多重绘约 100 次，单次 1024×440 文字绘制，
    /// 避免逐帧栅格化压主线程）。
    func revealBucket(line: LyricLine, position: TimeInterval) -> Int {
        let units = StageLyricUnits.units(for: line)
        guard !units.isEmpty else { return 100 }
        var sung = 0.0
        for unit in units {
            if position >= unit.end {
                sung += 1
            } else if position > unit.start {
                sung += (position - unit.start) / max(unit.end - unit.start, 0.01)
            }
        }
        return Int((sung / Double(units.count)) * 100)
    }

    /// 重绘歌词屏贴图：曲名卡（标题+歌手）或当前行（1–3 行
    /// 排版、逐行按已唱占比裁切亮色，boardLayout 的简化移植：
    /// 行数以字号最大者胜、行数罚分 [1, 0.94, 0.84]、单行
    /// 填充上限 0.56、行距 1.22 同值）。
    func redrawBoard() {
        guard let boardMaterial, let snapshot else { return }
        let palette = snapshot.palette
        let size = boardTextureSize
        let target = boardTarget ?? .card
        let position = context?.positionNow() ?? 0
        let image = MachiTextTexture.image(size: size) { context, canvas in
            palette.background.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            switch target {
            case .card:
                let title = snapshot.track?.title ?? ""
                let artist = snapshot.track?.artist ?? ""
                drawCentered(title.isEmpty ? "♪" : title, in: canvas,
                             y: canvas.height * 0.30, fontSize: 92,
                             color: palette.primary)
                if !artist.isEmpty {
                    drawCentered(artist, in: canvas, y: canvas.height * 0.58,
                                 fontSize: 52, color: palette.secondary)
                }
            case .line(let index):
                guard snapshot.lines.indices.contains(index) else { return }
                let line = snapshot.lines[index]
                drawLyricLine(line, position: position, canvas: canvas,
                              unlit: palette.primary.withAlphaComponent(0.45),
                              lit: palette.accent)
            }
        }
        boardMaterial.diffuse.contents = image
        boardMaterial.emission.contents = image
    }

    private func drawCentered(_ text: String, in canvas: CGSize, y: CGFloat,
                              fontSize: CGFloat, color: UIColor) {
        let font = UIFont(name: "STSongti-SC-Bold", size: fontSize)
            ?? .boldSystemFont(ofSize: fontSize)
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color,
        ])
        let textSize = string.size()
        string.draw(at: CGPoint(x: (canvas.width - textSize.width) / 2, y: y))
    }

    private func drawLyricLine(_ line: LyricLine, position: TimeInterval,
                               canvas: CGSize, unlit: UIColor, lit: UIColor) {
        let units = StageLyricUnits.units(for: line)
        guard !units.isEmpty else { return }
        let usableWidth = canvas.width * (1 - 0.05 * 2)
        // 试 1–3 行：按单元宽度贪心均分（splitRows 的目标宽口径）。
        var best: (rows: [[StageWordUnit]], fontSize: CGFloat, score: CGFloat)?
        for rowCount in 1...3 {
            guard rowCount <= units.count else { break }
            let rows = splitUnits(units, rows: rowCount)
            let blockHeight = canvas.height * (rowCount == 1 ? 0.56 : 0.8)
            var fontSize = blockHeight / (CGFloat(rowCount) * 1.22)
            // 按最宽行缩字号到可用宽内。
            for row in rows {
                let text = row.map { $0.text }.joined()
                let font = UIFont(name: "STSongti-SC-Bold", size: fontSize)
                    ?? .boldSystemFont(ofSize: fontSize)
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                if width > usableWidth, width > 0 {
                    fontSize *= usableWidth / width
                }
            }
            let penalty: CGFloat = [1, 0.94, 0.84][rowCount - 1]
            let score = fontSize * penalty
            if best == nil || score > best!.score {
                best = (rows, fontSize, score)
            }
        }
        guard let layout = best else { return }
        let font = UIFont(name: "STSongti-SC-Bold", size: layout.fontSize)
            ?? .boldSystemFont(ofSize: layout.fontSize)
        let lineHeight = layout.fontSize * 1.22
        let totalHeight = lineHeight * CGFloat(layout.rows.count)
        var y = (canvas.height - totalHeight) / 2
        for row in layout.rows {
            let text = row.map { $0.text }.joined()
            let rowWidth = (text as NSString).size(withAttributes: [.font: font]).width
            let startX = (canvas.width - rowWidth) / 2
            // 未唱层整行先画，亮色层按行内已唱占比裁切叠画。
            let unlitString = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: unlit,
            ])
            unlitString.draw(at: CGPoint(x: startX, y: y))
            var reveal = 0.0
            var total = 0.0
            for unit in row {
                let unitWidth = Double((unit.text as NSString)
                    .size(withAttributes: [.font: font]).width)
                total += unitWidth
                if position >= unit.end {
                    reveal += unitWidth
                } else if position > unit.start {
                    reveal += unitWidth * (position - unit.start)
                        / max(unit.end - unit.start, 0.01)
                }
            }
            if reveal > 0, total > 0 {
                let context = UIGraphicsGetCurrentContext()
                context?.saveGState()
                context?.clip(to: CGRect(x: startX, y: y,
                                         width: CGFloat(reveal), height: lineHeight))
                let litString = NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: lit,
                ])
                litString.draw(at: CGPoint(x: startX, y: y))
                context?.restoreGState()
            }
            y += lineHeight
        }
    }

    private func splitUnits(_ units: [StageWordUnit], rows: Int) -> [[StageWordUnit]] {
        guard rows > 1 else { return [units] }
        let font = UIFont(name: "STSongti-SC-Bold", size: 100)
            ?? .boldSystemFont(ofSize: 100)
        let widths = units.map {
            Double(($0.text as NSString).size(withAttributes: [.font: font]).width)
        }
        let target = widths.reduce(0, +) / Double(rows)
        var result: [[StageWordUnit]] = []
        var current: [StageWordUnit] = []
        var currentWidth = 0.0
        for (index, unit) in units.enumerated() {
            let remainingRows = rows - result.count
            let remainingUnits = units.count - index
            if !current.isEmpty, remainingRows > 1,
               currentWidth + widths[index] > target * 1.04,
               remainingUnits >= remainingRows - 1 {
                result.append(current)
                current = []
                currentWidth = 0
            }
            current.append(unit)
            currentWidth += widths[index]
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 跑马灯贴图：文本按目标刷新、横向滚动由渲染循环的
    /// contentsTransform 承载（ledStrip 的简化落点）。
    func refreshTicker() {
        guard let tickerMaterial, let snapshot, let target = boardTarget else { return }
        let text = machiTickerText(target: target, lines: snapshot.lines,
                                   title: snapshot.track?.title ?? "",
                                   artist: snapshot.track?.artist ?? "")
        let palette = snapshot.palette
        let image = MachiTextTexture.sign(
            text: text, size: CGSize(width: 1024, height: 64),
            background: machiColor(hex: "#0a0d14"), foreground: palette.accent,
            fontSize: 40)
        tickerMaterial.diffuse.contents = image
        tickerMaterial.emission.contents = image
    }

    /// 招牌贴图：曲名/歌手随曲目刷新（signs 的数据落点：
    /// 便利店 fascia 牌位无独立材质，贴图落在 kowloon 的
    /// barSign/hanging/roofBillboard 与 station motelSign 上，
    /// 按材质 name 分发；无对应节点的场景跳过）。
    func refreshSignTextures() {
        guard let snapshot else { return }
        let title = snapshot.track?.title ?? ""
        let artist = snapshot.track?.artist ?? ""
        let palette = snapshot.palette
        func texture(for material: SCNMaterial) {
            guard let name = material.name else { return }
            let text: String
            let size: CGSize
            let fontSize: CGFloat
            switch name {
            case "barSign":
                text = title; size = CGSize(width: 1024, height: 128); fontSize = 72
            case "roofBillboard":
                text = "九龍城寨"; size = CGSize(width: 1024, height: 360); fontSize = 190
            case "motelSign":
                text = title; size = CGSize(width: 640, height: 360); fontSize = 84
            default:
                if name.hasPrefix("hanging") {
                    let index = Int(name.dropFirst("hanging".count)) ?? 0
                    text = index == 0 && !artist.isEmpty ? artist : ["麺", "酒", "薬", "茶", "麺", "本", "麺", "酒"][index % 8]
                    size = CGSize(width: 256, height: 512); fontSize = 150
                } else {
                    return
                }
            }
            let image = MachiTextTexture.sign(
                text: text, size: size,
                background: machiColor(hex: "#14100e"), foreground: palette.accent,
                fontSize: fontSize)
            material.diffuse.contents = image
            material.emission.contents = image
        }
        for material in neonMaterials { texture(for: material) }
    }

    /// 封面：一张贴图为限（NativeCoverLoader 512 档），换曲
    /// 替换、卸载释放；取不到（本地服务未起等）保持调色板色。
    func loadCover(for snapshot: LyricStageSnapshot) {
        coverTask?.cancel()
        guard let raw = snapshot.track?.artworkURL, !raw.isEmpty else { return }
        let trackId = snapshot.track?.id
        coverTrackId = trackId
        coverTask = Task { [weak self] in
            let tier = NativeCoverLoader.wallTier(raw: raw, pixelExtent: 512)
            guard let proxied = NativeCoverLoader.shared.proxiedURLString(raw, tier: tier),
                  let image = await NativeCoverLoader.shared.image(for: proxied, tier: tier)
            else { return }
            await MainActor.run {
                guard let self, self.coverTrackId == trackId else { return }
                self.coverMaterial?.diffuse.contents = image
            }
        }
    }
}

// MARK: - 渲染循环（氛围时钟：环境/运镜/天气/闪烁/车辆）

extension MachiStageRenderer: SCNSceneRendererDelegate {

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let realDelta: Double
        if lastRenderTime < 0 {
            realDelta = 0
        } else {
            realDelta = min(0.1, max(0, time - lastRenderTime))
        }
        lastRenderTime = time
        // 氛围时间只在播放中前进（MachiClock：暂停即停）。
        let playing = lifecycleState == .playing && isActive
        let ambientDelta = playing ? realDelta : 0
        ambientTime += ambientDelta
        // 环境阻尼追目标（environment.step 移植）。
        environment.step(toward: environmentTarget, delta: realDelta)
        applyEnvironmentLook()
        // 运镜：开时氛围时间推进、幅度 4s 缓升；关时缓降回静止。
        let tuning = lastTuning ?? MachiTuningStore.valuesCached(now: CACurrentMediaTime())
        if playing, tuning.motion {
            motionTime += ambientDelta * tuning.motionSpeed
        }
        let step = realDelta / 4
        motionWeight = tuning.motion
            ? min(1, motionWeight + step) : max(0, motionWeight - step)
        if cameraDirty || motionWeight > 0 || (tuning.motion && playing) {
            applyCamera(tuning: tuning)
        }
        stepWeather(delta: ambientDelta)
        stepActors(delta: ambientDelta)
        // 跑马灯滚动：氛围时间驱动贴图偏移。
        if let tickerMaterial {
            let offset = Float((ambientTime * 0.045).truncatingRemainder(dividingBy: 1))
            tickerMaterial.diffuse.contentsTransform = SCNMatrix4MakeTranslation(offset, 0, 1)
            tickerMaterial.emission.contentsTransform = SCNMatrix4MakeTranslation(offset, 0, 1)
        }
        // 闪烁与模拟节拍（steady period 0.75s：霓虹亮度随拍）。
        let flicker = machiFlicker(at: ambientTime, seed: builtTrackId ?? "machi")
        var beatScale = 1.0
        if tuning.simulatedBeat {
            let phase = (ambientTime / 0.75).truncatingRemainder(dividingBy: 1)
            beatScale = 1 + 0.18 * exp(-phase * 6)
        }
        for material in neonMaterials {
            material.emission.intensity = CGFloat(flicker * beatScale) * glowScale
        }
    }

    /// 环境 → 灯光/天空/雾（environmentLook 的标量移植：
    /// warmth/overcast/artificial/streetLamps/sun/hemi/bloom
    /// 的公式逐值，落到 SceneKit 的光强与背景色上）。
    private func applyEnvironmentLook() {
        let daylight = environment.daylight
        let warmth = max(0, 1 - abs(daylight - 0.45) / 0.38)
        let overcast = min(1, max(environment.rain, environment.fog, environment.snow * 0.8))
        let night = 1 - daylight
        let artificial = 0.55 + 0.45 * machiSmoothstep(0.85, 0.2, daylight)
        let streetLamps = machiSmoothstep(0.62, 0.3, daylight)
        let sunIntensity = (1.35 + (3.0 - 1.35) * daylight)
            * (1 - 0.55 * overcast * daylight) * (1 - 0.25 * environment.fog)
        let hemiIntensity = 2.1 + 0.35 * daylight + 0.25 * overcast * daylight
        _ = warmth
        scene.background.contents = machiSkyColor(
            daylight: daylight,
            night: machiColor(hex: "#26324a"), dusk: machiColor(hex: "#e58a62"),
            day: machiColor(hex: "#cde4f2"))
        sunLight?.intensity = CGFloat(sunIntensity * 700)
        sunLight?.color = machiSkyColor(
            daylight: daylight,
            night: machiColor(hex: "#9cb3dc"), dusk: machiColor(hex: "#ffae78"),
            day: machiColor(hex: "#fff0da"))
        ambientLight?.intensity = CGFloat(hemiIntensity * 160)
        warmLight?.intensity = CGFloat(40 * artificial)
        for material in lampMaterials {
            material.emission.intensity = CGFloat(max(streetLamps, 0.25) * artificial + 0.2)
        }
        // 雾：fog 量 → 起止距离（haze/mist 的简化落点）。
        let fogAmount = 0.42 * environment.fog + 0.08 * environment.snow
        scene.fogStartDistance = fogAmount > 0.02 ? CGFloat(55 - 30 * fogAmount) : 1000
        scene.fogEndDistance = fogAmount > 0.02 ? CGFloat(95 - 40 * fogAmount) : 2000
        scene.fogColor = machiSkyColor(
            daylight: daylight,
            night: machiColor(hex: "#26324a"), dusk: machiColor(hex: "#e58a62"),
            day: machiColor(hex: "#cde4f2"))
        // 天空顶色作根视图底色（场景边缘外露时同色）。
        rootView.backgroundColor = machiSkyColor(
            daylight: daylight,
            night: machiColor(hex: "#0e1524"), dusk: machiColor(hex: "#2c2f5c"),
            day: machiColor(hex: "#4d8bd4"))
        _ = night
    }

    /// 雨丝下落/雪片飘落：定额节点回收（速度按天气量缩放，
    /// 透明度即降水量；积雪/湿度只影响材质观感，未单独建模）。
    private func stepWeather(delta: Double) {
        let rainAmount = environment.rain
        rainMaterial?.transparency = CGFloat(1 - rainAmount * 0.75)
        if rainAmount > 0.03, delta > 0 {
            for node in rainNodes {
                var y = node.position.y - Float(delta * 9)
                if y < 0 { y = 8 }
                node.position.y = y
            }
        }
        let snowAmount = environment.snow
        snowMaterial?.transparency = CGFloat(1 - snowAmount * 0.9)
        if snowAmount > 0.03, delta > 0 {
            for (index, node) in snowNodes.enumerated() {
                var y = node.position.y - Float(delta * 0.9)
                if y < 0 { y = 8 }
                node.position.y = y
                node.position.x += Float(sin(ambientTime * 0.8 + Double(index)) * delta * 0.3)
            }
        }
    }

    /// 车辆沿路往复（traffic 的简化：单车、恒速、到边回头）。
    private func stepActors(delta: Double) {
        guard delta > 0 else { return }
        for car in carNodes {
            var x = car.position.x + Float(delta * 2.2)
            if x > 7 { x = -7 }
            car.position.x = x
        }
    }
}

// MARK: - 取景控制条（MachiCameraBar 的原生等价物）

/// 町景取景控制条：对应网页命令 visualizer-machi-camera-bar
/// 打开的 MachiCameraBar（视角/镜头/运镜三页，控件与文案同
/// cameraControls.ts）。宿主 StageViewController 不接线本条
/// （底账口径：专属控制条若需宿主接线则渲染器自带等价条）：
/// 本条长在渲染器 view 内、底部安全区之上，右上角「取景」
/// 钮开关。写值与设置面板同一套 MachiTuningStore：分段/开关
/// 即写、滑块拖动即写（原生无网页的 preview/commit 两段，
/// UserDefaults 写廉价且渲染器走 0.25s 缓存，不会引发重渲染
/// 风暴，差异在此注明）。本条只含标准 UIKit 控件、不加任何
/// 手势识别器，与舞台宿主的双击/长按切样式/进度条拖动不冲突；
/// 条外区域触摸仍归宿主。本条不画网页的取景框四角/三分线
/// 装饰（纯装饰、且会压住舞台既有 UI，未移植项已注明）。
final class MachiCameraBarView: UIView {

    var onClose: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let tabSegment = UISegmentedControl(items: ["视角", "镜头", "运镜"])
    private let closeButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let contentStack = UIStackView()
    private var sceneId: MachiSceneId = .konbini
    private var currentTab = 0
    private var rowRefreshers: [() -> Void] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildChrome() {
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        tabSegment.selectedSegmentIndex = 0
        tabSegment.translatesAutoresizingMaskIntoConstraints = false
        tabSegment.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        blurView.contentView.addSubview(tabSegment)
        closeButton.setTitle("收起", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        blurView.contentView.addSubview(closeButton)
        resetButton.setTitle("复位", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        blurView.contentView.addSubview(resetButton)
        contentStack.axis = .vertical
        contentStack.spacing = 2
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tabSegment.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 10),
            tabSegment.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 14),
            closeButton.centerYAnchor.constraint(equalTo: tabSegment.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -14),
            resetButton.centerYAnchor.constraint(equalTo: tabSegment.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            tabSegment.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: tabSegment.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: blurView.contentView.bottomAnchor, constant: -10),
        ])
    }

    /// 换场景/打开时调：视角页调正在画的这个场景的那份视角。
    func setScene(_ scene: MachiSceneId, tuning: MachiTuningValues) {
        sceneId = scene
        rebuildRows()
    }

    @objc private func tabChanged() {
        currentTab = tabSegment.selectedSegmentIndex
        rebuildRows()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    /// 本页复位（网页 MachiCameraBar 的 reset 逐页口径）。
    @objc private func resetTapped() {
        switch currentTab {
        case 0:
            MachiTuningStore.camera = .default
            MachiTuningStore.setView(.defaults, for: sceneId)
        case 1:
            MachiTuningStore.aperture = MachiTuningValues.defaults.aperture
            MachiTuningStore.dof = MachiTuningValues.defaults.dof
            MachiTuningStore.dofRange = MachiTuningValues.defaults.dofRange
            MachiTuningStore.tiltShift = MachiTuningValues.defaults.tiltShift
            MachiTuningStore.focus = MachiTuningValues.defaults.focus
            MachiTuningStore.focusOffset = MachiTuningValues.defaults.focusOffset
        default:
            MachiTuningStore.motion = MachiTuningValues.defaults.motion
            MachiTuningStore.motionSpeed = MachiTuningValues.defaults.motionSpeed
        }
        rebuildRows()
    }

    private func rebuildRows() {
        for arranged in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        rowRefreshers = []
        switch currentTab {
        case 0: buildViewRows()
        case 1: buildLensRows()
        default: buildMotionRows()
        }
        for refresh in rowRefreshers { refresh() }
    }

    // MARK: 三页行集（与 MachiCameraBar.tsx 逐页对应）

    private func buildViewRows() {
        addSegmentRow(title: "镜头", items: MachiCameraChoice.allCases.map { $0.displayName },
                      read: { MachiCameraChoice.allCases.firstIndex(of: MachiTuningStore.camera) ?? 0 },
                      write: { MachiTuningStore.camera = MachiCameraChoice.allCases[$0] })
        addViewSlider(title: "转角", field: \.azimuth, range: -75...75, step: 1,
                      format: { String(format: "%+.0f°", $0) })
        addViewSlider(title: "俯仰", field: \.elevation, range: -12...40, step: 1,
                      format: { String(format: "%+.0f°", $0) })
        addViewSlider(title: "远近", field: \.zoom, range: 0.5...2.8, step: 0.05,
                      format: { String(format: "%.2f×", $0) })
        addViewSlider(title: "左右", field: \.panX, range: -5...5, step: 0.1,
                      format: { String(format: "%+.1f m", $0) })
        addViewSlider(title: "前后", field: \.panZ, range: -5...5, step: 0.1,
                      format: { String(format: "%+.1f m", $0) })
    }

    private func buildLensRows() {
        addSliderRow(title: "光圈",
                     range: 0...Double(MachiTuningStore.apertureStops.count - 1), step: 1,
                     format: { "f/\(MachiTuningStore.aperture(atTrackIndex: Int($0.rounded())))" },
                     read: { Double(MachiTuningStore.apertureTrackIndex(for: MachiTuningStore.aperture)) },
                     write: { MachiTuningStore.aperture = MachiTuningStore.aperture(atTrackIndex: Int($0.rounded())) })
        addSegmentRow(title: "对焦", items: MachiFocusChoice.allCases.map { $0.displayName },
                      read: { MachiFocusChoice.allCases.firstIndex(of: MachiTuningStore.focus) ?? 0 },
                      write: { MachiTuningStore.focus = MachiFocusChoice.allCases[$0] })
        addSliderRow(title: "对焦偏移", range: -10...10, step: 0.1,
                     format: { String(format: "%+.1f m", $0) },
                     read: { MachiTuningStore.focusOffset },
                     write: { MachiTuningStore.focusOffset = $0 })
        addSliderRow(title: "清晰范围", range: 0.3...3, step: 0.05,
                     format: { String(format: "%.2f×", $0) },
                     read: { MachiTuningStore.dofRange },
                     write: { MachiTuningStore.dofRange = $0 })
        addSliderRow(title: "景深", range: 0...2, step: 0.05,
                     format: { String(format: "%.0f%%", $0 * 50) },
                     read: { MachiTuningStore.dof },
                     write: { MachiTuningStore.dof = $0 })
        addSliderRow(title: "移轴", range: 0...1, step: 0.05,
                     format: { String(format: "%.0f%%", $0 * 100) },
                     read: { MachiTuningStore.tiltShift },
                     write: { MachiTuningStore.tiltShift = $0 })
    }

    private func buildMotionRows() {
        addSwitchRow(title: "运镜",
                     read: { MachiTuningStore.motion },
                     write: { MachiTuningStore.motion = $0 })
        addSliderRow(title: "运镜速度", range: 0.25...3, step: 0.05,
                     format: { String(format: "%.2f×", $0) },
                     read: { MachiTuningStore.motionSpeed },
                     write: { MachiTuningStore.motionSpeed = $0 })
        let note = UILabel()
        note.text = "视角滑块调当前场景（\(sceneId.rawValue)）的那份；拖滑块即切自定义。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .lightText
        contentStack.addArrangedSubview(note)
    }

    // MARK: 行工厂（字号 ≥12pt、深色玻璃浅字与网页口径一致）

    private func makeLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return label
    }

    private func addSliderRow(title: String, range: ClosedRange<Double>, step: Double,
                              format: @escaping (Double) -> String,
                              read: @escaping () -> Double,
                              write: @escaping (Double) -> Void) {
        let container = UIView()
        let label = makeLabel(title)
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.translatesAutoresizingMaskIntoConstraints = false
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(slider)
        container.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 52),
            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        contentStack.addArrangedSubview(container)
        rowRefreshers.append {
            let value = read()
            slider.value = Float(value)
            valueLabel.text = format(value)
        }
        slider.addAction(UIAction { _ in
            let stepped = (Double(slider.value) / step).rounded() * step
            write(stepped)
            valueLabel.text = format(read())
        }, for: .valueChanged)
    }

    /// 视角滑块：一动即切自定义并写当前场景那份（网页取景条
    /// setView 口径：拖哪一项都从当前显示值改起并固定）。
    private func addViewSlider(title: String,
                               field: WritableKeyPath<MachiCameraViewValues, Double>,
                               range: ClosedRange<Double>, step: Double,
                               format: @escaping (Double) -> String) {
        addSliderRow(title: title, range: range, step: step, format: format,
                     read: { [weak self] in
                         guard let self else { return 0 }
                         if MachiTuningStore.camera == .custom {
                             return MachiTuningStore.view(for: self.sceneId)[keyPath: field]
                         }
                         return MachiCameraViewValues.defaults[keyPath: field]
                     },
                     write: { [weak self] value in
                         guard let self else { return }
                         var view = MachiTuningStore.camera == .custom
                             ? MachiTuningStore.view(for: self.sceneId)
                             : MachiCameraViewValues.defaults
                         view[keyPath: field] = value
                         MachiTuningStore.camera = .custom
                         MachiTuningStore.setView(view, for: self.sceneId)
                     })
    }

    private func addSegmentRow(title: String, items: [String],
                               read: @escaping () -> Int,
                               write: @escaping (Int) -> Void) {
        let container = UIView()
        let label = makeLabel(title)
        let segment = UISegmentedControl(items: items)
        segment.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(segment)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            segment.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            segment.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            segment.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        contentStack.addArrangedSubview(container)
        rowRefreshers.append {
            let index = read()
            if items.indices.contains(index) { segment.selectedSegmentIndex = index }
        }
        segment.addAction(UIAction { _ in
            guard items.indices.contains(segment.selectedSegmentIndex) else { return }
            write(segment.selectedSegmentIndex)
        }, for: .valueChanged)
    }

    private func addSwitchRow(title: String,
                              read: @escaping () -> Bool,
                              write: @escaping (Bool) -> Void) {
        let container = UIView()
        let label = makeLabel(title)
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(toggle)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggle.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        contentStack.addArrangedSubview(container)
        rowRefreshers.append { toggle.isOn = read() }
        toggle.addAction(UIAction { _ in write(toggle.isOn) }, for: .valueChanged)
    }
}
