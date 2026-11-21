import UIKit

// 花火 hanabi 调参存储与面板（3.7 (57) 工作流 B6）：
// 网页版 folia-major/src/components/visualizer/hanabi/tuning.ts、
// hanabiTuning.ts（normalizeHanabiTuning）与 types.ts 的
// HanabiTuning / DEFAULT_HANABI_TUNING 的原生承接。网页每个
// 参数在本文件 HanabiTuningStore 里各有一个属性，UserDefaults
// 键前缀 "folia.tuning.hanabi."，缺省值与钳制范围与网页
// normalizeHanabiTuning 逐字对齐（见各属性注释）；渲染器
// （HanabiStageRenderer）只经本门面读参，逐帧读走 0.25s
// 缓存（照 PendoloTuningStore / StageEffectSettings 先例）。
// render 参数在网页是一个 {scale, antialias} 对象，原生拆成
// renderScale / renderAntialias 两个字符串属性存两键，取值集
// 与网页 LyricRenderOverride 一致（normalizeLyricRenderOverride
// 口径：不认识的值回到 "global"）；原生舞台暂无全局渲染倍率
// 消费点，渲染器按 "global" = 不缩放处理（见渲染器报告）。

/// 配色模式（网页 HanabiTuning.colorMode）。
enum HanabiColorMode: String, CaseIterable {
    case theme
    case vivid
    case mixed

    var displayName: String {
        switch self {
        case .theme: return "主题"
        case .vivid: return "鲜艳"
        case .mixed: return "混合"
        }
    }
}

/// 画质档（网页 HanabiTuning.renderQuality）：只动烟花辉光
/// 分辨率与环境粒子数量（hanabiTuning.ts HANABI_QUALITY_PROFILES：
/// full glowScale 1 / ambientScale 1；balanced 0.7 / 1；
/// low 0.5 / 0.6）。原生无 Pixi bloom filter 链，落点为粒子
/// 预算倍率与辉光精灵尺寸（见渲染器降级策略）。
enum HanabiRenderQuality: String, CaseIterable {
    case full
    case balanced
    case low

    var displayName: String {
        switch self {
        case .full: return "完整"
        case .balanced: return "均衡"
        case .low: return "省电"
        }
    }

    /// 烟花辉光相对倍率（网页 glowScale，按轴）。
    var glowScale: Double {
        switch self {
        case .full: return 1
        case .balanced: return 0.7
        case .low: return 0.5
        }
    }

    /// 环境粒子数量倍率（网页 ambientScale）。
    var ambientScale: Double {
        switch self {
        case .full, .balanced: return 1
        case .low: return 0.6
        }
    }
}

/// 一次读全的参数快照（渲染器逐帧消费的形状）。
struct HanabiTuningValues: Equatable {
    var renderScale: String = "global"        // 网页 render.scale
    var renderAntialias: String = "global"    // 网页 render.antialias
    var colorMode: HanabiColorMode = .mixed
    var sparkAmount: Double = 1
    var ornamentAmount: Double = 1
    var textMotion: Double = 1
    var blockOpacity: Double = 1
    var riseSpeed: Double = 1
    var spin: Double = 1
    var ambient: Double = 1
    var glow: Double = 1
    var bloom: Double = 0.8
    var chorusBloom: Double = 1.3
    var launches: Bool = true
    var overlayFrame: Bool = true
    var textOnly: Bool = false
    var sky: Double = 0.85
    var collage: Double = 1
    var renderQuality: HanabiRenderQuality = .full

    static let defaults = HanabiTuningValues()
}

/// 花火调参存储门面：网页 tuning.ts 每个参数一个属性。
enum HanabiTuningStore {

    private static let prefix = "folia.tuning.hanabi."
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

    // MARK: 分辨率与抗锯齿（网页 render: LyricRenderOverride）

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

    /// 取值集："global" / "auto" / "on" / "off"。
    static var renderAntialias: String {
        get {
            let raw = defaults.string(forKey: key("renderAntialias")) ?? "global"
            return ["global", "auto", "on", "off"].contains(raw) ? raw : "global"
        }
        set {
            defaults.set(["global", "auto", "on", "off"].contains(newValue)
                ? newValue : "global", forKey: key("renderAntialias"))
        }
    }

