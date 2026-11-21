import UIKit

// 町景 machi 调参存储与面板（3.7 (57) 工作流 B7）：
// 网页版 folia-major/src/components/visualizer/machi/types.ts 的
// MachiTuning / DEFAULT_MACHI_TUNING、machiTuning.ts 的
// normalizeMachiTuning、tuning.ts 的字段表逐参数原生承接。
// 网页每个参数在 MachiTuningStore 里各有一个属性，UserDefaults
// 键前缀 "folia.tuning.machi."，缺省与钳制范围逐字对齐网页：
//  - scene 缺省 "auto"（auto/konbini/station/kowloon）
//  - timeOfDay 缺省 "auto"（auto/day/dusk/night）
//  - weather 缺省 "auto"（auto/clear/rain/snow/fog）
//  - camera 缺省 "default"（default/custom）
//  - views.<场景>.{azimuth,elevation,zoom,panX,panZ}：每场景
//    一份自定义视角，缺省全 0/0/1/0/0（DEFAULT_MACHI_VIEW），
//    范围见 MACHI_VIEW_LIMITS（azimuth ±75°、elevation
//    −12…40°、zoom 0.5…2.8、panX/panZ ±5m）
//  - motion 缺省 false、motionSpeed [0.25, 3] 缺省 1
//    （MACHI_MOTION_SPEED_LIMITS）
//  - 景深 MACHI_DOF_LIMITS：aperture [1.4, 16] 缺省 8、
//    dof [0, 2] 缺省 1、dofRange [0.3, 3] 缺省 1、
//    tiltShift [0, 1] 缺省 0.3、focusOffset [−10, 10] 缺省 0
//  - focus 缺省 "center"（center/lyrics/manual）
//  - simulatedBeat 缺省 true
//  - quality（DEFAULT_MACHI_QUALITY = high 预设 + adaptive）：
//    renderScale 缺省 "global"（global/1/0.75/0.5）、
//    antialias 缺省 "global"（global/off/fxaa/smaa/ssaa）、
//    shadows/reflections 缺省 "high"（off/low/high）、
//    glow 缺省 true、adaptive 缺省 true
// 不认识的存值一律回缺省（网页 normalize 口径）。面板拨动即
// 写存储；渲染器经 valuesCached(now:) 的 0.25s 缓存逐帧读
// （照 PendoloTuningStore / StageEffectSettings 先例）。

/// 场景（网页 MachiSceneId；"auto" 只在 tuning.scene 出现）。
enum MachiSceneChoice: String, CaseIterable {
    case auto
    case konbini
    case station
    case kowloon

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .konbini: return "便利店"
        case .station: return "加油站"
        case .kowloon: return "城寨酒吧"
        }
    }
}

/// 已定场景（auto 解析后的落点，网页 MachiSceneId 本体）。
enum MachiSceneId: String, CaseIterable {
    case konbini
    case station
    case kowloon
}

enum MachiTimeChoice: String, CaseIterable {
    case auto
    case day
    case dusk
    case night

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .day: return "白天"
        case .dusk: return "黄昏"
        case .night: return "夜晚"
        }
    }
}

enum MachiWeatherChoice: String, CaseIterable {
    case auto
    case clear
    case rain
    case snow
    case fog

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .clear: return "晴"
        case .rain: return "雨"
        case .snow: return "雪"
        case .fog: return "雾"
        }
    }
}

enum MachiCameraChoice: String, CaseIterable {
    case `default`
    case custom

    var displayName: String {
        switch self {
        case .default: return "默认构图"
        case .custom: return "自定义"
        }
    }
}

enum MachiFocusChoice: String, CaseIterable {
    case center
    case lyrics
    case manual

    var displayName: String {
        switch self {
        case .center: return "画面中心"
        case .lyrics: return "歌词屏"
        case .manual: return "手动"
        }
    }
}

/// 阴影 / 倒影档（网页 MachiDetailLevel）。
enum MachiDetailChoice: String, CaseIterable {
    case off
    case low
    case high

    var displayName: String {
        switch self {
        case .off: return "关"
        case .low: return "低"
        case .high: return "高"
        }
    }
}

/// 自定义视角（网页 MachiCameraView，相对场景默认构图）。
struct MachiCameraViewValues: Equatable {
    var azimuth: Double = 0       // 度，[−75, 75]
    var elevation: Double = 0     // 度，[−12, 40]
    var zoom: Double = 1          // 倍数，[0.5, 2.8]
    var panX: Double = 0          // 米，[−5, 5]
    var panZ: Double = 0          // 米，[−5, 5]

