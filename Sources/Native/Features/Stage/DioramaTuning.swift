import UIKit

// 镜台 diorama 调参（3.7 (57) 工作流 B2）：网页版
// folia-major/src/components/visualizer/diorama/tuning.ts 与
// src/types.ts 的 DEFAULT_DIORAMA_TUNING 逐参数原生承接。
// 存储键前缀 "folia.tuning.diorama."（任务书定名）；缺省与
// 钳制范围逐字对齐网页 resolveStoredDioramaTuning：
//  - cameraSpeed [0.55, 1.85] 缺省 1
//  - motionAmount [0.4, 1.6] 缺省 1
//  - audioReactivity [0, 1.5] 缺省 1（协议无频谱数据源，
//    本参数只存不用于相机，见渲染器头注）
//  - geometryVisibility: enabled 缺省 true、mode 缺省
//    "clouds"（另一档 "corridor"）、strands/blobs/ribbons/
//    rings 缺省全 true（box→strands、sphere→blobs、
//    cone→ribbons、torus→rings，网页 dioramaGeometry.ts 同映射）
//  - particleDensity [96, 1536] 步进 24 缺省 576（每锚点请求点数）
//  - particleScale [0.65, 1.6] 缺省 1（网页 particleScale 与
//    DIORAMA_PARTICLE_SIZE_* 别名同集）
//  - particleGlowEnabled 缺省 true；particleGlowIntensity
//    [0.1, 1.5] 缺省 0.65
//  - showParticles 缺省 true
//  - backgroundParticleCircumference [4, 48] 步进 2 缺省 28
//  - backgroundParticleRadial [1, 4] 步进 1 缺省 2
//    （每行尘埃数 = 圆周 × 径向，缺省 56，与网页旧单滑杆同值）
//  - glowEnabled 缺省 true、glowIntensity [0.1, 1.5] 缺省 1
//  - soulEnabled 缺省 true、soulIntensity [0.1, 1.5] 缺省 1
//  - soulActiveEnabled 缺省 false（当前字漂移子开关，无自有强度）
//  - gradientEnabled 缺省 false、gradientIntensity [0.1, 1.5] 缺省 1
//  - keywordColoringEnabled 缺省 true（协议无主题 wordColors
//    数据源，原生只存不用，见渲染器未移植清单）
//  - render.scale / render.antialias 缺省 "global"（网页
//    LyricRenderOverride 缺省跟随全局；原生渲染分辨率由
//    SCNView 按 bounds×scale 决定，本两项只存不用）
// 面板拨动即写存储；渲染器经 snapshot() 的 0.25s 缓存逐帧读
// （照 StageEffectSettings 先例）。

/// 几何可见性模式（网页 DioramaGeometryMode）。
enum DioramaGeometryMode: String {
    case clouds
    case corridor
}

/// 一份完整调参快照（值类型，渲染器逐帧消费缓存副本）。
struct DioramaTuningValues {
    var cameraSpeed: Double = 1
    var motionAmount: Double = 1
    var audioReactivity: Double = 1
    var geometryEnabled: Bool = true
    var geometryMode: DioramaGeometryMode = .clouds
    var geometryStrands: Bool = true
    var geometryBlobs: Bool = true
    var geometryRibbons: Bool = true
    var geometryRings: Bool = true
    var particleDensity: Int = 576
    var particleScale: Double = 1
    var particleGlowEnabled: Bool = true
    var particleGlowIntensity: Double = 0.65
    var showParticles: Bool = true
    var backgroundParticleCircumference: Int = 28
    var backgroundParticleRadial: Int = 2
    var glowEnabled: Bool = true
    var glowIntensity: Double = 1
    var soulEnabled: Bool = true
    var soulIntensity: Double = 1
    var soulActiveEnabled: Bool = false
    var gradientEnabled: Bool = false
    var gradientIntensity: Double = 1
    var keywordColoringEnabled: Bool = true
    var renderScale: String = "global"
    var renderAntialias: String = "global"

    /// 网页 resolveDioramaMotionParams 的 normal 预设等价物
    /// （原生协议无主题 animationIntensity 字段，subMode 恒
    /// normal：move 1 / drift 0.62 / smooth 0.42 / audio 1 /
    /// weave 1，再乘滑杆）：smoothTime = 0.42 / cameraSpeed。
    var smoothTime: Double { 0.42 / max(cameraSpeed, 0.01) }
    var moveScale: Double { motionAmount }
    var driftScale: Double { 0.62 * motionAmount }
    var weaveScale: Double { motionAmount }
}

enum DioramaTuningStore {

    static let keyPrefix = "folia.tuning.diorama."
    private static let defaults = UserDefaults.standard

    private static func key(_ name: String) -> String { keyPrefix + name }