    /// render 倍率的数值落点："global" → nil（跟随全局挡位）。
    static var renderScaleValue: Double? {
        let raw = renderScale
        return raw == "global" ? nil : Double(raw)
    }

    // MARK: 枚举

    /// 配色模式，缺省 mixed；不认识的存值回 mixed
    /// （网页 normalize：非三值之一回缺省）。
    static var colorMode: HanabiColorMode {
        get {
            defaults.string(forKey: key("colorMode"))
                .flatMap { HanabiColorMode(rawValue: $0) } ?? .mixed
        }
        set { defaults.set(newValue.rawValue, forKey: key("colorMode")) }
    }

    /// 画质档，缺省 full；不认识的存值回 full。
    static var renderQuality: HanabiRenderQuality {
        get {
            defaults.string(forKey: key("renderQuality"))
                .flatMap { HanabiRenderQuality(rawValue: $0) } ?? .full
        }
        set { defaults.set(newValue.rawValue, forKey: key("renderQuality")) }
    }

    // MARK: 数值（范围 = 网页 normalizeHanabiTuning / tuning.ts modKeys）

    /// 烟花粒子数量倍率，[0, 2]，缺省 1。
    static var sparkAmount: Double {
        get { doubleValue("sparkAmount", fallback: 1, range: 0...2) }
        set { setDouble("sparkAmount", newValue, range: 0...2) }
    }

    /// MG 装饰件数量倍率，[0, 2]，缺省 1。
    static var ornamentAmount: Double {
        get { doubleValue("ornamentAmount", fallback: 1, range: 0...2) }
        set { setDouble("ornamentAmount", newValue, range: 0...2) }
    }

    /// 文字动作幅度，[0, 2]，缺省 1。
    static var textMotion: Double {
        get { doubleValue("textMotion", fallback: 1, range: 0...2) }
        set { setDouble("textMotion", newValue, range: 0...2) }
    }

    /// 字底色块不透明度，[0, 1]，缺省 1。
    static var blockOpacity: Double {
        get { doubleValue("blockOpacity", fallback: 1, range: 0...1) }
        set { setDouble("blockOpacity", newValue, range: 0...1) }
    }

    /// 上升速度倍率，[0, 2]，缺省 1（0 = 不上升）。
    static var riseSpeed: Double {
        get { doubleValue("riseSpeed", fallback: 1, range: 0...2) }
        set { setDouble("riseSpeed", newValue, range: 0...2) }
    }

    /// 旋转倍率，[0, 2]，缺省 1（0 = 不转）。
    static var spin: Double {
        get { doubleValue("spin", fallback: 1, range: 0...2) }
        set { setDouble("spin", newValue, range: 0...2) }
    }

    /// 环境粒子倍率，[0, 2]，缺省 1。
    static var ambient: Double {
        get { doubleValue("ambient", fallback: 1, range: 0...2) }
        set { setDouble("ambient", newValue, range: 0...2) }
    }

    /// 烟花辉光倍率，[0, 2]，缺省 1。
    static var glow: Double {
        get { doubleValue("glow", fallback: 1, range: 0...2) }
        set { setDouble("glow", newValue, range: 0...2) }
    }

    /// 整体全屏辉光，[0, 2]，缺省 0.8。
    static var bloom: Double {
        get { doubleValue("bloom", fallback: 0.8, range: 0...2) }
        set { setDouble("bloom", newValue, range: 0...2) }
    }

    /// 副歌全屏辉光，[0, 2]，缺省 1.3。
    static var chorusBloom: Double {
        get { doubleValue("chorusBloom", fallback: 1.3, range: 0...2) }
        set { setDouble("chorusBloom", newValue, range: 0...2) }
    }

    /// 夜空底不透明度，[0, 1]，缺省 0.85。
    static var sky: Double {
        get { doubleValue("sky", fallback: 0.85, range: 0...1) }
        set { setDouble("sky", newValue, range: 0...1) }
    }

