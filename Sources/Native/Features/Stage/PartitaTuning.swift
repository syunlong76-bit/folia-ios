import UIKit

// 云阶 partita 调参存储与面板（3.7 (57) 工作流 C1）：
// 网页版 folia-major/src/components/visualizer/partita/tuning.ts
// 与 src/types.ts 的 PartitaTuning / DEFAULT_PARTITA_TUNING、
// partitaLayout.resolvePartitaTuning 的原生承接。网页每个参数
// 在本文件 PartitaTuningStore 里各有一个属性，UserDefaults 键
// 前缀 "folia.tuning.partita."，缺省与钳制与网页逐字对齐：
//  - stagger 钳制 0…180（clampPartitaStagger），读时以
//    min/max 归序（resolve：smaller first）；
//  - 面板拖动一端越过另一端时带着另一端一起走（settingsPanels
//    的 handlePartitaMin/MaxChange），本面板 sliderChanged 同义；
//  - 网页 tuning.ts 无自定义 reset → 还原即全字段回缺省。

/// 一次读全的参数快照（渲染器消费的形状，已归序）。
struct PartitaTuningValues: Equatable {
    var showGuideLines: Bool = true       // DEFAULT_PARTITA_TUNING
    var useSemanticLayout: Bool = true
    var staggerMin: Double = 20
    var staggerMax: Double = 100
    var avoidOverlap: Bool = false

    static let defaults = PartitaTuningValues()

    /// resolvePartitaTuning 的归序：两端钳 0…180、小者为 min。
    var resolved: PartitaTuningValues {
        var v = self
        let lo = min(max(min(staggerMin, staggerMax), 0), 180)
        let hi = min(max(max(staggerMin, staggerMax), 0), 180)
        v.staggerMin = lo
        v.staggerMax = hi
        return v
    }
}

/// 云阶调参存储门面：网页 tuning.ts 每个参数一个属性。
enum PartitaTuningStore {

    private static let prefix = "folia.tuning.partita."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

    private static func boolValue(_ name: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    /// clampPartitaStagger：有限值钳 0…180，非有限回退缺省。
    private static func staggerValue(_ name: String, fallback: Double) -> Double {
        guard let raw = defaults.object(forKey: key(name)) as? Double,
              raw.isFinite else { return fallback }
        return min(180, max(0, raw))
    }

    static var showGuideLines: Bool {
        get { boolValue("showGuideLines", fallback: true) }
        set { defaults.set(newValue, forKey: key("showGuideLines")) }
    }

    static var useSemanticLayout: Bool {
        get { boolValue("useSemanticLayout", fallback: true) }
        set { defaults.set(newValue, forKey: key("useSemanticLayout")) }
    }

    static var staggerMin: Double {
        get { staggerValue("staggerMin", fallback: 20) }
        set { defaults.set(min(180, max(0, newValue)), forKey: key("staggerMin")) }
    }

    static var staggerMax: Double {
        get { staggerValue("staggerMax", fallback: 100) }
        set { defaults.set(min(180, max(0, newValue)), forKey: key("staggerMax")) }
    }

    static var avoidOverlap: Bool {
        get { boolValue("avoidOverlap", fallback: false) }
        set { defaults.set(newValue, forKey: key("avoidOverlap")) }
    }

    // MARK: 整组读 / 写 / 还原

    static func values() -> PartitaTuningValues {
        var v = PartitaTuningValues()
        v.showGuideLines = showGuideLines
        v.useSemanticLayout = useSemanticLayout
        v.staggerMin = staggerMin
        v.staggerMax = staggerMax
        v.avoidOverlap = avoidOverlap
        return v.resolved
    }

    static func apply(_ values: PartitaTuningValues) {
        showGuideLines = values.showGuideLines
        useSemanticLayout = values.useSemanticLayout
        staggerMin = values.staggerMin
        staggerMax = values.staggerMax
        avoidOverlap = values.avoidOverlap
        cachedValues = nil
        cachedAt = -1
    }

    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 PendoloTuningStore 先例）

    private static var cachedValues: PartitaTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> PartitaTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 云阶调参面板入口（协调者接线点名形状）。
enum PartitaTuning {
    static func makePanel() -> UIViewController {
        PartitaTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 云阶调参面板：网页 PartitaSettingsPanel 的原生承接，控件集
/// 逐项对应（引导线/语义布局/防重叠三开关 + stagger 双滑杆
/// 0…180 步进 5px，一端越过另一端带着走）。拨动即写
/// PartitaTuningStore，渲染器经 0.25s 缓存至多 0.25s 后生效。
/// 系统风格：systemBackground / label 语义色自动适配深色，
/// 字号下限 12pt。
final class PartitaTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var switches: [String: UISwitch] = [:]
    private var sliders: [String: UISlider] = [:]
    private var valueLabels: [String: UILabel] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "云阶 · 调参"
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

        addSwitch(key: "showGuideLines", title: "引导线")
        addSwitch(key: "useSemanticLayout", title: "语义布局")
        addSwitch(key: "avoidOverlap", title: "防止文字重叠")
        addSlider(key: "staggerMin", title: "错位下限")
        addSlider(key: "staggerMax", title: "错位上限")

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

    private func addSlider(key: String, title: String) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .label
        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabels[key] = valueLabel
        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 180
        slider.accessibilityIdentifier = key
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        sliders[key] = slider
        let row = UIStackView(arrangedSubviews: [header, slider])
        row.axis = .vertical
        row.spacing = 4
        stack.addArrangedSubview(row)
    }

    private func refreshFromStore() {
        let v = PartitaTuningStore.values()
        switches["showGuideLines"]?.isOn = v.showGuideLines
        switches["useSemanticLayout"]?.isOn = v.useSemanticLayout
        switches["avoidOverlap"]?.isOn = v.avoidOverlap
        sliders["staggerMin"]?.value = Float(v.staggerMin)
        sliders["staggerMax"]?.value = Float(v.staggerMax)
        valueLabels["staggerMin"]?.text = "\(Int(v.staggerMin))px"
        valueLabels["staggerMax"]?.text = "\(Int(v.staggerMax))px"
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        switch toggle.accessibilityIdentifier {
        case "showGuideLines": PartitaTuningStore.showGuideLines = toggle.isOn
        case "useSemanticLayout": PartitaTuningStore.useSemanticLayout = toggle.isOn
        case "avoidOverlap": PartitaTuningStore.avoidOverlap = toggle.isOn
        default: break
        }
    }

    /// 网页面板口径：一端被拖过另一端时带着另一端一起走
    /// （两端同写），而不是靠 merge 交换两端。
    @objc private func sliderChanged(_ slider: UISlider) {
        let value = Double((slider.value / 5).rounded() * 5)
        let current = PartitaTuningStore.values()
        if slider.accessibilityIdentifier == "staggerMin" {
            PartitaTuningStore.staggerMin = value
            PartitaTuningStore.staggerMax = max(value, current.staggerMax)
        } else if slider.accessibilityIdentifier == "staggerMax" {
            PartitaTuningStore.staggerMin = min(current.staggerMin, value)
            PartitaTuningStore.staggerMax = value
        }
        refreshFromStore()
    }

    @objc private func resetTapped() {
        PartitaTuningStore.resetAll()
        refreshFromStore()
    }
}
