import UIKit

// 商籁 sonnet 调参（3.7 (57) 工作流 B3）：网页版 sonnet/tuning.ts
// ＋ types.ts 的 SonnetTuning / DEFAULT_SONNET_TUNING 的原生承接。
//
// 存储口径：
//  - 每参数一个属性，UserDefaults 键前缀 "folia.tuning.sonnet."；
//    读时按网页 tuning.ts 的 resolve() 逐项钳制（numberWithin /
//    switchOr / outerFrameMode 白名单 / render 走
//    normalizeLyricRenderOverride），存量缺失或非法值回到缺省，
//    缺省逐字对齐 DEFAULT_SONNET_TUNING。
//  - render（LyricRenderOverride）拆两键存：renderScale 存字符串
//    （"global" 或 "0.5"/"0.75"/"1"/"1.5"/"2"）、renderAntialias
//    存字符串（"global"/"on"/"off"）；网页 normalize 口径：不认
//    识的 scale → "global"，antialias 只认 on/off、其余 → "global"。
//  - 渲染器逐帧读参走 SonnetTuningStore.cachedSnapshot()：0.25s
//    进程内缓存（与 StageEffectSettings.emphasisEnabledCached
//    同口径），面板拨动后至多 0.25s 在舞台生效。

/// 外框模式（网页 SonnetOuterFrameMode）。
enum SonnetOuterFrameMode: String, CaseIterable {
    case none
    case frame
    case full

    var displayName: String {
        switch self {
        case .none: return "无"
        case .frame: return "边框"
        case .full: return "完整"
        }
    }
}

/// 分辨率覆盖（网页 LyricRenderOverride.scale）："global" 跟随
/// 全局挡位，或固定倍率。rawValue 即落盘字符串。
enum SonnetRenderScaleOverride: String, CaseIterable {
    case global
    case x0_5 = "0.5"
    case x0_75 = "0.75"
    case x1 = "1"
    case x1_5 = "1.5"
    case x2 = "2"

    var displayName: String {
        self == .global ? "跟随全局" : "\(rawValue)×"
    }

    /// 固定倍率（global 时 nil = 跟随全局）。
    var multiplier: Double? {
        self == .global ? nil : Double(rawValue)
    }
}

/// 抗锯齿覆盖（网页 LyricRenderOverride.antialias）。
enum SonnetRenderAntialiasOverride: String, CaseIterable {
    case global
    case on
    case off

    var displayName: String {
        switch self {
        case .global: return "跟随全局"
        case .on: return "开"
        case .off: return "关"
        }
    }
}

/// 一份调参快照（渲染器每 0.25s 取一份，字段与网页
/// SonnetTuning 一一对应；render 拆为两个覆盖枚举）。
struct SonnetTuningSnapshot: Equatable {
    var renderScale: SonnetRenderScaleOverride = .global
    var renderAntialias: SonnetRenderAntialiasOverride = .global
    var cameraIntensity: Double = 1
    var typographyMotion: Double = 1
    var mgDensity: Double = 1
    var showOnlyText: Bool = false
    var showGuide: Bool = true
    var showBackgroundMg: Bool = true
    var showFixedGeo: Bool = true
    var showGiantDecorativeText: Bool = true
    var showBackgroundDecor: Bool = true
    var enableTransitions: Bool = true
    var outerFrameMode: SonnetOuterFrameMode = .full
    var textureResolution: Double = 1.5
    var postProcessEnabled: Bool = false
    var postProcessGrain: Double = 0.2
    var postProcessContrast: Double = 0
    var postProcessRgbShift: Double = 0
    var postProcessHalftone: Double = 0
    var postProcessVignette: Double = 0.85
    var postProcessLensDistortion: Double = 0.3
    var postProcessLensDispersion: Double = 0.6

    static let defaults = SonnetTuningSnapshot()
}

enum SonnetTuningStore {

    private static let prefix = "folia.tuning.sonnet."
    private static var defaults: UserDefaults { .standard }

