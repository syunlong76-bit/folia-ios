import UIKit

// 时计 pendolo 调参存储与面板（3.7 (57) 工作流 B1）：
// 网页版 folia-major/src/components/visualizer/pendolo/tuning.ts
// 与 src/types.ts 的 PendoloTuning / DEFAULT_PENDOLO_TUNING 的
// 原生承接。网页每个参数在本文件 PendoloTuningStore 里各有一
// 个属性，UserDefaults 键前缀 "folia.tuning.pendolo."，缺省值
// 与钳制范围与网页 resolve() 逐字对齐（见各属性注释）；渲染
// 器（PendoloStageRenderer）只经本门面读参，逐帧读走 0.25s
// 缓存（照 StageEffectSettings.emphasisEnabledCached 先例）。
// render 参数在网页是一个 {scale, antialias} 对象，原生拆成
// renderScale / renderAntialias 两个字符串属性存两键，取值集
// 与网页 LyricRenderOverride 一致（normalizeLyricRenderOverride
// 口径：不认识的值回到 "global"）。

/// 齿轮装饰档位（网页 PendoloTuning.showGearDecor）。
enum PendoloGearDecor: String, CaseIterable {
    case none
    case subtle
    case full

    var displayName: String {
        switch self {
        case .none: return "无"
        case .subtle: return "弱"
        case .full: return "全"
        }
    }
}

/// 一次读全的参数快照（渲染器逐帧消费的形状）。
struct PendoloTuningValues: Equatable {
    var renderScale: String = "global"        // 网页 render.scale
    var renderAntialias: String = "global"    // 网页 render.antialias
    var arcRadius: Double = 0.42
    var arcAngleDeg: Double = 100
    var wheelCenterX: Double = 0.0
    var wheelCenterY: Double = 0.50
    var tickSnappiness: Double = 2.0
    var activeScale: Double = 1.25
    var showGearDecor: PendoloGearDecor = .subtle
    var showCenterGradient: Bool = true
    var showCoverOnWatchFace: Bool = false
    var enableLineGlow: Bool = false
    var mirrorLayout: Bool = false
    var tiltDeg: Double = 0
    var tiltAxisDeg: Double = 0
    var parallaxDepth: Double = 1
    var hubView: Bool = false
    var hubViewHeight: Double = 1.4
    var hubViewBack: Double = 1.2

    static let defaults = PendoloTuningValues()
}

/// 时计调参存储门面：网页 tuning.ts 每个参数一个属性。
enum PendoloTuningStore {

    private static let prefix = "folia.tuning.pendolo."
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

    /// render 倍率的数值落点： "global" → nil（跟随全局挡位，
    /// 原生舞台无全局挡位消费点，渲染器按 nil = 不缩放处理）。
    static var renderScaleValue: Double? {
        let raw = renderScale
        return raw == "global" ? nil : Double(raw)
    }

    // MARK: 几何与运动（范围 = 网页 tuning.ts resolve 钳制）

    /// 弧半径（视口短边比例），[0.25, 0.80]，缺省 0.42。
    static var arcRadius: Double {
        get { doubleValue("arcRadius", fallback: 0.42, range: 0.25...0.80) }
        set { setDouble("arcRadius", newValue, range: 0.25...0.80) }
    }

    /// 弧总张角（度），[40, 160]，缺省 100。
    static var arcAngleDeg: Double {
        get { doubleValue("arcAngleDeg", fallback: 100, range: 40...160) }
        set { setDouble("arcAngleDeg", newValue, range: 40...160) }
    }

    /// 轮心横坐标（视口宽比例，自左缘量；镜像时自右缘量），
    /// resolve 钳制 [-0.30, 0.50]，缺省 0；网页面板滑杆范围
    /// [-0.2, 0.4] 更窄，面板沿用面板范围。
    static var wheelCenterX: Double {
        get { doubleValue("wheelCenterX", fallback: 0, range: -0.30...0.50) }
        set { setDouble("wheelCenterX", newValue, range: -0.30...0.50) }
    }

    /// 轮心纵坐标（视口高比例），[0.20, 0.80]，缺省 0.50。
    static var wheelCenterY: Double {
        get { doubleValue("wheelCenterY", fallback: 0.50, range: 0.20...0.80) }
        set { setDouble("wheelCenterY", newValue, range: 0.20...0.80) }
    }

    /// 棘轮弹簧敏捷度，[0.5, 2.0]，缺省 2.0。
    static var tickSnappiness: Double {
        get { doubleValue("tickSnappiness", fallback: 2.0, range: 0.5...2.0) }
        set { setDouble("tickSnappiness", newValue, range: 0.5...2.0) }
    }

