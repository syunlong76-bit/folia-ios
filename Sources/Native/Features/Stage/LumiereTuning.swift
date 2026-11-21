import UIKit

// 绘光 lumiere 调参存储与面板（3.7 (57) 工作流 B5）：
// 网页版 folia-major/src/components/visualizer/lumiere/tuning.ts、
// src/types.ts 的 LumiereTuning / DEFAULT_LUMIERE_TUNING 与
// src/utils/lumiereTuning.ts（normalizeLumiereTuning 钳制）的
// 原生承接。网页每个参数在本文件 LumiereTuningStore 里各有一
// 个属性，UserDefaults 键前缀 "folia.tuning.lumiere."，缺省值
// 与钳制范围逐字对齐（见各属性注释）；渲染器
// （LumiereStageRenderer）只经本门面读参，逐帧读走 0.25s
// 缓存（照 StageEffectSettings / PendoloTuningStore 先例）。
// render 参数在网页是一个 {scale, antialias} 对象，原生拆成
// renderScale / renderAntialias 两个字符串属性存两键，取值集
// 与网页 LyricRenderOverride 一致。

/// 画质档位（网页 LumiereRenderQuality）。
enum LumiereRenderQuality: String, CaseIterable {
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
}

/// 一次读全的参数快照（渲染器逐帧消费的形状）。
struct LumiereTuningValues: Equatable {
    var renderScale: String = "global"        // 网页 render.scale
    var renderAntialias: String = "global"    // 网页 render.antialias
    var lightIntensity: Double = 1            // [0.3, 2]
    var audioResponse: Double = 1             // [0, 2]
    var fogDensity: Double = 1                // [0, 2]
    var darkField: Double = 0.75              // [0, 1]
    var moteAmount: Double = 1                // [0, 2]
    var bloom: Double = 1                     // [0, 2]
    var textBloom: Double = 1                 // [0, 2]
    var unlitOpacity: Double = 0.22           // [0.05, 0.6]
    var windowNeighbors: Int = 2              // 1 | 2
    var decay: Double = 1                     // [0, 2]
    var echo: Double = 1                      // [0, 2]
    var fogOctaves: Int = 5                   // [2, 6] 整数
    var lineArt: Bool = true
    var frontBokeh: Bool = true
    var trails: Bool = true
    var hideTrails: Bool = false
    var seamlessTransitions: Bool = true
    var overlayFrame: Bool = true
    var textOnly: Bool = false
    var keywordColors: Bool = true
    var themeIcons: Bool = true
    var themeColorMix: Double = 0.3           // [0, 1]
    var renderQuality: LumiereRenderQuality = .full

    static let defaults = LumiereTuningValues()
}

/// 绘光调参存储门面：网页 tuning.ts 每个参数一个属性。
enum LumiereTuningStore {

    private static let prefix = "folia.tuning.lumiere."
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

    // MARK: 光（网页 LumiereSettingsPanel LIGHT 组）

    /// 光强倍率，[0.3, 2]，缺省 1。
    static var lightIntensity: Double {
        get { doubleValue("lightIntensity", fallback: 1, range: 0.3...2) }
        set { setDouble("lightIntensity", newValue, range: 0.3...2) }
    }

    /// 随音乐变亮，[0, 2]，缺省 1（0 = 不随音乐变）。
    static var audioResponse: Double {
        get { doubleValue("audioResponse", fallback: 1, range: 0...2) }
        set { setDouble("audioResponse", newValue, range: 0...2) }
    }

    /// 图形辉光，[0, 2]，缺省 1。
    static var bloom: Double {
        get { doubleValue("bloom", fallback: 1, range: 0...2) }
        set { setDouble("bloom", newValue, range: 0...2) }
    }

    /// 文字辉光，[0, 2]，缺省 1。
    static var textBloom: Double {
        get { doubleValue("textBloom", fallback: 1, range: 0...2) }
        set { setDouble("textBloom", newValue, range: 0...2) }
    }

    // MARK: 氛围（ATMOSPHERE 组）