    /// PV 拼贴数量倍率，[0, 2]，缺省 1。
    static var collage: Double {
        get { doubleValue("collage", fallback: 1, range: 0...2) }
        set { setDouble("collage", newValue, range: 0...2) }
    }

    // MARK: 开关（网页 normalize 口径：launches / overlayFrame
    // 为 `!== false`，即缺省 true、只有存了 false 才关；
    // textOnly 为 `=== true`，缺省 false）

    /// 升空尾迹开关，缺省 true。
    static var launches: Bool {
        get { boolValue("launches", fallback: true) }
        set { defaults.set(newValue, forKey: key("launches")) }
    }

    /// 画框装饰开关，缺省 true。
    static var overlayFrame: Bool {
        get { boolValue("overlayFrame", fallback: true) }
        set { defaults.set(newValue, forKey: key("overlayFrame")) }
    }

    /// 仅显示歌词文字，缺省 false。
    static var textOnly: Bool {
        get { boolValue("textOnly", fallback: false) }
        set { defaults.set(newValue, forKey: key("textOnly")) }
    }

    // MARK: 全量读写

    /// 一次读全（每属性各自钳制/回缺省，与网页 normalize 同义）。
    static func values() -> HanabiTuningValues {
        HanabiTuningValues(
            renderScale: renderScale,
            renderAntialias: renderAntialias,
            colorMode: colorMode,
            sparkAmount: sparkAmount,
            ornamentAmount: ornamentAmount,
            textMotion: textMotion,
            blockOpacity: blockOpacity,
            riseSpeed: riseSpeed,
            spin: spin,
            ambient: ambient,
            glow: glow,
            bloom: bloom,
            chorusBloom: chorusBloom,
            launches: launches,
            overlayFrame: overlayFrame,
            textOnly: textOnly,
            sky: sky,
            collage: collage,
            renderQuality: renderQuality)
    }

