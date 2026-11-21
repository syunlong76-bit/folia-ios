import UIKit

// 雾笺 nebbia 调参存储与面板（3.7 (57) 工作流 B8）：
// 网页版 folia-major/src/components/visualizer/nebbia/tuning.ts、
// types.ts（NebbiaTuning / DEFAULT_NEBBIA_TUNING / NEBBIA_LIMITS）
// 与 NebbiaSettingsPanel.tsx 的原生承接。网页每个参数在本文件
// NebbiaTuningStore 里各有一个属性，UserDefaults 键前缀
// "folia.tuning.nebbia."，缺省值与钳制范围逐字对齐网页
// normalizeNebbiaTuning（数值经 NEBBIA_LIMITS 夹取；开关组经
// subsetOf 按固定顺序过滤、空组回缺省——scenery 例外：网页
// 明确「窗外可以全关」，存过空组即空组，只有没存过才用缺省）。
// render 在网页是一个 {scale, antialias} 对象，原生拆成
// renderScale / renderAntialias 两键（口径同 PendoloTuning）。
// 渲染器（NebbiaStageRenderer）只经本门面读参，逐帧读走
// 0.25s 缓存（照 PendoloTuningStore.valuesCached 先例）。

// MARK: - 枚举（rawValue 与网页字面量逐字一致）

/// 字怎么出现（NEBBIA_APPEAR_STYLES）。
enum NebbiaAppearStyle: String, CaseIterable {
    case write
    case fade
    case breath

    var displayName: String {
        switch self {
        case .write: return "手指书写"
        case .fade: return "慢慢显现"
        case .breath: return "哈气后书写"
        }
    }
}

/// 写完怎么消失（NEBBIA_FADE_STYLES）。
enum NebbiaFadeStyle: String, CaseIterable {
    case fog
    case fingers

    var displayName: String {
        switch self {
        case .fog: return "慢慢起雾"
        case .fingers: return "手指抹掉"
        }
    }
}

/// 一句的构图（NEBBIA_LAYOUTS）。
enum NebbiaLayout: String, CaseIterable {
    case ribbon
    case lines2
    case lines3
    case cross
    case pillar
    case header
    case badge
    case columns
    case orbit

    var displayName: String {
        switch self {
        case .ribbon: return "横条"
        case .lines2: return "两行错落"
        case .lines3: return "三行错落"
        case .cross: return "十字"
        case .pillar: return "竖柱"
        case .header: return "刊头"
        case .badge: return "徽章"
        case .columns: return "竖排几列"
        case .orbit: return "环绕"
        }
    }
}

/// 窗外画哪几样（NEBBIA_SCENERY，可全关）。
enum NebbiaSceneryPart: String, CaseIterable {
    case spot
    case buildings
    case lights
    case cars
    case road

    var displayName: String {
        switch self {
        case .spot: return "聚光灯"
        case .buildings: return "楼群"
        case .lights: return "光斑"
        case .cars: return "车灯"
        case .road: return "马路"
        }
    }
}

/// 窗外的雨（NEBBIA_RAIN）。
enum NebbiaRainMode: String, CaseIterable {
    case slant
    case straight
    case off

    var displayName: String {
        switch self {
        case .slant: return "斜着"
        case .straight: return "竖直"
        case .off: return "不下"
        }
    }
}

/// 窗外是什么（NEBBIA_BEHIND）。
enum NebbiaBehind: String, CaseIterable {
    case night
    case aquarium
    case backdrop

    var displayName: String {
        switch self {
        case .night: return "雨夜街景"
        case .aquarium: return "梦海流萤"
        case .backdrop: return "背景"
        }
    }
}

/// 前面雾玻璃上的水（NEBBIA_GLASS）。
enum NebbiaGlass: String, CaseIterable {
    case rain
    case dew
    case snow

    var displayName: String {
        switch self {
        case .rain: return "雨窗"
        case .dew: return "凝露"
        case .snow: return "融雪"
        }
    }
}

// MARK: - 参数快照