    /// 暗场强度，[0, 1]，缺省 0.75（浅色主题保底 0.94 在渲染器侧落）。
    static var darkField: Double {
        get { doubleValue("darkField", fallback: 0.75, range: 0...1) }
        set { setDouble("darkField", newValue, range: 0...1) }
    }

    /// 烟雾浓度，[0, 2]，缺省 1。
    static var fogDensity: Double {
        get { doubleValue("fogDensity", fallback: 1, range: 0...2) }
        set { setDouble("fogDensity", newValue, range: 0...2) }
    }

    /// 烟雾细节（倍频数），整数 [2, 6]，缺省 5。
    static var fogOctaves: Int {
        get {
            guard let raw = defaults.object(forKey: key("fogOctaves")) as? Double else { return 5 }
            return Int(min(6, max(2, raw.rounded())))
        }
        set { defaults.set(Double(min(6, max(2, newValue))), forKey: key("fogOctaves")) }
    }

    /// 浮尘数量，[0, 2]，缺省 1。
    static var moteAmount: Double {
        get { doubleValue("moteAmount", fallback: 1, range: 0...2) }
        set { setDouble("moteAmount", newValue, range: 0...2) }
    }

    /// 前景散景，缺省 true。
    static var frontBokeh: Bool {
        get { boolValue("frontBokeh", fallback: true) }
        set { defaults.set(newValue, forKey: key("frontBokeh")) }
    }

    /// 线稿，缺省 true。
    static var lineArt: Bool {
        get { boolValue("lineArt", fallback: true) }
        set { defaults.set(newValue, forKey: key("lineArt")) }
    }

    /// 画框，缺省 true。
    static var overlayFrame: Bool {
        get { boolValue("overlayFrame", fallback: true) }
        set { defaults.set(newValue, forKey: key("overlayFrame")) }
    }

    // MARK: 文字（TEXT 组）

    /// 仅显示歌词文字，缺省 false。
    static var textOnly: Bool {
        get { boolValue("textOnly", fallback: false) }
        set { defaults.set(newValue, forKey: key("textOnly")) }
    }

    /// 未唱字透明度，[0.05, 0.6]，缺省 0.22。
    static var unlitOpacity: Double {
        get { doubleValue("unlitOpacity", fallback: 0.22, range: 0.05...0.6) }
        set { setDouble("unlitOpacity", newValue, range: 0.05...0.6) }
    }

    /// 邻行：1 = 上一行 + 当前行，2 = 上一行 + 当前行 + 下一行，缺省 2。
    static var windowNeighbors: Int {
        get {
            guard let raw = defaults.object(forKey: key("windowNeighbors")) as? Double else { return 2 }
            return raw == 1 ? 1 : 2
        }
        set { defaults.set(Double(newValue == 1 ? 1 : 2), forKey: key("windowNeighbors")) }
    }

    /// 崩解强度，[0, 2]，缺省 1。
    static var decay: Double {
        get { doubleValue("decay", fallback: 1, range: 0...2) }
        set { setDouble("decay", newValue, range: 0...2) }
    }

    /// 背景歌词亮度，[0, 2]，缺省 1（0 = 关）。
    static var echo: Double {
        get { doubleValue("echo", fallback: 1, range: 0...2) }
        set { setDouble("echo", newValue, range: 0...2) }
    }

    /// 所有换位都走轨迹线，缺省 true（用户 tuning 缺省；场景缺省为 false，以用户面为准）。
    static var trails: Bool {
        get { boolValue("trails", fallback: true) }
        set { defaults.set(newValue, forKey: key("trails")) }
    }

    /// 隐藏所有轨迹线，缺省 false。
    static var hideTrails: Bool {
        get { boolValue("hideTrails", fallback: false) }
        set { defaults.set(newValue, forKey: key("hideTrails")) }
    }

    /// 轨迹过渡（段落无缝交接），缺省 true；改它在网页会重新编译程序，原生为近似开关。
    static var seamlessTransitions: Bool {
        get { boolValue("seamlessTransitions", fallback: true) }
        set { defaults.set(newValue, forKey: key("seamlessTransitions")) }
    }

    // MARK: 主题（THEME 组）