    private static func key(_ name: String) -> String { prefix + name }

    // MARK: 读写法（网页 resolve() 的钳制口径）

    private static func number(_ name: String, fallback: Double,
                               range: ClosedRange<Double>) -> Double {
        guard let stored = defaults.object(forKey: key(name)) as? Double
        else { return fallback }
        return min(range.upperBound, max(range.lowerBound, stored))
    }

    private static func setNumber(_ name: String, _ value: Double,
                                  range: ClosedRange<Double>) {
        defaults.set(min(range.upperBound, max(range.lowerBound, value)),
                     forKey: key(name))
        invalidateCache()
    }

    private static func flag(_ name: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    private static func setFlag(_ name: String, _ value: Bool) {
        defaults.set(value, forKey: key(name))
        invalidateCache()
    }

    // MARK: render（LyricRenderOverride，缺省 {scale:'global', antialias:'global'}）

    static var renderScale: SonnetRenderScaleOverride {
        get {
            defaults.string(forKey: key("renderScale"))
                .flatMap { SonnetRenderScaleOverride(rawValue: $0) } ?? .global
        }
        set {
            defaults.set(newValue.rawValue, forKey: key("renderScale"))
            invalidateCache()
        }
    }

    static var renderAntialias: SonnetRenderAntialiasOverride {
        get {
            defaults.string(forKey: key("renderAntialias"))
                .flatMap { SonnetRenderAntialiasOverride(rawValue: $0) } ?? .global
        }
        set {
            defaults.set(newValue.rawValue, forKey: key("renderAntialias"))
            invalidateCache()
        }
    }

    // MARK: 动效强度（网页范围 0...2，缺省 1）

    static var cameraIntensity: Double {
        get { number("cameraIntensity", fallback: 1, range: 0...2) }
        set { setNumber("cameraIntensity", newValue, range: 0...2) }
    }

    static var typographyMotion: Double {
        get { number("typographyMotion", fallback: 1, range: 0...2) }
        set { setNumber("typographyMotion", newValue, range: 0...2) }
    }

    static var mgDensity: Double {
        get { number("mgDensity", fallback: 1, range: 0...2) }
        set { setNumber("mgDensity", newValue, range: 0...2) }
    }

    // MARK: 显隐开关（缺省见 DEFAULT_SONNET_TUNING）

    static var showOnlyText: Bool {
        get { flag("showOnlyText", fallback: false) }
        set { setFlag("showOnlyText", newValue) }
    }

    static var showGuide: Bool {
        get { flag("showGuide", fallback: true) }
        set { setFlag("showGuide", newValue) }
    }

    static var showBackgroundMg: Bool {
        get { flag("showBackgroundMg", fallback: true) }
        set { setFlag("showBackgroundMg", newValue) }
    }

    static var showFixedGeo: Bool {
        get { flag("showFixedGeo", fallback: true) }
        set { setFlag("showFixedGeo", newValue) }
    }

    static var showGiantDecorativeText: Bool {
        get { flag("showGiantDecorativeText", fallback: true) }
        set { setFlag("showGiantDecorativeText", newValue) }
    }

    static var showBackgroundDecor: Bool {
        get { flag("showBackgroundDecor", fallback: true) }
        set { setFlag("showBackgroundDecor", newValue) }
    }

    static var enableTransitions: Bool {
        get { flag("enableTransitions", fallback: true) }
        set { setFlag("enableTransitions", newValue) }
    }

    // MARK: 外框与纹理

    static var outerFrameMode: SonnetOuterFrameMode {
        get {
            defaults.string(forKey: key("outerFrameMode"))
                .flatMap { SonnetOuterFrameMode(rawValue: $0) } ?? .full
        }
        set {
            defaults.set(newValue.rawValue, forKey: key("outerFrameMode"))
            invalidateCache()
        }
    }

    /// 纹理分辨率（网页范围 0.5...4，缺省 1.5）。
    static var textureResolution: Double {
        get { number("textureResolution", fallback: 1.5, range: 0.5...4) }
        set { setNumber("textureResolution", newValue, range: 0.5...4) }
    }

    // MARK: 后处理（缺省 enabled=false；各量程见 types.ts 注释）

    static var postProcessEnabled: Bool {
        get { flag("postProcessEnabled", fallback: false) }
        set { setFlag("postProcessEnabled", newValue) }
    }

    static var postProcessGrain: Double {
        get { number("postProcessGrain", fallback: 0.2, range: 0...1) }
        set { setNumber("postProcessGrain", newValue, range: 0...1) }
    }

    static var postProcessContrast: Double {
        get { number("postProcessContrast", fallback: 0, range: 0...1) }
        set { setNumber("postProcessContrast", newValue, range: 0...1) }
    }

    static var postProcessRgbShift: Double {
        get { number("postProcessRgbShift", fallback: 0, range: 0...1) }
        set { setNumber("postProcessRgbShift", newValue, range: 0...1) }
    }

    static var postProcessHalftone: Double {
        get { number("postProcessHalftone", fallback: 0, range: 0...1) }
        set { setNumber("postProcessHalftone", newValue, range: 0...1) }
    }

    static var postProcessVignette: Double {
        get { number("postProcessVignette", fallback: 0.85, range: 0...2) }
        set { setNumber("postProcessVignette", newValue, range: 0...2) }
    }

    static var postProcessLensDistortion: Double {
        get { number("postProcessLensDistortion", fallback: 0.3, range: 0...2) }
        set { setNumber("postProcessLensDistortion", newValue, range: 0...2) }
    }

    static var postProcessLensDispersion: Double {
        get { number("postProcessLensDispersion", fallback: 0.6, range: 0...1) }
        set { setNumber("postProcessLensDispersion", newValue, range: 0...1) }
    }

    // MARK: 快照与重置

    /// 全量快照（逐项走上面的钳制读法）。
    static func snapshot() -> SonnetTuningSnapshot {
        var snap = SonnetTuningSnapshot()
        snap.renderScale = renderScale
        snap.renderAntialias = renderAntialias
        snap.cameraIntensity = cameraIntensity
        snap.typographyMotion = typographyMotion
        snap.mgDensity = mgDensity
        snap.showOnlyText = showOnlyText
        snap.showGuide = showGuide
        snap.showBackgroundMg = showBackgroundMg
        snap.showFixedGeo = showFixedGeo
        snap.showGiantDecorativeText = showGiantDecorativeText
        snap.showBackgroundDecor = showBackgroundDecor
        snap.enableTransitions = enableTransitions
        snap.outerFrameMode = outerFrameMode
        snap.textureResolution = textureResolution
        snap.postProcessEnabled = postProcessEnabled
        snap.postProcessGrain = postProcessGrain
        snap.postProcessContrast = postProcessContrast
        snap.postProcessRgbShift = postProcessRgbShift
        snap.postProcessHalftone = postProcessHalftone
        snap.postProcessVignette = postProcessVignette
        snap.postProcessLensDistortion = postProcessLensDistortion
        snap.postProcessLensDispersion = postProcessLensDispersion
        return snap
    }

    /// 恢复缺省（网页 handleResetSonnetTuning：清掉全部本前缀键）。
    static func resetAll() {
        for name in allKeyNames {
            defaults.removeObject(forKey: key(name))
        }
        invalidateCache()
    }

    private static let allKeyNames = [
        "renderScale", "renderAntialias",
        "cameraIntensity", "typographyMotion", "mgDensity",
        "showOnlyText", "showGuide", "showBackgroundMg", "showFixedGeo",
        "showGiantDecorativeText", "showBackgroundDecor", "enableTransitions",
        "outerFrameMode", "textureResolution",
        "postProcessEnabled", "postProcessGrain", "postProcessContrast",
        "postProcessRgbShift", "postProcessHalftone", "postProcessVignette",
        "postProcessLensDistortion", "postProcessLensDispersion",
    ]

    // MARK: 逐帧读的 0.25s 缓存（渲染器专用）

    private static var cache = SonnetTuningSnapshot.defaults
    private static var cacheAt: CFTimeInterval = -1

    static func cachedSnapshot(now: CFTimeInterval) -> SonnetTuningSnapshot {
        if cacheAt < 0 || now - cacheAt > 0.25 {
            cache = snapshot()
            cacheAt = now
        }
        return cache
    }

    private static func invalidateCache() {
        cacheAt = -1
    }
}

// MARK: - 调参面板

/// 商籁调参面入口（协调者接线用）：SonnetTuning.makePanel()。
enum SonnetTuning {
    static func makePanel() -> UIViewController {
        SonnetTuningPanelViewController()
    }
}

/// 商籁调参面板：UIKit 系统风格、深色底、字号 ≥12pt（正文 14、
/// 分组标题 13、数值 13）。分组与控件集对网页
/// SonnetSettingsPanel.tsx 五组：画质（纹理分辨率）/ 渲染（分辨
/// 率·抗锯齿覆盖）/ 动效 / 后处理 / 显示。拨动即写
/// SonnetTuningStore（滑杆 .valueChanged 连续写、开关/分段即时
/// 写），渲染器经 0.25s 缓存至多 0.25s 后生效。
final class SonnetTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var valueLabels: [String: UILabel] = [:]
    private var gatedPostControls: [UIControl] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "商籁 · 调参"
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildViews()
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
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        let snap = SonnetTuningStore.snapshot()

