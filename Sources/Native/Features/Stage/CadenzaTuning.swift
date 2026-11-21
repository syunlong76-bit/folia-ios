import UIKit

// 心象 cadenza 调参存储与面板（3.7 (57) 工作流 C1）：
// 网页版 folia-major/src/components/visualizer/cadenza/tuning.ts
// 与 src/types.ts 的 CadenzaTuning / DEFAULT_CADENZA_TUNING 的
// 原生承接。网页每个参数在本文件 CadenzaTuningStore 里各有一
// 个属性，UserDefaults 键前缀 "folia.tuning.cadenza."，缺省值
// 与网页逐字对齐；渲染器（CadenzaStageRenderer）只经本门面
// 读参，逐帧读走 0.25s 缓存（照 PendoloTuningStore 先例）。
// 网页口径注记：
//  - beamIntensity 网页已废弃：tuning.ts 的 read/merge 恒强制
//    为 0，本门面同义（只读恒 0、不落键、面板不给控件）。
//  - fontScale / widthRatio / motionAmount / glowIntensity 网页
//    tuning.ts 不设数值钳制（fontScale 的实际落点由准备态
//    chooseFontPx 结果再 clamp 24…132 决定，渲染器已照此落）；
//    本门面的钳制范围即下方滑杆范围，仅为面板可达域。
//  - render 在网页是一个 {scale, antialias} 对象，原生拆成
//    renderScale / renderAntialias 两键；网页心象面板
//    （CadenzaSettingsPanel）只给分辨率一行、不给抗锯齿
//    （LyricRenderQualityRows antialias={false}），本面板同义
//    只出 scale 一行，antialias 恒 "global" 只存类型对齐。
//  - 网页 reset 只还原 render（面板上只有渲染一组，其余字段
//    只能靠配置导入得到）；原生面板把其余字段一并出成可调项
//    （任务书 C1 第 3 条），按网页同一规则「reset 覆盖面板
//    可见项」，原生 resetAll 还原全部字段，此差异在此注明。

/// 一次读全的参数快照（渲染器逐帧消费的形状）。
struct CadenzaTuningValues: Equatable {
    var renderScale: String = "global"        // 网页 render.scale
    var renderAntialias: String = "global"    // 网页 render.antialias
    var fontScale: Double = 1.12              // DEFAULT_CADENZA_TUNING
    var widthRatio: Double = 0.72
    var motionAmount: Double = 1
    var glowIntensity: Double = 1
    /// 网页恒 0（已废弃），仅为类型对齐保留。
    var beamIntensity: Double = 0

    static let defaults = CadenzaTuningValues()
}

/// 心象调参存储门面：网页 tuning.ts 每个参数一个属性。
enum CadenzaTuningStore {

    private static let prefix = "folia.tuning.cadenza."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

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

    /// render 倍率的数值落点："global" → nil（跟随全局挡位；
    /// 原生 cadenza 为 UIKit 矢量绘制、无画布缩放消费点，
    /// 渲染器不消费本值，仅存档对齐，见 C1 报告）。
    static var renderScaleValue: Double? {
        let raw = renderScale
        return raw == "global" ? nil : Double(raw)
    }

    // MARK: 版式与运动（缺省 = DEFAULT_CADENZA_TUNING）

    /// 字号倍率，缺省 1.12，面板范围 0.5…2。
    static var fontScale: Double {
        get { doubleValue("fontScale", fallback: 1.12, range: 0.5...2) }
        set { setDouble("fontScale", newValue, range: 0.5...2) }
    }

    /// 行宽占视口宽比例，缺省 0.72，面板范围 0.3…1。
    static var widthRatio: Double {
        get { doubleValue("widthRatio", fallback: 0.72, range: 0.3...1) }
        set { setDouble("widthRatio", newValue, range: 0.3...1) }
    }

    /// 运动量（verticalLift / localFloat / active 脉动幅度），
    /// 缺省 1，面板范围 0…2。
    static var motionAmount: Double {
        get { doubleValue("motionAmount", fallback: 1, range: 0...2) }
        set { setDouble("motionAmount", newValue, range: 0...2) }
    }

    /// 辉光强度（网页以 max(glowIntensity, 0) 乘进辉光 alpha），
    /// 缺省 1，面板范围 0…2。
    static var glowIntensity: Double {
        get { doubleValue("glowIntensity", fallback: 1, range: 0...2) }
        set { setDouble("glowIntensity", newValue, range: 0...2) }
    }

    /// 网页恒 0：不落键、不可写。
    static var beamIntensity: Double { 0 }

    // MARK: 整组读 / 写 / 还原

    static func values() -> CadenzaTuningValues {
        var v = CadenzaTuningValues()
        v.renderScale = renderScale
        v.fontScale = fontScale
        v.widthRatio = widthRatio
        v.motionAmount = motionAmount
        v.glowIntensity = glowIntensity
        v.beamIntensity = 0
        return v
    }