    static let defaults = MachiCameraViewValues()
}

/// 画质（网页 MachiQuality；renderScale/antialias 的 "global"
/// = 跟随全局挡位，原生舞台无全局挡位消费点，渲染器按不缩放 /
/// 默认抗锯齿处理，见渲染器头注）。
struct MachiQualityValues: Equatable {
    var renderScale: String = "global"
    var antialias: String = "global"
    var shadows: MachiDetailChoice = .high
    var reflections: MachiDetailChoice = .high
    var glow: Bool = true
    var adaptive: Bool = true

    static let defaults = MachiQualityValues()
}

/// 一次读全的参数快照（渲染器逐帧消费的形状）。
struct MachiTuningValues: Equatable {
    var scene: MachiSceneChoice = .auto
    var timeOfDay: MachiTimeChoice = .auto
    var weather: MachiWeatherChoice = .auto
    var camera: MachiCameraChoice = .default
    var viewKonbini = MachiCameraViewValues.defaults
    var viewStation = MachiCameraViewValues.defaults
    var viewKowloon = MachiCameraViewValues.defaults
    var motion: Bool = false
    var motionSpeed: Double = 1
    var aperture: Double = 8
    var dof: Double = 1
    var dofRange: Double = 1
    var tiltShift: Double = 0.3
    var focus: MachiFocusChoice = .center
    var focusOffset: Double = 0
    var simulatedBeat: Bool = true
    var quality = MachiQualityValues.defaults

    static let defaults = MachiTuningValues()

    func view(for scene: MachiSceneId) -> MachiCameraViewValues {
        switch scene {
        case .konbini: return viewKonbini
        case .station: return viewStation
        case .kowloon: return viewKowloon
        }
    }
}

/// 町景调参存储门面：网页 tuning.ts 每个参数一个属性。
enum MachiTuningStore {

    private static let prefix = "folia.tuning.machi."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

    // MARK: 光圈档（网页 MACHI_APERTURE_STOPS / cameraControls）