        // —— 画质（网页 QUALITY_GROUP）——
        addSection("画质")
        addSlider(id: "textureResolution", title: "纹理分辨率",
                  note: "越高越清晰、越吃性能（网页同警告）",
                  value: snap.textureResolution, min: 0.5, max: 4, step: 0.25) {
            SonnetTuningStore.textureResolution = $0
        }

        // —— 渲染覆盖（网页 RENDER_GROUP，#929）——
        addSection("渲染")
        addSegment(id: "renderScale", title: "分辨率",
                   items: SonnetRenderScaleOverride.allCases.map { $0.displayName },
                   selected: SonnetRenderScaleOverride.allCases.firstIndex(of: snap.renderScale) ?? 0) { index in
            SonnetTuningStore.renderScale = SonnetRenderScaleOverride.allCases[index]
        }
        addSegment(id: "renderAntialias", title: "抗锯齿",
                   items: SonnetRenderAntialiasOverride.allCases.map { $0.displayName },
                   selected: SonnetRenderAntialiasOverride.allCases.firstIndex(of: snap.renderAntialias) ?? 0) { index in
            SonnetTuningStore.renderAntialias = SonnetRenderAntialiasOverride.allCases[index]
        }

        // —— 动效（网页 MOTION_GROUP，0...2 步进 0.05）——
        addSection("动效")
        addSlider(id: "cameraIntensity", title: "镜头强度",
                  value: snap.cameraIntensity, min: 0, max: 2, step: 0.05) {
            SonnetTuningStore.cameraIntensity = $0
        }
        addSlider(id: "typographyMotion", title: "文字动效",
                  value: snap.typographyMotion, min: 0, max: 2, step: 0.05) {
            SonnetTuningStore.typographyMotion = $0
        }
        addSlider(id: "mgDensity", title: "MG 密度",
                  value: snap.mgDensity, min: 0, max: 2, step: 0.05) {
            SonnetTuningStore.mgDensity = $0
        }

