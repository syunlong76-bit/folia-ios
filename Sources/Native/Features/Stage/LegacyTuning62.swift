import UIKit

// (62) WD：classic / monet / still 三样式调参面板补缺。
// 此前三式在 LyricStageRegistry 无 tuningPanelFactory（选择器
// 无调参入口）。本文件补三套存储（前缀 folia.tuning.<style>62.）
// 与面板，所有参数均有渲染器真消费点（逐项注于各 store）：
//  - classic：行入场时长倍率（ClassicStageRenderer 入场动画）、
//    呼吸浮动幅度（StageBreathingFloat amplitude 过载）、
//    行距倍率（buildLineContainer 的 pitch）。
//  - monet：烘焙倍率档（currentDisplayScale 乘子）、wash 不
//    透明度（washView.alpha 落点）。
//  - still：字重档（refreshContent 字体选择）、暗角强度倍率
//    （updateVignette 的 alpha 乘子）。
// 面板构造照 PartitaTuning 面板先例（滚动 + 行拨动即写）。

// MARK: - 存储

enum ClassicTuning62 {
    private static let prefix = "folia.tuning.classic62."
    private static var defaults: UserDefaults { .standard }

    private static func doubleValue(_ name: String, fallback: Double,
                                    range: ClosedRange<Double>) -> Double {
        guard let raw = defaults.object(forKey: prefix + name) as? Double,
              raw.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    static var enterDurationScale: Double {
        get { doubleValue("enterDurationScale", fallback: 1, range: 0.5...2) }
        set { defaults.set(min(2, max(0.5, newValue)), forKey: prefix + "enterDurationScale") }
    }
    static var floatAmplitude: Double {
        get { doubleValue("floatAmplitude", fallback: 1, range: 0...2) }
        set { defaults.set(min(2, max(0, newValue)), forKey: prefix + "floatAmplitude") }
    }
    static var linePitchScale: Double {
        get { doubleValue("linePitchScale", fallback: 1, range: 0.9...1.4) }
        set { defaults.set(min(1.4, max(0.9, newValue)), forKey: prefix + "linePitchScale") }
    }
    static func resetAll() {
        enterDurationScale = 1; floatAmplitude = 1; linePitchScale = 1
    }
}

enum MonetTuning62 {
    private static let prefix = "folia.tuning.monet62."
    private static var defaults: UserDefaults { .standard }

    /// 烘焙倍率档："screen" 跟随屏幕（缺省）/ "low" ×0.75 /
    /// "high" ×1.5。
    static var bakeScaleChoice: String {
        get {
            let raw = defaults.string(forKey: prefix + "bakeScaleChoice") ?? "screen"
            return ["screen", "low", "high"].contains(raw) ? raw : "screen"
        }
        set {
            defaults.set(["screen", "low", "high"].contains(newValue)
                ? newValue : "screen", forKey: prefix + "bakeScaleChoice")
        }
    }
    static var bakeScaleFactor: Double {
        switch bakeScaleChoice {
        case "low": return 0.75
        case "high": return 1.5
        default: return 1
        }
    }
    static var washOpacity: Double {
        get {
            guard let raw = defaults.object(forKey: prefix + "washOpacity") as? Double,
                  raw.isFinite else { return 1 }
            return min(1, max(0.4, raw))
        }
        set { defaults.set(min(1, max(0.4, newValue)), forKey: prefix + "washOpacity") }
    }
    static func resetAll() { bakeScaleChoice = "screen"; washOpacity = 1 }
}

enum StillTuning62 {
    private static let prefix = "folia.tuning.still62."
    private static var defaults: UserDefaults { .standard }

