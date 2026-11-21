import UIKit

// 浮名 fume 调参存储与面板（3.7 (57) 工作流 C1）：
// 网页版 folia-major/src/components/visualizer/fume/tuning.ts
// 与 src/types.ts 的 FumeTuning / DEFAULT_FUME_TUNING 的原生
// 承接。网页每个参数在本文件 FumeTuningStore 里各有一个属性，
// UserDefaults 键前缀 "folia.tuning.fume."，缺省与钳制与网页
// tuning.ts 的 inRange 逐字对齐（cameraSpeed 0.55…1.85、
// glowIntensity 0…1.8、backgroundObjectOpacity 0…1、
// heroScale 0.82…1.32、textHoldRatio 0…1；cameraTrackingMode
// 只认 stepped/smooth、其余回退缺省 smooth）。
// 渲染器（FumeStageRenderer）的取值序：宿主快照 ext 的
// "fume.*" 覆盖优先，其下以本门面为底（此前 ext 缺项时恒回
// 硬编码缺省，面板改动无从生效——本次接线补齐）。
// render 在网页是一个 {scale, antialias} 对象，原生拆成
// renderScale / renderAntialias 两键；网页浮名面板
// （FumeSettingsPanel）渲染组只给分辨率一行，本面板同义。
// 原生 fume 为 UIKit 矢量绘制、无画布缩放消费点，renderScale
// 仅存档对齐、渲染器不消费（见 C1 报告）。

/// 一次读全的参数快照（渲染器消费的形状）。
struct FumeStoredTuningValues: Equatable {
    var renderScale: String = "global"        // 网页 render.scale
    var renderAntialias: String = "global"    // 网页 render.antialias
    var hidePrintSymbols: Bool = false        // DEFAULT_FUME_TUNING
    var disableGeometricBackground: Bool = true
    var backgroundObjectOpacity: Double = 0.5
    var textHoldRatio: Double = 1
    var cameraTrackingMode: String = "smooth" // "stepped" | "smooth"
    var cameraSpeed: Double = 1
    var glowIntensity: Double = 1
    var heroScale: Double = 1

    static let defaults = FumeStoredTuningValues()
}

/// 浮名调参存储门面：网页 tuning.ts 每个参数一个属性。
enum FumeTuningStore {

    private static let prefix = "folia.tuning.fume."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