    private static func doubleValue(_ name: String, fallback: Double,
                                    range: ClosedRange<Double>) -> Double {
        let raw = defaults.object(forKey: key(name)) as? Double ?? fallback
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    private static func boolValue(_ name: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    private static func intValue(_ name: String, fallback: Int,
                                 range: ClosedRange<Int>, step: Int) -> Int {
        let raw = defaults.object(forKey: key(name)) as? Int ?? fallback
        let clamped = min(range.upperBound, max(range.lowerBound, raw))
        guard step > 1 else { return clamped }
        let snapped = Int((Double(clamped - range.lowerBound) / Double(step)).rounded())
            * step + range.lowerBound
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    static func setDouble(_ name: String, _ value: Double) {
        defaults.set(value, forKey: key(name))
    }

    static func setBool(_ name: String, _ value: Bool) {
        defaults.set(value, forKey: key(name))
    }

    static func setInt(_ name: String, _ value: Int) {
        defaults.set(value, forKey: key(name))
    }

    static func setString(_ name: String, _ value: String) {
        defaults.set(value, forKey: key(name))
    }

    /// 全量读取（每次直读 UserDefaults；逐帧消费走下方缓存面）。
    static func load() -> DioramaTuningValues {
        var v = DioramaTuningValues()
        v.cameraSpeed = doubleValue("cameraSpeed", fallback: 1, range: 0.55...1.85)
        v.motionAmount = doubleValue("motionAmount", fallback: 1, range: 0.4...1.6)
        v.audioReactivity = doubleValue("audioReactivity", fallback: 1, range: 0...1.5)
        v.geometryEnabled = boolValue("geometryVisibility.enabled", fallback: true)
        let modeRaw = defaults.string(forKey: key("geometryVisibility.mode")) ?? "clouds"
        v.geometryMode = DioramaGeometryMode(rawValue: modeRaw) ?? .clouds
        v.geometryStrands = boolValue("geometryVisibility.strands", fallback: true)
        v.geometryBlobs = boolValue("geometryVisibility.blobs", fallback: true)
        v.geometryRibbons = boolValue("geometryVisibility.ribbons", fallback: true)
        v.geometryRings = boolValue("geometryVisibility.rings", fallback: true)
        v.particleDensity = intValue("particleDensity", fallback: 576,
                                     range: 96...1536, step: 24)
        v.particleScale = doubleValue("particleScale", fallback: 1, range: 0.65...1.6)
        v.particleGlowEnabled = boolValue("particleGlowEnabled", fallback: true)
        v.particleGlowIntensity = doubleValue("particleGlowIntensity",
                                              fallback: 0.65, range: 0.1...1.5)
        v.showParticles = boolValue("showParticles", fallback: true)
        v.backgroundParticleCircumference = intValue(
            "backgroundParticleCircumference", fallback: 28, range: 4...48, step: 2)
        v.backgroundParticleRadial = intValue(
            "backgroundParticleRadial", fallback: 2, range: 1...4, step: 1)
        v.glowEnabled = boolValue("glowEnabled", fallback: true)
        v.glowIntensity = doubleValue("glowIntensity", fallback: 1, range: 0.1...1.5)
        v.soulEnabled = boolValue("soulEnabled", fallback: true)
        v.soulIntensity = doubleValue("soulIntensity", fallback: 1, range: 0.1...1.5)
        v.soulActiveEnabled = boolValue("soulActiveEnabled", fallback: false)
        v.gradientEnabled = boolValue("gradientEnabled", fallback: false)
        v.gradientIntensity = doubleValue("gradientIntensity", fallback: 1, range: 0.1...1.5)
        v.keywordColoringEnabled = boolValue("keywordColoringEnabled", fallback: true)
        v.renderScale = defaults.string(forKey: key("render.scale")) ?? "global"
        v.renderAntialias = defaults.string(forKey: key("render.antialias")) ?? "global"
        return v
    }

    /// 恢复网页缺省（对应网页 handleResetDioramaTuning：
    /// 整组键移除后 load() 即回缺省）。
    static func resetAll() {
        let names = [
            "cameraSpeed", "motionAmount", "audioReactivity",
            "geometryVisibility.enabled", "geometryVisibility.mode",
            "geometryVisibility.strands", "geometryVisibility.blobs",
            "geometryVisibility.ribbons", "geometryVisibility.rings",
            "particleDensity", "particleScale", "particleGlowEnabled",
            "particleGlowIntensity", "showParticles",
            "backgroundParticleCircumference", "backgroundParticleRadial",
            "glowEnabled", "glowIntensity", "soulEnabled", "soulIntensity",
            "soulActiveEnabled", "gradientEnabled", "gradientIntensity",
            "keywordColoringEnabled", "render.scale", "render.antialias",
        ]
        for name in names { defaults.removeObject(forKey: key(name)) }
        cachedAt = -1
    }

    // MARK: 逐帧读的缓存面（0.25s 刷新，照 StageEffectSettings 先例）

    private static var cached = DioramaTuningValues()
    private static var cachedAt: CFTimeInterval = -1

    static func snapshot(now: CFTimeInterval) -> DioramaTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 {
            cached = load()
            cachedAt = now
        }
        return cached
    }
}

// MARK: - 调参面板

enum DioramaTuning {
    static func makePanel() -> UIViewController {
        DioramaTuningPanelViewController()
    }
}

/// 镜台调参面板：UIKit 系统风格、深色底、字号 ≥12pt；
/// 每项拨动即写 DioramaTuningStore，舞台至多 0.25s 后生效。
final class DioramaTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var refreshers: [() -> Void] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "镜台调参"
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildViews()
        refreshAll()
    }