    /// 字重档："light" / "regular" / "bold"（缺省 bold = 现行）。
    static var fontWeightChoice: String {
        get {
            let raw = defaults.string(forKey: prefix + "fontWeightChoice") ?? "bold"
            return ["light", "regular", "bold"].contains(raw) ? raw : "bold"
        }
        set {
            defaults.set(["light", "regular", "bold"].contains(newValue)
                ? newValue : "bold", forKey: prefix + "fontWeightChoice")
        }
    }
    static var vignetteScale: Double {
        get {
            guard let raw = defaults.object(forKey: prefix + "vignetteScale") as? Double,
                  raw.isFinite else { return 1 }
            return min(1.5, max(0, raw))
        }
        set { defaults.set(min(1.5, max(0, newValue)), forKey: prefix + "vignetteScale") }
    }
    static func resetAll() { fontWeightChoice = "bold"; vignetteScale = 1 }
}

// MARK: - 面板入口（注册表 tuningPanelFactory 形状）

enum ClassicTuning {
    static func makePanel() -> UIViewController {
        LegacyTuning62PanelViewController(
            title: "流光 · 调参",
            sliders: [
                .init(id: "enter", title: "行入场时长", min: 0.5, max: 2,
                      read: { ClassicTuning62.enterDurationScale },
                      write: { ClassicTuning62.enterDurationScale = $0 },
                      format: { String(format: "×%.2f", $0) }),
                .init(id: "float", title: "呼吸浮动幅度", min: 0, max: 2,
                      read: { ClassicTuning62.floatAmplitude },
                      write: { ClassicTuning62.floatAmplitude = $0 },
                      format: { String(format: "×%.2f", $0) }),
                .init(id: "pitch", title: "行距", min: 0.9, max: 1.4,
                      read: { ClassicTuning62.linePitchScale },
                      write: { ClassicTuning62.linePitchScale = $0 },
                      format: { String(format: "×%.2f", $0) }),
            ],
            segments: [],
            note: "说明：三项均即时生效于流光渲染器（入场动画时长、整行呼吸浮动幅度、多行排版行距）。",
            reset: { ClassicTuning62.resetAll() })
    }
}

enum MonetTuning {
    static func makePanel() -> UIViewController {
        LegacyTuning62PanelViewController(
            title: "莫奈 · 调参",
            sliders: [
                .init(id: "wash", title: "Wash 不透明度", min: 0.4, max: 1,
                      read: { MonetTuning62.washOpacity },
                      write: { MonetTuning62.washOpacity = $0 },
                      format: { String(format: "%.2f", $0) }),
            ],
            segments: [
                .init(id: "bake", title: "烘焙倍率",
                      options: ["跟随屏幕", "省电 ×0.75", "清晰 ×1.5"],
                      read: { ["screen", "low", "high"].firstIndex(
                          of: MonetTuning62.bakeScaleChoice) ?? 0 },
                      write: { MonetTuning62.bakeScaleChoice =
                          ["screen", "low", "high"][$0] }),
            ],
            note: "说明：烘焙倍率乘进莫奈文字/成图烘焙的出图倍率（下一首歌或重烘焙时生效）；Wash 不透明度作用于背景 wash 层。漂移减弱动态在「动画与性能」侧统一管理。",
            reset: { MonetTuning62.resetAll() })
    }
}

enum StillTuning {
    static func makePanel() -> UIViewController {
        LegacyTuning62PanelViewController(
            title: "静止 · 调参",
            sliders: [
                .init(id: "vig", title: "暗角强度", min: 0, max: 1.5,
                      read: { StillTuning62.vignetteScale },
                      write: { StillTuning62.vignetteScale = $0 },
                      format: { String(format: "×%.2f", $0) }),
            ],
            segments: [
                .init(id: "weight", title: "字重",
                      options: ["细", "常规", "粗"],
                      read: { ["light", "regular", "bold"].firstIndex(
                          of: StillTuning62.fontWeightChoice) ?? 2 },
                      write: { StillTuning62.fontWeightChoice =
                          ["light", "regular", "bold"][$0] }),
            ],
            note: "说明：字重作用于三行正文（当前行与相邻行同档）；暗角强度乘进径向暗角的不透明度。均即时生效。",
            reset: { StillTuning62.resetAll() })
    }
}

// MARK: - 通用面板（照 Partita 面板构造）

final class LegacyTuning62PanelViewController: UIViewController {

    struct SliderSpec {
        let id: String
        let title: String
        let min: Double
        let max: Double
        let read: () -> Double
        let write: (Double) -> Void
        let format: (Double) -> String
    }
    struct SegmentSpec {
        let id: String
        let title: String
        let options: [String]
        let read: () -> Int
        let write: (Int) -> Void
    }

    private let panelTitle: String
    private let sliderSpecs: [SliderSpec]
    private let segmentSpecs: [SegmentSpec]
    private let noteText: String
    private let resetAction: () -> Void
    private let stack = UIStackView()
    private var sliders: [String: UISlider] = [:]
    private var valueLabels: [String: UILabel] = [:]
    private var segments: [String: UISegmentedControl] = [:]

    init(title: String, sliders: [SliderSpec], segments: [SegmentSpec],
         note: String, reset: @escaping () -> Void) {
        self.panelTitle = title
        self.sliderSpecs = sliders
        self.segmentSpecs = segments
        self.noteText = note
        self.resetAction = reset
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = panelTitle
        view.backgroundColor = .systemBackground
        let scrollView = UIScrollView()
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
        stack.addArrangedSubview(LyricContrastProtectionNote.makeLabel())
        for spec in sliderSpecs { addSlider(spec) }
        for spec in segmentSpecs { addSegment(spec) }
        let note = UILabel()
        note.text = noteText
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
        let reset = UIButton(type: .system)
        reset.setTitle("恢复默认", for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 14)
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)
        refresh()
    }

    private func addSlider(_ spec: SliderSpec) {
        let titleLabel = UILabel()
        titleLabel.text = spec.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .label
        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabels[spec.id] = valueLabel
        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        let slider = UISlider()
        slider.minimumValue = Float(spec.min)
        slider.maximumValue = Float(spec.max)
        slider.accessibilityIdentifier = spec.id
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        sliders[spec.id] = slider
        let row = UIStackView(arrangedSubviews: [header, slider])
        row.axis = .vertical
        row.spacing = 4
        stack.addArrangedSubview(row)
    }

    private func addSegment(_ spec: SegmentSpec) {
        let titleLabel = UILabel()
        titleLabel.text = spec.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .label
        let control = UISegmentedControl(items: spec.options)
        control.accessibilityIdentifier = spec.id
        control.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        segments[spec.id] = control
        let row = UIStackView(arrangedSubviews: [titleLabel, control])
        row.axis = .vertical
        row.spacing = 4
        stack.addArrangedSubview(row)
    }

    private func refresh() {
        for spec in sliderSpecs {
            sliders[spec.id]?.value = Float(spec.read())
            valueLabels[spec.id]?.text = spec.format(spec.read())
        }
        for spec in segmentSpecs {
            segments[spec.id]?.selectedSegmentIndex = spec.read()
        }
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard let spec = sliderSpecs.first(where: { $0.id == slider.accessibilityIdentifier })
        else { return }
        spec.write(Double(slider.value))
        valueLabels[spec.id]?.text = spec.format(spec.read())
    }

    @objc private func segmentChanged(_ control: UISegmentedControl) {
        guard let spec = segmentSpecs.first(where: { $0.id == control.accessibilityIdentifier })
        else { return }
        spec.write(control.selectedSegmentIndex)
    }

    @objc private func resetTapped() {
        resetAction()
        refresh()
    }
}