/// 一次读全的参数快照（渲染器逐帧消费的形状）。
/// 字段缺省 = 网页 DEFAULT_NEBBIA_TUNING 逐字抄录。
struct NebbiaTuningValues: Equatable {
    var renderScale: String = "global"       // 网页 render.scale
    var renderAntialias: String = "global"   // 网页 render.antialias
    var appear: [NebbiaAppearStyle] = [.write, .fade]
    var fade: [NebbiaFadeStyle] = [.fog]
    var layouts: [NebbiaLayout] = NebbiaLayout.allCases
    var behind: NebbiaBehind = .night
    var glass: NebbiaGlass = .rain
    var scenery: [NebbiaSceneryPart] = NebbiaSceneryPart.allCases
    var rain: NebbiaRainMode = .slant
    var credits: Bool = true
    var jitter: Double = 0.6
    var warp: Double = 0.6
    var mist: Double = 0.75
    var hold: Double = 1.2
    var refog: Double = 4
    var strokeWidth: Double = 0.09
    var writeSpeed: Double = 1
    var doodle: Double = 0.3
    var busSpeed: Double = 1
    var neon: Double = 1
    var spot: Double = 0.5
    var spotX: Double = 0.8
    var rainHit: Double = 1
    var rainBig: Double = 1
    var bump: Double = 1
    var jellies: Double = 16
    var jellySize: Double = 1
    var bubbles: Double = 0.6
    var dew: Double = 1
    var dewSize: Double = 1
    var dewGlint: Double = 1
    var snow: Double = 1
    var snowSize: Double = 1
    var snowMelt: Double = 1

    static let defaults = NebbiaTuningValues()
}

// MARK: - 存储门面

/// 雾笺调参存储门面：网页 tuning.ts 每个参数一个属性。
enum NebbiaTuningStore {

    private static let prefix = "folia.tuning.nebbia."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

    // MARK: 基础读写（数值钳制 = 网页 numberWithin + NEBBIA_LIMITS）

    private static func doubleValue(_ name: String, fallback: Double,
                                    range: ClosedRange<Double>) -> Double {
        guard let raw = defaults.object(forKey: key(name)) as? NSNumber else {
            return fallback
        }
        return min(range.upperBound, max(range.lowerBound, raw.doubleValue))
    }

    private static func setDouble(_ name: String, _ value: Double,
                                  range: ClosedRange<Double>) {
        defaults.set(min(range.upperBound, max(range.lowerBound, value)),
                     forKey: key(name))
        invalidateCache()
    }

    private static func boolValue(_ name: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    /// 枚举单选：不认识的存值回缺省（网页 find ?? base 同义）。
    private static func enumValue<T: RawRepresentable>(
        _ name: String, fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key(name))
            .flatMap { T(rawValue: $0) } ?? fallback
    }

    private static func setEnum<T: RawRepresentable>(
        _ name: String, _ value: T) where T.RawValue == String {
        defaults.set(value.rawValue, forKey: key(name))
        invalidateCache()
    }

    /// 开关组：以逗号串存 rawValue 集合。读时按 CaseIterable
    /// 固定顺序过滤（网页 subsetOf）；从未存过 → fallback；
    /// 存过但过滤后为空 → allowEmpty 时为空组（scenery），
    /// 否则回 fallback（appear/fade/layouts 至少留一项）。
    private static func groupValue<T: RawRepresentable & CaseIterable>(
        _ name: String, fallback: [T], allowEmpty: Bool) -> [T]
        where T.RawValue == String, T.AllCases: Collection {
        guard let raw = defaults.object(forKey: key(name)) as? String else {
            return fallback
        }
        let stored = Set(raw.split(separator: ",").map(String.init))
        let picked = T.allCases.filter { stored.contains($0.rawValue) }
        if picked.isEmpty && !allowEmpty { return fallback }
        return picked
    }