    private func refreshAll() {
        for refresh in refreshers { refresh() }
    }

    private func buildViews() {
        let titleLabel = UILabel()
        titleLabel.text = "镜台调参"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        addSection("相机与运动")
        addSlider(title: "相机速度", keyName: "cameraSpeed",
                  range: 0.55...1.85, fallback: 1, format: "%.2f")
        addSlider(title: "运动幅度", keyName: "motionAmount",
                  range: 0.4...1.6, fallback: 1, format: "%.2f")
        addSlider(title: "音频反应", keyName: "audioReactivity",
                  range: 0...1.5, fallback: 1, format: "%.2f",
                  note: "协议暂无频谱数据源，当前只保存不驱动画面")

        addSection("几何陈列")
        addSwitch(title: "显示几何层", keyName: "geometryVisibility.enabled", fallback: true)
        addModeSegment()
        addSwitch(title: "丝束（方块）", keyName: "geometryVisibility.strands", fallback: true)
        addSwitch(title: "团块（球体）", keyName: "geometryVisibility.blobs", fallback: true)
        addSwitch(title: "缎带（锥体）", keyName: "geometryVisibility.ribbons", fallback: true)
        addSwitch(title: "圆环", keyName: "geometryVisibility.rings", fallback: true)

        addSection("粒子")
        addIntSlider(title: "粒子密度", keyName: "particleDensity",
                     range: 96...1536, step: 24, fallback: 576)
        addSlider(title: "粒子缩放", keyName: "particleScale",
                  range: 0.65...1.6, fallback: 1, format: "%.2f")
        addSwitch(title: "粒子辉光", keyName: "particleGlowEnabled", fallback: true)
        addSlider(title: "粒子辉光强度", keyName: "particleGlowIntensity",
                  range: 0.1...1.5, fallback: 0.65, format: "%.2f")
        addSwitch(title: "背景尘埃", keyName: "showParticles", fallback: true)
        addIntSlider(title: "尘埃·圆周密度", keyName: "backgroundParticleCircumference",
                     range: 4...48, step: 2, fallback: 28)
        addIntSlider(title: "尘埃·径向密度", keyName: "backgroundParticleRadial",
                     range: 1...4, step: 1, fallback: 2)

        addSection("跟唱特效")
        addSwitch(title: "辉光跟唱", keyName: "glowEnabled", fallback: true)
        addSlider(title: "辉光强度", keyName: "glowIntensity",
                  range: 0.1...1.5, fallback: 1, format: "%.2f")
        addSwitch(title: "灵魂出窍", keyName: "soulEnabled", fallback: true)
        addSlider(title: "灵魂强度", keyName: "soulIntensity",
                  range: 0.1...1.5, fallback: 1, format: "%.2f")
        addSwitch(title: "当前字漂移", keyName: "soulActiveEnabled", fallback: false,
                  note: "灵魂出窍的子开关，借用灵魂强度")
        addSwitch(title: "渐变跟唱", keyName: "gradientEnabled", fallback: false)
        addSlider(title: "渐变强度", keyName: "gradientIntensity",
                  range: 0.1...1.5, fallback: 1, format: "%.2f")
        addSwitch(title: "关键字着色", keyName: "keywordColoringEnabled", fallback: true,
                  note: "协议暂无主题关键字数据源，当前只保存不驱动画面")

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        let resetRow = UIView()
        resetRow.addSubview(resetButton)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resetRow.heightAnchor.constraint(equalToConstant: 48),
            resetButton.leadingAnchor.constraint(equalTo: resetRow.leadingAnchor),
            resetButton.centerYAnchor.constraint(equalTo: resetRow.centerYAnchor),
        ])
        stack.addArrangedSubview(resetRow)
    }

    @objc private func resetTapped() {
        DioramaTuningStore.resetAll()
        refreshAll()
        Breadcrumbs.log("stage.diorama.tuning reset")
    }

    // MARK: 行构建

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.55)
        let container = UIView()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        stack.addArrangedSubview(container)
    }

    private func addSwitch(title: String, keyName: String, fallback: Bool,
                           note: String? = nil) {
        let toggle = UISwitch()
        let row = makeRow(title: title, note: note, control: toggle)
        stack.addArrangedSubview(row)
        let refresh = {
            toggle.isOn = DioramaTuningStore.loadBool(keyName, fallback: fallback)
        }
        refreshers.append(refresh)
        toggle.addAction(UIAction { _ in
            DioramaTuningStore.setBool(keyName, toggle.isOn)
            Breadcrumbs.log("stage.diorama.tuning \(keyName)=\(toggle.isOn)")
        }, for: .valueChanged)
    }

    private func addSlider(title: String, keyName: String,
                           range: ClosedRange<Double>, fallback: Double,
                           format: String, note: String? = nil) {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        let row = makeSliderRow(title: title, note: note, slider: slider, valueLabel: valueLabel)
        stack.addArrangedSubview(row)
        let refresh = {
            let value = DioramaTuningStore.loadDouble(keyName, fallback: fallback, range: range)
            slider.value = Float(value)
            valueLabel.text = String(format: format, value)
        }
        refreshers.append(refresh)
        slider.addAction(UIAction { _ in
            let value = Double(slider.value)
            DioramaTuningStore.setDouble(keyName, value)
            valueLabel.text = String(format: format, value)
        }, for: .valueChanged)
    }

    private func addIntSlider(title: String, keyName: String,
                              range: ClosedRange<Int>, step: Int, fallback: Int) {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        let row = makeSliderRow(title: title, note: nil, slider: slider, valueLabel: valueLabel)
        stack.addArrangedSubview(row)
        let refresh = {
            let value = DioramaTuningStore.loadInt(keyName, fallback: fallback,
                                                   range: range, step: step)
            slider.value = Float(value)
            valueLabel.text = "\(value)"
        }
        refreshers.append(refresh)
        slider.addAction(UIAction { _ in
            let raw = Int(slider.value.rounded())
            let snapped = step > 1
                ? range.lowerBound + Int((Double(raw - range.lowerBound) / Double(step)).rounded()) * step
                : raw
            let value = min(range.upperBound, max(range.lowerBound, snapped))
            DioramaTuningStore.setInt(keyName, value)
            valueLabel.text = "\(value)"
        }, for: .valueChanged)
    }

    private func addModeSegment() {
        let segment = UISegmentedControl(items: ["点云阵列", "走廊隧道"])
        let row = makeRow(title: "几何模式", note: nil, control: segment)
        stack.addArrangedSubview(row)
        let refresh = {
            segment.selectedSegmentIndex =
                DioramaTuningStore.load().geometryMode == .corridor ? 1 : 0
        }
        refreshers.append(refresh)
        segment.addAction(UIAction { _ in
            let mode = segment.selectedSegmentIndex == 1 ? "corridor" : "clouds"
            DioramaTuningStore.setString("geometryVisibility.mode", mode)
            Breadcrumbs.log("stage.diorama.tuning mode=\(mode)")
        }, for: .valueChanged)
    }

    private func makeRow(title: String, note: String?, control: UIControl) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        var constraints: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            container.heightAnchor.constraint(equalToConstant: note == nil ? 48 : 58),
        ]
        if let note {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = .systemFont(ofSize: 12)
            noteLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            noteLabel.numberOfLines = 1
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(noteLabel)
            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                noteLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            ])
        } else {
            constraints.append(
                titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func makeSliderRow(title: String, note: String?,
                               slider: UISlider, valueLabel: UILabel) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)
        var constraints: [NSLayoutConstraint] = [
            container.heightAnchor.constraint(equalToConstant: note == nil ? 48 : 58),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 44),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
        ]
        if let note {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = .systemFont(ofSize: 12)
            noteLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(noteLabel)
            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                noteLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
                slider.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 5),
                valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 5),
            ])
        } else {
            constraints.append(contentsOf: [
                titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }
}

// MARK: - 面板用的便捷读取（与 load() 同钳制口径）

extension DioramaTuningStore {
    static func loadBool(_ name: String, fallback: Bool) -> Bool {
        boolValue(name, fallback: fallback)
    }

    static func loadDouble(_ name: String, fallback: Double,
                           range: ClosedRange<Double>) -> Double {
        doubleValue(name, fallback: fallback, range: range)
    }

    static func loadInt(_ name: String, fallback: Int,
                        range: ClosedRange<Int>, step: Int) -> Int {
        intValue(name, fallback: fallback, range: range, step: step)
    }
}