    /// 主题色占比，[0, 1]，缺省 0.3（0 = 香槟金光）。
    static var themeColorMix: Double {
        get { doubleValue("themeColorMix", fallback: 0.3, range: 0...1) }
        set { setDouble("themeColorMix", newValue, range: 0...1) }
    }

    /// 关键字着色，缺省 true。
    static var keywordColors: Bool {
        get { boolValue("keywordColors", fallback: true) }
        set { defaults.set(newValue, forKey: key("keywordColors")) }
    }

    /// 主题图标，缺省 true。
    static var themeIcons: Bool {
        get { boolValue("themeIcons", fallback: true) }
        set { defaults.set(newValue, forKey: key("themeIcons")) }
    }

    // MARK: 性能（PERFORMANCE 组）

    /// 画质档位，缺省 full；不认识的存值回 full。
    static var renderQuality: LumiereRenderQuality {
        get {
            defaults.string(forKey: key("renderQuality"))
                .flatMap { LumiereRenderQuality(rawValue: $0) } ?? .full
        }
        set { defaults.set(newValue.rawValue, forKey: key("renderQuality")) }
    }

    // MARK: 全量读写

    /// 一次读全（每属性各自钳制/回缺省，与网页 normalize 同义）。
    static func values() -> LumiereTuningValues {
        LumiereTuningValues(
            renderScale: renderScale,
            renderAntialias: renderAntialias,
            lightIntensity: lightIntensity,
            audioResponse: audioResponse,
            fogDensity: fogDensity,
            darkField: darkField,
            moteAmount: moteAmount,
            bloom: bloom,
            textBloom: textBloom,
            unlitOpacity: unlitOpacity,
            windowNeighbors: windowNeighbors,
            decay: decay,
            echo: echo,
            fogOctaves: fogOctaves,
            lineArt: lineArt,
            frontBokeh: frontBokeh,
            trails: trails,
            hideTrails: hideTrails,
            seamlessTransitions: seamlessTransitions,
            overlayFrame: overlayFrame,
            textOnly: textOnly,
            keywordColors: keywordColors,
            themeIcons: themeIcons,
            themeColorMix: themeColorMix,
            renderQuality: renderQuality)
    }

    /// 写回全量（恢复默认用；逐项经属性钳制）。
    static func apply(_ values: LumiereTuningValues) {
        renderScale = values.renderScale
        renderAntialias = values.renderAntialias
        lightIntensity = values.lightIntensity
        audioResponse = values.audioResponse
        fogDensity = values.fogDensity
        darkField = values.darkField
        moteAmount = values.moteAmount
        bloom = values.bloom
        textBloom = values.textBloom
        unlitOpacity = values.unlitOpacity
        windowNeighbors = values.windowNeighbors
        decay = values.decay
        echo = values.echo
        fogOctaves = values.fogOctaves
        lineArt = values.lineArt
        frontBokeh = values.frontBokeh
        trails = values.trails
        hideTrails = values.hideTrails
        seamlessTransitions = values.seamlessTransitions
        overlayFrame = values.overlayFrame
        textOnly = values.textOnly
        keywordColors = values.keywordColors
        themeIcons = values.themeIcons
        themeColorMix = values.themeColorMix
        renderQuality = values.renderQuality
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 StageEffectSettings 先例）

    private static var cachedValues: LumiereTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> LumiereTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 绘光调参面板入口（协调者接线点名形状）。
enum LumiereTuning {
    static func makePanel() -> UIViewController {
        LumiereTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 绘光调参面板：网页 LumiereSettingsPanel.tsx 的原生承接。
/// 分组与控件集与网页逐项对应（光 / 氛围 / 文字 / 主题 /
/// 性能 / 渲染）；滑杆范围与步进照网页面板入参（缺省步进
/// 0.05，darkField / unlitOpacity / themeColorMix 步进 0.01，
/// fogOctaves 整数步进 1）；拨动即写 LumiereTuningStore，
/// 渲染器经 0.25s 缓存至多 0.25s 后生效。系统风格：
/// systemBackground / label 语义色自动适配深色，字号下限 12pt。
final class LumiereTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var sliderRows: [SliderRowRefs] = []
    private var switchRows: [SwitchRowRefs] = []
    private var neighborsSegment: UISegmentedControl?
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
        title = "绘光参数"
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

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resetButton.backgroundColor = .secondarySystemBackground
        resetButton.layer.cornerRadius = 8
        resetButton.addTarget(self, action: #selector(applyDefaults), for: .touchUpInside)
        resetButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(resetButton)

        // 光
        addSection("光")
        addSlider(title: "光强", min: 0.3, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.lightIntensity },
                  write: { LumiereTuningStore.lightIntensity = $0 })
        addSlider(title: "随音乐变亮", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.audioResponse },
                  write: { LumiereTuningStore.audioResponse = $0 })
        addSlider(title: "图形辉光", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.bloom },
                  write: { LumiereTuningStore.bloom = $0 })
        addSlider(title: "文字辉光", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.textBloom },
                  write: { LumiereTuningStore.textBloom = $0 })