    private static func setGroup<T: RawRepresentable & CaseIterable & Equatable>(
        _ name: String, _ value: [T], fallback: [T], allowEmpty: Bool)
        where T.RawValue == String, T.AllCases: Collection {
        let ordered = T.allCases.filter { value.contains($0) }
        let final = ordered.isEmpty && !allowEmpty ? fallback : ordered
        defaults.set(final.map { $0.rawValue }.joined(separator: ","),
                     forKey: key(name))
        invalidateCache()
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
            invalidateCache()
        }
    }

    /// 取值集："global" / "auto" / "on" / "off"。网页雾笺面板
    /// 不出抗锯齿行（全屏着色器无 MSAA），存储位保留对齐。
    static var renderAntialias: String {
        get {
            let raw = defaults.string(forKey: key("renderAntialias")) ?? "global"
            return ["global", "auto", "on", "off"].contains(raw) ? raw : "global"
        }
        set {
            defaults.set(["global", "auto", "on", "off"].contains(newValue)
                ? newValue : "global", forKey: key("renderAntialias"))
            invalidateCache()
        }
    }

    /// render 倍率的数值落点："global" → nil（跟随全局挡位；
    /// 原生渲染面以钳制上限为准，nil = 不额外缩放，见渲染器）。
    static var renderScaleValue: Double? {
        let raw = renderScale
        return raw == "global" ? nil : Double(raw)
    }

    // MARK: 开关组与枚举

    /// 出现方式（至少一种），缺省 [write, fade]。
    static var appear: [NebbiaAppearStyle] {
        get { groupValue("appear", fallback: [.write, .fade], allowEmpty: false) }
        set { setGroup("appear", newValue, fallback: [.write, .fade], allowEmpty: false) }
    }

    /// 消失方式（至少一种），缺省 [fog]。
    static var fade: [NebbiaFadeStyle] {
        get { groupValue("fade", fallback: [.fog], allowEmpty: false) }
        set { setGroup("fade", newValue, fallback: [.fog], allowEmpty: false) }
    }

    /// 构图（至少一种），缺省全开。
    static var layouts: [NebbiaLayout] {
        get { groupValue("layouts", fallback: NebbiaLayout.allCases, allowEmpty: false) }
        set { setGroup("layouts", newValue, fallback: NebbiaLayout.allCases, allowEmpty: false) }
    }

    /// 窗外，缺省 night。
    static var behind: NebbiaBehind {
        get { enumValue("behind", fallback: .night) }
        set { setEnum("behind", newValue) }
    }

    /// 玻璃，缺省 rain（没存过玻璃的旧 tuning 在网页按窗外
    /// 搭配 NEBBIA_GLASS_FOR 推导；原生无旧存档来源，恒 rain
    /// 缺省，与 night 的默认搭配一致）。
    static var glass: NebbiaGlass {
        get { enumValue("glass", fallback: .rain) }
        set { setEnum("glass", newValue) }
    }

    /// 窗外画哪几样（可以全关），缺省全开。
    static var scenery: [NebbiaSceneryPart] {
        get { groupValue("scenery", fallback: NebbiaSceneryPart.allCases, allowEmpty: true) }
        set { setGroup("scenery", newValue, fallback: NebbiaSceneryPart.allCases, allowEmpty: true) }
    }

    /// 窗外的雨，缺省 slant。
    static var rain: NebbiaRainMode {
        get { enumValue("rain", fallback: .slant) }
        set { setEnum("rain", newValue) }
    }

    /// 片尾写曲名和歌手，缺省 true。
    static var credits: Bool {
        get { boolValue("credits", fallback: true) }
        set { defaults.set(newValue, forKey: key("credits")); invalidateCache() }
    }

    // MARK: 数值项（范围 = NEBBIA_LIMITS，缺省 = DEFAULT_NEBBIA_TUNING）

    /// 手写歪斜 [0, 1.5]，缺省 0.6。
    static var jitter: Double {
        get { doubleValue("jitter", fallback: 0.6, range: 0...1.5) }
        set { setDouble("jitter", newValue, range: 0...1.5) }
    }

    /// 手写变形 [0, 1.5]，缺省 0.6。
    static var warp: Double {
        get { doubleValue("warp", fallback: 0.6, range: 0...1.5) }
        set { setDouble("warp", newValue, range: 0...1.5) }
    }

    /// 雾气浓度 [0.2, 1]，缺省 0.75。
    static var mist: Double {
        get { doubleValue("mist", fallback: 0.75, range: 0.2...1) }
        set { setDouble("mist", newValue, range: 0.2...1) }
    }

    /// 下一句开始后保持秒数 [0, 6]，缺省 1.2。
    static var hold: Double {
        get { doubleValue("hold", fallback: 1.2, range: 0...6) }
        set { setDouble("hold", newValue, range: 0...6) }
    }

    /// 重新起雾秒数 [0.5, 12]，缺省 4。
    static var refog: Double {
        get { doubleValue("refog", fallback: 4, range: 0.5...12) }
        set { setDouble("refog", newValue, range: 0.5...12) }
    }

    /// 笔画粗细（× 字号）[0.04, 0.16]，缺省 0.09。
    static var strokeWidth: Double {
        get { doubleValue("strokeWidth", fallback: 0.09, range: 0.04...0.16) }
        set { setDouble("strokeWidth", newValue, range: 0.04...0.16) }
    }

    /// 书写速度 [0.4, 2.5]，缺省 1。
    static var writeSpeed: Double {
        get { doubleValue("writeSpeed", fallback: 1, range: 0.4...2.5) }
        set { setDouble("writeSpeed", newValue, range: 0.4...2.5) }
    }

    /// 句尾画图标概率 [0, 1]，缺省 0.3。
    static var doodle: Double {
        get { doubleValue("doodle", fallback: 0.3, range: 0...1) }
        set { setDouble("doodle", newValue, range: 0...1) }
    }

    /// 车速 [0, 3]，缺省 1。
    static var busSpeed: Double {
        get { doubleValue("busSpeed", fallback: 1, range: 0...3) }
        set { setDouble("busSpeed", newValue, range: 0...3) }
    }

    /// 主题色霓虹亮度 [0, 2]，缺省 1。
    static var neon: Double {
        get { doubleValue("neon", fallback: 1, range: 0...2) }
        set { setDouble("neon", newValue, range: 0...2) }
    }

    /// 聚光灯强度 [0, 2]，缺省 0.5。
    static var spot: Double {
        get { doubleValue("spot", fallback: 0.5, range: 0...2) }
        set { setDouble("spot", newValue, range: 0...2) }
    }

    /// 聚光灯横向位置（× 屏宽）[0, 1]，缺省 0.8。
    static var spotX: Double {
        get { doubleValue("spotX", fallback: 0.8, range: 0...1) }
        set { setDouble("spotX", newValue, range: 0...1) }
    }

    /// 雨点打玻璃密度 [0, 3]，缺省 1。
    static var rainHit: Double {
        get { doubleValue("rainHit", fallback: 1, range: 0...3) }
        set { setDouble("rainHit", newValue, range: 0...3) }
    }

    /// 吐字大雨点大小 [0, 2]，缺省 1。
    static var rainBig: Double {
        get { doubleValue("rainBig", fallback: 1, range: 0...2) }
        set { setDouble("rainBig", newValue, range: 0...2) }
    }

    /// 颠簸强度 [0, 2.5]，缺省 1。
    static var bump: Double {
        get { doubleValue("bump", fallback: 1, range: 0...2.5) }
        set { setDouble("bump", newValue, range: 0...2.5) }
    }

    /// 水母数量 [0, 24]（NEBBIA_MAX_JELLIES），缺省 16。
    static var jellies: Double {
        get { doubleValue("jellies", fallback: 16, range: 0...24) }
        set { setDouble("jellies", newValue, range: 0...24) }
    }

    /// 水母大小 [0.5, 1.8]，缺省 1。
    static var jellySize: Double {
        get { doubleValue("jellySize", fallback: 1, range: 0.5...1.8) }
        set { setDouble("jellySize", newValue, range: 0.5...1.8) }
    }

    /// 气泡多少 [0, 1]，缺省 0.6。
    static var bubbles: Double {
        get { doubleValue("bubbles", fallback: 0.6, range: 0...1) }
        set { setDouble("bubbles", newValue, range: 0...1) }
    }

    /// 冷凝水珠多少 [0, 1.5]，缺省 1。
    static var dew: Double {
        get { doubleValue("dew", fallback: 1, range: 0...1.5) }
        set { setDouble("dew", newValue, range: 0...1.5) }
    }

    /// 冷凝水珠大小 [0.5, 2]，缺省 1。
    static var dewSize: Double {
        get { doubleValue("dewSize", fallback: 1, range: 0.5...2) }
        set { setDouble("dewSize", newValue, range: 0.5...2) }
    }

    /// 冷凝水珠高光 [0, 2]，缺省 1。
    static var dewGlint: Double {
        get { doubleValue("dewGlint", fallback: 1, range: 0...2) }
        set { setDouble("dewGlint", newValue, range: 0...2) }
    }

    /// 雪多少 [0, 3]，缺省 1。
    static var snow: Double {
        get { doubleValue("snow", fallback: 1, range: 0...3) }
        set { setDouble("snow", newValue, range: 0...3) }
    }

    /// 雪花大小 [0.5, 2]，缺省 1。
    static var snowSize: Double {
        get { doubleValue("snowSize", fallback: 1, range: 0.5...2) }
        set { setDouble("snowSize", newValue, range: 0.5...2) }
    }

    /// 雪化速度 [0.25, 3]，缺省 1。
    static var snowMelt: Double {
        get { doubleValue("snowMelt", fallback: 1, range: 0.25...3) }
        set { setDouble("snowMelt", newValue, range: 0.25...3) }
    }

    // MARK: 全量读写

    /// 一次读全（每属性各自钳制/回缺省，与网页 normalize 同义）。
    static func values() -> NebbiaTuningValues {
        NebbiaTuningValues(
            renderScale: renderScale,
            renderAntialias: renderAntialias,
            appear: appear,
            fade: fade,
            layouts: layouts,
            behind: behind,
            glass: glass,
            scenery: scenery,
            rain: rain,
            credits: credits,
            jitter: jitter,
            warp: warp,
            mist: mist,
            hold: hold,
            refog: refog,
            strokeWidth: strokeWidth,
            writeSpeed: writeSpeed,
            doodle: doodle,
            busSpeed: busSpeed,
            neon: neon,
            spot: spot,
            spotX: spotX,
            rainHit: rainHit,
            rainBig: rainBig,
            bump: bump,
            jellies: jellies,
            jellySize: jellySize,
            bubbles: bubbles,
            dew: dew,
            dewSize: dewSize,
            dewGlint: dewGlint,
            snow: snow,
            snowSize: snowSize,
            snowMelt: snowMelt)
    }

    /// 写回全量（逐项经属性钳制）。
    static func apply(_ values: NebbiaTuningValues) {
        renderScale = values.renderScale
        renderAntialias = values.renderAntialias
        appear = values.appear
        fade = values.fade
        layouts = values.layouts
        behind = values.behind
        glass = values.glass
        scenery = values.scenery
        rain = values.rain
        credits = values.credits
        jitter = values.jitter
        warp = values.warp
        mist = values.mist
        hold = values.hold
        refog = values.refog
        strokeWidth = values.strokeWidth
        writeSpeed = values.writeSpeed
        doodle = values.doodle
        busSpeed = values.busSpeed
        neon = values.neon
        spot = values.spot
        spotX = values.spotX
        rainHit = values.rainHit
        rainBig = values.rainBig
        bump = values.bump
        jellies = values.jellies
        jellySize = values.jellySize
        bubbles = values.bubbles
        dew = values.dew
        dewSize = values.dewSize
        dewGlint = values.dewGlint
        snow = values.snow
        snowSize = values.snowSize
        snowMelt = values.snowMelt
        invalidateCache()
    }

    /// 恢复网页缺省（网页面板重置同义）。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 PendoloTuningStore 先例）

    private static var cachedValues: NebbiaTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> NebbiaTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }

    private static func invalidateCache() {
        cachedValues = nil
        cachedAt = -1
    }
}