    /// 写回全量（面板恢复默认用；逐项经属性钳制）。
    static func apply(_ values: HanabiTuningValues) {
        renderScale = values.renderScale
        renderAntialias = values.renderAntialias
        colorMode = values.colorMode
        sparkAmount = values.sparkAmount
        ornamentAmount = values.ornamentAmount
        textMotion = values.textMotion
        blockOpacity = values.blockOpacity
        riseSpeed = values.riseSpeed
        spin = values.spin
        ambient = values.ambient
        glow = values.glow
        bloom = values.bloom
        chorusBloom = values.chorusBloom
        launches = values.launches
        overlayFrame = values.overlayFrame
        textOnly = values.textOnly
        sky = values.sky
        collage = values.collage
        renderQuality = values.renderQuality
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省（网页存储 reset 同义：render 一并还原）。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 PendoloTuningStore 先例）

    private static var cachedValues: HanabiTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> HanabiTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 花火调参面板入口（协调者接线点名形状）。
enum HanabiTuning {
    static func makePanel() -> UIViewController {
        HanabiTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 花火调参面板：网页 HanabiSettingsPanel.tsx 的原生承接。
/// 分组与控件集与网页逐项对应（烟花 / 舞台 / 文字 / 装饰 /
/// 配色 / 性能 / 渲染）；滑块范围照网页 SliderRow 入参
/// （min/max 见各行，step 网页缺省 0.05、sky 与 blockOpacity
/// 为 0.01），步进在写入时吸附；拨动即写 HanabiTuningStore，
/// 渲染器经 0.25s 缓存至多 0.25s 后生效，无需重开舞台。
/// 系统风格：systemBackground / label 语义色自动适配深色，
/// 字号下限 12pt。网页的「恢复默认」通知钮在原生落为面板
/// 末尾的恢复默认钮（resetAll，含 render 组，网页 reset
/// 同样整份还原）。
final class HanabiTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var sliderRows: [SliderRowRefs] = []
    private var switchRows: [SwitchRowRefs] = []
    private var colorModeSegment: UISegmentedControl?
    private var qualitySegment: UISegmentedControl?
    private var renderScaleSegment: UISegmentedControl?
    private var renderAntialiasSegment: UISegmentedControl?

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
        title = "花火参数"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
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

        // 烟花组（网页 FIREWORKS_CONTROLS）。
        addSection("烟花")
        addSlider(title: "烟花粒子量", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.sparkAmount },
                  write: { HanabiTuningStore.sparkAmount = $0 })
        addSlider(title: "辉光", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.glow },
                  write: { HanabiTuningStore.glow = $0 })
        addSlider(title: "副歌辉光", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.chorusBloom },
                  write: { HanabiTuningStore.chorusBloom = $0 })
        addSlider(title: "整体辉光", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.bloom },
                  write: { HanabiTuningStore.bloom = $0 })
        addSwitch(title: "升空尾迹",
                  read: { HanabiTuningStore.launches },
                  write: { HanabiTuningStore.launches = $0 })

        // 舞台组（网页 STAGE_CONTROLS）。
        addSection("舞台")
        addSlider(title: "夜空", min: 0, max: 1, step: 0.01,
                  read: { HanabiTuningStore.sky },
                  write: { HanabiTuningStore.sky = $0 })
        addSlider(title: "上升速度", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.riseSpeed },
                  write: { HanabiTuningStore.riseSpeed = $0 })
        addSlider(title: "旋转", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.spin },
                  write: { HanabiTuningStore.spin = $0 })
        addSlider(title: "环境粒子", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.ambient },
                  write: { HanabiTuningStore.ambient = $0 })
        addSwitch(title: "画框装饰",
                  read: { HanabiTuningStore.overlayFrame },
                  write: { HanabiTuningStore.overlayFrame = $0 })

        // 文字组（网页 TEXT_CONTROLS）。
        addSection("文字")
        addSwitch(title: "仅显示歌词",
                  read: { HanabiTuningStore.textOnly },
                  write: { HanabiTuningStore.textOnly = $0 })
        addSlider(title: "文字动作", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.textMotion },
                  write: { HanabiTuningStore.textMotion = $0 })
        addSlider(title: "色块不透明度", min: 0, max: 1, step: 0.01,
                  read: { HanabiTuningStore.blockOpacity },
                  write: { HanabiTuningStore.blockOpacity = $0 })

        // 装饰组（网页 DECOR_CONTROLS）。
        addSection("装饰")
        addSlider(title: "PV 拼贴", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.collage },
                  write: { HanabiTuningStore.collage = $0 })
        addSlider(title: "装饰件数量", min: 0, max: 2, step: 0.05,
                  read: { HanabiTuningStore.ornamentAmount },
                  write: { HanabiTuningStore.ornamentAmount = $0 })

        // 配色组（网页 COLOR_GROUP：Segmented 三档）。
        addSection("配色")
        let colorSegment = UISegmentedControl(
            items: [HanabiColorMode.mixed, .vivid, .theme].map { $0.displayName })
        colorSegment.addTarget(self, action: #selector(colorModeChanged), for: .valueChanged)
        colorModeSegment = colorSegment
        stack.addArrangedSubview(makeRow(title: "配色模式", control: colorSegment))

        // 性能组（网页 PERFORMANCE_GROUP：画质 Segmented）。
        addSection("性能")
        let qualitySegment = UISegmentedControl(
            items: HanabiRenderQuality.allCases.map { $0.displayName })
        qualitySegment.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        self.qualitySegment = qualitySegment
        stack.addArrangedSubview(makeRow(title: "画质", control: qualitySegment))

        // 渲染组（网页 LyricRenderQualityRows：倍率 + 抗锯齿）。
        addSection("渲染")
        let scaleSegment = UISegmentedControl(items: ["global", "0.5", "0.75", "1", "1.5", "2"].map {
            $0 == "global" ? "跟随全局" : "\($0)×"
        })
        scaleSegment.addTarget(self, action: #selector(renderScaleChanged), for: .valueChanged)
        renderScaleSegment = scaleSegment
        stack.addArrangedSubview(makeRow(title: "分辨率倍率", control: scaleSegment))
        let aaSegment = UISegmentedControl(items: ["跟随全局", "自动", "开", "关"])
        aaSegment.addTarget(self, action: #selector(renderAntialiasChanged), for: .valueChanged)
        renderAntialiasSegment = aaSegment
        stack.addArrangedSubview(makeRow(title: "抗锯齿", control: aaSegment))

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        resetButton.backgroundColor = .secondarySystemBackground
        resetButton.layer.cornerRadius = 8
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        resetButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(resetButton)

        let note = UILabel()
        note.text = "说明：副歌辉光依赖歌词副歌标记，协议未下发该字段，原生暂不触发；分辨率与抗锯齿为存储对齐项，原生舞台暂无消费点。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
    }

    // MARK: 行工厂

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        stack.addArrangedSubview(label)
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
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        switchRows.append(SwitchRowRefs(toggle: toggle, read: read, write: write))
        stack.addArrangedSubview(makeRow(title: title, control: toggle))
    }

    private func addSlider(title: String,
                           min: Double, max: Double, step: Double,
                           read: @escaping () -> Double,
                           write: @escaping (Double) -> Void) {
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
            valueLabel.widthAnchor.constraint(equalToConstant: 52),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        sliderRows.append(SliderRowRefs(
            slider: slider, valueLabel: valueLabel, step: step,
            format: { String(format: "%.2f", $0) }, read: read, write: write))
        slider.tag = sliderRows.count - 1
        stack.addArrangedSubview(container)
    }

    // MARK: 回显与动作

    private func refreshFromStore() {
        for row in sliderRows {
            let value = row.read()
            row.slider.value = Float(value)
            row.valueLabel.text = row.format(value)
        }
        for row in switchRows { row.toggle.isOn = row.read() }
        let colorOrder: [HanabiColorMode] = [.mixed, .vivid, .theme]
        if let index = colorOrder.firstIndex(of: HanabiTuningStore.colorMode) {
            colorModeSegment?.selectedSegmentIndex = index
        }
        if let index = HanabiRenderQuality.allCases.firstIndex(
            of: HanabiTuningStore.renderQuality) {
            qualitySegment?.selectedSegmentIndex = index
        }
        let scaleOptions = ["global", "0.5", "0.75", "1", "1.5", "2"]
        if let index = scaleOptions.firstIndex(of: HanabiTuningStore.renderScale) {
            renderScaleSegment?.selectedSegmentIndex = index
        }
        let aaOptions = ["global", "auto", "on", "off"]
        if let index = aaOptions.firstIndex(of: HanabiTuningStore.renderAntialias) {
            renderAntialiasSegment?.selectedSegmentIndex = index
        }
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        guard let row = switchRows.first(where: { $0.toggle === toggle }) else { return }
        row.write(toggle.isOn)
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard sliderRows.indices.contains(slider.tag) else { return }
        let row = sliderRows[slider.tag]
        // 步进吸附（网页 SliderRow step 同口径）再写存储。
        let raw = Double(slider.value)
        let stepped = (raw / row.step).rounded() * row.step
        row.write(stepped)
        row.valueLabel.text = row.format(row.read())
    }

    @objc private func colorModeChanged() {
        guard let segment = colorModeSegment else { return }
        let order: [HanabiColorMode] = [.mixed, .vivid, .theme]
        guard order.indices.contains(segment.selectedSegmentIndex) else { return }
        HanabiTuningStore.colorMode = order[segment.selectedSegmentIndex]
    }

    @objc private func qualityChanged() {
        guard let segment = qualitySegment,
              HanabiRenderQuality.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        HanabiTuningStore.renderQuality =
            HanabiRenderQuality.allCases[segment.selectedSegmentIndex]
    }

    @objc private func renderScaleChanged() {
        guard let segment = renderScaleSegment else { return }
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        guard options.indices.contains(segment.selectedSegmentIndex) else { return }
        HanabiTuningStore.renderScale = options[segment.selectedSegmentIndex]
    }

    @objc private func renderAntialiasChanged() {
        guard let segment = renderAntialiasSegment else { return }
        let options = ["global", "auto", "on", "off"]
        guard options.indices.contains(segment.selectedSegmentIndex) else { return }
        HanabiTuningStore.renderAntialias = options[segment.selectedSegmentIndex]
    }

    @objc private func resetTapped() {
        HanabiTuningStore.resetAll()
        refreshFromStore()
    }
}
