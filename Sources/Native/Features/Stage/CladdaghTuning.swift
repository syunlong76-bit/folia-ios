import UIKit

// 回环 claddagh 调参存储与面板（3.7 (57) 工作流 C2）：
// 网页版 folia-major/src/components/visualizer/claddagh/
// tuning.ts、src/types.ts 的 CladdaghTuning /
// DEFAULT_CLADDAGH_TUNING 与 settingsPanels.tsx 的
// CladdaghSettingsPanel 的原生承接。UserDefaults 键前缀
// "folia.tuning.claddagh."；缺省与钳制逐字对齐网页
// resolve()：focusScaleRatio [0, 1.5]、radiusScale
// [0.5, 1.5]、ellipseTiltDeg [0, 60]、letterSpacingOffset
// [-5, 20]、positionX/Y [-40, 40]（CLADDAGH_POSITION_
// LIMIT_PERCENT）、translationScale [0.5, 2]、translation-
// LetterSpacingOffset [-5, 20]、showAxisLine /
// showTranslation 为布尔直取。渲染器（CladdaghStage-
// Renderer）只经本门面读参，逐帧读走 0.25s 缓存（照
// StageEffectSettings / PendoloTuningStore 先例）。
// 译文环参数（showTranslation 一组）只存不用：协议
// LyricLine 无译文字段、无数据通路，见渲染器头注差异表。

/// 一次读全的参数快照（渲染器消费的形状）。
struct CladdaghTuningValues: Equatable {
    var focusScaleRatio: Double = 0.65
    var radiusScale: Double = 1.0
    var ellipseTiltDeg: Double = 45
    var showAxisLine: Bool = true
    var letterSpacingOffset: Double = 0
    var positionX: Double = 0
    var positionY: Double = 0
    var showTranslation: Bool = false
    var translationScale: Double = 1
    var translationLetterSpacingOffset: Double = 0

    static let defaults = CladdaghTuningValues()
}

/// 回环调参存储门面：网页 tuning.ts 每个参数一个属性。
enum CladdaghTuningStore {

    private static let prefix = "folia.tuning.claddagh."
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

