import UIKit

// 倾诉 tilt 调参存储与面板（3.7 (57) 工作流 C2）：
// 网页版 folia-major/src/components/visualizer/tilt/tuning.ts、
// src/types.ts 的 TiltTuning / DEFAULT_TILT_TUNING 与
// settingsPanels.tsx 的 TiltSettingsPanel 的原生承接。
// UserDefaults 键前缀 "folia.tuning.tilt."；缺省与钳制逐字
// 对齐网页 resolve()：splitProbability / tiltStyleProbability
// 均钳 [0, 1]，colorScheme 取值集 default/swap/accentAll/
// primaryAll、不认识的存值回 default（网页 ?? base 口径）。
// 渲染器（TiltStageRenderer）只经本门面读参，逐帧读走 0.25s
// 缓存（照 StageEffectSettings / PendoloTuningStore 先例）。

/// 配色方案（网页 TiltColorScheme；TiltLine.getColors 口径）：
/// default = 正段 primary / 倾段 accent；swap = 正段 accent /
/// 倾段 primary；accentAll = 两段皆 accent；primaryAll = 皆
/// primary（accent 缺失时网页以 primary 兜底，原生调色板
/// accent 恒有值，不另设兜底）。
enum TiltColorScheme: String, CaseIterable {
    case `default`
    case swap
    case accentAll
    case primaryAll

    var displayName: String {
        switch self {
        case .default: return "默认"
        case .swap: return "互换"
        case .accentAll: return "全强调"
        case .primaryAll: return "全主色"
        }
    }
}

/// 一次读全的参数快照（渲染器消费的形状）。
struct TiltTuningValues: Equatable {
    var splitProbability: Double = 0.75
    var tiltStyleProbability: Double = 0.35
    var colorScheme: TiltColorScheme = .default

    static let defaults = TiltTuningValues()
}

/// 倾诉调参存储门面：网页 tuning.ts 每个参数一个属性。
enum TiltTuningStore {

    private static let prefix = "folia.tuning.tilt."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

    private static func probability(_ name: String, fallback: Double) -> Double {
        guard let raw = defaults.object(forKey: key(name)) as? Double else {
            return fallback
        }
        return min(1, max(0, raw))
    }

    /// 分段概率，[0, 1]，缺省 0.75（DEFAULT_TILT_TUNING）。
    static var splitProbability: Double {
        get { probability("splitProbability", fallback: 0.75) }
        set { defaults.set(min(1, max(0, newValue)), forKey: key("splitProbability")) }
    }

    /// 倾斜段概率，[0, 1]，缺省 0.35（DEFAULT_TILT_TUNING）。
    static var tiltStyleProbability: Double {
        get { probability("tiltStyleProbability", fallback: 0.35) }
        set { defaults.set(min(1, max(0, newValue)), forKey: key("tiltStyleProbability")) }
    }

    /// 配色方案，缺省 default；不认识的存值回 default。
    static var colorScheme: TiltColorScheme {
        get {
            defaults.string(forKey: key("colorScheme"))
                .flatMap { TiltColorScheme(rawValue: $0) } ?? .default
        }
        set { defaults.set(newValue.rawValue, forKey: key("colorScheme")) }
    }

    /// 一次读全（每属性各自钳制/回缺省，与网页 resolve 同义）。
    static func values() -> TiltTuningValues {
        TiltTuningValues(splitProbability: splitProbability,
                         tiltStyleProbability: tiltStyleProbability,
                         colorScheme: colorScheme)
    }

    /// 写回全量（恢复默认用；逐项经属性钳制）。
    static func apply(_ values: TiltTuningValues) {
        splitProbability = values.splitProbability
        tiltStyleProbability = values.tiltStyleProbability
        colorScheme = values.colorScheme
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 StageEffectSettings 先例）

    private static var cachedValues: TiltTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> TiltTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 倾诉调参面板入口（协调者接线点名形状）。
enum TiltTuning {
    static func makePanel() -> UIViewController {
        TiltTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 倾诉调参面板：网页 TiltSettingsPanel 的原生承接。控件集
/// 与网页逐项对应：配色方案四档（网页为 PictureGrid 图示
/// 选择，原生以分段控件承接、档位与取值集一致）、分段概率
/// 与倾斜概率两条滑杆（网页 min 0 / max 1 / step 0.05、百分
/// 比格式）。拨动即写 TiltTuningStore，渲染器经 0.25s 缓存
/// 生效（已缓存的行布局在下一次布局指纹变化时重建）。系统
/// 风格：systemBackground / label 语义色适配深色，字号 ≥12pt。
final class TiltTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var splitSlider: UISlider?
    private var splitValueLabel: UILabel?
    private var tiltSlider: UISlider?
    private var tiltValueLabel: UILabel?
    private var schemeSegment: UISegmentedControl?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "倾诉参数"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
    }

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

        // 配色方案（网页 PictureGrid 四档）。
        let scheme = UISegmentedControl(
            items: TiltColorScheme.allCases.map { $0.displayName })
        scheme.addTarget(self, action: #selector(schemeChanged), for: .valueChanged)
        schemeSegment = scheme
        stack.addArrangedSubview(makeRow(title: "配色方案", control: scheme))

        let split = addSlider(title: "分段概率",
                              action: #selector(splitChanged(_:)))
        splitSlider = split.slider
        splitValueLabel = split.valueLabel
        let tilt = addSlider(title: "倾斜概率",
                             action: #selector(tiltChanged(_:)))
        tiltSlider = tilt.slider
        tiltValueLabel = tilt.valueLabel

        let reset = UIButton(type: .system)
        reset.setTitle("恢复默认", for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        reset.backgroundColor = .secondarySystemBackground
        reset.layer.cornerRadius = 8
        reset.heightAnchor.constraint(equalToConstant: 40).isActive = true
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)

        let note = UILabel()
        note.text = "说明：配色与概率在下一行歌词布局时生效；已显示的行不中途换装（与网页按行重算布局一致）。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
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

    private func addSlider(title: String, action: Selector)
        -> (slider: UISlider, valueLabel: UILabel) {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.addTarget(self, action: action, for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 52),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        stack.addArrangedSubview(container)
        return (slider, valueLabel)
    }

    /// 网页 step 0.05：写入时吸附（与 PendoloTuning 面板同口径）。
    private func snapped(_ slider: UISlider) -> Double {
        (Double(slider.value) / 0.05).rounded() * 0.05
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func refreshFromStore() {
        let values = TiltTuningStore.values()
        splitSlider?.value = Float(values.splitProbability)
        splitValueLabel?.text = percent(values.splitProbability)
        tiltSlider?.value = Float(values.tiltStyleProbability)
        tiltValueLabel?.text = percent(values.tiltStyleProbability)
        if let index = TiltColorScheme.allCases.firstIndex(of: values.colorScheme) {
            schemeSegment?.selectedSegmentIndex = index
        }
    }

    @objc private func splitChanged(_ slider: UISlider) {
        let value = snapped(slider)
        TiltTuningStore.splitProbability = value
        splitValueLabel?.text = percent(value)
    }

    @objc private func tiltChanged(_ slider: UISlider) {
        let value = snapped(slider)
        TiltTuningStore.tiltStyleProbability = value
        tiltValueLabel?.text = percent(value)
    }

    @objc private func schemeChanged() {
        guard let segment = schemeSegment,
              TiltColorScheme.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        TiltTuningStore.colorScheme = TiltColorScheme.allCases[segment.selectedSegmentIndex]
    }

    @objc private func resetTapped() {
        TiltTuningStore.resetAll()
        refreshFromStore()
    }
}