        // —— 后处理（网页 POST_PROCESS_GROUP；子项随总开关启停）——
        addSection("后处理")
        addSwitch(id: "postProcessEnabled", title: "后处理总开关",
                  isOn: snap.postProcessEnabled) { [weak self] isOn in
            SonnetTuningStore.postProcessEnabled = isOn
            self?.refreshPostGating(isOn)
        }
        let postSliders: [(id: String, title: String, value: Double, max: Double,
                           write: (Double) -> Void)] = [
            ("postProcessGrain", "胶片颗粒", snap.postProcessGrain, 1,
             { SonnetTuningStore.postProcessGrain = $0 }),
            ("postProcessContrast", "对比度", snap.postProcessContrast, 1,
             { SonnetTuningStore.postProcessContrast = $0 }),
            ("postProcessRgbShift", "RGB 偏移", snap.postProcessRgbShift, 1,
             { SonnetTuningStore.postProcessRgbShift = $0 }),
            ("postProcessLensDistortion", "镜头畸变", snap.postProcessLensDistortion, 2,
             { SonnetTuningStore.postProcessLensDistortion = $0 }),
            ("postProcessLensDispersion", "镜头色散", snap.postProcessLensDispersion, 1,
             { SonnetTuningStore.postProcessLensDispersion = $0 }),
            ("postProcessHalftone", "半调网点", snap.postProcessHalftone, 1,
             { SonnetTuningStore.postProcessHalftone = $0 }),
            ("postProcessVignette", "暗角", snap.postProcessVignette, 2,
             { SonnetTuningStore.postProcessVignette = $0 }),
        ]
        for item in postSliders {
            let slider = addSlider(id: item.id, title: item.title,
                                   value: item.value, min: 0, max: item.max,
                                   step: 0.05, write: item.write)
            gatedPostControls.append(slider)
        }
        refreshPostGating(snap.postProcessEnabled)