    private static func boolValue(_ name: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    /// 焦点缩放比，[0, 1.5]，缺省 0.65。渲染面两处消费：
    /// 字素缩放 (1 + focus × F) 与间距标尺 (1 + focus) /
    /// (1 + 0.65)（VisualizerCladdagh 的 focusSpacingScale）。
    static var focusScaleRatio: Double {
        get { doubleValue("focusScaleRatio", fallback: 0.65, range: 0...1.5) }
        set { setDouble("focusScaleRatio", newValue, range: 0...1.5) }
    }

    /// 半径倍率，[0.5, 1.5]，缺省 1.0。
    static var radiusScale: Double {
        get { doubleValue("radiusScale", fallback: 1.0, range: 0.5...1.5) }
        set { setDouble("radiusScale", newValue, range: 0.5...1.5) }
    }

    /// 椭圆倾角（度），[0, 60]，缺省 45；投影旋转角取其负，
    /// 轴线角 = 90 − 本值。
    static var ellipseTiltDeg: Double {
        get { doubleValue("ellipseTiltDeg", fallback: 45, range: 0...60) }
        set { setDouble("ellipseTiltDeg", newValue, range: 0...60) }
    }

    /// 显示中心轴线，缺省 true。
    static var showAxisLine: Bool {
        get { boolValue("showAxisLine", fallback: true) }
        set { defaults.set(newValue, forKey: key("showAxisLine")) }
    }

    /// 字距偏移（px/字间隙），[-5, 20]，缺省 0。
    static var letterSpacingOffset: Double {
        get { doubleValue("letterSpacingOffset", fallback: 0, range: -5...20) }
        set { setDouble("letterSpacingOffset", newValue, range: -5...20) }
    }

    /// 圆环横向位置（画面宽百分比，0 在正中），[-40, 40]，缺省 0。
    static var positionX: Double {
        get { doubleValue("positionX", fallback: 0, range: -40...40) }
        set { setDouble("positionX", newValue, range: -40...40) }
    }

    /// 圆环纵向位置（画面高百分比，0 在正中），[-40, 40]，缺省 0。
    static var positionY: Double {
        get { doubleValue("positionY", fallback: 0, range: -40...40) }
        set { setDouble("positionY", newValue, range: -40...40) }
    }

    /// 沿环显示译文，缺省 false（只存不用，见文件头注）。
    static var showTranslation: Bool {
        get { boolValue("showTranslation", fallback: false) }
        set { defaults.set(newValue, forKey: key("showTranslation")) }
    }

    /// 译文字号倍率，[0.5, 2]，缺省 1（只存不用）。
    static var translationScale: Double {
        get { doubleValue("translationScale", fallback: 1, range: 0.5...2) }
        set { setDouble("translationScale", newValue, range: 0.5...2) }
    }

    /// 译文字距偏移，[-5, 20]，缺省 0（只存不用）。
    static var translationLetterSpacingOffset: Double {
        get { doubleValue("translationLetterSpacingOffset", fallback: 0, range: -5...20) }
        set { setDouble("translationLetterSpacingOffset", newValue, range: -5...20) }
    }

    /// 一次读全（每属性各自钳制/回缺省，与网页 resolve 同义）。
    static func values() -> CladdaghTuningValues {
        CladdaghTuningValues(
            focusScaleRatio: focusScaleRatio,
            radiusScale: radiusScale,
            ellipseTiltDeg: ellipseTiltDeg,
            showAxisLine: showAxisLine,
            letterSpacingOffset: letterSpacingOffset,
            positionX: positionX,
            positionY: positionY,
            showTranslation: showTranslation,
            translationScale: translationScale,
            translationLetterSpacingOffset: translationLetterSpacingOffset)
    }

    /// 写回全量（恢复默认用；逐项经属性钳制）。
    static func apply(_ values: CladdaghTuningValues) {
        focusScaleRatio = values.focusScaleRatio
        radiusScale = values.radiusScale
        ellipseTiltDeg = values.ellipseTiltDeg
        showAxisLine = values.showAxisLine
        letterSpacingOffset = values.letterSpacingOffset
        positionX = values.positionX
        positionY = values.positionY
        showTranslation = values.showTranslation
        translationScale = values.translationScale
        translationLetterSpacingOffset = values.translationLetterSpacingOffset
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 StageEffectSettings 先例）

    private static var cachedValues: CladdaghTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> CladdaghTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 回环调参面板入口（协调者接线点名形状）。
enum CladdaghTuning {
    static func makePanel() -> UIViewController {
        CladdaghTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 回环调参面板：网页 CladdaghSettingsPanel 的原生承接。
/// 控件集与网页逐项对应（滑杆范围/步进/格式照网页入参：
/// 焦点格式为 ×(值+1)、位置为带符号百分比、字距为 px）；
/// 译文两条子滑杆仅在「显示译文」打开时展开（网页 Reveal
/// 同义），但协议无译文数据，开关当前只存不用（见注记）。
/// 拨动即写 CladdaghTuningStore，渲染器经 0.25s 缓存生效。
/// 系统风格：systemBackground / label 语义色适配深色，
/// 字号 ≥12pt。
final class CladdaghTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var sliderRows: [SliderRowRefs] = []
    private var switchRows: [SwitchRowRefs] = []
    private var translationRows: [UIView] = []

    private struct SliderRowRefs {
        let slider: UISlider
        let valueLabel: UILabel
        let step: Double
        let format: (Double) -> String
        let read: () -> Double
        let write: (Double) -> Void
    }

    private struct SwitchRowRefs {
        let toggle: UISwitch
        let read: () -> Bool
        let write: (Bool) -> Void
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "回环参数"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
        refreshTranslationRows()
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

        addSlider(title: "焦点缩放", min: 0, max: 1.5, step: 0.05,
                  format: { String(format: "%.2f×", $0 + 1) },
                  read: { CladdaghTuningStore.focusScaleRatio },
                  write: { CladdaghTuningStore.focusScaleRatio = $0 })
        addSlider(title: "圆环半径", min: 0.5, max: 1.5, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { CladdaghTuningStore.radiusScale },
                  write: { CladdaghTuningStore.radiusScale = $0 })
        addSlider(title: "圆环横移", min: -40, max: 40, step: 1,
                  format: { "\( $0 > 0 ? "+" : "" )\(Int($0.rounded()))%" },
                  read: { CladdaghTuningStore.positionX },
                  write: { CladdaghTuningStore.positionX = $0 })
        addSlider(title: "圆环纵移", min: -40, max: 40, step: 1,
                  format: { "\( $0 > 0 ? "+" : "" )\(Int($0.rounded()))%" },
                  read: { CladdaghTuningStore.positionY },
                  write: { CladdaghTuningStore.positionY = $0 })
        addSlider(title: "椭圆倾角", min: 0, max: 60, step: 1,
                  format: { "\(Int($0.rounded()))°" },
                  read: { CladdaghTuningStore.ellipseTiltDeg },
                  write: { CladdaghTuningStore.ellipseTiltDeg = $0 })
        addSwitch(title: "中心轴线",
                  read: { CladdaghTuningStore.showAxisLine },
                  write: { CladdaghTuningStore.showAxisLine = $0 })
        addSlider(title: "字距偏移", min: -5, max: 20, step: 0.5,
                  format: { String(format: "%+.1fpx", $0) },
                  read: { CladdaghTuningStore.letterSpacingOffset },
                  write: { CladdaghTuningStore.letterSpacingOffset = $0 })
        addSwitch(title: "沿环显示译文",
                  read: { CladdaghTuningStore.showTranslation },
                  write: { [weak self] in
                      CladdaghTuningStore.showTranslation = $0
                      self?.refreshTranslationRows()
                  })
        translationRows.append(addSlider(
            title: "译文字号", min: 0.5, max: 2, step: 0.05,
            format: { String(format: "%.2f×", $0) },
            read: { CladdaghTuningStore.translationScale },
            write: { CladdaghTuningStore.translationScale = $0 }))
        translationRows.append(addSlider(
            title: "译文字距", min: -5, max: 20, step: 0.5,
            format: { String(format: "%+.1fpx", $0) },
            read: { CladdaghTuningStore.translationLetterSpacingOffset },
            write: { CladdaghTuningStore.translationLetterSpacingOffset = $0 }))

        let reset = UIButton(type: .system)
        reset.setTitle("恢复默认", for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        reset.backgroundColor = .secondarySystemBackground
        reset.layer.cornerRadius = 8
        reset.heightAnchor.constraint(equalToConstant: 40).isActive = true
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)

        let note = UILabel()
        note.text = "说明：协议未下发逐行译文，「沿环显示译文」一组参数已保存但暂不生效，待译文数据通路接入后启用。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
    }

    @discardableResult
    private func addSlider(title: String, min: Double, max: Double,
                           step: Double, format: @escaping (Double) -> String,
                           read: @escaping () -> Double,
                           write: @escaping (Double) -> Void) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
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
            valueLabel.widthAnchor.constraint(equalToConstant: 64),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        sliderRows.append(SliderRowRefs(
            slider: slider, valueLabel: valueLabel, step: step,
            format: format, read: read, write: write))
        slider.tag = sliderRows.count - 1
        stack.addArrangedSubview(container)
        return container
    }

    @discardableResult
    private func addSwitch(title: String, read: @escaping () -> Bool,
                           write: @escaping (Bool) -> Void) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(toggle)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        switchRows.append(SwitchRowRefs(toggle: toggle, read: read, write: write))
        toggle.tag = switchRows.count - 1
        stack.addArrangedSubview(container)
        return container
    }

    private func refreshFromStore() {
        for row in sliderRows {
            let value = row.read()
            row.slider.value = Float(value)
            row.valueLabel.text = row.format(value)
        }
        for row in switchRows { row.toggle.isOn = row.read() }
    }

    private func refreshTranslationRows() {
        let shown = CladdaghTuningStore.showTranslation
        for row in translationRows { row.isHidden = !shown }
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard sliderRows.indices.contains(slider.tag) else { return }
        let row = sliderRows[slider.tag]
        let value = (Double(slider.value) / row.step).rounded() * row.step
        row.write(value)
        row.valueLabel.text = row.format(row.read())
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        guard switchRows.indices.contains(toggle.tag) else { return }
        switchRows[toggle.tag].write(toggle.isOn)
    }

    @objc private func resetTapped() {
        CladdaghTuningStore.resetAll()
        refreshFromStore()
        refreshTranslationRows()
    }
}
