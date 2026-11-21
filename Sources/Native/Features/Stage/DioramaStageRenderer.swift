import UIKit
import SceneKit
import QuartzCore

// 镜台 diorama（3.7 (57) 工作流 B2 全量原生移植）：网页版
// folia-major/src/components/visualizer/diorama/ 的 Three.js
// 3D 歌词飞越场景以 SceneKit 等价重写（终局口径 100% 原生、
// 无 WebGL/WKWebView）。数据通路对照（网页 → 原生）：
//  - VisualizerDiorama 的 sequencer/走廊分段 → 本文件按曲目
//    重建 frames（buildPath），种子 = track.id 的 hashSeed；
//    跨曲 46 单位偏移走廊 + 3.2s 贝塞尔飞行未落（见文末清单），
//    切歌靠 SmoothDamp 追赶 + 24 单位 seek-snap 定版口径衔接。
//  - cameraPath.buildDioramaPath → buildPath（步距 8、yaw
//    上限 0.5、pitch 上限 0.32、种子正弦同式）。
//  - getDioramaTextPlacement → textPlacement（offsetR/U、
//    scale 0.82–1.28、roll 0.2、yaw 0.16、look 1.1，weave 缩放）。
//  - getDioramaShot/resolveShotOffset → shotKind/resolveShot
//    （13 种运镜的偏移公式逐式移植；选镜权重表简化为种子
//    均匀抽选 + 前两行防重复，见文末清单）。
//  - CameraRig 的 SmoothDamp 追随 + 读头 truck（tanh 饱和）
//    + hold-settle（3s 延迟 / 5s 缓动）+ idle drift 层叠正弦
//    → updateCamera；回正（reading-alignment）权重缓动以
//    lookAt 目标混合近似（见文末清单）。
//  - DioramaScene 的当前行逐单元平面（辉光/灵魂/渐变三条
//    独立跟唱路径）→ buildActiveUnits/updateActiveUnits；
//    邻行整行栅格平面 + resolveNeighborLineOpacity 曲线、
//    LINES_AHEAD 3 / LINES_BEHIND 2 窗口 → buildNeighborLines。
//  - buildFormation 的陈列构成（ring/gate/colonnade/arch/
//    helix/canopy/rail/totem/cluster 按运镜配形、单行单族、
//    文字净空带 lateral 5.2）→ buildFormation（构成与计数
//    照搬，点云化改为 SceneKit 实体几何 + 光晕点层近似）。
//  - dioramaMoteField 的尘埃壳（内径 2.4、径向跨度 5.2、
//    纵向压 0.64、窗口 -2…+5 行）→ buildMotes。
//  - 雾带 FOG_NEAR 12 / FOG_FAR 30、主题色 COLOR_DAMP_RATE
//    1.2 阻尼、文字生命周期（远端 32→40 淡入、近端 2.0→0.9
//    溶解）→ frameTick 内逐帧计算。
//  - 镜台陈列：走廊下方一块镜面台板（物理材质金属度台面，
//    随相机跟随）+ 当前行侧后方的封面陈列牌（封面只用当前
//    一张、经 NativeCoverLoader 取图），对应任务书「镜台
//    陈列、镜面反射感、封面场景内呈现」。
// 时钟纪律：歌词进度、当前行、相机追随、跟唱包络只消费
// 宿主 frameTick(position)；SceneKit 渲染循环（isPlaying）
// 只驱动陈列物自转/尘埃漂移等环境动画，不读播放位置。
// 频谱：协议 hostCapabilities.requiresSpectrum=false、无
// 音频数据源，audioReactivity 只存不用（网页口径里音频也
// 从不驱动相机，只驱动几何包络；原生包络以中性值运行）。
final class DioramaStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: true, requiresSpectrum: false, supportsLineSeek: true)

    // MARK: 网页常量（dioramaSceneConstants / cameraPath）

    private enum C {
        static let stepDistance: Double = 8
        static let maxYaw: Double = 0.5
        static let maxPitch: Double = 0.32
        static let heroDistance: Double = 5.2
        static let cameraLift: Double = 0.5
        static let safeFrameFraction: Double = 0.92
        static let swayAmp: Double = 0.4
        static let liftAmp: Double = 0.4
        static let distAmp: Double = 0.5
        static let snapDistance: Double = 24
        static let textOffsetR: Double = 1.8
        static let textOffsetU: Double = 1.2
        static let textRoll: Double = 0.2
        static let textYaw: Double = 0.16
        static let textLook: Double = 1.1
        static let lineFontSize: Double = 0.62
        static let targetFrameWidthFraction: Double = 0.72
        static let minFitScale: Double = 0.28
        static let fogNear: Double = 12
        static let fogFar: Double = 30
        static let textDissolveStart: Double = 2.0
        static let textDissolveEnd: Double = 0.9
        static let textFadeInStart: Double = 32
        static let textFadeInEnd: Double = 40
        static let colorDampRate: Double = 1.2
        static let activeLineOpacity: Double = 0.92
        static let unsungUnitOpacity: Double = 0.5
        static let unitGlowMaxOpacity: Double = 0.9
        static let soulMaxOpacity: Double = 0.6
        static let linesAhead = 3
        static let linesBehind = 2
        static let shapeFadeInStart: Double = 20
        static let shapeFadeInEnd: Double = 27
        static let shapeDissolveStart: Double = 3.0
        static let shapeDissolveEnd: Double = 1.2
    }

    // MARK: 向量与帧（cameraPath 的 DioramaVec/DioramaFrame）

    private struct Vec3: Equatable {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }
        var length: Double { (x * x + y * y + z * z).squareRoot() }
        var normalized: Vec3 {
            let l = length
            return l > 0 ? Vec3(x: x / l, y: y / l, z: z / l) : self
        }
        static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
            Vec3(x: a.y * b.z - a.z * b.y,
                 y: a.z * b.x - a.x * b.z,
                 z: a.x * b.y - a.y * b.x)
        }
        var scn: SCNVector3 { SCNVector3(Float(x), Float(y), Float(z)) }
    }

    private struct Frame {
        var position: Vec3
        var forward: Vec3
        var right: Vec3
        var up: Vec3
        static let identity = Frame(position: Vec3(),
                                    forward: Vec3(x: 0, y: 0, z: -1),
                                    right: Vec3(x: 1, y: 0, z: 0),
                                    up: Vec3(x: 0, y: 1, z: 0))
    }

    private struct TextPlacement {
        var offsetR: Double
        var offsetU: Double
        var scale: Double
        var roll: Double
        var yaw: Double
        var lookR: Double
    }

    // MARK: 视图与场景

    private let rootView = LyricStageRootView()
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let worldNode = SCNNode()
    private let plinthNode = SCNNode()
    private let coverNode = SCNNode()
    private var coverMaterial: SCNMaterial?

    private var context: LyricStageContext?
    private var snapshot: LyricStageSnapshot?
    /// (61) WC：歌词对比保护衬底（StagePalette 基础设施）。
    private let lyricScrimView = LyricContrastScrimView()
    private var isActive = false

    // MARK: 走廊状态

    private var frames: [Frame] = []
    private var seedBase: Int = 1
    private var builtTrackId: String? = nil
    private var builtLineCount = -1
    private var builtWindowKey = ""
    private var stickyIndex = 0
    private var activeIndex: Int? = nil
    private var lineNodes: [Int: SCNNode] = [:]
    private var lineMaterials: [Int: SCNMaterial] = [:]
    private var formationNodes: [Int: [SCNNode]] = [:]
    private var formationMaterials: [Int: [SCNMaterial]] = [:]
    private var moteNode: SCNNode?
    private var moteWindowCenter = Int.min
    private var activeUnitsGroup: SCNNode?
    private var unitBaseMats: [SCNMaterial] = []
    private var unitBaseNodes: [SCNNode] = []
    private var unitWhiteImages: [UIImage] = []
    private var unitAccentImages: [UIImage] = []
    /// 每单元正文状态（0 未唱 / 1 正在唱 / 2 唱完），只在变化时换栅格图。
    private var unitStates: [Int] = []
    private var unitGlowMats: [SCNMaterial] = []
    private var unitGlowNodes: [SCNNode] = []
    private var unitSoulMats: [SCNMaterial] = []
    private var unitSoulNodes: [SCNNode] = []
    private var unitGroups: [SCNNode] = []
    private var activeUnits: [StageWordUnit] = []
    private var unitLightVals: [Double] = []
    private var unitSoulVals: [Double] = []
    private var activeLineWorldWidth: Double = 0

    // MARK: 相机状态（SmoothDamp 逐轴速度）

    private var camPos = Vec3(x: 0, y: 0.6, z: 9)
    private var camVel = Vec3()
    private var lookPos = Vec3(x: 0, y: 0, z: -10)
    private var lookVel = Vec3()
    private var cameraInitialized = false
    private var lastTickWall: CFTimeInterval = -1
    private var lastPosition: TimeInterval = 0

    // MARK: 主题色阻尼（COLOR_DAMP_RATE）

    private var dampedPrimary: UIColor?
    private var dampedAccent: UIColor?
    private var dampedBackground: UIColor?

    private var coverTask: Task<Void, Never>?
    private var coverKey: String? = nil
    private var spinAngle: Double = 0

    init() {
        view = rootView
        rootView.backgroundColor = .black
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.isPlaying = false
        scnView.rendersContinuously = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isUserInteractionEnabled = false
        rootView.addSubview(scnView)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 120
        camera.fieldOfView = 55
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.6, 9)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 650
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        let keyLight = SCNLight()
        keyLight.type = .omni
        keyLight.intensity = 900
        key.light = keyLight
        key.name = "diorama.keyLight"
        scene.rootNode.addChildNode(key)

        scene.fogStartDistance = CGFloat(C.fogNear)
        scene.fogEndDistance = CGFloat(C.fogFar)
        scene.rootNode.addChildNode(worldNode)

        // 镜面台板：走廊下方的物理台面（金属度 + 低粗糙度
        // 给出反射感），尺寸有限、随相机在 XZ 平面跟随。
        let plinthGeo = SCNPlane(width: 90, height: 90)
        let plinthMat = SCNMaterial()
        plinthMat.lightingModel = .physicallyBased
        plinthMat.metalness.contents = 0.85
        plinthMat.roughness.contents = 0.28
        plinthMat.diffuse.contents = UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        plinthMat.isDoubleSided = false
        plinthGeo.materials = [plinthMat]
        plinthNode.geometry = plinthGeo
        plinthNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        plinthNode.name = "diorama.plinth"
        scene.rootNode.addChildNode(plinthNode)

        // 封面陈列牌：立板 + 封面贴面，位置每帧随当前行帧更新。
        let boardGeo = SCNBox(width: 1.9, height: 1.9, length: 0.08, chamferRadius: 0.03)
        let boardMat = SCNMaterial()
        boardMat.lightingModel = .physicallyBased
        boardMat.metalness.contents = 0.6
        boardMat.roughness.contents = 0.35
        boardMat.diffuse.contents = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        boardGeo.materials = [boardMat]
        coverNode.geometry = boardGeo
        let faceGeo = SCNPlane(width: 1.7, height: 1.7)
        let faceMat = SCNMaterial()
        faceMat.diffuse.contents = UIColor.darkGray
        faceMat.emission.contents = UIColor.black
        faceGeo.materials = [faceMat]
        let faceNode = SCNNode(geometry: faceGeo)
        faceNode.position = SCNVector3(0, 0, 0.06)
        coverNode.addChildNode(faceNode)
        coverMaterial = faceMat
        coverNode.opacity = 0
        scene.rootNode.addChildNode(coverNode)

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
            seedBase = Self.hashSeed(snapshot.track?.id)
            frames = Self.buildPath(count: max(snapshot.lines.count, 1), seedBase: seedBase)
            stickyIndex = 0
            activeIndex = nil
            builtWindowKey = ""
            moteWindowCenter = Int.min
            clearWindow()
            loadCover(snapshot)
            Breadcrumbs.log("stage.diorama.build track=\(snapshot.track?.id ?? "nil") lines=\(snapshot.lines.count)")
        }
        dampedPrimary = dampedPrimary ?? snapshot.palette.primary
        dampedAccent = dampedAccent ?? snapshot.palette.accent
        dampedBackground = dampedBackground ?? snapshot.palette.background
        scene.background.contents = snapshot.palette.background
        rootView.setNeedsLayout()
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        isActive = active && state != .destroyed
        scnView.isPlaying = isActive
        scnView.rendersContinuously = isActive
        if !isActive { lastTickWall = -1 }
    }

    func frameTick(position: TimeInterval) {
        guard isActive, let snapshot else { return }
        let now = CACurrentMediaTime()
        let delta = lastTickWall < 0 ? 0.016 : min(max(now - lastTickWall, 0.001), 0.1)
        lastTickWall = now
        lastPosition = position
        let tuning = DioramaTuningStore.snapshot(now: now)

        updateDampedColors(snapshot: snapshot, delta: delta)

        // 当前行（sticky 口径）：间奏行（纯省略号）不成为
        // 读头，沿用上一真实行（网页 onInterlude 同语义）。
        let lines = snapshot.lines
        var rawIndex = ClassicStageRenderer.activeIndex(in: lines, at: position)
            ?? LyricParser.currentIndex(in: lines, at: position)
        if let idx = rawIndex, lines.indices.contains(idx),
           Self.isInterlude(lines[idx].text) {
            rawIndex = activeIndex ?? rawIndex
        }
        if let idx = rawIndex { stickyIndex = idx }
        let current = lines.isEmpty ? nil : min(max(stickyIndex, 0), lines.count - 1)

        if current != activeIndex {
            activeIndex = current
            rebuildWindow(snapshot: snapshot, tuning: tuning)
        } else {
            // 调参变化（密度/可见性/尘埃轴）也要重建窗口。
            let key = windowKey(tuning: tuning, index: current ?? -1)
            if key != builtWindowKey { rebuildWindow(snapshot: snapshot, tuning: tuning) }
        }

        updateCamera(snapshot: snapshot, tuning: tuning,
                     position: position, delta: delta)
        updateActiveUnits(position: position, delta: delta, tuning: tuning)
        updateLifecycleFades()
        spinAngle += delta * 0.05
    }

    func unmount() {
        isActive = false
        scnView.isPlaying = false
        scnView.rendersContinuously = false
        coverTask?.cancel()
        coverTask = nil
        clearWindow()
        moteNode?.removeFromParentNode()
        moteNode = nil
        scnView.scene = nil
        context = nil
        snapshot = nil
        Breadcrumbs.log("stage.diorama.unmount")
    }

    // MARK: 布局

    private func performLayout() {
        lyricScrimView.sync(in: rootView, palette: snapshot?.palette ?? .neutralDark,
                              rect: rootView.bounds, at: 0)

        scnView.frame = rootView.bounds
    }

    // MARK: 确定性随机（网页 seededUnit / hashSeed）

    private static func seededUnit(_ seed: Double) -> Double {
        let x = sin(seed * 12.9898) * 43758.5453
        return x - floor(x)
    }

    private static func hashSeed(_ value: String?) -> Int {
        guard let value, !value.isEmpty else { return 1 }
        var hash = 0
        for scalar in value.unicodeScalars {
            hash = (hash * 31 + Int(scalar.value)) % 100000
        }
        return hash == 0 ? 1 : hash
    }

    private static func isInterlude(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return trimmed.allSatisfy { $0 == "." || $0 == "…" || $0 == "・" || $0 == "·" }
    }

    // MARK: 路径（buildDioramaPath 逐式移植）

    private static func buildPath(count: Int, seedBase: Int) -> [Frame] {
        let n = max(count, 1)
        let base = Double(seedBase)
        var positions: [Vec3] = []
        var pos = Vec3()
        for i in 0...n {
            positions.append(pos)
            let yaw = C.maxYaw * (sin(Double(i) * 0.23 + base * 0.017) * 0.62
                + sin(Double(i) * 0.11 + base * 0.041 + 1.3) * 0.38)
            let pitch = C.maxPitch * sin(Double(i) * 0.17 + base * 0.029 + 0.7)
            let cp = cos(pitch)
            let dir = Vec3(x: sin(yaw) * cp, y: sin(pitch), z: -cos(yaw) * cp)
            pos = pos + dir * C.stepDistance
        }
        var result: [Frame] = []
        let worldUp = Vec3(x: 0, y: 1, z: 0)
        for i in 0..<n {
            let forward = (positions[i + 1] - positions[i]).normalized
            let right = Vec3.cross(forward, worldUp).normalized
            let up = Vec3.cross(right, forward).normalized
            result.append(Frame(position: positions[i], forward: forward,
                                right: right, up: up))
        }
        return result
    }

    private func frame(at index: Int) -> Frame {
        guard !frames.isEmpty else { return .identity }
        return frames[min(max(index, 0), frames.count - 1)]
    }

    /// composeLocal：帧内 (right, up, depth) → 世界点。
    private func compose(_ frame: Frame, r: Double, u: Double, d: Double) -> Vec3 {
        frame.position + frame.right * r + frame.up * u + frame.forward * d
    }

    // MARK: 文本排布（getDioramaTextPlacement 逐式移植）

    private func textPlacement(lineIndex: Int, weave: Double) -> TextPlacement {
        let base = Double(seedBase)
        let i = Double(max(lineIndex, 0))
        func unit(_ k: Double) -> Double {
            Self.seededUnit(base + i * 11 + k)
        }
        let jitterR = (unit(2) - 0.5) * 0.6
        let jitterU = (unit(4) - 0.5) * 0.6
        let wanderR = sin(i * 0.47 + base * 0.019) * 0.7 + jitterR
        let wanderU = sin(i * 0.29 + base * 0.027 + 0.9) * 0.7 + jitterU
        return TextPlacement(
            offsetR: wanderR * C.textOffsetR * weave,
            offsetU: wanderU * C.textOffsetU * weave,
            scale: 0.82 + unit(5) * 0.46,
            roll: (unit(6) - 0.5) * 2 * C.textRoll * weave,
            yaw: (unit(7) - 0.5) * 2 * C.textYaw * weave,
            lookR: (unit(8) - 0.5) * 2 * C.textLook * weave)
    }

    /// 帧 → SceneKit 变换（基向量 right/up/-forward + 位置）。
    private func nodeTransform(frame: Frame, r: Double, u: Double, d: Double) -> simd_float4x4 {
        let origin = compose(frame, r: r, u: u, d: d)
        let back = frame.forward * -1
        return simd_float4x4(columns: (
            SIMD4<Float>(Float(frame.right.x), Float(frame.right.y), Float(frame.right.z), 0),
            SIMD4<Float>(Float(frame.up.x), Float(frame.up.y), Float(frame.up.z), 0),
            SIMD4<Float>(Float(back.x), Float(back.y), Float(back.z), 0),
            SIMD4<Float>(Float(origin.x), Float(origin.y), Float(origin.z), 1)))
    }

    // MARK: 文本栅格（画布栅格化，原生以 UIGraphics 等价）

    private struct Raster {
        var image: UIImage
        var widthPx: CGFloat
        var heightPx: CGFloat
    }

    private func rasterize(text: String, fontPx: CGFloat, color: UIColor) -> Raster? {
        guard !text.isEmpty else { return nil }
        let font = StageFonts.bold(size: fontPx)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = fontPx * 0.25
        let canvas = CGSize(width: ceil(size.width) + pad * 2,
                            height: ceil(size.height) + pad * 2)
        guard canvas.width > 0, canvas.height > 0, canvas.width < 8192 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { _ in
            (text as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: attrs)
        }
        return Raster(image: image, widthPx: canvas.width, heightPx: canvas.height)
    }

    /// 行宽（世界单位，fontPx 栅格口径）与帧适配缩放。
    private func lineMetrics(text: String, fontPx: CGFloat = 64) -> (width: Double, fit: Double) {
        let font = StageFonts.bold(size: fontPx)
        let pxWidth = Double((text as NSString).size(withAttributes: [.font: font]).width)
        let worldWidth = pxWidth * C.lineFontSize / Double(fontPx)
        guard let snapshot else { return (worldWidth, 1) }
        let viewport = snapshot.viewport.size
        let aspect = viewport.height > 0 ? Double(viewport.width / viewport.height) : 1.5
        let halfWidth = C.heroDistance * tan(27.5 * Double.pi / 180) * aspect
        let target = halfWidth * 2 * C.targetFrameWidthFraction
        let fit = worldWidth > 0 ? max(C.minFitScale, min(target / worldWidth, 1.6)) : 1
        return (worldWidth, fit)
    }

    // MARK: 窗口构建（当前行单元 + 邻行 + 陈列 + 尘埃）

    private func windowKey(tuning: DioramaTuningValues, index: Int) -> String {
        "\(index)|\(tuning.geometryEnabled)|\(tuning.geometryMode.rawValue)"
            + "|\(tuning.geometryStrands)\(tuning.geometryBlobs)\(tuning.geometryRibbons)\(tuning.geometryRings)"
            + "|\(tuning.particleDensity)|\(tuning.particleScale)"
            + "|\(tuning.showParticles)|\(tuning.backgroundParticleCircumference)x\(tuning.backgroundParticleRadial)"
            + "|\(tuning.weaveScale)"
    }

    private func clearWindow() {
        for (_, node) in lineNodes { node.removeFromParentNode() }
        lineNodes.removeAll()
        lineMaterials.removeAll()
        formationNodes.removeAll()
        formationMaterials.removeAll()
        activeUnitsGroup?.removeFromParentNode()
        activeUnitsGroup = nil
        unitBaseMats = []
        unitBaseNodes = []
        unitWhiteImages = []
        unitAccentImages = []
        unitStates = []
        unitGlowMats = []
        unitGlowNodes = []
        unitSoulMats = []
        unitSoulNodes = []
        unitGroups = []
        activeUnits = []
        unitLightVals = []
        unitSoulVals = []
    }

    private func rebuildWindow(snapshot: LyricStageSnapshot, tuning: DioramaTuningValues) {
        clearWindow()
        guard let current = activeIndex, snapshot.lines.indices.contains(current) else {
            builtWindowKey = windowKey(tuning: tuning, index: -1)
            return
        }
        builtWindowKey = windowKey(tuning: tuning, index: current)
        let lo = max(0, current - C.linesBehind)
        let hi = min(snapshot.lines.count - 1, current + C.linesAhead)
        for index in lo...hi where index != current {
            buildNeighborLine(index: index, snapshot: snapshot, tuning: tuning)
        }
        buildActiveUnits(index: current, snapshot: snapshot, tuning: tuning)
        if tuning.geometryEnabled {
            for index in lo...hi {
                buildFormation(index: index, snapshot: snapshot, tuning: tuning)
            }
        }
        buildMotes(center: current, tuning: tuning)
        positionCover(index: current)
    }

    private func buildNeighborLine(index: Int, snapshot: LyricStageSnapshot,
                                   tuning: DioramaTuningValues) {
        let line = snapshot.lines[index]
        // 邻行染色（网页口径）：过去行 primary、未来行 secondary，
        // 建时按色栅格（逐帧不换图）。
        let tint = index < (activeIndex ?? index)
            ? snapshot.palette.primary : snapshot.palette.secondary
        guard !line.text.isEmpty,
              let raster = rasterize(text: line.text, fontPx: 64, color: tint) else { return }
        let placement = textPlacement(lineIndex: index, weave: tuning.weaveScale)
        let metrics = lineMetrics(text: line.text)
        let worldPerPx = C.lineFontSize / 64
        let plane = SCNPlane(
            width: CGFloat(Double(raster.widthPx) * worldPerPx * metrics.fit * placement.scale),
            height: CGFloat(Double(raster.heightPx) * worldPerPx * metrics.fit * placement.scale))
        let material = SCNMaterial()
        material.diffuse.contents = raster.image
        material.emission.contents = raster.image
        material.isDoubleSided = true
        material.lightingModel = .constant
        plane.materials = [material]
        let frame = frame(at: index)
        let holder = SCNNode()
        holder.simdTransform = nodeTransform(frame: frame, r: placement.offsetR,
                                             u: placement.offsetU, d: 0)
        let tilt = SCNNode(geometry: plane)
        tilt.eulerAngles = SCNVector3(0, Float(placement.yaw), Float(placement.roll))
        holder.addChildNode(tilt)
        let offset = index - (activeIndex ?? index)
        holder.opacity = CGFloat(Self.neighborOpacity(offset: offset))
        worldNode.addChildNode(holder)
        lineNodes[index] = holder
        lineMaterials[index] = material
    }

    /// resolveNeighborLineOpacity 逐值移植。
    private static func neighborOpacity(offset: Int) -> Double {
        // (61) WC：非当前行不透明下限 0.45——原逐值（0.3/0.1/
        // 0.34/0.16/0.06）逐个抬到下限，纵深改由缩放/雾化表达。
        switch offset {
        case -1: return 0.45
        case -2: return 0.45
        case 1: return 0.45
        case 2: return 0.45
        case 3: return 0.45
        default: return 0
        }
    }

    private func buildActiveUnits(index: Int, snapshot: LyricStageSnapshot,
                                  tuning: DioramaTuningValues) {
        let line = snapshot.lines[index]
        let units = StageLyricUnits.units(for: line)
        activeUnits = units
        unitLightVals = [Double](repeating: 0, count: units.count)
        unitSoulVals = [Double](repeating: 0, count: units.count)
        guard !units.isEmpty else { return }
        let placement = textPlacement(lineIndex: index, weave: tuning.weaveScale)
        let metrics = lineMetrics(text: line.text)
        let fit = metrics.fit * placement.scale
        activeLineWorldWidth = metrics.width * fit

        let group = SCNNode()
        let frame = frame(at: index)
        group.simdTransform = nodeTransform(frame: frame, r: placement.offsetR,
                                            u: placement.offsetU, d: 0)
        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(0, Float(placement.yaw), Float(placement.roll))
        group.addChildNode(tilt)

        // 逐单元布局：以整行测量定槽位（前缀宽度），与网页
        // layoutDioramaActiveUnits 的前缀测量同口径近似。
        let fontPx: CGFloat = 64
        let font = StageFonts.bold(size: fontPx)
        let worldPerPx = C.lineFontSize / Double(fontPx)
        var cursorPx: Double = 0
        let totalPx = Double((line.text as NSString).size(withAttributes: [.font: font]).width)
        var searchStart = line.text.startIndex
        for unit in units {
            // 在整行中定位本单元的起始字素偏移（顺序查找）。
            var unitStartPx = cursorPx
            if let range = line.text.range(of: unit.text, range: searchStart..<line.text.endIndex) {
                let prefix = String(line.text[line.text.startIndex..<range.lowerBound])
                unitStartPx = Double((prefix as NSString).size(withAttributes: [.font: font]).width)
                searchStart = range.upperBound
            }
            let unitPx = Double((unit.text as NSString).size(withAttributes: [.font: font]).width)
            cursorPx = unitStartPx + unitPx
            _ = totalPx

            let unitGroup = SCNNode()
            let centerX = (unitStartPx + unitPx / 2 - totalPx / 2) * worldPerPx * fit
            unitGroup.position = SCNVector3(Float(centerX), 0, 0)

            func makePlane(image: UIImage, wPx: CGFloat, hPx: CGFloat,
                           z: Float) -> (SCNNode, SCNMaterial) {
                let geo = SCNPlane(width: CGFloat(Double(wPx) * worldPerPx * fit),
                                   height: CGFloat(Double(hPx) * worldPerPx * fit))
                let mat = SCNMaterial()
                mat.diffuse.contents = image
                mat.emission.contents = image
                mat.isDoubleSided = true
                mat.lightingModel = .constant
                geo.materials = [mat]
                let node = SCNNode(geometry: geo)
                node.position = SCNVector3(0, 0, z)
                return (node, mat)
            }
            guard let baseRaster = rasterize(text: unit.text, fontPx: fontPx, color: .white) else { continue }
            // accent 版栅格：正在唱的单元换 accent 图、辉光/灵魂
            // 层恒用 accent 图（SceneKit 纹理不可逐帧染色，
            // 以双栅格切换等价 three.js 的 material.color×map）。
            let accentRaster = rasterize(text: unit.text, fontPx: fontPx,
                                         color: snapshot.palette.accent) ?? baseRaster
            unitWhiteImages.append(baseRaster.image)
            unitAccentImages.append(accentRaster.image)
            unitStates.append(-1)
            let (baseNode, baseMat) = makePlane(image: baseRaster.image,
                                                wPx: baseRaster.widthPx, hPx: baseRaster.heightPx, z: 0)
            unitGroup.addChildNode(baseNode)
            unitBaseNodes.append(baseNode)
            // 辉光层：accent 栅格、略放大、置于字后。
            let (glowNode, glowMat) = makePlane(image: accentRaster.image,
                                                wPx: accentRaster.widthPx, hPx: accentRaster.heightPx, z: -0.02)
            glowNode.scale = SCNVector3(1.18, 1.18, 1)
            glowNode.opacity = 0
            unitGroup.addChildNode(glowNode)
            // 灵魂层：accent 栅格副本，唱完后升起消散。
            let (soulNode, soulMat) = makePlane(image: accentRaster.image,
                                                wPx: accentRaster.widthPx, hPx: accentRaster.heightPx, z: 0.01)
            soulNode.opacity = 0
            unitGroup.addChildNode(soulNode)

            tilt.addChildNode(unitGroup)
            unitGroups.append(unitGroup)
            unitBaseMats.append(baseMat)
            unitGlowMats.append(glowMat)
            unitGlowNodes.append(glowNode)
            unitSoulMats.append(soulMat)
            unitSoulNodes.append(soulNode)
        }
        group.opacity = CGFloat(C.activeLineOpacity)
        worldNode.addChildNode(group)
        activeUnitsGroup = group
    }

    // MARK: 陈列构成（buildFormation 的构成移植）

    private enum ShapeKind { case box, sphere, cone, torus }

    private func shotKind(lineIndex: Int) -> Int {
        // 13 种运镜的种子抽选 + 前两行防重复（网页权重表简化，
        // 见文末清单）。返回 0...12 对应 pushIn/pullBack/orbit/
        // track/crane/hold/swell/spiral/pendulum/flyby/arc/float/glide。
        func pick(_ idx: Int) -> Int {
            Int(Self.seededUnit(Double(seedBase) + Double(idx) * 101 + 7) * 13) % 13
        }
        var kind = pick(lineIndex)
        if lineIndex > 0, kind == pick(lineIndex - 1) { kind = (kind + 5) % 13 }
        if lineIndex > 1, kind == pick(lineIndex - 2) { kind = (kind + 3) % 13 }
        return kind
    }

    private func buildFormation(index: Int, snapshot: LyricStageSnapshot,
                                tuning: DioramaTuningValues) {
        let frame = frame(at: index)
        let placement = textPlacement(lineIndex: index, weave: tuning.weaveScale)
        let kind = shotKind(lineIndex: index)
        let salt = Double(seedBase + index * 97)
        func rnd(_ k: Double) -> Double { Self.seededUnit(salt + k) }
        let volume = tuning.particleScale
        var specs: [(kind: ShapeKind, r: Double, u: Double, d: Double, scale: Double, stretchY: Double)] = []
        func add(_ kind: ShapeKind, _ r: Double, _ u: Double, _ d: Double,
                 _ scale: Double, _ stretchY: Double = 1) {
            specs.append((kind, r, u, d, scale * volume, stretchY))
        }
        func addPair(_ kind: ShapeKind, _ lateral: Double, _ u: Double, _ d: Double,
                     _ scale: Double, _ stretchY: Double = 1) {
            add(kind, -abs(lateral), u, d, scale, stretchY)
            add(kind, abs(lateral), u, d, scale, stretchY)
        }
        switch kind {
        case 2: // orbit 环
            for j in 0..<6 {
                let a = Double(j) / 6 * Double.pi * 2 + rnd(2) * 0.6
                add(j == 0 ? .torus : .sphere, cos(a) * 4.4, sin(a) * 4.4,
                    0.6 + rnd(10 + Double(j)) * 1.4, 0.42 + rnd(20 + Double(j)) * 0.32)
            }
        case 0: // pushIn 门柱
            let gate = 4.3 + rnd(1) * 0.5
            for (si, side) in [-1.0, 1.0].enumerated() {
                add(.box, side * gate, -0.6, 0.5 + rnd(Double(si)) * 0.5,
                    0.55 + rnd(2 + Double(si)) * 0.2, 2.8 + rnd(6 + Double(si)) * 0.8)
                add(.box, side * (gate + 1.6), 0.6, 4.5 + rnd(3 + Double(si)) * 2,
                    0.7 + rnd(4 + Double(si)) * 0.3, 3.4)
            }
        case 3: // track 列柱
            for si in 0..<2 {
                let side = si == 0 ? -1.0 : 1.0
                for j in 0..<3 {
                    add(.box, side * (4.2 + rnd(Double(si * 5 + j)) * 0.4),
                        -0.4 + (rnd(Double(si * 7 + j)) - 0.5) * 0.6,
                        0.5 + Double(j) * 2.4, 0.5 + rnd(Double(si * 3 + j)) * 0.15,
                        2.6 + rnd(Double(si + j)) * 0.6)
                }
            }
        case 4: // crane 拱
            for j in 0..<5 {
                let a = Double.pi * (0.15 + 0.7 * Double(j) / 4)
                add(.box, cos(a) * 3.6, abs(sin(a)) * 3.6 + 1.2,
                    0.6 + rnd(30 + Double(j)) * 0.8, 0.45 + rnd(40 + Double(j)) * 0.25, 1.4)
            }
        case 6: // swell 图腾
            let lat = 4.2 + rnd(2) * 0.5
            for j in 0..<2 {
                addPair(.box, lat, -1.5 + Double(j) * 2.1, 1 + Double(j) * 1.2,
                        0.48 - Double(j) * 0.06, 1.45)
            }
            addPair(.sphere, lat, 2.65, 3.4, 0.5)
        case 7: // spiral 螺旋
            let dir = shotDir(lineIndex: index)
            for j in 0..<7 {
                let frac = Double(j) / 6
                let a = dir * frac * Double.pi * 2.2 + rnd(1) * 0.5
                add(.sphere, cos(a) * 4.3, -2.2 + frac * 5.2, 0.5 + frac * 2.2,
                    0.32 + rnd(20 + Double(j)) * 0.2)
            }
        case 8: // pendulum  canopy 垂幕
            for j in 0..<4 {
                add(.box, -3.9 + Double(j) * 2.6 + (rnd(Double(j)) - 0.5) * 0.5,
                    3.0 + rnd(Double(j * 2)) * 1.2, 0.5 + rnd(Double(j * 3)) * 1.2,
                    0.3 + rnd(Double(j * 4)) * 0.12, 2.2 + rnd(Double(j * 5)) * 0.8)
            }
        case 9: // flyby 轨道
            for j in 0..<3 {
                addPair(.box, 4.25 + rnd(Double(j)) * 0.25, -0.45 + Double(j) * 0.45,
                        1 + Double(j) * 2.1, 0.42 + rnd(Double(j * 3)) * 0.1, 2.2)
            }
        case 1: // pullBack 揭示簇
            addPair(.sphere, 5.8 + rnd(9) * 0.5, 1.25, 6.8 + rnd(11), 1.25 + rnd(12) * 0.25)
            for j in 0..<2 {
                addPair(j == 0 ? .box : .cone, 4.4 + Double(j) * 1.15,
                        -1.4 + Double(j) * 2.2, 2.2 + Double(j) * 2.1,
                        0.58 + rnd(Double(j * 4)) * 0.18, j == 0 ? 1.5 : 1)
            }
        case 10: // arc 弧列
            let dir = shotDir(lineIndex: index)
            for j in 0..<5 {
                let a = (-0.5 + Double(j) / 4) * 1.5 * dir
                add(j == 2 ? .torus : .sphere, sin(a) * 5.2, 0.3 + cos(a) * 0.7,
                    1.0 + rnd(20 + Double(j)) * 1.6, 0.45 + rnd(30 + Double(j)) * 0.32)
            }
        case 11: // float 悬浮球列
            for j in 0..<3 {
                addPair(.sphere, 4.1 + Double(j) * 0.85, -1.2 + Double(j) * 1.35,
                        1.2 + Double(j) * 1.55, 0.42 + rnd(Double(j * 4)) * 0.22)
            }
        case 12: // glide 上升塔
            for j in 0..<3 {
                addPair(.box, 4.25 + rnd(Double(j)) * 0.3, -1.5 + Double(j) * 1.7,
                        1 + Double(j) * 1.7, 0.46 + rnd(Double(j * 2)) * 0.12, 1.85)
            }
        default: // hold 静框
            addPair(.torus, 5.6, 1.55, 7.2 + rnd(1), 1.05 + rnd(2) * 0.2)
            addPair(.sphere, 4.45, -1.1, 2.1 + rnd(4), 0.58 + rnd(5) * 0.16)
        }

        // 家族可见性（dioramaGeometry.isKindVisible 同映射）。
        let visible = specs.filter { spec in
            switch spec.kind {
            case .box: return tuning.geometryStrands
            case .sphere: return tuning.geometryBlobs
            case .cone: return tuning.geometryRibbons
            case .torus: return tuning.geometryRings
            }
        }
        guard tuning.geometryMode == .clouds else {
            // corridor 模式：陈列改为沿路径的点环隧道（buildCorridor）。
            buildCorridorRing(index: index, snapshot: snapshot, tuning: tuning)
            return
        }
        var nodes: [SCNNode] = []
        var mats: [SCNMaterial] = []
        for (j, spec) in visible.enumerated() {
            let geometry: SCNGeometry
            switch spec.kind {
            case .box: geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.06)
            case .sphere: geometry = SCNSphere(radius: 0.74)
            case .cone: geometry = SCNCone(topRadius: 0, bottomRadius: 0.68, height: 1.4)
            case .torus: geometry = SCNTorus(ringRadius: 0.9, pipeRadius: 0.16)
            }
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.metalness.contents = 0.35
            material.roughness.contents = 0.4
            let slotColor = j % 2 == 0 ? (dampedPrimary ?? snapshot.palette.primary)
                                       : (dampedAccent ?? snapshot.palette.accent)
            material.diffuse.contents = slotColor
            material.emission.contents = slotColor.withAlphaComponent(0.25)
            if tuning.particleGlowEnabled {
                material.emission.intensity = CGFloat(0.35 * tuning.particleGlowIntensity)
            } else {
                material.emission.intensity = 0
            }
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            let world = compose(frame, r: placement.offsetR + spec.r,
                                u: placement.offsetU + spec.u, d: spec.d)
            node.position = world.scn
            node.scale = SCNVector3(Float(spec.scale), Float(spec.scale * spec.stretchY),
                                    Float(spec.scale))
            node.name = "diorama.shape"
            worldNode.addChildNode(node)
            nodes.append(node)
            mats.append(material)
        }
        formationNodes[index] = nodes
        formationMaterials[index] = mats
    }

    private func shotDir(lineIndex: Int) -> Double {
        Self.seededUnit(Double(seedBase) + Double(lineIndex) * 7 + 3) < 0.5 ? -1 : 1
    }

    /// corridor 模式：本行帧处一圈点环（隧道截面）。
    private func buildCorridorRing(index: Int, snapshot: LyricStageSnapshot,
                                   tuning: DioramaTuningValues) {
        let frame = frame(at: index)
        let perRing = 20
        var vertices: [SCNVector3] = []
        for j in 0..<perRing {
            let a = Double(j) / Double(perRing) * Double.pi * 2
            let p = compose(frame, r: cos(a) * 3.4, u: sin(a) * 3.4, d: 0)
            vertices.append(p.scn)
        }
        let node = makePointsNode(vertices: vertices,
                                  color: dampedPrimary ?? snapshot.palette.primary)
        worldNode.addChildNode(node)
        formationNodes[index] = [node]
        formationMaterials[index] = []
    }

    private func makePointsNode(vertices: [SCNVector3], color: UIColor) -> SCNNode {
        let source = SCNGeometrySource(vertices: vertices)
        var indices: [UInt32] = []
        indices.reserveCapacity(vertices.count)
        for i in 0..<vertices.count { indices.append(UInt32(i)) }
        let indexData = Data(bytes: indices, count: indices.count * 4)
        let element = SCNGeometryElement(data: indexData, primitiveType: .point,
                                         primitiveCount: vertices.count, bytesPerIndex: 4)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    // MARK: 背景尘埃（dioramaMoteField 的壳层移植）

    private func buildMotes(center: Int, tuning: DioramaTuningValues) {
        moteNode?.removeFromParentNode()
        moteNode = nil
        guard tuning.showParticles, let snapshot else { return }
        moteWindowCenter = center
        let perLine = tuning.backgroundParticleCircumference * tuning.backgroundParticleRadial
        var vertices: [SCNVector3] = []
        let golden = Double.pi * (3 - (5.0).squareRoot())
        let phase = Self.seededUnit(Double(seedBase) + 991) * Double.pi * 2
        for lineOffset in -2...5 {
            let lineIndex = center + lineOffset
            let frame: Frame
            if lineIndex >= 0 && lineIndex < frames.count {
                frame = frames[lineIndex]
            } else if let last = frames.last {
                // 路径外延（extendDioramaFrame 同口径）。
                let steps = Double(lineIndex - (frames.count - 1))
                frame = Frame(position: last.position + last.forward * (C.stepDistance * steps),
                              forward: last.forward, right: last.right, up: last.up)
            } else {
                frame = .identity
            }
            let total = perLine
            for p in 0..<total {
                let s = Double(seedBase + lineIndex * 131 + p * 17)
                let stratum = (Double(p / max(tuning.backgroundParticleCircumference, 1)) + 0.35
                    + Self.seededUnit(s + 4) * 0.3) / Double(max(tuning.backgroundParticleRadial, 1))
                let radius = 2.4 + (max(0, min(1, stratum))).squareRoot() * 5.2
                let angle = phase + Double(lineIndex) * golden
                    + Double(p) / Double(max(total, 1)) * Double.pi * 2
                    + (Self.seededUnit(s + 3) - 0.5) * 0.4
                let depth = (Self.seededUnit(s + 2) - 0.5) * C.stepDistance
                let point = compose(frame, r: cos(angle) * radius,
                                    u: sin(angle) * radius * 0.64, d: depth)
                vertices.append(point.scn)
            }
        }
        let node = makePointsNode(vertices: vertices,
                                  color: (dampedPrimary ?? snapshot.palette.primary)
                                    .withAlphaComponent(0.5))
        worldNode.addChildNode(node)
        moteNode = node
    }

    // MARK: 封面（只用当前封面一张）

    private func loadCover(_ snapshot: LyricStageSnapshot) {
        coverTask?.cancel()
        guard let raw = snapshot.track?.artworkURL, !raw.isEmpty else {
            coverKey = nil
            coverNode.opacity = 0
            return
        }
        guard raw != coverKey else { return }
        coverKey = raw
        let urlString = NativeCoverLoader.shared.proxiedURLString(raw, tier: 512) ?? raw
        let taskKey = raw
        coverTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(for: urlString, tier: 512)
            guard let self, !Task.isCancelled, self.coverKey == taskKey else { return }
            await MainActor.run { [weak self] in
                guard let self, self.coverKey == taskKey, let image else { return }
                self.coverMaterial?.diffuse.contents = image
                self.coverMaterial?.emission.contents = image
                self.coverMaterial?.emission.intensity = 0.35
                self.coverNode.opacity = 0.92
            }
        }
    }

    private func positionCover(index: Int) {
        let frame = frame(at: index)
        let placement = textPlacement(lineIndex: index, weave: 1)
        coverNode.simdTransform = nodeTransform(frame: frame,
                                                r: placement.offsetR - 4.9,
                                                u: placement.offsetU + 0.4, d: 2.2)
    }

    // MARK: 主题色阻尼

    private func lerpColor(_ current: UIColor, _ target: UIColor, _ k: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        current.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k,
                       blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }

    private func updateDampedColors(snapshot: LyricStageSnapshot, delta: Double) {
        let k = CGFloat(1 - exp(-C.colorDampRate * delta))
        if let cur = dampedPrimary { dampedPrimary = lerpColor(cur, snapshot.palette.primary, k) }
        if let cur = dampedAccent { dampedAccent = lerpColor(cur, snapshot.palette.accent, k) }
        if let cur = dampedBackground {
            dampedBackground = lerpColor(cur, snapshot.palette.background, k)
            scene.fogColor = dampedBackground ?? snapshot.palette.background
            scene.background.contents = dampedBackground
        }
    }

    // MARK: 相机（CameraRig 的 SmoothDamp 追随移植）

    private static func smoothDamp(current: Double, target: Double,
                                   velocity: inout Double,
                                   smoothTime: Double, delta: Double) -> Double {
        let t = max(0.0001, smoothTime)
        let omega = 2 / t
        let x = omega * delta
        let expTerm = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (velocity + omega * change) * delta
        let newVelocity = (velocity - omega * temp) * expTerm
        velocity = newVelocity
        return target + (change + temp) * expTerm
    }

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    private static func easeInOut(_ p: Double) -> Double {
        let c = clamp01(p)
        return c * c * (3 - 2 * c)
    }

    /// resolveHoldSettle：唱完 3s 后 5s 内释放构图。
    private static func holdSettle(secondsHeld: Double) -> Double {
        let t = clamp01((secondsHeld - 3) / 5)
        return 1 - t * t * (3 - 2 * t)
    }

    /// resolveShotOffset 的偏移公式移植（13 种，节选量纲同网页）。
    private func resolveShot(kind: Int, progress: Double, wordProgress: Double,
                             moveScale: Double) -> (right: Double, up: Double, back: Double) {
        let hero = C.heroDistance
        let lift = C.cameraLift
        let e = Self.easeInOut(progress)
        let dir = shotDir(lineIndex: activeIndex ?? 0)
        var right = 0.0
        var up = lift
        var back = hero
        switch kind {
        case 0: // pushIn
            back = hero * (1.5 - 0.8 * e); up = lift * (1.2 - 0.5 * e) + 0.15
        case 1: // pullBack
            back = hero * (0.85 + 1.15 * e); up = lift + 1.7 * e
        case 2: // orbit
            let theta = dir * 0.55 * (2 * e - 1)
            right = hero * sin(theta); back = hero * cos(theta); up = lift + 0.4
        case 3: // track
            right = dir * hero * 0.34 * sin(Double.pi * Self.clamp01(wordProgress))
            back = hero * 1.06; up = lift + 0.12
        case 4: // crane
            let from = dir > 0 ? -1.5 : 2.4
            let to = dir > 0 ? 2.4 : -1.4
            up = from + (to - from) * e; back = hero * 1.05
        case 6: // swell
            let theta = dir * 0.4 * e
            right = hero * sin(theta) * 1.1; back = hero * (1.0 + 0.35 * e)
            up = lift + 1.2 * e + 0.3
        case 7: // spiral
            let theta = dir * 0.7 * (2 * e - 1)
            right = hero * sin(theta) * 0.85; back = hero * (1.05 - 0.1 * e)
            up = lift - 0.8 + 2.4 * e
        case 8: // pendulum
            right = dir * hero * 0.45 * (2 * e - 1)
            up = lift + 0.9 - 0.9 * sin(Double.pi * e); back = hero * 1.02
        case 9: // flyby
            right = dir * hero * (0.7 - 1.4 * e)
            back = hero * (0.78 + 0.12 * sin(Double.pi * e)); up = lift + 0.05
        case 10: // arc
            let theta = dir * 0.5 * sin(Double.pi * e)
            right = hero * sin(theta) * 1.3; back = hero * (1.05 + 0.12 * (1 - cos(theta)))
            up = lift + 0.5 * sin(Double.pi * e)
        case 11: // float
            right = dir * hero * 0.16 * sin(e * Double.pi * 2)
            up = lift + 0.6 + 0.5 * sin(e * Double.pi * 2 + 1.0)
            back = hero * (1.05 + 0.06 * sin(e * Double.pi))
        case 12: // glide
            right = dir * hero * 0.22 * e; up = lift + 1.4 * e
            back = hero * (1.15 - 0.25 * e)
        default: // hold
            up = lift + 0.3 * sin(progress * Double.pi); back = hero
        }
        let m = moveScale
        return (right * m, lift + (up - lift) * m, hero + (back - hero) * m)
    }

    private func updateCamera(snapshot: LyricStageSnapshot, tuning: DioramaTuningValues,
                              position: TimeInterval, delta: Double) {
        guard let current = activeIndex, snapshot.lines.indices.contains(current) else {
            // 无歌词：相机停在原点缓漂（纯音乐幻影走廊未落，见清单）。
            let driftT = CACurrentMediaTime()
            cameraNode.position = SCNVector3(Float(sin(driftT * 0.11) * 0.25),
                                             Float(0.6 + sin(driftT * 0.09) * 0.12),
                                             Float(9 + cos(driftT * 0.05) * 0.3))
            cameraNode.look(at: SCNVector3(0, 0, -10))
            return
        }
        let line = snapshot.lines[current]
        let frame = frame(at: current)
        let placement = textPlacement(lineIndex: current, weave: tuning.weaveScale)
        let span = max(line.end - line.start, 0.001)
        let progress = Self.clamp01((position - line.start) / span)
        // 逐词进度（读头 truck 用）：按已唱单元比例。
        var wordProgress = progress
        if !activeUnits.isEmpty {
            var revealed = 0.0
            for unit in activeUnits {
                if position >= unit.end { revealed += 1 }
                else if position >= unit.start {
                    revealed += Self.clamp01((position - unit.start) / max(unit.end - unit.start, 0.001))
                    break
                } else { break }
            }
            wordProgress = revealed / Double(activeUnits.count)
        }
        let settle = Self.holdSettle(secondsHeld: position - line.end)
        // truck：tanh 饱和曲线（resolveReadHeadTruck 同式）。
        let viewport = snapshot.viewport.size
        let aspect = viewport.height > 0 ? Double(viewport.width / viewport.height) : 1.5
        let visibleHalf = C.heroDistance * tan(27.5 * Double.pi / 180) * aspect
            * C.safeFrameFraction
        var truck = 0.0
        if activeLineWorldWidth > 0 {
            let wordOffset = (Self.clamp01(wordProgress) - 0.5) * activeLineWorldWidth
            let allowed = max(abs(visibleHalf - activeLineWorldWidth / 2), 0.001)
            truck = allowed * tanh(wordOffset / allowed) * settle
        }
        let headR = placement.offsetR + truck
        let headU = placement.offsetU
        let base = compose(frame, r: headR, u: headU, d: 0)

        let kind = shotKind(lineIndex: current)
        let shot = resolveShot(kind: kind, progress: progress,
                               wordProgress: wordProgress,
                               moveScale: tuning.moveScale * settle)
        // idle drift（resolveCameraDrift 的层叠正弦）。
        let t = position
        let ph = Double(seedBase) * 0.017
        let driftScale = tuning.driftScale
        let swayX = (sin(t * 0.11 + ph) * 0.6 + sin(t * 0.047 + ph * 1.7) * 0.4) * C.swayAmp * driftScale
        let swayY = sin(t * 0.09 + ph * 0.7) * C.swayAmp * 0.5 * driftScale
        let liftD = (sin(t * 0.13 + ph * 1.3) * 0.6 + sin(t * 0.061 + ph * 2.1) * 0.4) * C.liftAmp * driftScale
        let distD = sin(t * 0.05 + ph * 1.1) * C.distAmp * driftScale

        let offR = shot.right + swayX
        let offU = shot.up + swayY + liftD
        let offB = shot.back + distD
        let pose = base + frame.right * offR + frame.up * offU + frame.forward * (-offB)

        let smoothTime = tuning.smoothTime
        let gap = (pose - camPos).length
        if !cameraInitialized || gap > C.snapDistance {
            camPos = pose
            camVel = Vec3()
            lookPos = base + frame.right * (placement.lookR * settle)
            lookVel = Vec3()
            cameraInitialized = true
        } else {
            var vx = camVel.x, vy = camVel.y, vz = camVel.z
            camPos = Vec3(
                x: Self.smoothDamp(current: camPos.x, target: pose.x, velocity: &vx, smoothTime: smoothTime, delta: delta),
                y: Self.smoothDamp(current: camPos.y, target: pose.y, velocity: &vy, smoothTime: smoothTime, delta: delta),
                z: Self.smoothDamp(current: camPos.z, target: pose.z, velocity: &vz, smoothTime: smoothTime, delta: delta))
            camVel = Vec3(x: vx, y: vy, z: vz)
            let lookTarget = base + frame.right * (placement.lookR * settle)
            var lx = lookVel.x, ly = lookVel.y, lz = lookVel.z
            lookPos = Vec3(
                x: Self.smoothDamp(current: lookPos.x, target: lookTarget.x, velocity: &lx, smoothTime: smoothTime, delta: delta),
                y: Self.smoothDamp(current: lookPos.y, target: lookTarget.y, velocity: &ly, smoothTime: smoothTime, delta: delta),
                z: Self.smoothDamp(current: lookPos.z, target: lookTarget.z, velocity: &lz, smoothTime: smoothTime, delta: delta))
            lookVel = Vec3(x: lx, y: ly, z: lz)
        }
        cameraNode.position = camPos.scn
        cameraNode.look(at: lookPos.scn)
        // 键光跟随相机，台板跟随相机 XZ（无限台面错觉）。
        if let keyLight = scene.rootNode.childNode(withName: "diorama.keyLight", recursively: false) {
            keyLight.position = camPos.scn
        }
        plinthNode.position = SCNVector3(Float(camPos.x), Float(camPos.y - 3.4), Float(camPos.z))
        positionCoverIfNeeded(current: current, base: base)
    }

    private func positionCoverIfNeeded(current: Int, base: Vec3) {
        // 封面牌每帧贴当前行帧（rebuild 时也设过一次）。
        positionCover(index: current)
        _ = base
    }

    // MARK: 跟唱（updateDioramaActiveUnits 的三路移植）

    private static func stepEnvelope(current: Double, target: Double,
                                     attack: Double, release: Double, delta: Double) -> Double {
        current + (target - current) * (1 - exp(-(target > current ? attack : release) * delta))
    }

    private func updateActiveUnits(position: TimeInterval, delta: Double,
                                   tuning: DioramaTuningValues) {
        guard !activeUnits.isEmpty else { return }
        let glowEffective = tuning.glowEnabled ? tuning.glowIntensity : 0
        let soulEffective = tuning.soulEnabled ? tuning.soulIntensity : 0
        let gradientEffective = tuning.gradientEnabled ? tuning.gradientIntensity : 0
        let palette = snapshot?.palette
        for (i, unit) in activeUnits.enumerated() {
            guard unitBaseMats.indices.contains(i) else { break }
            let isActive = position >= unit.start && position < unit.end
            let isPassed = position >= unit.end
            // 辉光包络：快攻慢放（网页 lightVals 同纪律）。
            let lightTarget = isActive ? 1.0 : 0.0
            unitLightVals[i] = Self.stepEnvelope(current: unitLightVals[i],
                                                 target: lightTarget,
                                                 attack: 18, release: 3.5, delta: delta)
            // 灵魂包络：唱完后缓慢充能、脱离升起。
            let soulTarget = isPassed ? 1.0 : (isActive && tuning.soulActiveEnabled ? 0.6 : 0.0)
            unitSoulVals[i] = Self.stepEnvelope(current: unitSoulVals[i],
                                                target: soulTarget,
                                                attack: 6, release: 1.6, delta: delta)
            // 正文三态：未唱 0.5 暗（白栅格 + 低不透明度）、
            // 正在唱 accent（换 accent 栅格）、唱完 primary 亮
            // （回白栅格；渐变跟唱开启时唱完保持 accent 栅格
            // 近似「填充加深」，强度以辉光层叠加近似）。
            // 状态只在变化时换图（每单元至多两次），不逐帧换。
            let state = isActive ? 1 : (isPassed ? 2 : 0)
            if unitStates.indices.contains(i), unitStates[i] != state {
                unitStates[i] = state
                if unitBaseMats.indices.contains(i) {
                    let useAccent = state == 1 || (state == 2 && gradientEffective > 0)
                    let image = useAccent
                        ? unitAccentImages[i] : unitWhiteImages[i]
                    unitBaseMats[i].diffuse.contents = image
                    unitBaseMats[i].emission.contents = image
                }
            }
            if unitBaseNodes.indices.contains(i) {
                unitBaseNodes[i].opacity = state == 0
                    ? CGFloat(C.unsungUnitOpacity) : 1
            }
            // 辉光层（独立路径）：accent 染色在重建时以 accent
            // 色栅格近似不可得，此处以节点 opacity + 材质
            // emission 图承载强度包络。
            if unitGlowNodes.indices.contains(i) {
                unitGlowNodes[i].opacity = CGFloat(
                    unitLightVals[i] * glowEffective * C.unitGlowMaxOpacity)
            }
            // 灵魂层（独立路径）：唱完升起 0.5em、膨胀 1.3、淡出。
            if unitSoulNodes.indices.contains(i) {
                let soul = unitSoulVals[i] * soulEffective
                unitSoulNodes[i].opacity = CGFloat(soul * C.soulMaxOpacity)
                if unitSoulNodes.indices.contains(i) {
                    let node = unitSoulNodes[i]
                    let liftEm = isPassed ? 0.5 * min(soul, 1) : 0.06 * soul
                    node.position = SCNVector3(0, Float(liftEm * C.lineFontSize), 0.01)
                    let swell = 1 + (isPassed ? 0.3 : 0.1) * min(soul, 1)
                    node.scale = SCNVector3(Float(swell), Float(swell), 1)
                }
            }
        }
    }

    // MARK: 生命周期淡入/溶解（文字与陈列共用距离口径）

    private static func smoothstep01(_ t: Double) -> Double {
        let c = clamp01(t)
        return c * c * (3 - 2 * c)
    }

    private static func textLife(distance: Double) -> Double {
        let farT = clamp01((distance - C.textFadeInStart) / (C.textFadeInEnd - C.textFadeInStart))
        let farFade = 1 - smoothstep01(farT)
        let nearT = clamp01((distance - C.textDissolveEnd) / (C.textDissolveStart - C.textDissolveEnd))
        return farFade * smoothstep01(nearT)
    }

    private static func shapeLife(distance: Double) -> Double {
        let farT = clamp01((C.shapeFadeInEnd - distance) / (C.shapeFadeInEnd - C.shapeFadeInStart))
        let nearT = clamp01((distance - C.shapeDissolveEnd) / (C.shapeDissolveStart - C.shapeDissolveEnd))
        return smoothstep01(farT) * smoothstep01(nearT)
    }

    private func updateLifecycleFades() {
        let cam = camPos
        for (index, holder) in lineNodes {
            let nodePos = holder.position
            let d = (Vec3(x: Double(nodePos.x), y: Double(nodePos.y), z: Double(nodePos.z)) - cam).length
            let base = Self.neighborOpacity(offset: index - (activeIndex ?? index))
            holder.opacity = CGFloat(base * Self.textLife(distance: d))
        }
        for (_, nodes) in formationNodes {
            for node in nodes {
                let p = node.position
                let d = (Vec3(x: Double(p.x), y: Double(p.y), z: Double(p.z)) - cam).length
                node.opacity = CGFloat(Self.shapeLife(distance: d))
                // 环境自转（SceneKit 循环域的等价：由渲染帧的
                // spinAngle 驱动，与歌词同步无关）。
                if node.name == "diorama.shape" {
                    node.eulerAngles = SCNVector3(0, Float(spinAngle * 10), 0)
                }
            }
        }
    }

}