        // —— 显示（网页 DISPLAY_GROUP）——
        addSection("显示")
        addSegment(id: "outerFrameMode", title: "外框模式",
                   items: SonnetOuterFrameMode.allCases.map { $0.displayName },
                   selected: SonnetOuterFrameMode.allCases.firstIndex(of: snap.outerFrameMode) ?? 2) { index in
            SonnetTuningStore.outerFrameMode = SonnetOuterFrameMode.allCases[index]
        }
        let switches: [(id: String, title: String, isOn: Bool,
                        write: (Bool) -> Void)] = [
            ("showOnlyText", "只显示文字", snap.showOnlyText,
             { SonnetTuningStore.showOnlyText = $0 }),
            ("showGuide", "引导线", snap.showGuide,
             { SonnetTuningStore.showGuide = $0 }),
            ("showBackgroundMg", "背景 MG", snap.showBackgroundMg,
             { SonnetTuningStore.showBackgroundMg = $0 }),
            ("showFixedGeo", "固定几何", snap.showFixedGeo,
             { SonnetTuningStore.showFixedGeo = $0 }),
            ("showGiantDecorativeText", "巨型装饰字", snap.showGiantDecorativeText,
             { SonnetTuningStore.showGiantDecorativeText = $0 }),
            ("showBackgroundDecor", "背景装饰", snap.showBackgroundDecor,
             { SonnetTuningStore.showBackgroundDecor = $0 }),
            ("enableTransitions", "转场", snap.enableTransitions,
             { SonnetTuningStore.enableTransitions = $0 }),
        ]
        for item in switches {
            addSwitch(id: item.id, title: item.title, isOn: item.isOn, write: item.write)
        }