    private static func doubleValue(_ name: String, fallback: Double,
                                    range: ClosedRange<Double>) -> Double {
        guard let raw = defaults.object(forKey: key(name)) as? Double,
              raw.isFinite else { return fallback }
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

    // MARK: 分辨率（网页 render: LyricRenderOverride）

    /// 取值集："global" / "0.5" / "0.75" / "1" / "1.5" / "2"。
    static var renderScale: String {
        get {
            let raw = defaults.string(forKey: key("renderScale")) ?? "global"
            return ["global", "0.5", "0.75", "1", "1.5", "2"].contains(raw)
                ? raw : "global"
        }
        set {
            defaults.set(["global", "0.5", "0.75", "1", "1.5", "2"]
                .contains(newValue) ? newValue : "global",
                         forKey: key("renderScale"))
        }
    }

    // MARK: 开关与数值（缺省/钳制 = DEFAULT_FUME_TUNING + tuning.ts）

    static var hidePrintSymbols: Bool {
        get { boolValue("hidePrintSymbols", fallback: false) }
        set { defaults.set(newValue, forKey: key("hidePrintSymbols")) }
    }

    /// 注意缺省为 true（网页 DEFAULT_FUME_TUNING）：几何背景
    /// 默认关；面板开关以「显示几何背景」正向呈现（网页
    /// FumeSettingsPanel 同义：checked = !disable）。
    static var disableGeometricBackground: Bool {
        get { boolValue("disableGeometricBackground", fallback: true) }
        set { defaults.set(newValue, forKey: key("disableGeometricBackground")) }
    }

    static var backgroundObjectOpacity: Double {
        get { doubleValue("backgroundObjectOpacity", fallback: 0.5, range: 0...1) }
        set { setDouble("backgroundObjectOpacity", newValue, range: 0...1) }
    }

    static var textHoldRatio: Double {
        get { doubleValue("textHoldRatio", fallback: 1, range: 0...1) }
        set { setDouble("textHoldRatio", newValue, range: 0...1) }
    }

    /// 只认 "stepped" / "smooth"，其余回退缺省 "smooth"
    /// （网页 tuning.ts cameraTrackingMode 同义）。
    static var cameraTrackingMode: String {
        get {
            let raw = defaults.string(forKey: key("cameraTrackingMode")) ?? "smooth"
            return (raw == "stepped" || raw == "smooth") ? raw : "smooth"
        }
        set {
            defaults.set((newValue == "stepped" || newValue == "smooth")
                ? newValue : "smooth", forKey: key("cameraTrackingMode"))
        }
    }

    static var cameraSpeed: Double {
        get { doubleValue("cameraSpeed", fallback: 1, range: 0.55...1.85) }
        set { setDouble("cameraSpeed", newValue, range: 0.55...1.85) }
    }

    static var glowIntensity: Double {
        get { doubleValue("glowIntensity", fallback: 1, range: 0...1.8) }
        set { setDouble("glowIntensity", newValue, range: 0...1.8) }
    }

    static var heroScale: Double {
        get { doubleValue("heroScale", fallback: 1, range: 0.82...1.32) }
        set { setDouble("heroScale", newValue, range: 0.82...1.32) }
    }

    // MARK: 整组读 / 写 / 还原

    static func values() -> FumeStoredTuningValues {
        var v = FumeStoredTuningValues()
        v.renderScale = renderScale
        v.hidePrintSymbols = hidePrintSymbols
        v.disableGeometricBackground = disableGeometricBackground
        v.backgroundObjectOpacity = backgroundObjectOpacity
        v.textHoldRatio = textHoldRatio
        v.cameraTrackingMode = cameraTrackingMode
        v.cameraSpeed = cameraSpeed
        v.glowIntensity = glowIntensity
        v.heroScale = heroScale
        return v
    }

    static func apply(_ values: FumeStoredTuningValues) {
        renderScale = values.renderScale
        hidePrintSymbols = values.hidePrintSymbols
        disableGeometricBackground = values.disableGeometricBackground
        backgroundObjectOpacity = values.backgroundObjectOpacity
        textHoldRatio = values.textHoldRatio
        cameraTrackingMode = values.cameraTrackingMode
        cameraSpeed = values.cameraSpeed
        glowIntensity = values.glowIntensity
        heroScale = values.heroScale
        cachedValues = nil
        cachedAt = -1
    }

    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 PendoloTuningStore 先例）

    private static var cachedValues: FumeStoredTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> FumeStoredTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 浮名调参面板入口（协调者接线点名形状）。
enum FumeTuning {
    static func makePanel() -> UIViewController {
        FumeTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 浮名调参面板：网页 FumeSettingsPanel 的原生承接，控件集
/// 逐项对应（隐藏印刷符开关、几何背景开关取反呈现、五滑杆
/// 范围/步进照网页 SliderRow 入参、相机模式分段、渲染组只有
/// 分辨率一行）。拨动即写 FumeTuningStore；渲染器在下一次
/// 快照 apply 时以本门面为底取值（ext 覆盖优先）。
/// 系统风格：systemBackground / label 语义色自动适配深色，
/// 字号下限 12pt。
final class FumeTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var switches: [String: UISwitch] = [:]
    private var sliders: [String: UISlider] = [:]
    private var valueLabels: [String: UILabel] = [:]
    private var modeSegment: UISegmentedControl?
    private var renderSegment: UISegmentedControl?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "浮名 · 调参"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
    }

    private func buildViews() {
        // (61) WC：歌词对比保护说明行（全样式统一文案）。
        stack.addArrangedSubview(LyricContrastProtectionNote.makeLabel())
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])

        addSwitch(key: "hidePrintSymbols", title: "隐藏印刷符")
        // 网页口径：开关显示的是「几何背景开」，存的是 disable 取反。
        addSwitch(key: "geometricBackground", title: "几何背景")
        addSlider(key: "backgroundObjectOpacity", title: "背景图形透明度",
                  min: 0, max: 1, step: 0.05, format: "%")
        addSlider(key: "textHoldRatio", title: "文字留存比例",
                  min: 0, max: 1, step: 0.05, format: "%")
        addSlider(key: "cameraSpeed", title: "相机速度",
                  min: 0.55, max: 1.85, step: 0.05, format: "×")

        let modeTitle = UILabel()
        modeTitle.text = "相机跟随模式"
        modeTitle.font = .systemFont(ofSize: 13)
        modeTitle.textColor = .label
        let mode = UISegmentedControl(items: ["步进", "平滑"])
        mode.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        modeSegment = mode
        let modeRow = UIStackView(arrangedSubviews: [modeTitle, mode])
        modeRow.axis = .vertical
        modeRow.spacing = 6
        stack.addArrangedSubview(modeRow)

        addSlider(key: "glowIntensity", title: "辉光强度",
                  min: 0, max: 1.8, step: 0.05, format: "×")
        addSlider(key: "heroScale", title: "主块缩放",
                  min: 0.82, max: 1.32, step: 0.02, format: "×")

        let renderTitle = UILabel()
        renderTitle.text = "渲染分辨率"
        renderTitle.font = .systemFont(ofSize: 13)
        renderTitle.textColor = .label
        let render = UISegmentedControl(items: ["默认", "0.5×", "0.75×", "1×", "1.5×", "2×"])
        render.addTarget(self, action: #selector(renderChanged(_:)), for: .valueChanged)
        renderSegment = render
        let renderRow = UIStackView(arrangedSubviews: [renderTitle, render])
        renderRow.axis = .vertical
        renderRow.spacing = 6
        stack.addArrangedSubview(renderRow)

        let reset = UIButton(type: .system)
        reset.setTitle("恢复默认", for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 14)
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)
    }