        // 氛围
        addSection("氛围")
        addSlider(title: "暗场", min: 0, max: 1, step: 0.01,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.darkField },
                  write: { LumiereTuningStore.darkField = $0 })
        addSlider(title: "烟雾浓度", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.fogDensity },
                  write: { LumiereTuningStore.fogDensity = $0 })
        addSlider(title: "烟雾细节", min: 2, max: 6, step: 1,
                  format: { "\(Int($0.rounded()))" },
                  read: { Double(LumiereTuningStore.fogOctaves) },
                  write: { LumiereTuningStore.fogOctaves = Int($0.rounded()) })
        addSlider(title: "浮尘数量", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.moteAmount },
                  write: { LumiereTuningStore.moteAmount = $0 })
        addSwitch(title: "前景散景",
                  read: { LumiereTuningStore.frontBokeh },
                  write: { LumiereTuningStore.frontBokeh = $0 })
        addSwitch(title: "线稿",
                  read: { LumiereTuningStore.lineArt },
                  write: { LumiereTuningStore.lineArt = $0 })
        addSwitch(title: "画框",
                  read: { LumiereTuningStore.overlayFrame },
                  write: { LumiereTuningStore.overlayFrame = $0 })

        // 文字
        addSection("文字")
        addSwitch(title: "仅显示歌词文字",
                  read: { LumiereTuningStore.textOnly },
                  write: { LumiereTuningStore.textOnly = $0 })
        addSlider(title: "未唱字透明度", min: 0.05, max: 0.6, step: 0.01,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.unlitOpacity },
                  write: { LumiereTuningStore.unlitOpacity = $0 })
        let neighbors = UISegmentedControl(items: ["上一行", "上下行"])
        neighbors.addTarget(self, action: #selector(neighborsChanged), for: .valueChanged)
        neighborsSegment = neighbors
        stack.addArrangedSubview(makeRow(title: "邻行显示", control: neighbors))
        addSlider(title: "崩解强度", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.decay },
                  write: { LumiereTuningStore.decay = $0 })
        addSlider(title: "背景歌词亮度", min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.echo },
                  write: { LumiereTuningStore.echo = $0 })
        addSwitch(title: "轨迹飞行",
                  read: { LumiereTuningStore.trails },
                  write: { LumiereTuningStore.trails = $0 })
        addSwitch(title: "隐藏轨迹线",
                  read: { LumiereTuningStore.hideTrails },
                  write: { LumiereTuningStore.hideTrails = $0 })
        addSwitch(title: "无缝过渡",
                  read: { LumiereTuningStore.seamlessTransitions },
                  write: { LumiereTuningStore.seamlessTransitions = $0 })

        // 主题
        addSection("主题")
        addSlider(title: "主题色占比", min: 0, max: 1, step: 0.01,
                  format: { String(format: "%.2f", $0) },
                  read: { LumiereTuningStore.themeColorMix },
                  write: { LumiereTuningStore.themeColorMix = $0 })
        addSwitch(title: "关键字着色",
                  read: { LumiereTuningStore.keywordColors },
                  write: { LumiereTuningStore.keywordColors = $0 })
        addSwitch(title: "主题图标",
                  read: { LumiereTuningStore.themeIcons },
                  write: { LumiereTuningStore.themeIcons = $0 })

        // 性能
        addSection("性能")
        let quality = UISegmentedControl(
            items: LumiereRenderQuality.allCases.map { $0.displayName })
        quality.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        qualitySegment = quality
        stack.addArrangedSubview(makeRow(title: "画质", control: quality))

        // 渲染
        addSection("渲染")
        let scaleSegment = UISegmentedControl(
            items: ["global", "0.5", "0.75", "1", "1.5", "2"].map {
                $0 == "global" ? "跟随全局" : "\($0)×"
            })
        scaleSegment.addTarget(self, action: #selector(renderScaleChanged), for: .valueChanged)
        renderScaleSegment = scaleSegment
        stack.addArrangedSubview(makeRow(title: "分辨率倍率", control: scaleSegment))
        let aaSegment = UISegmentedControl(items: ["跟随全局", "自动", "开", "关"])
        aaSegment.addTarget(self, action: #selector(renderAntialiasChanged), for: .valueChanged)
        renderAntialiasSegment = aaSegment
        stack.addArrangedSubview(makeRow(title: "抗锯齿", control: aaSegment))

        let note = UILabel()
        note.text = "说明：原生绘光以 CoreAnimation 图层等价呈现网页 Pixi 光场；随音乐变亮因协议无频谱数据源暂不生效，关键字着色与主题图标因协议未下发 wordColors / lyricsIcons 暂不生效。"
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
                           format: @escaping (Double) -> String,
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
            slider: slider, valueLabel: valueLabel,
            step: step, format: format, read: read, write: write))
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
        neighborsSegment?.selectedSegmentIndex =
            LumiereTuningStore.windowNeighbors == 1 ? 0 : 1
        if let index = LumiereRenderQuality.allCases.firstIndex(
            of: LumiereTuningStore.renderQuality) {
            qualitySegment?.selectedSegmentIndex = index
        }
        let scaleOptions = ["global", "0.5", "0.75", "1", "1.5", "2"]
        if let index = scaleOptions.firstIndex(of: LumiereTuningStore.renderScale) {
            renderScaleSegment?.selectedSegmentIndex = index
        }
        let aaOptions = ["global", "auto", "on", "off"]
        if let index = aaOptions.firstIndex(of: LumiereTuningStore.renderAntialias) {
            renderAntialiasSegment?.selectedSegmentIndex = index
        }
    }

    @objc private func applyDefaults() {
        LumiereTuningStore.resetAll()
        refreshFromStore()
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        guard let row = switchRows.first(where: { $0.toggle === toggle }) else { return }
        row.write(toggle.isOn)
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard sliderRows.indices.contains(slider.tag) else { return }
        let row = sliderRows[slider.tag]
        let raw = Double(slider.value)
        let stepped = (raw / row.step).rounded() * row.step
        row.write(stepped)
        row.valueLabel.text = row.format(row.read())
    }

    @objc private func neighborsChanged() {
        guard let segment = neighborsSegment else { return }
        LumiereTuningStore.windowNeighbors = segment.selectedSegmentIndex == 0 ? 1 : 2
    }

    @objc private func qualityChanged() {
        guard let segment = qualitySegment,
              LumiereRenderQuality.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        LumiereTuningStore.renderQuality =
            LumiereRenderQuality.allCases[segment.selectedSegmentIndex]
    }

    @objc private func renderScaleChanged() {
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        guard let segment = renderScaleSegment,
              options.indices.contains(segment.selectedSegmentIndex) else { return }
        LumiereTuningStore.renderScale = options[segment.selectedSegmentIndex]
    }

    @objc private func renderAntialiasChanged() {
        let options = ["global", "auto", "on", "off"]
        guard let segment = renderAntialiasSegment,
              options.indices.contains(segment.selectedSegmentIndex) else { return }
        LumiereTuningStore.renderAntialias = options[segment.selectedSegmentIndex]
    }
}