/// 雾笺调参面板入口（协调者接线点名形状）。
enum NebbiaTuning {
    static func makePanel() -> UIViewController {
        NebbiaTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 雾笺调参面板：网页 NebbiaSettingsPanel.tsx 的原生承接。
/// 分组与控件逐项对应网页（窗外组含窗外三选/水族箱三滑块/
/// 窗外五开关/窗外雨三选；雾上写字组八滑块+片尾开关；出现/
/// 消失/构图三组开关——组内最后一项关不掉，与网页 disabled
/// 同义；车窗与街景组五滑块，水族箱时颠簸行隐藏、网页同
/// 逻辑；玻璃组三选+按玻璃类型切换的三组滑块；渲染组只有
/// 分辨率倍率，网页雾笺不出抗锯齿行）。拨动即写
/// NebbiaTuningStore，渲染器经 0.25s 缓存至多 0.25s 后生效。
/// 系统风格：systemBackground / label 语义色自动适配深色，
/// 字号下限 12pt。
final class NebbiaTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

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
        let afterWrite: (() -> Void)?
    }

    private var sliderRows: [SliderRowRefs] = []
    private var switchRows: [SwitchRowRefs] = []
    private var behindSegment: UISegmentedControl?
    private var glassSegment: UISegmentedControl?
    private var rainSegment: UISegmentedControl?
    private var renderScaleSegment: UISegmentedControl?
    private var aquaRows: [UIView] = []
    private var glassRainRows: [UIView] = []
    private var glassDewRows: [UIView] = []
    private var glassSnowRows: [UIView] = []
    private var bumpRow: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "雾笺参数"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
    }

    // MARK: 格式化（网页 panelRows 的 percent/times 与本面板 seconds/count）

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
    private static func formatTimes(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }
    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }
    private static func formatCount(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    // MARK: 搭建

    private func buildViews() {
        // (61) WC：歌词对比保护说明行（全样式统一文案）。
        stack.addArrangedSubview(LyricContrastProtectionNote.makeLabel())
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

        // 恢复默认（网页重置钮同义）。
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resetButton.backgroundColor = .secondarySystemBackground
        resetButton.layer.cornerRadius = 8
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        resetButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(resetButton)

        // —— 窗外组（网页 SCENERY_GROUP + 窗外三选行） ——
        addSection("窗外")
        let behind = UISegmentedControl(
            items: NebbiaBehind.allCases.map { $0.displayName })
        behind.addTarget(self, action: #selector(behindChanged), for: .valueChanged)
        behindSegment = behind
        stack.addArrangedSubview(makeRow(title: "窗外", control: behind))
        aquaRows.append(addSlider(title: "水母数量",
                  min: 0, max: 24, step: 1, format: Self.formatCount,
                  read: { NebbiaTuningStore.jellies },
                  write: { NebbiaTuningStore.jellies = $0 }))
        aquaRows.append(addSlider(title: "水母大小",
                  min: 0.5, max: 1.8, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.jellySize },
                  write: { NebbiaTuningStore.jellySize = $0 }))
        aquaRows.append(addSlider(title: "气泡多少",
                  min: 0, max: 1, step: 0.05, format: Self.formatPercent,
                  read: { NebbiaTuningStore.bubbles },
                  write: { NebbiaTuningStore.bubbles = $0 }))
        for part in NebbiaSceneryPart.allCases {
            // 窗外五开关可全关（网页 scenery 同义）。
            addSwitch(title: part.displayName,
                      read: { NebbiaTuningStore.scenery.contains(part) },
                      write: { on in
                          var next = NebbiaTuningStore.scenery
                          if on { if !next.contains(part) { next.append(part) } }
                          else { next.removeAll { $0 == part } }
                          NebbiaTuningStore.scenery = next
                      })
        }
        let rain = UISegmentedControl(
            items: NebbiaRainMode.allCases.map { $0.displayName })
        rain.addTarget(self, action: #selector(rainChanged), for: .valueChanged)
        rainSegment = rain
        stack.addArrangedSubview(makeRow(title: "窗外的雨", control: rain))

        // —— 雾上写字组（网页 WRITING_GROUP） ——
        addSection("雾上写字")
        addSlider(title: "笔画粗细",
                  min: 0.04, max: 0.16, step: 0.005, format: Self.formatPercent,
                  read: { NebbiaTuningStore.strokeWidth },
                  write: { NebbiaTuningStore.strokeWidth = $0 })
        addSlider(title: "书写速度",
                  min: 0.4, max: 2.5, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.writeSpeed },
                  write: { NebbiaTuningStore.writeSpeed = $0 })
        addSlider(title: "手写歪斜",
                  min: 0, max: 1.5, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.jitter },
                  write: { NebbiaTuningStore.jitter = $0 })
        addSlider(title: "手写变形",
                  min: 0, max: 1.5, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.warp },
                  write: { NebbiaTuningStore.warp = $0 })
        addSlider(title: "句尾画图标",
                  min: 0, max: 1, step: 0.05, format: Self.formatPercent,
                  read: { NebbiaTuningStore.doodle },
                  write: { NebbiaTuningStore.doodle = $0 })
        addSlider(title: "雾气浓度",
                  min: 0.2, max: 1, step: 0.01, format: Self.formatPercent,
                  read: { NebbiaTuningStore.mist },
                  write: { NebbiaTuningStore.mist = $0 })
        addSlider(title: "下一句开始后保持",
                  min: 0, max: 6, step: 0.1, format: Self.formatSeconds,
                  read: { NebbiaTuningStore.hold },
                  write: { NebbiaTuningStore.hold = $0 })
        addSlider(title: "重新起雾用时",
                  min: 0.5, max: 12, step: 0.5, format: Self.formatSeconds,
                  read: { NebbiaTuningStore.refog },
                  write: { NebbiaTuningStore.refog = $0 })
        addSwitch(title: "片尾写曲名和歌手",
                  read: { NebbiaTuningStore.credits },
                  write: { NebbiaTuningStore.credits = $0 })

        // —— 出现组 ——
        addSection("出现")
        for style in NebbiaAppearStyle.allCases {
            addSwitch(title: style.displayName,
                      read: { NebbiaTuningStore.appear.contains(style) },
                      write: { [weak self] on in
                          self?.toggleGroupItem(
                              current: NebbiaTuningStore.appear, item: style, on: on,
                              write: { NebbiaTuningStore.appear = $0 })
                      })
        }

        // —— 消失组 ——
        addSection("消失")
        for style in NebbiaFadeStyle.allCases {
            addSwitch(title: style.displayName,
                      read: { NebbiaTuningStore.fade.contains(style) },
                      write: { [weak self] on in
                          self?.toggleGroupItem(
                              current: NebbiaTuningStore.fade, item: style, on: on,
                              write: { NebbiaTuningStore.fade = $0 })
                      })
        }

        // —— 构图组 ——
        addSection("构图")
        for layout in NebbiaLayout.allCases {
            addSwitch(title: layout.displayName,
                      read: { NebbiaTuningStore.layouts.contains(layout) },
                      write: { [weak self] on in
                          self?.toggleGroupItem(
                              current: NebbiaTuningStore.layouts, item: layout, on: on,
                              write: { NebbiaTuningStore.layouts = $0 })
                      })
        }

        // —— 车窗与街景组（网页 WINDOW_GROUP） ——
        addSection("车窗与街景")
        addSlider(title: "车速",
                  min: 0, max: 3, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.busSpeed },
                  write: { NebbiaTuningStore.busSpeed = $0 })
        addSlider(title: "霓虹",
                  min: 0, max: 2, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.neon },
                  write: { NebbiaTuningStore.neon = $0 })
        bumpRow = addSlider(title: "颠簸",
                  min: 0, max: 2.5, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.bump },
                  write: { NebbiaTuningStore.bump = $0 })
        addSlider(title: "聚光灯",
                  min: 0, max: 2, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.spot },
                  write: { NebbiaTuningStore.spot = $0 })
        addSlider(title: "聚光灯位置",
                  min: 0, max: 1, step: 0.01, format: Self.formatPercent,
                  read: { NebbiaTuningStore.spotX },
                  write: { NebbiaTuningStore.spotX = $0 })

        // —— 玻璃组（网页 GLASS_GROUP） ——
        addSection("前面的玻璃")
        let glass = UISegmentedControl(
            items: NebbiaGlass.allCases.map { $0.displayName })
        glass.addTarget(self, action: #selector(glassChanged), for: .valueChanged)
        glassSegment = glass
        stack.addArrangedSubview(makeRow(title: "玻璃上的水", control: glass))
        glassRainRows.append(addSlider(title: "雨点打在玻璃上",
                  min: 0, max: 3, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.rainHit },
                  write: { NebbiaTuningStore.rainHit = $0 }))
        glassRainRows.append(addSlider(title: "吐字时的大雨点",
                  min: 0, max: 2, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.rainBig },
                  write: { NebbiaTuningStore.rainBig = $0 }))
        glassDewRows.append(addSlider(title: "冷凝水珠多少",
                  min: 0, max: 1.5, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.dew },
                  write: { NebbiaTuningStore.dew = $0 }))
        glassDewRows.append(addSlider(title: "冷凝水珠大小",
                  min: 0.5, max: 2, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.dewSize },
                  write: { NebbiaTuningStore.dewSize = $0 }))
        glassDewRows.append(addSlider(title: "冷凝水珠高光",
                  min: 0, max: 2, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.dewGlint },
                  write: { NebbiaTuningStore.dewGlint = $0 }))
        glassSnowRows.append(addSlider(title: "雪多少",
                  min: 0, max: 3, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.snow },
                  write: { NebbiaTuningStore.snow = $0 }))
        glassSnowRows.append(addSlider(title: "雪花大小",
                  min: 0.5, max: 2, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.snowSize },
                  write: { NebbiaTuningStore.snowSize = $0 }))
        glassSnowRows.append(addSlider(title: "雪化得多快",
                  min: 0.25, max: 3, step: 0.05, format: Self.formatTimes,
                  read: { NebbiaTuningStore.snowMelt },
                  write: { NebbiaTuningStore.snowMelt = $0 }))

        // —— 渲染组（网页 RENDER_GROUP：只有倍率一行） ——
        addSection("渲染")
        let scaleOptions = ["global", "0.5", "0.75", "1", "1.5", "2"]
        let scaleSegment = UISegmentedControl(items: scaleOptions.map {
            $0 == "global" ? "跟随全局" : "\($0)×"
        })
        scaleSegment.addTarget(self, action: #selector(renderScaleChanged), for: .valueChanged)
        renderScaleSegment = scaleSegment
        stack.addArrangedSubview(makeRow(title: "分辨率倍率", control: scaleSegment))

        let note = UILabel()
        note.text = "说明：舞台内右下小控件可直接切换窗外与玻璃（对应命令面板「雾笺：切换窗外」「雾笺：切换玻璃」）。原生呈现为离屏烘焙场景＋雾层＋逐字擦出，不逐帧全屏重绘；笔顺数据原生侧无数据源，书写按逐字渐进擦出近似（见渲染器文件头）。"
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

    @discardableResult
    private func addSwitch(title: String,
                           read: @escaping () -> Bool,
                           write: @escaping (Bool) -> Void,
                           afterWrite: (() -> Void)? = nil) -> UIView {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        switchRows.append(SwitchRowRefs(
            toggle: toggle, read: read, write: write, afterWrite: afterWrite))
        toggle.tag = switchRows.count - 1
        let row = makeRow(title: title, control: toggle)
        stack.addArrangedSubview(row)
        return row
    }

    @discardableResult
    private func addSlider(title: String,
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
            valueLabel.widthAnchor.constraint(equalToConstant: 56),
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

    /// 开关组拨动：关掉最后一项时不写入并回弹开关（网页
    /// 该项 disabled 的等价行为）。
    private func toggleGroupItem<T: Equatable>(current: [T], item: T, on: Bool,
                                               write: ([T]) -> Void) {
        var next = current
        if on { if !next.contains(item) { next.append(item) } }
        else { next.removeAll { $0 == item } }
        if next.isEmpty {
            refreshSwitches()
            return
        }
        write(next)
    }

    // MARK: 回显与动作

    private func refreshFromStore() {
        refreshSliders()
        refreshSwitches()
        if let index = NebbiaBehind.allCases.firstIndex(of: NebbiaTuningStore.behind) {
            behindSegment?.selectedSegmentIndex = index
        }
        if let index = NebbiaGlass.allCases.firstIndex(of: NebbiaTuningStore.glass) {
            glassSegment?.selectedSegmentIndex = index
        }
        if let index = NebbiaRainMode.allCases.firstIndex(of: NebbiaTuningStore.rain) {
            rainSegment?.selectedSegmentIndex = index
        }
        let scaleOptions = ["global", "0.5", "0.75", "1", "1.5", "2"]
        if let index = scaleOptions.firstIndex(of: NebbiaTuningStore.renderScale) {
            renderScaleSegment?.selectedSegmentIndex = index
        }
        refreshContextRows()
    }

    private func refreshSliders() {
        for row in sliderRows {
            let value = row.read()
            row.slider.value = Float(value)
            row.valueLabel.text = row.format(value)
        }
    }

    private func refreshSwitches() {
        for row in switchRows { row.toggle.isOn = row.read() }
    }

    /// 上下文行显隐：水族箱三滑块只在 behind=aquarium 时显
    /// （且颠簸行藏，网页 NOT_IN_AQUARIUM 同义）；玻璃三组
    /// 滑块按当前玻璃类型只显一组。
    private func refreshContextRows() {
        let aquarium = NebbiaTuningStore.behind == .aquarium
        for row in aquaRows { row.isHidden = !aquarium }
        bumpRow?.isHidden = aquarium
        let glass = NebbiaTuningStore.glass
        for row in glassRainRows { row.isHidden = glass != .rain }
        for row in glassDewRows { row.isHidden = glass != .dew }
        for row in glassSnowRows { row.isHidden = glass != .snow }
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        guard switchRows.indices.contains(toggle.tag) else { return }
        let row = switchRows[toggle.tag]
        row.write(toggle.isOn)
        row.afterWrite?()
        // 组开关可能被 toggleGroupItem 拒绝（关最后一项）：回显为准。
        refreshSwitches()
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard sliderRows.indices.contains(slider.tag) else { return }
        let row = sliderRows[slider.tag]
        let raw = Double(slider.value)
        let stepped = (raw / row.step).rounded() * row.step
        row.write(stepped)
        row.valueLabel.text = row.format(row.read())
    }

    @objc private func behindChanged() {
        guard let segment = behindSegment,
              NebbiaBehind.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        NebbiaTuningStore.behind = NebbiaBehind.allCases[segment.selectedSegmentIndex]
        refreshContextRows()
    }

    @objc private func glassChanged() {
        guard let segment = glassSegment,
              NebbiaGlass.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        NebbiaTuningStore.glass = NebbiaGlass.allCases[segment.selectedSegmentIndex]
        refreshContextRows()
    }

    @objc private func rainChanged() {
        guard let segment = rainSegment,
              NebbiaRainMode.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        NebbiaTuningStore.rain = NebbiaRainMode.allCases[segment.selectedSegmentIndex]
    }

    @objc private func renderScaleChanged() {
        guard let segment = renderScaleSegment else { return }
        let options = ["global", "0.5", "0.75", "1", "1.5", "2"]
        guard options.indices.contains(segment.selectedSegmentIndex) else { return }
        NebbiaTuningStore.renderScale = options[segment.selectedSegmentIndex]
    }

    @objc private func resetTapped() {
        NebbiaTuningStore.resetAll()
        refreshFromStore()
    }
}