    static func apply(_ values: CadenzaTuningValues) {
        renderScale = values.renderScale
        fontScale = values.fontScale
        widthRatio = values.widthRatio
        motionAmount = values.motionAmount
        glowIntensity = values.glowIntensity
        cachedValues = nil
        cachedAt = -1
    }

    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 PendoloTuningStore 先例）

    private static var cachedValues: CadenzaTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> CadenzaTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 心象调参面板入口（协调者接线点名形状）。
enum CadenzaTuning {
    static func makePanel() -> UIViewController {
        CadenzaTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 心象调参面板：网页 CadenzaSettingsPanel（仅渲染组）＋
/// DEFAULT_CADENZA_TUNING 其余字段的原生承接（C1 第 3 条）。
/// 拨动即写 CadenzaTuningStore，渲染器经 0.25s 缓存至多
/// 0.25s 后生效。系统风格：systemBackground / label 语义色
/// 自动适配深色，字号下限 12pt。
final class CadenzaTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var valueLabels: [String: UILabel] = [:]
    private var sliders: [String: UISlider] = [:]
    private var renderSegment: UISegmentedControl?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "心象 · 调参"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
    }

    private func buildViews() {
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

        addSlider(key: "fontScale", title: "字号倍率", min: 0.5, max: 2, step: 0.01)
        addSlider(key: "widthRatio", title: "行宽比例", min: 0.3, max: 1, step: 0.01)
        addSlider(key: "motionAmount", title: "运动量", min: 0, max: 2, step: 0.05)
        addSlider(key: "glowIntensity", title: "辉光强度", min: 0, max: 2, step: 0.05)

        // 渲染组（网页面板唯一一组）：只有分辨率、无抗锯齿行。
        let renderTitle = UILabel()
        renderTitle.text = "渲染分辨率"
        renderTitle.font = .systemFont(ofSize: 13)
        renderTitle.textColor = .label
        let segment = UISegmentedControl(items: ["默认", "0.5×", "0.75×", "1×", "1.5×", "2×"])
        segment.addTarget(self, action: #selector(renderChanged(_:)), for: .valueChanged)
        renderSegment = segment
        let renderRow = UIStackView(arrangedSubviews: [renderTitle, segment])
        renderRow.axis = .vertical
        renderRow.spacing = 6
        stack.addArrangedSubview(renderRow)

        let reset = UIButton(type: .system)
        reset.setTitle("恢复默认", for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 14)
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)
    }

    private func makeRow(title: String, control: UIControl) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .label
        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        let row = UIStackView(arrangedSubviews: [header, control])
        row.axis = .vertical
        row.spacing = 4
        return row
    }

    private func addSlider(key: String, title: String,
                           min: Double, max: Double, step: Double) {
        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.tag = Int(step * 1000)
        slider.accessibilityIdentifier = key
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        sliders[key] = slider
        let row = makeRow(title: title, control: slider)
        if let header = row.arrangedSubviews.first as? UIStackView,
           let valueLabel = header.arrangedSubviews.last as? UILabel {
            valueLabels[key] = valueLabel
        }
        stack.addArrangedSubview(row)
    }

    private func refreshFromStore() {
        let v = CadenzaTuningStore.values()
        let numbers: [String: Double] = [
            "fontScale": v.fontScale, "widthRatio": v.widthRatio,
            "motionAmount": v.motionAmount, "glowIntensity": v.glowIntensity,
        ]
        for (key, slider) in sliders {
            if let value = numbers[key] { slider.value = Float(value) }
            valueLabels[key]?.text = String(format: "%.2f", numbers[key] ?? 0)
        }
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        renderSegment?.selectedSegmentIndex =
            options.firstIndex(of: v.renderScale) ?? 0
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard let key = slider.accessibilityIdentifier else { return }
        let step = Double(slider.tag) / 1000
        var value = Double(slider.value)
        if step > 0 { value = (value / step).rounded() * step }
        switch key {
        case "fontScale": CadenzaTuningStore.fontScale = value
        case "widthRatio": CadenzaTuningStore.widthRatio = value
        case "motionAmount": CadenzaTuningStore.motionAmount = value
        case "glowIntensity": CadenzaTuningStore.glowIntensity = value
        default: break
        }
        valueLabels[key]?.text = String(format: "%.2f", value)
    }

    @objc private func renderChanged(_ segment: UISegmentedControl) {
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        guard options.indices.contains(segment.selectedSegmentIndex) else { return }
        CadenzaTuningStore.renderScale = options[segment.selectedSegmentIndex]
    }

    @objc private func resetTapped() {
        CadenzaTuningStore.resetAll()
        refreshFromStore()
    }
}