    /// 焦点行缩放，[1.00, 1.60]，缺省 1.25。
    static var activeScale: Double {
        get { doubleValue("activeScale", fallback: 1.25, range: 1.00...1.60) }
        set { setDouble("activeScale", newValue, range: 1.00...1.60) }
    }

    /// 表盘倾斜（度），[-70, 70]（PENDOLO_TILT_LIMIT_DEG），缺省 0。
    static var tiltDeg: Double {
        get { doubleValue("tiltDeg", fallback: 0, range: -70...70) }
        set { setDouble("tiltDeg", newValue, range: -70...70) }
    }

    /// 倾斜轴方向（度），[-90, 90]，缺省 0。
    static var tiltAxisDeg: Double {
        get { doubleValue("tiltAxisDeg", fallback: 0, range: -90...90) }
        set { setDouble("tiltAxisDeg", newValue, range: -90...90) }
    }

    /// 分层视差强度，[0, 2]，缺省 1。
    static var parallaxDepth: Double {
        get { doubleValue("parallaxDepth", fallback: 1, range: 0...2) }
        set { setDouble("parallaxDepth", newValue, range: 0...2) }
    }

    /// 轮心视角相机高度（弧半径倍数），[0.4, 3]
    /// （PENDOLO_HUB_VIEW_HEIGHT_MIN/MAX），缺省 1.4。
    static var hubViewHeight: Double {
        get { doubleValue("hubViewHeight", fallback: 1.4, range: 0.4...3) }
        set { setDouble("hubViewHeight", newValue, range: 0.4...3) }
    }

    /// 轮心视角相机后退（弧半径倍数），[0.2, 3]
    /// （PENDOLO_HUB_VIEW_BACK_MIN/MAX），缺省 1.2。
    static var hubViewBack: Double {
        get { doubleValue("hubViewBack", fallback: 1.2, range: 0.2...3) }
        set { setDouble("hubViewBack", newValue, range: 0.2...3) }
    }

    // MARK: 开关与枚举

    /// 齿轮装饰档位，缺省 subtle；不认识的存值回 subtle
    /// （网页 resolve 口径：非三值之一回 base）。
    static var showGearDecor: PendoloGearDecor {
        get {
            defaults.string(forKey: key("showGearDecor"))
                .flatMap { PendoloGearDecor(rawValue: $0) } ?? .subtle
        }
        set { defaults.set(newValue.rawValue, forKey: key("showGearDecor")) }
    }

    /// 中心径向渐变，缺省 true。
    static var showCenterGradient: Bool {
        get { boolValue("showCenterGradient", fallback: true) }
        set { defaults.set(newValue, forKey: key("showCenterGradient")) }
    }

    /// 表盘上显示封面，缺省 false。
    static var showCoverOnWatchFace: Bool {
        get { boolValue("showCoverOnWatchFace", fallback: false) }
        set { defaults.set(newValue, forKey: key("showCoverOnWatchFace")) }
    }

    /// 齿轮线辉光，缺省 false。
    static var enableLineGlow: Bool {
        get { boolValue("enableLineGlow", fallback: false) }
        set { defaults.set(newValue, forKey: key("enableLineGlow")) }
    }

    /// 左右镜像布局，缺省 false。
    static var mirrorLayout: Bool {
        get { boolValue("mirrorLayout", fallback: false) }
        set { defaults.set(newValue, forKey: key("mirrorLayout")) }
    }

    /// 轮心视角，缺省 false。
    static var hubView: Bool {
        get { boolValue("hubView", fallback: false) }
        set { defaults.set(newValue, forKey: key("hubView")) }
    }

    // MARK: 全量读写

    /// 一次读全（每属性各自钳制/回缺省，与网页 resolve 同义）。
    static func values() -> PendoloTuningValues {
        PendoloTuningValues(
            renderScale: renderScale,
            renderAntialias: renderAntialias,
            arcRadius: arcRadius,
            arcAngleDeg: arcAngleDeg,
            wheelCenterX: wheelCenterX,
            wheelCenterY: wheelCenterY,
            tickSnappiness: tickSnappiness,
            activeScale: activeScale,
            showGearDecor: showGearDecor,
            showCenterGradient: showCenterGradient,
            showCoverOnWatchFace: showCoverOnWatchFace,
            enableLineGlow: enableLineGlow,
            mirrorLayout: mirrorLayout,
            tiltDeg: tiltDeg,
            tiltAxisDeg: tiltAxisDeg,
            parallaxDepth: parallaxDepth,
            hubView: hubView,
            hubViewHeight: hubViewHeight,
            hubViewBack: hubViewBack)
    }