        // —— 重置 ——
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认调参", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        let resetRow = UIView()
        resetRow.addSubview(resetButton)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resetButton.topAnchor.constraint(equalTo: resetRow.topAnchor, constant: 14),
            resetButton.bottomAnchor.constraint(equalTo: resetRow.bottomAnchor, constant: -6),
            resetButton.centerXAnchor.constraint(equalTo: resetRow.centerXAnchor),
        ])
        stack.addArrangedSubview(resetRow)
    }

    private func refreshPostGating(_ enabled: Bool) {
        for control in gatedPostControls { control.isEnabled = enabled }
    }

    @objc private func resetTapped() {
        SonnetTuningStore.resetAll()
        // 整面重建回显缺省（最简且无旧值残留）。
        for sub in stack.arrangedSubviews {
            stack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        valueLabels.removeAll()
        gatedPostControls.removeAll()
        buildViews()
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
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        ])
        stack.addArrangedSubview(container)
    }

    private func makeTitleBlock(title: String, note: String?) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        let column = UIStackView(arrangedSubviews: [titleLabel])
        column.axis = .vertical
        column.spacing = 2
        if let note {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = .systemFont(ofSize: 12, weight: .regular)
            noteLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            noteLabel.numberOfLines = 0
            column.addArrangedSubview(noteLabel)
        }
        return column
    }

    private func makeRow(title: String, note: String?, control: UIView) -> UIView {
        let row = UIView()
        let titles = makeTitleBlock(title: title, note: note)
        titles.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titles)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            titles.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titles.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titles.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 6),
            titles.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -6),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: titles.trailingAnchor, constant: 12),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return row
    }

    @discardableResult
    private func addSlider(id: String, title: String, note: String? = nil,
                           value: Double, min: Double, max: Double, step: Double,
                           write: @escaping (Double) -> Void) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.value = Float(value)
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        valueLabel.text = Self.formatTimes(value)
        valueLabels[id] = valueLabel
        let group = UIStackView(arrangedSubviews: [slider, valueLabel])
        group.axis = .horizontal
        group.spacing = 8
        group.alignment = .center
        let action = SliderAction { raw in
            let stepped = (raw / step).rounded() * step
            let clamped = Swift.min(max, Swift.max(min, stepped))
            valueLabel.text = Self.formatTimes(clamped)
            write(clamped)
        }
        sliderActions[id] = action
        slider.addTarget(action, action: #selector(SliderAction.fired(_:)),
                         for: .valueChanged)
        stack.addArrangedSubview(makeRow(title: title, note: note, control: group))
        return slider
    }

    private func addSwitch(id: String, title: String, isOn: Bool,
                           write: @escaping (Bool) -> Void) {
        let toggle = UISwitch()
        toggle.isOn = isOn
        let action = SwitchAction(write: write)
        switchActions[id] = action
        toggle.addTarget(action, action: #selector(SwitchAction.fired(_:)),
                         for: .valueChanged)
        stack.addArrangedSubview(makeRow(title: title, note: nil, control: toggle))
    }

    private func addSegment(id: String, title: String, items: [String],
                            selected: Int, write: @escaping (Int) -> Void) {
        let segment = UISegmentedControl(items: items)
        segment.selectedSegmentIndex = selected
        segment.apportionsSegmentWidthsByContent = true
        let action = SegmentAction(write: write)
        segmentActions[id] = action
        segment.addTarget(action, action: #selector(SegmentAction.fired(_:)),
                          for: .valueChanged)
        stack.addArrangedSubview(makeRow(title: title, note: nil, control: segment))
    }

    private static func formatTimes(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    // 控件 target 的持有者（UISlider/UISwitch 的 target 不强引，
    // 面板存活期间由本字典持有，面板释放后随之释放）。
    private var sliderActions: [String: SliderAction] = [:]
    private var switchActions: [String: SwitchAction] = [:]
    private var segmentActions: [String: SegmentAction] = [:]

    private final class SliderAction: NSObject {
        let handler: (Double) -> Void
        init(handler: @escaping (Double) -> Void) { self.handler = handler }
        @objc func fired(_ sender: UISlider) { handler(Double(sender.value)) }
    }

    private final class SwitchAction: NSObject {
        let write: (Bool) -> Void
        init(write: @escaping (Bool) -> Void) { self.write = write }
        @objc func fired(_ sender: UISwitch) { write(sender.isOn) }
    }

    private final class SegmentAction: NSObject {
        let write: (Int) -> Void
        init(write: @escaping (Int) -> Void) { self.write = write }
        @objc func fired(_ sender: UISegmentedControl) {
            write(sender.selectedSegmentIndex)
        }
    }
}