    private func addSwitch(key: String, title: String) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = .label
        let toggle = UISwitch()
        toggle.accessibilityIdentifier = key
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        switches[key] = toggle
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        stack.addArrangedSubview(row)
    }

    private func addSlider(key: String, title: String,
                           min: Double, max: Double, step: Double, format: String) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .label
        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.accessibilityIdentifier = format
        valueLabels[key] = valueLabel
        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.tag = Int(step * 1000)
        slider.accessibilityIdentifier = key
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        sliders[key] = slider
        let row = UIStackView(arrangedSubviews: [header, slider])
        row.axis = .vertical
        row.spacing = 4
        stack.addArrangedSubview(row)
    }

    private func formatValue(_ key: String, _ value: Double) -> String {
        if valueLabels[key]?.accessibilityIdentifier == "%" {
            return "\(Int((value * 100).rounded()))%"
        }
        return String(format: "%.2f×", value)
    }

    private func refreshFromStore() {
        let v = FumeTuningStore.values()
        switches["hidePrintSymbols"]?.isOn = v.hidePrintSymbols
        switches["geometricBackground"]?.isOn = !v.disableGeometricBackground
        let numbers: [String: Double] = [
            "backgroundObjectOpacity": v.backgroundObjectOpacity,
            "textHoldRatio": v.textHoldRatio,
            "cameraSpeed": v.cameraSpeed,
            "glowIntensity": v.glowIntensity,
            "heroScale": v.heroScale,
        ]
        for (key, slider) in sliders {
            if let value = numbers[key] { slider.value = Float(value) }
            if let value = numbers[key] {
                valueLabels[key]?.text = formatValue(key, value)
            }
        }
        modeSegment?.selectedSegmentIndex = v.cameraTrackingMode == "stepped" ? 0 : 1
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        renderSegment?.selectedSegmentIndex =
            options.firstIndex(of: v.renderScale) ?? 0
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        switch toggle.accessibilityIdentifier {
        case "hidePrintSymbols":
            FumeTuningStore.hidePrintSymbols = toggle.isOn
        case "geometricBackground":
            FumeTuningStore.disableGeometricBackground = !toggle.isOn
        default: break
        }
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard let key = slider.accessibilityIdentifier else { return }
        let step = Double(slider.tag) / 1000
        var value = Double(slider.value)
        if step > 0 { value = (value / step).rounded() * step }
        switch key {
        case "backgroundObjectOpacity": FumeTuningStore.backgroundObjectOpacity = value
        case "textHoldRatio": FumeTuningStore.textHoldRatio = value
        case "cameraSpeed": FumeTuningStore.cameraSpeed = value
        case "glowIntensity": FumeTuningStore.glowIntensity = value
        case "heroScale": FumeTuningStore.heroScale = value
        default: break
        }
        valueLabels[key]?.text = formatValue(key, value)
    }

    @objc private func modeChanged(_ segment: UISegmentedControl) {
        FumeTuningStore.cameraTrackingMode =
            segment.selectedSegmentIndex == 0 ? "stepped" : "smooth"
    }

    @objc private func renderChanged(_ segment: UISegmentedControl) {
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        guard options.indices.contains(segment.selectedSegmentIndex) else { return }
        FumeTuningStore.renderScale = options[segment.selectedSegmentIndex]
    }

    @objc private func resetTapped() {
        FumeTuningStore.resetAll()
        refreshFromStore()
    }
}