    /// 光圈档表（f 值，相邻两档进光量差一倍）。
    static let apertureStops: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]

    /// f 值 → 滑块格（轨道反序：第 0 格 f/16、末格 f/1.4，
    /// 不在档上取最近档，网页 machiApertureToTrack 同口径）。
    static func apertureTrackIndex(for aperture: Double) -> Int {
        let track = apertureStops.reversed()
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, stop) in track.enumerated() {
            let distance = abs(log(stop / max(aperture, 0.01)))
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// 滑块格 → f 值（网页 machiApertureFromTrack）。
    static func aperture(atTrackIndex index: Int) -> Double {
        let track = [Double](apertureStops.reversed())
        let clamped = min(track.count - 1, max(0, index))
        return track[clamped]
    }

    // MARK: 基础读写（钳制 / 回缺省与网页 normalize 同义）

    private static func doubleValue(_ name: String, fallback: Double,
                                    range: ClosedRange<Double>) -> Double {
        guard let raw = defaults.object(forKey: key(name)) as? Double else {
            return fallback
        }
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    private static func setDouble(_ name: String, _ value: Double,
                                  range: ClosedRange<Double>) {
        defaults.set(min(range.upperBound, max(range.lowerBound, value)),
                     forKey: key(name))
    }

    private static func boolValue(_ name: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    private static func choiceValue<T: RawRepresentable>(
        _ name: String, fallback: T
    ) -> T where T.RawValue == String {
        defaults.string(forKey: key(name))
            .flatMap { T(rawValue: $0) } ?? fallback
    }

    // MARK: 场景 / 时间 / 天气

    /// 场景，缺省 auto（网页 DEFAULT_MACHI_TUNING.scene）。
    static var scene: MachiSceneChoice {
        get { choiceValue("scene", fallback: .auto) }
        set { defaults.set(newValue.rawValue, forKey: key("scene")) }
    }

    /// 时间，缺省 auto（跟本地时钟，见 environment 的 daylight 表）。
    static var timeOfDay: MachiTimeChoice {
        get { choiceValue("timeOfDay", fallback: .auto) }
        set { defaults.set(newValue.rawValue, forKey: key("timeOfDay")) }
    }

    /// 天气，缺省 auto（按 seed 加权选，见渲染器头注）。
    static var weather: MachiWeatherChoice {
        get { choiceValue("weather", fallback: .auto) }
        set { defaults.set(newValue.rawValue, forKey: key("weather")) }
    }

    // MARK: 镜头

    /// 镜头模式，缺省 default。
    static var camera: MachiCameraChoice {
        get { choiceValue("camera", fallback: .default) }
        set { defaults.set(newValue.rawValue, forKey: key("camera")) }
    }

    /// 某场景的自定义视角（网页 views[scene]，五项各自钳制）。
    static func view(for scene: MachiSceneId) -> MachiCameraViewValues {
        let base = "views.\(scene.rawValue)."
        return MachiCameraViewValues(
            azimuth: doubleValue(base + "azimuth", fallback: 0, range: -75...75),
            elevation: doubleValue(base + "elevation", fallback: 0, range: -12...40),
            zoom: doubleValue(base + "zoom", fallback: 1, range: 0.5...2.8),
            panX: doubleValue(base + "panX", fallback: 0, range: -5...5),
            panZ: doubleValue(base + "panZ", fallback: 0, range: -5...5))
    }

    static func setView(_ view: MachiCameraViewValues, for scene: MachiSceneId) {
        let base = "views.\(scene.rawValue)."
        setDouble(base + "azimuth", view.azimuth, range: -75...75)
        setDouble(base + "elevation", view.elevation, range: -12...40)
        setDouble(base + "zoom", view.zoom, range: 0.5...2.8)
        setDouble(base + "panX", view.panX, range: -5...5)
        setDouble(base + "panZ", view.panZ, range: -5...5)
        cachedValues = nil
        cachedAt = -1
    }

    /// 运镜开关，缺省 false。
    static var motion: Bool {
        get { boolValue("motion", fallback: false) }
        set { defaults.set(newValue, forKey: key("motion")) }
    }

    /// 运镜快慢（倍数），[0.25, 3]，缺省 1。
    static var motionSpeed: Double {
        get { doubleValue("motionSpeed", fallback: 1, range: 0.25...3) }
        set { setDouble("motionSpeed", newValue, range: 0.25...3) }
    }

    // MARK: 景深（MACHI_DOF_LIMITS）

    /// 光圈 f 值，[1.4, 16]，缺省 8（f/8 是网页的微缩感原点）。
    static var aperture: Double {
        get { doubleValue("aperture", fallback: 8, range: 1.4...16) }
        set { setDouble("aperture", newValue, range: 1.4...16) }
    }

    /// 景深强度，[0, 2]，缺省 1（0 = 关）。
    static var dof: Double {
        get { doubleValue("dof", fallback: 1, range: 0...2) }
        set { setDouble("dof", newValue, range: 0...2) }
    }

    /// 清晰范围倍数，[0.3, 3]，缺省 1。
    static var dofRange: Double {
        get { doubleValue("dofRange", fallback: 1, range: 0.3...3) }
        set { setDouble("dofRange", newValue, range: 0.3...3) }
    }

    /// 移轴，[0, 1]，缺省 0.3。
    static var tiltShift: Double {
        get { doubleValue("tiltShift", fallback: 0.3, range: 0...1) }
        set { setDouble("tiltShift", newValue, range: 0...1) }
    }

    /// 对焦在哪，缺省 center。
    static var focus: MachiFocusChoice {
        get { choiceValue("focus", fallback: .center) }
        set { defaults.set(newValue.rawValue, forKey: key("focus")) }
    }

    /// 手动对焦前后（米），[−10, 10]，缺省 0。
    static var focusOffset: Double {
        get { doubleValue("focusOffset", fallback: 0, range: -10...10) }
        set { setDouble("focusOffset", newValue, range: -10...10) }
    }

    // MARK: 灯光

    /// 模拟节拍，缺省 true（无智能动感数据源时霓虹随拍与
    /// 大屏闪拍按固定节拍走，网页 MACHI_BEAT.steady）。
    static var simulatedBeat: Bool {
        get { boolValue("simulatedBeat", fallback: true) }
        set { defaults.set(newValue, forKey: key("simulatedBeat")) }
    }

    // MARK: 画质（quality.*，网页 MachiQuality 逐项拆键存）

    /// 分辨率倍率："global"/"1"/"0.75"/"0.5"，缺省 "global"。
    static var qualityRenderScale: String {
        get {
            let raw = defaults.string(forKey: key("quality.renderScale")) ?? "global"
            return ["global", "1", "0.75", "0.5"].contains(raw) ? raw : "global"
        }
        set {
            defaults.set(["global", "1", "0.75", "0.5"].contains(newValue)
                ? newValue : "global", forKey: key("quality.renderScale"))
        }
    }

    /// 抗锯齿："global"/"off"/"fxaa"/"smaa"/"ssaa"，缺省 "global"。
    static var qualityAntialias: String {
        get {
            let raw = defaults.string(forKey: key("quality.antialias")) ?? "global"
            return ["global", "off", "fxaa", "smaa", "ssaa"].contains(raw)
                ? raw : "global"
        }
        set {
            defaults.set(["global", "off", "fxaa", "smaa", "ssaa"].contains(newValue)
                ? newValue : "global", forKey: key("quality.antialias"))
        }
    }

    /// 阴影档，缺省 high（high=2048 / low=1024 / off=关，网页口径）。
    static var qualityShadows: MachiDetailChoice {
        get { choiceValue("quality.shadows", fallback: .high) }
        set { defaults.set(newValue.rawValue, forKey: key("quality.shadows")) }
    }

    /// 倒影档，缺省 high（原生以镜面高光近似，见渲染器头注）。
    static var qualityReflections: MachiDetailChoice {
        get { choiceValue("quality.reflections", fallback: .high) }
        set { defaults.set(newValue.rawValue, forKey: key("quality.reflections")) }
    }

    /// 辉光（bloom 与镜头光条），缺省 true。
    static var qualityGlow: Bool {
        get { boolValue("quality.glow", fallback: true) }
        set { defaults.set(newValue, forKey: key("quality.glow")) }
    }

    /// 自动降级，缺省 true（原生只存：SCNView 无分级降质
    /// 通路，帧率由系统调度，见渲染器未移植清单）。
    static var qualityAdaptive: Bool {
        get { boolValue("quality.adaptive", fallback: true) }
        set { defaults.set(newValue, forKey: key("quality.adaptive")) }
    }

    static var quality: MachiQualityValues {
        get {
            MachiQualityValues(
                renderScale: qualityRenderScale,
                antialias: qualityAntialias,
                shadows: qualityShadows,
                reflections: qualityReflections,
                glow: qualityGlow,
                adaptive: qualityAdaptive)
        }
        set {
            qualityRenderScale = newValue.renderScale
            qualityAntialias = newValue.antialias
            qualityShadows = newValue.shadows
            qualityReflections = newValue.reflections
            qualityGlow = newValue.glow
            qualityAdaptive = newValue.adaptive
        }
    }

    // MARK: 全量读写

    /// 一次读全（每属性各自钳制/回缺省，与网页 normalize 同义）。
    static func values() -> MachiTuningValues {
        MachiTuningValues(
            scene: scene,
            timeOfDay: timeOfDay,
            weather: weather,
            camera: camera,
            viewKonbini: view(for: .konbini),
            viewStation: view(for: .station),
            viewKowloon: view(for: .kowloon),
            motion: motion,
            motionSpeed: motionSpeed,
            aperture: aperture,
            dof: dof,
            dofRange: dofRange,
            tiltShift: tiltShift,
            focus: focus,
            focusOffset: focusOffset,
            simulatedBeat: simulatedBeat,
            quality: quality)
    }

    /// 写回全量（面板预设/恢复默认用；逐项经属性钳制）。
    static func apply(_ values: MachiTuningValues) {
        scene = values.scene
        timeOfDay = values.timeOfDay
        weather = values.weather
        camera = values.camera
        setView(values.viewKonbini, for: .konbini)
        setView(values.viewStation, for: .station)
        setView(values.viewKowloon, for: .kowloon)
        motion = values.motion
        motionSpeed = values.motionSpeed
        aperture = values.aperture
        dof = values.dof
        dofRange = values.dofRange
        tiltShift = values.tiltShift
        focus = values.focus
        focusOffset = values.focusOffset
        simulatedBeat = values.simulatedBeat
        quality = values.quality
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省（网页 handleResetMachiTuning 同义）。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 StageEffectSettings 先例）

    private static var cachedValues: MachiTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> MachiTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 町景调参面板入口（协调者接线点名形状）。
enum MachiTuning {
    static func makePanel() -> UIViewController {
        MachiTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 町景调参面板：网页 MachiSettingsPanel.tsx 的原生承接。
/// 控件集与网页逐项对应：场景 / 时间 / 天气 / 模拟节拍 /
/// 镜头（模式 + 当前场景五滑块）/ 运镜 / 景深（光圈按档走）/
/// 画质（预设三档 + 细项）。拨动即写 MachiTuningStore，渲染
/// 器经 0.25s 缓存至多 0.25s 后生效。系统风格：systemBackground
/// / label 语义色自动适配深色，字号下限 12pt。
final class MachiTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var refreshers: [() -> Void] = []
    /// 视角滑块调哪个场景（场景=auto 时可挑，缺省 konbini；
    /// 渲染器内的取景条则恒调正在画的场景，见渲染器头注）。
    private var viewScene: MachiSceneId = .konbini

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "町景参数"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshAll()
    }

    private func refreshAll() {
        for refresh in refreshers { refresh() }
    }

    // MARK: 搭建

    private func buildViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        addSection("场景")
        addSegment(title: "场景", items: MachiSceneChoice.allCases.map { $0.displayName },
                   read: { MachiSceneChoice.allCases.firstIndex(of: MachiTuningStore.scene) ?? 0 },
                   write: { MachiTuningStore.scene = MachiSceneChoice.allCases[$0] })
        addSection("天空")
        addSegment(title: "时间", items: MachiTimeChoice.allCases.map { $0.displayName },
                   read: { MachiTimeChoice.allCases.firstIndex(of: MachiTuningStore.timeOfDay) ?? 0 },
                   write: { MachiTuningStore.timeOfDay = MachiTimeChoice.allCases[$0] })
        addSegment(title: "天气", items: MachiWeatherChoice.allCases.map { $0.displayName },
                   read: { MachiWeatherChoice.allCases.firstIndex(of: MachiTuningStore.weather) ?? 0 },
                   write: { MachiTuningStore.weather = MachiWeatherChoice.allCases[$0] })
        addSection("灯光")
        addSwitch(title: "模拟节拍",
                  read: { MachiTuningStore.simulatedBeat },
                  write: { MachiTuningStore.simulatedBeat = $0 })

        addSection("镜头")
        addSegment(title: "镜头模式", items: MachiCameraChoice.allCases.map { $0.displayName },
                   read: { MachiCameraChoice.allCases.firstIndex(of: MachiTuningStore.camera) ?? 0 },
                   write: { MachiTuningStore.camera = MachiCameraChoice.allCases[$0] })
        addSegment(title: "视角所属场景", items: MachiSceneId.allCases.map {
                       MachiSceneChoice(rawValue: $0.rawValue)?.displayName ?? $0.rawValue
                   },
                   read: { MachiSceneId.allCases.firstIndex(of: self.viewScene) ?? 0 },
                   write: { [weak self] index in
                       self?.viewScene = MachiSceneId.allCases[index]
                       self?.refreshAll()
                   })
        addViewSlider(title: "视角 · 转角", field: \.azimuth,
                      range: -75...75, step: 1,
                      format: { String(format: "%+.0f°", $0) })
        addViewSlider(title: "视角 · 俯仰", field: \.elevation,
                      range: -12...40, step: 1,
                      format: { String(format: "%+.0f°", $0) })
        addViewSlider(title: "视角 · 远近", field: \.zoom,
                      range: 0.5...2.8, step: 0.05,
                      format: { String(format: "%.2f×", $0) })
        addViewSlider(title: "视角 · 左右平移", field: \.panX,
                      range: -5...5, step: 0.1,
                      format: { String(format: "%+.1f m", $0) })
        addViewSlider(title: "视角 · 前后平移", field: \.panZ,
                      range: -5...5, step: 0.1,
                      format: { String(format: "%+.1f m", $0) })
        addSwitch(title: "运镜",
                  read: { MachiTuningStore.motion },
                  write: { MachiTuningStore.motion = $0 })
        addSlider(title: "运镜速度",
                  range: 0.25...3, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { MachiTuningStore.motionSpeed },
                  write: { MachiTuningStore.motionSpeed = $0 })

        addSection("景深")
        addApertureSlider()
        addSlider(title: "景深强度",
                  range: 0...2, step: 0.05,
                  format: { String(format: "%.0f%%", $0 * 50) },
                  read: { MachiTuningStore.dof },
                  write: { MachiTuningStore.dof = $0 })
        addSlider(title: "清晰范围",
                  range: 0.3...3, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { MachiTuningStore.dofRange },
                  write: { MachiTuningStore.dofRange = $0 })
        addSlider(title: "移轴",
                  range: 0...1, step: 0.05,
                  format: { String(format: "%.0f%%", $0 * 100) },
                  read: { MachiTuningStore.tiltShift },
                  write: { MachiTuningStore.tiltShift = $0 })
        addSegment(title: "对焦", items: MachiFocusChoice.allCases.map { $0.displayName },
                   read: { MachiFocusChoice.allCases.firstIndex(of: MachiTuningStore.focus) ?? 0 },
                   write: { MachiTuningStore.focus = MachiFocusChoice.allCases[$0] })
        addSlider(title: "手动对焦偏移",
                  range: -10...10, step: 0.1,
                  format: { String(format: "%+.1f m", $0) },
                  read: { MachiTuningStore.focusOffset },
                  write: { MachiTuningStore.focusOffset = $0 })

        addSection("画质")
        addQualityPresetRow()
        addSegment(title: "分辨率", items: ["跟随全局", "100%", "75%", "50%"],
                   read: { ["global", "1", "0.75", "0.5"].firstIndex(of: MachiTuningStore.qualityRenderScale) ?? 0 },
                   write: { MachiTuningStore.qualityRenderScale = ["global", "1", "0.75", "0.5"][$0] })
        addSegment(title: "抗锯齿", items: ["跟随全局", "关", "FXAA", "SMAA", "超采样"],
                   read: { ["global", "off", "fxaa", "smaa", "ssaa"].firstIndex(of: MachiTuningStore.qualityAntialias) ?? 0 },
                   write: { MachiTuningStore.qualityAntialias = ["global", "off", "fxaa", "smaa", "ssaa"][$0] })
        addSegment(title: "阴影", items: MachiDetailChoice.allCases.map { $0.displayName },
                   read: { MachiDetailChoice.allCases.firstIndex(of: MachiTuningStore.qualityShadows) ?? 2 },
                   write: { MachiTuningStore.qualityShadows = MachiDetailChoice.allCases[$0] })
        addSegment(title: "倒影", items: MachiDetailChoice.allCases.map { $0.displayName },
                   read: { MachiDetailChoice.allCases.firstIndex(of: MachiTuningStore.qualityReflections) ?? 2 },
                   write: { MachiTuningStore.qualityReflections = MachiDetailChoice.allCases[$0] })
        addSwitch(title: "辉光",
                  read: { MachiTuningStore.qualityGlow },
                  write: { MachiTuningStore.qualityGlow = $0 })
        addSwitch(title: "自动降级",
                  read: { MachiTuningStore.qualityAdaptive },
                  write: { MachiTuningStore.qualityAdaptive = $0 })

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        let resetRow = UIView()
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetRow.addSubview(resetButton)
        NSLayoutConstraint.activate([
            resetRow.heightAnchor.constraint(equalToConstant: 48),
            resetButton.leadingAnchor.constraint(equalTo: resetRow.leadingAnchor),
            resetButton.centerYAnchor.constraint(equalTo: resetRow.centerYAnchor),
        ])
        stack.addArrangedSubview(resetRow)

        let note = UILabel()
        note.text = "说明：移轴与自动降级在原生只保存数值（SceneKit 无移轴通路、降级由系统调度）；分辨率「跟随全局」按 1× 处理。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
    }

    @objc private func resetTapped() {
        MachiTuningStore.resetAll()
        refreshAll()
    }

    // MARK: 行工厂

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        stack.addArrangedSubview(container)
    }

    private func makeRow(title: String, control: UIControl) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])
        return container
    }

    private func addSwitch(title: String,
                           read: @escaping () -> Bool,
                           write: @escaping (Bool) -> Void) {
        let toggle = UISwitch()
        stack.addArrangedSubview(makeRow(title: title, control: toggle))
        refreshers.append { toggle.isOn = read() }
        toggle.addAction(UIAction { _ in write(toggle.isOn) }, for: .valueChanged)
    }

    private func addSegment(title: String, items: [String],
                            read: @escaping () -> Int,
                            write: @escaping (Int) -> Void) {
        let segment = UISegmentedControl(items: items)
        stack.addArrangedSubview(makeRow(title: title, control: segment))
        refreshers.append {
            let index = read()
            if items.indices.contains(index) {
                segment.selectedSegmentIndex = index
            }
        }
        segment.addAction(UIAction { _ in
            guard items.indices.contains(segment.selectedSegmentIndex) else { return }
            write(segment.selectedSegmentIndex)
        }, for: .valueChanged)
    }

    private func addSlider(title: String,
                           range: ClosedRange<Double>, step: Double,
                           format: @escaping (Double) -> String,
                           read: @escaping () -> Double,
                           write: @escaping (Double) -> Void) {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        for sub in [titleLabel, slider, valueLabel] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 56),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        stack.addArrangedSubview(container)
        refreshers.append {
            let value = read()
            slider.value = Float(value)
            valueLabel.text = format(value)
        }
        slider.addAction(UIAction { _ in
            let raw = Double(slider.value)
            let stepped = (raw / step).rounded() * step
            write(stepped)
            valueLabel.text = format(read())
        }, for: .valueChanged)
    }

    /// 视角五滑块：读写当前 viewScene 那份（写时切到自定义
    /// 模式？网页面板不自动切模式——滑块只在 custom 时出现；
    /// 原生面板恒显示但只写 views，模式由上方分段单独切，
    /// 与网页「默认构图下取景条滑块一动即转 custom」的差异
    /// 只在取景条侧，见渲染器头注）。
    private func addViewSlider(title: String,
                               field: WritableKeyPath<MachiCameraViewValues, Double>,
                               range: ClosedRange<Double>, step: Double,
                               format: @escaping (Double) -> String) {
        addSlider(title: title, range: range, step: step, format: format,
                  read: { [weak self] in
                      guard let self else { return 0 }
                      return MachiTuningStore.view(for: self.viewScene)[keyPath: field]
                  },
                  write: { [weak self] value in
                      guard let self else { return }
                      var view = MachiTuningStore.view(for: self.viewScene)
                      view[keyPath: field] = value
                      MachiTuningStore.setView(view, for: self.viewScene)
                  })
    }

    /// 光圈按档走（网页 SliderRow 同口径：轨道反序、存 f 值）。
    private func addApertureSlider() {
        let maxIndex = Double(MachiTuningStore.apertureStops.count - 1)
        addSlider(title: "光圈",
                  range: 0...maxIndex, step: 1,
                  format: { index in
                      "f/\(MachiTuningStore.aperture(atTrackIndex: Int(index.rounded())))"
                  },
                  read: { Double(MachiTuningStore.apertureTrackIndex(for: MachiTuningStore.aperture)) },
                  write: { MachiTuningStore.aperture = MachiTuningStore.aperture(atTrackIndex: Int($0.rounded())) })
    }

    /// 画质预设三档（网页 MACHI_QUALITY_PRESETS 逐值照搬；
    /// 预设不单独存，细项对不上任何一档时三档均不选中）。
    private func addQualityPresetRow() {
        let segment = UISegmentedControl(items: ["高", "平衡", "低"])
        stack.addArrangedSubview(makeRow(title: "画质预设", control: segment))
        let presets: [MachiQualityValues] = [
            MachiQualityValues(renderScale: "global", antialias: "global",
                               shadows: .high, reflections: .high,
                               glow: true, adaptive: MachiTuningStore.qualityAdaptive),
            MachiQualityValues(renderScale: "global", antialias: "fxaa",
                               shadows: .low, reflections: .low,
                               glow: true, adaptive: MachiTuningStore.qualityAdaptive),
            MachiQualityValues(renderScale: "0.75", antialias: "off",
                               shadows: .off, reflections: .off,
                               glow: false, adaptive: MachiTuningStore.qualityAdaptive),
        ]
        refreshers.append {
            let current = MachiTuningStore.quality
            segment.selectedSegmentIndex = presets.firstIndex {
                $0.renderScale == current.renderScale
                    && $0.antialias == current.antialias
                    && $0.shadows == current.shadows
                    && $0.reflections == current.reflections
                    && $0.glow == current.glow
            } ?? UISegmentedControl.noSegment
        }
        segment.addAction(UIAction { [weak self] _ in
            guard presets.indices.contains(segment.selectedSegmentIndex) else { return }
            MachiTuningStore.quality = presets[segment.selectedSegmentIndex]
            self?.refreshAll()
        }, for: .valueChanged)
    }
}