    /// 写回全量（面板预设/恢复默认用；逐项经属性钳制）。
    static func apply(_ values: PendoloTuningValues) {
        renderScale = values.renderScale
        renderAntialias = values.renderAntialias
        arcRadius = values.arcRadius
        arcAngleDeg = values.arcAngleDeg
        wheelCenterX = values.wheelCenterX
        wheelCenterY = values.wheelCenterY
        tickSnappiness = values.tickSnappiness
        activeScale = values.activeScale
        showGearDecor = values.showGearDecor
        showCenterGradient = values.showCenterGradient
        showCoverOnWatchFace = values.showCoverOnWatchFace
        enableLineGlow = values.enableLineGlow
        mirrorLayout = values.mirrorLayout
        tiltDeg = values.tiltDeg
        tiltAxisDeg = values.tiltAxisDeg
        parallaxDepth = values.parallaxDepth
        hubView = values.hubView
        hubViewHeight = values.hubViewHeight
        hubViewBack = values.hubViewBack
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省（网页面板「默认」钮同义：render 一并还原）。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 StageEffectSettings 先例）

    private static var cachedValues: PendoloTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> PendoloTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 时计调参面板入口（协调者接线点名形状）。
enum PendoloTuning {
    static func makePanel() -> UIViewController {
        PendoloTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 时计调参面板：网页 PendoloSettingsPanel.tsx 的原生承接。
/// 控件集与网页逐项对应（滑杆范围/步进照网页 SliderRow 入参，
/// 步进在写入时吸附）；拨动即写 PendoloTuningStore，渲染器经
/// 0.25s 缓存至多 0.25s 后生效，无需重开舞台。系统风格：
/// systemBackground / label 语义色自动适配深色，字号下限 12pt。
/// 预设钮照网页四钮：默认 / 预设1 前倾 / 预设2 侧倾 / 预设3
/// 轮心视角（预设只换视角与轮盘、保留当前镜像选择，网页同义；
/// 默认钮连镜像一并还原且含 render 组，网页默认钮不含 render
/// 组——原生面板把 render 放在同页末尾，恢复默认一并还原，
/// 差异在此注明）。
final class PendoloTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var sliderRows: [SliderRowRefs] = []
    private var switchRows: [SwitchRowRefs] = []
    private var gearSegment: UISegmentedControl?
    private var renderScaleSegment: UISegmentedControl?
    private var renderAntialiasSegment: UISegmentedControl?
    private var tiltRows: [UIView] = []
    private var hubRows: [UIView] = []

    private struct SliderRowRefs {
        let key: String
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
        title = "时计参数"
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

        // 预设行（网页组标题栏四钮）。
        let presetStack = UIStackView()
        presetStack.axis = .horizontal
        presetStack.spacing = 8
        presetStack.distribution = .fillEqually
        let presets: [(String, Selector)] = [
            ("默认", #selector(applyDefaultPreset)),
            ("预设 1", #selector(applyPresetTiltForward)),
            ("预设 2", #selector(applyPresetTilt)),
            ("预设 3", #selector(applyPresetHubView)),
        ]
        for (label, action) in presets {
            let button = UIButton(type: .system)
            button.setTitle(label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            button.backgroundColor = .secondarySystemBackground
            button.layer.cornerRadius = 8
            button.addTarget(self, action: action, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            presetStack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(presetStack)

        addSwitch(title: "左右镜像",
                  read: { PendoloTuningStore.mirrorLayout },
                  write: { PendoloTuningStore.mirrorLayout = $0 })
        addSlider(key: "wheelCenterX", title: "轮心横移",
                  min: -0.2, max: 0.4, step: 0.01,
                  format: { String(format: "%+.0f%%", $0 * 100) },
                  read: { PendoloTuningStore.wheelCenterX },
                  write: { PendoloTuningStore.wheelCenterX = $0 })
        addSlider(key: "wheelCenterY", title: "轮心纵移",
                  min: 0.2, max: 0.8, step: 0.01,
                  format: { String(format: "%.0f%%", $0 * 100) },
                  read: { PendoloTuningStore.wheelCenterY },
                  write: { PendoloTuningStore.wheelCenterY = $0 })
        addSlider(key: "arcRadius", title: "轮盘半径",
                  min: 0.25, max: 0.8, step: 0.01,
                  format: { String(format: "%.0f%%", $0 * 100) },
                  read: { PendoloTuningStore.arcRadius },
                  write: { PendoloTuningStore.arcRadius = $0 })
        addSlider(key: "arcAngleDeg", title: "弧线张角",
                  min: 40, max: 160, step: 5,
                  format: { "\(Int($0.rounded()))°" },
                  read: { PendoloTuningStore.arcAngleDeg },
                  write: { PendoloTuningStore.arcAngleDeg = $0 })
        addSwitch(title: "轮心视角",
                  read: { PendoloTuningStore.hubView },
                  write: { [weak self] in
                      PendoloTuningStore.hubView = $0
                      self?.refreshPerspectiveRows()
                  })
        hubRows.append(addSlider(key: "hubViewHeight", title: "轮心视角 · 相机高度",
                  min: 0.4, max: 3, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { PendoloTuningStore.hubViewHeight },
                  write: { PendoloTuningStore.hubViewHeight = $0 }))
        hubRows.append(addSlider(key: "hubViewBack", title: "轮心视角 · 相机后退",
                  min: 0.2, max: 3, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { PendoloTuningStore.hubViewBack },
                  write: { PendoloTuningStore.hubViewBack = $0 }))
        tiltRows.append(addSlider(key: "tiltDeg", title: "表盘倾斜",
                  min: -70, max: 70, step: 1,
                  format: { "\(Int($0.rounded()))°" },
                  read: { PendoloTuningStore.tiltDeg },
                  write: { PendoloTuningStore.tiltDeg = $0 }))
        tiltRows.append(addSlider(key: "tiltAxisDeg", title: "倾斜轴方向",
                  min: -90, max: 90, step: 1,
                  format: { "\(Int($0.rounded()))°" },
                  read: { PendoloTuningStore.tiltAxisDeg },
                  write: { PendoloTuningStore.tiltAxisDeg = $0 }))
        addSlider(key: "parallaxDepth", title: "分层视差",
                  min: 0, max: 2, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { PendoloTuningStore.parallaxDepth },
                  write: { PendoloTuningStore.parallaxDepth = $0 })
        addSlider(key: "tickSnappiness", title: "棘轮敏捷度",
                  min: 0.5, max: 2, step: 0.1,
                  format: { String(format: "%.1f×", $0) },
                  read: { PendoloTuningStore.tickSnappiness },
                  write: { PendoloTuningStore.tickSnappiness = $0 })
        addSlider(key: "activeScale", title: "焦点行缩放",
                  min: 1, max: 1.6, step: 0.05,
                  format: { String(format: "%.2f×", $0) },
                  read: { PendoloTuningStore.activeScale },
                  write: { PendoloTuningStore.activeScale = $0 })

        // 齿轮装饰（网页 Segmented 三档）。
        let gear = UISegmentedControl(
            items: PendoloGearDecor.allCases.map { $0.displayName })
        gear.addTarget(self, action: #selector(gearChanged), for: .valueChanged)
        gearSegment = gear
        stack.addArrangedSubview(makeRow(title: "齿轮装饰", control: gear))

        addSwitch(title: "中心渐变",
                  read: { PendoloTuningStore.showCenterGradient },
                  write: { PendoloTuningStore.showCenterGradient = $0 })
        addSwitch(title: "表盘显示封面",
                  read: { PendoloTuningStore.showCoverOnWatchFace },
                  write: { PendoloTuningStore.showCoverOnWatchFace = $0 })
        addSwitch(title: "齿轮线辉光",
                  read: { PendoloTuningStore.enableLineGlow },
                  write: { PendoloTuningStore.enableLineGlow = $0 })

        // 渲染组（网页 LyricRenderQualityRows：倍率 + 抗锯齿）。
        let sectionLabel = UILabel()
        sectionLabel.text = "渲染"
        sectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sectionLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(sectionLabel)
        let scaleOptions = ["global", "0.5", "0.75", "1", "1.5", "2"]
        let scaleSegment = UISegmentedControl(items: scaleOptions.map {
            $0 == "global" ? "跟随全局" : "\($0)×"
        })
        scaleSegment.tag = 0
        scaleSegment.addTarget(self, action: #selector(renderChanged(_:)), for: .valueChanged)
        renderScaleSegment = scaleSegment
        stack.addArrangedSubview(makeRow(title: "分辨率倍率", control: scaleSegment))
        let aaOptions = ["global", "auto", "on", "off"]
        let aaSegment = UISegmentedControl(items: ["跟随全局", "自动", "开", "关"])
        aaSegment.tag = 1
        aaSegment.addTarget(self, action: #selector(renderChanged(_:)), for: .valueChanged)
        renderAntialiasSegment = aaSegment
        _ = aaOptions
        stack.addArrangedSubview(makeRow(title: "抗锯齿", control: aaSegment))

        let note = UILabel()
        note.text = "说明：轮心视角与表盘倾斜在原生为透视近似呈现；封面在表盘上以调色板色盘占位（协议未下发封面位图）。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
    }

    // MARK: 行工厂

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

    @discardableResult
    private func addSwitch(title: String,
                           read: @escaping () -> Bool,
                           write: @escaping (Bool) -> Void) -> UIView {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        switchRows.append(SwitchRowRefs(toggle: toggle, read: read, write: write))
        let row = makeRow(title: title, control: toggle)
        stack.addArrangedSubview(row)
        return row
    }

    @discardableResult
    private func addSlider(key: String, title: String,
                           min: Double, max: Double, step: Double,
                           format: @escaping (Double) -> String,
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
            valueLabel.widthAnchor.constraint(equalToConstant: 52),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        sliderRows.append(SliderRowRefs(
            key: key, slider: slider, valueLabel: valueLabel,
            step: step, format: format, read: read, write: write))
        slider.tag = sliderRows.count - 1
        stack.addArrangedSubview(container)
        return container
    }

    // MARK: 回显与动作

    private func refreshFromStore() {
        for row in sliderRows {
            let value = row.read()
            row.slider.value = Float(value)
            row.valueLabel.text = row.format(value)
        }
        for row in switchRows { row.toggle.isOn = row.read() }
        if let index = PendoloGearDecor.allCases.firstIndex(
            of: PendoloTuningStore.showGearDecor) {
            gearSegment?.selectedSegmentIndex = index
        }
        let scaleOptions = ["global", "0.5", "0.75", "1", "1.5", "2"]
        if let index = scaleOptions.firstIndex(of: PendoloTuningStore.renderScale) {
            renderScaleSegment?.selectedSegmentIndex = index
        }
        let aaOptions = ["global", "auto", "on", "off"]
        if let index = aaOptions.firstIndex(of: PendoloTuningStore.renderAntialias) {
            renderAntialiasSegment?.selectedSegmentIndex = index
        }
        refreshPerspectiveRows()
    }

    /// 轮心视角开时藏倾斜两行、显相机两行（网页面板同逻辑）。
    private func refreshPerspectiveRows() {
        let hub = PendoloTuningStore.hubView
        for row in tiltRows { row.isHidden = hub }
        for row in hubRows { row.isHidden = !hub }
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

    @objc private func gearChanged() {
        guard let segment = gearSegment,
              PendoloGearDecor.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        PendoloTuningStore.showGearDecor =
            PendoloGearDecor.allCases[segment.selectedSegmentIndex]
    }

    @objc private func renderChanged(_ segment: UISegmentedControl) {
        if segment.tag == 0 {
            let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
            guard options.indices.contains(segment.selectedSegmentIndex) else { return }
            PendoloTuningStore.renderScale = options[segment.selectedSegmentIndex]
        } else {
            let options = ["global", "auto", "on", "off"]
            guard options.indices.contains(segment.selectedSegmentIndex) else { return }
            PendoloTuningStore.renderAntialias = options[segment.selectedSegmentIndex]
        }
    }

    // MARK: 预设（网页 PendoloSettingsPanel 三预设逐值照搬）

    @objc private func applyDefaultPreset() {
        PendoloTuningStore.resetAll()
        refreshFromStore()
    }

    @objc private func applyPresetTiltForward() {
        var values = PendoloTuningValues.defaults
        values.mirrorLayout = PendoloTuningStore.mirrorLayout
        values.arcRadius = 0.5
        values.wheelCenterX = 0.3
        values.tickSnappiness = 1.8
        values.tiltDeg = 40
        values.tiltAxisDeg = -10
        values.parallaxDepth = 2
        PendoloTuningStore.apply(values)
        refreshFromStore()
    }

    @objc private func applyPresetTilt() {
        var values = PendoloTuningValues.defaults
        values.mirrorLayout = PendoloTuningStore.mirrorLayout
        values.arcRadius = 0.5
        values.wheelCenterX = 0.3
        values.tiltDeg = -53
        values.tiltAxisDeg = 66
        values.parallaxDepth = 1.65
        PendoloTuningStore.apply(values)
        refreshFromStore()
    }

    @objc private func applyPresetHubView() {
        var values = PendoloTuningValues.defaults
        values.mirrorLayout = PendoloTuningStore.mirrorLayout
        values.hubView = true
        values.hubViewHeight = 1.4
        values.hubViewBack = 1.2
        values.parallaxDepth = 1
        PendoloTuningStore.apply(values)
        refreshFromStore()
    }
}
