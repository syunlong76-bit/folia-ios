import UIKit

// 凝彩 tempera 调参存储 + 面板（3.7 (57) 工作流 B4）：
// 对应网页版 folia-major/src/components/visualizer/tempera/tuning.ts
// 与 src/types.ts 的 TemperaTuning / DEFAULT_TEMPERA_TUNING。
// - 每参数一个属性，UserDefaults 键前缀 "folia.tuning.tempera."，
//   缺省逐字对齐 DEFAULT_TEMPERA_TUNING，数值按 tuning.ts 的
//   resolve() 钳制区间（numberWithin）落盘/读回双钳。
// - render（LyricRenderOverride）拆为 renderScale /
//   renderAntialias 两个字符串属性（缺省均为 "global"，与网页
//   { scale: 'global', antialias: 'global' } 等价）；原生暂无
//   全局渲染挡位消费方，存而待接（见渲染器头注未移植项）。
// - layerImages（用户图片池 placement 数组）在原生无图片源
//   （协议无图片下发、宿主无 IndexedDB 等价物），只存计数与
//   JSON 原文占位（layerImagesJSON，缺省 "[]"），渲染器不消费；
//   layerImageDepth / layerImageFrequency 照常存储待图片链补齐。
// - 渲染器逐帧读走 snapshotCached(now:) 的 0.25s 缓存
//   （照 StageEffectSettings 先例），面板拨动至多 0.25s 生效。

/// 凝彩色彩模式（网页 TemperaColorMode）。
enum TemperaColorMode: String, CaseIterable {
    case duo
    case mono
    case gradient
}

/// 一帧渲染所需的全部凝彩参数快照（值类型，渲染器缓存消费）。
struct TemperaTuningValues: Equatable {
    var renderScale: String = "global"
    var renderAntialias: String = "global"
    var cameraIntensity: Double = 1
    var glyphMotion: Double = 1
    var wholeLineLyrics: Bool = false
    var glyphSettleStretch: Double = 0.5
    var depthOfField: Double = 1
    var depthPan: Double = 1
    var glyphDepth: Double = 1
    var colorMode: TemperaColorMode = .duo
    var textInversion: Bool = true
    var layerImagesJSON: String = "[]"
    var layerImageDepth: String = "back"
    var layerImageFrequency: Double = 0.6
    var showBlocks: Bool = true
    var showDecor: Bool = true
    var showCornerMarks: Bool = true
    var enableTransitions: Bool = true
    var textureResolution: Double = 1.5
    var postProcessEnabled: Bool = true
    var postProcessTextureCompression: Bool = false
    var postProcessGrain: Double = 0.2
    var postProcessContrast: Double = 0
    var postProcessRgbShift: Double = 0
    var postProcessVignette: Double = 0.85
    var postProcessLensDistortion: Double = 0.3
}

enum TemperaTuningStore {

    static let keyPrefix = "folia.tuning.tempera."

    private static func key(_ name: String) -> String { keyPrefix + name }

    private static func numberWithin(_ name: String, fallback: Double,
                                     min lo: Double, max hi: Double) -> Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key(name)) != nil else { return fallback }
        let raw = defaults.double(forKey: key(name))
        return min(max(raw, lo), hi)
    }

    private static func setNumber(_ name: String, _ value: Double,
                                  min lo: Double, max hi: Double) {
        UserDefaults.standard.set(min(max(value, lo), hi), forKey: key(name))
        invalidateCache()
    }

    private static func boolValue(_ name: String, fallback: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key(name)) != nil else { return fallback }
        return defaults.bool(forKey: key(name))
    }

    private static func setBool(_ name: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key(name))
        invalidateCache()
    }

    private static func stringValue(_ name: String, fallback: String) -> String {
        UserDefaults.standard.string(forKey: key(name)) ?? fallback
    }

    private static func setString(_ name: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key(name))
        invalidateCache()
    }

    // MARK: render 覆盖（网页 render: { scale, antialias }）

    static var renderScale: String {
        get { stringValue("renderScale", fallback: "global") }
        set { setString("renderScale", newValue) }
    }

    static var renderAntialias: String {
        get { stringValue("renderAntialias", fallback: "global") }
        set { setString("renderAntialias", newValue) }
    }

    // MARK: 镜头 / 字形运动

    /// 网页 cameraIntensity，0...2，缺省 1。
    static var cameraIntensity: Double {
        get { numberWithin("cameraIntensity", fallback: 1, min: 0, max: 2) }
        set { setNumber("cameraIntensity", newValue, min: 0, max: 2) }
    }

    /// 网页 glyphMotion，0...2，缺省 1。
    static var glyphMotion: Double {
        get { numberWithin("glyphMotion", fallback: 1, min: 0, max: 2) }
        set { setNumber("glyphMotion", newValue, min: 0, max: 2) }
    }

    /// 网页 wholeLineLyrics，缺省 false。
    static var wholeLineLyrics: Bool {
        get { boolValue("wholeLineLyrics", fallback: false) }
        set { setBool("wholeLineLyrics", newValue) }
    }

    /// 网页 glyphSettleStretch，0...1，缺省 0.5。
    static var glyphSettleStretch: Double {
        get { numberWithin("glyphSettleStretch", fallback: 0.5, min: 0, max: 1) }
        set { setNumber("glyphSettleStretch", newValue, min: 0, max: 1) }
    }

    // MARK: 墨染奥行景深（原生无鼓点数据源，深度量仍存储）

    /// 网页 depthOfField，0...2，缺省 1。
    static var depthOfField: Double {
        get { numberWithin("depthOfField", fallback: 1, min: 0, max: 2) }
        set { setNumber("depthOfField", newValue, min: 0, max: 2) }
    }

    /// 网页 depthPan，0...2，缺省 1。
    static var depthPan: Double {
        get { numberWithin("depthPan", fallback: 1, min: 0, max: 2) }
        set { setNumber("depthPan", newValue, min: 0, max: 2) }
    }

    /// 网页 glyphDepth，0...2，缺省 1。
    static var glyphDepth: Double {
        get { numberWithin("glyphDepth", fallback: 1, min: 0, max: 2) }
        set { setNumber("glyphDepth", newValue, min: 0, max: 2) }
    }

    // MARK: 色彩与文字

    /// 网页 colorMode（duo/mono/gradient），缺省 duo。
    static var colorMode: TemperaColorMode {
        get {
            TemperaColorMode(rawValue: stringValue("colorMode", fallback: "duo")) ?? .duo
        }
        set { setString("colorMode", newValue.rawValue) }
    }

    /// 网页 textInversion，缺省 true。
    static var textInversion: Bool {
        get { boolValue("textInversion", fallback: true) }
        set { setBool("textInversion", newValue) }
    }

    // MARK: 用户图片池（原生暂无图片源，仅存 placement 原文）

    /// 网页 layerImages 的 JSON 原文占位，缺省 "[]"。
    static var layerImagesJSON: String {
        get { stringValue("layerImagesJSON", fallback: "[]") }
        set { setString("layerImagesJSON", newValue) }
    }

    /// 图片池条数（由 JSON 顶层数组长度粗计，供面板展示）。
    static var layerImagesCount: Int {
        let raw = layerImagesJSON
        guard let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return 0 }
        return min(array.count, 16)
    }

    /// 网页 layerImageDepth（back/front），缺省 back。
    static var layerImageDepth: String {
        get {
            let raw = stringValue("layerImageDepth", fallback: "back")
            return (raw == "front" || raw == "back") ? raw : "back"
        }
        set { setString("layerImageDepth", (newValue == "front") ? "front" : "back") }
    }

    /// 网页 layerImageFrequency，0...1，缺省 0.6。
    static var layerImageFrequency: Double {
        get { numberWithin("layerImageFrequency", fallback: 0.6, min: 0, max: 1) }
        set { setNumber("layerImageFrequency", newValue, min: 0, max: 1) }
    }

    // MARK: 显示开关与转场

    /// 网页 showBlocks，缺省 true。
    static var showBlocks: Bool {
        get { boolValue("showBlocks", fallback: true) }
        set { setBool("showBlocks", newValue) }
    }

    /// 网页 showDecor，缺省 true。
    static var showDecor: Bool {
        get { boolValue("showDecor", fallback: true) }
        set { setBool("showDecor", newValue) }
    }

    /// 网页 showCornerMarks，缺省 true。
    static var showCornerMarks: Bool {
        get { boolValue("showCornerMarks", fallback: true) }
        set { setBool("showCornerMarks", newValue) }
    }

    /// 网页 enableTransitions，缺省 true。
    static var enableTransitions: Bool {
        get { boolValue("enableTransitions", fallback: true) }
        set { setBool("enableTransitions", newValue) }
    }

    /// 网页 textureResolution，0.5...4，缺省 1.5。
    static var textureResolution: Double {
        get { numberWithin("textureResolution", fallback: 1.5, min: 0.5, max: 4) }
        set { setNumber("textureResolution", newValue, min: 0.5, max: 4) }
    }

    // MARK: 后处理

    /// 网页 postProcessEnabled，缺省 true。
    static var postProcessEnabled: Bool {
        get { boolValue("postProcessEnabled", fallback: true) }
        set { setBool("postProcessEnabled", newValue) }
    }

    /// 网页 postProcessTextureCompression，缺省 false。
    static var postProcessTextureCompression: Bool {
        get { boolValue("postProcessTextureCompression", fallback: false) }
        set { setBool("postProcessTextureCompression", newValue) }
    }

    /// 网页 postProcessGrain，0...1，缺省 0.2。
    static var postProcessGrain: Double {
        get { numberWithin("postProcessGrain", fallback: 0.2, min: 0, max: 1) }
        set { setNumber("postProcessGrain", newValue, min: 0, max: 1) }
    }

    /// 网页 postProcessContrast，0...1，缺省 0。
    static var postProcessContrast: Double {
        get { numberWithin("postProcessContrast", fallback: 0, min: 0, max: 1) }
        set { setNumber("postProcessContrast", newValue, min: 0, max: 1) }
    }

    /// 网页 postProcessRgbShift，0...1，缺省 0。
    static var postProcessRgbShift: Double {
        get { numberWithin("postProcessRgbShift", fallback: 0, min: 0, max: 1) }
        set { setNumber("postProcessRgbShift", newValue, min: 0, max: 1) }
    }

    /// 网页 postProcessVignette，0...2，缺省 0.85。
    static var postProcessVignette: Double {
        get { numberWithin("postProcessVignette", fallback: 0.85, min: 0, max: 2) }
        set { setNumber("postProcessVignette", newValue, min: 0, max: 2) }
    }

    /// 网页 postProcessLensDistortion，0...2，缺省 0.3。
    static var postProcessLensDistortion: Double {
        get { numberWithin("postProcessLensDistortion", fallback: 0.3, min: 0, max: 2) }
        set { setNumber("postProcessLensDistortion", newValue, min: 0, max: 2) }
    }

    // MARK: 全量快照 + 逐帧缓存（0.25s，照 StageEffectSettings 先例）

    static func snapshot() -> TemperaTuningValues {
        TemperaTuningValues(
            renderScale: renderScale,
            renderAntialias: renderAntialias,
            cameraIntensity: cameraIntensity,
            glyphMotion: glyphMotion,
            wholeLineLyrics: wholeLineLyrics,
            glyphSettleStretch: glyphSettleStretch,
            depthOfField: depthOfField,
            depthPan: depthPan,
            glyphDepth: glyphDepth,
            colorMode: colorMode,
            textInversion: textInversion,
            layerImagesJSON: layerImagesJSON,
            layerImageDepth: layerImageDepth,
            layerImageFrequency: layerImageFrequency,
            showBlocks: showBlocks,
            showDecor: showDecor,
            showCornerMarks: showCornerMarks,
            enableTransitions: enableTransitions,
            textureResolution: textureResolution,
            postProcessEnabled: postProcessEnabled,
            postProcessTextureCompression: postProcessTextureCompression,
            postProcessGrain: postProcessGrain,
            postProcessContrast: postProcessContrast,
            postProcessRgbShift: postProcessRgbShift,
            postProcessVignette: postProcessVignette,
            postProcessLensDistortion: postProcessLensDistortion)
    }

    private static var cachedValues = TemperaTuningValues()
    private static var cachedAt: CFTimeInterval = -1

    static func snapshotCached(now: CFTimeInterval) -> TemperaTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 {
            cachedValues = snapshot()
            cachedAt = now
        }
        return cachedValues
    }

    static func invalidateCache() {
        cachedAt = -1
    }

    /// 恢复网页缺省（面板「恢复默认」用）。
    static func resetToDefaults() {
        let defaults = UserDefaults.standard
        for name in [
            "renderScale", "renderAntialias", "cameraIntensity", "glyphMotion",
            "wholeLineLyrics", "glyphSettleStretch", "depthOfField", "depthPan",
            "glyphDepth", "colorMode", "textInversion", "layerImagesJSON",
            "layerImageDepth", "layerImageFrequency", "showBlocks", "showDecor",
            "showCornerMarks", "enableTransitions", "textureResolution",
            "postProcessEnabled", "postProcessTextureCompression",
            "postProcessGrain", "postProcessContrast", "postProcessRgbShift",
            "postProcessVignette", "postProcessLensDistortion",
        ] {
            defaults.removeObject(forKey: key(name))
        }
        invalidateCache()
    }
}

// MARK: - 调参面板

enum TemperaTuning {
    static func makePanel() -> UIViewController {
        TemperaTuningPanelViewController()
    }
}

/// 凝彩调参面板：UIKit 系统风格（系统背景/标签色，深色下可读，
/// 字号下限 12pt），拨动即写 TemperaTuningStore。由协调者在
/// 设置页/样式面板接线 present；本文件只负责面板本体。
final class TemperaTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var sliderValueLabels: [Int: UILabel] = [:]
    private var sliders: [Int: UISlider] = [:]
    private var switches: [Int: UISwitch] = [:]
    private var segments: [Int: UISegmentedControl] = [:]

    // 滑块 tag → (标题, 范围, 读写)
    private struct SliderSpec {
        let title: String
        let min: Double
        let max: Double
        let read: () -> Double
        let write: (Double) -> Void
    }

    private struct SwitchSpec {
        let title: String
        let note: String?
        let read: () -> Bool
        let write: (Bool) -> Void
    }

    private lazy var sliderSpecs: [Int: SliderSpec] = [
        0: SliderSpec(title: "镜头强度", min: 0, max: 2,
                      read: { TemperaTuningStore.cameraIntensity },
                      write: { TemperaTuningStore.cameraIntensity = $0 }),
        1: SliderSpec(title: "字形动感", min: 0, max: 2,
                      read: { TemperaTuningStore.glyphMotion },
                      write: { TemperaTuningStore.glyphMotion = $0 }),
        2: SliderSpec(title: "入场拉伸", min: 0, max: 1,
                      read: { TemperaTuningStore.glyphSettleStretch },
                      write: { TemperaTuningStore.glyphSettleStretch = $0 }),
        3: SliderSpec(title: "景深（墨染奥行）", min: 0, max: 2,
                      read: { TemperaTuningStore.depthOfField },
                      write: { TemperaTuningStore.depthOfField = $0 }),
        4: SliderSpec(title: "镜头平移（墨染奥行）", min: 0, max: 2,
                      read: { TemperaTuningStore.depthPan },
                      write: { TemperaTuningStore.depthPan = $0 }),
        5: SliderSpec(title: "歌词远近（墨染奥行）", min: 0, max: 2,
                      read: { TemperaTuningStore.glyphDepth },
                      write: { TemperaTuningStore.glyphDepth = $0 }),
        6: SliderSpec(title: "图片出现频率", min: 0, max: 1,
                      read: { TemperaTuningStore.layerImageFrequency },
                      write: { TemperaTuningStore.layerImageFrequency = $0 }),
        7: SliderSpec(title: "纹理分辨率", min: 0.5, max: 4,
                      read: { TemperaTuningStore.textureResolution },
                      write: { TemperaTuningStore.textureResolution = $0 }),
        8: SliderSpec(title: "后处理 · 颗粒", min: 0, max: 1,
                      read: { TemperaTuningStore.postProcessGrain },
                      write: { TemperaTuningStore.postProcessGrain = $0 }),
        9: SliderSpec(title: "后处理 · 对比", min: 0, max: 1,
                      read: { TemperaTuningStore.postProcessContrast },
                      write: { TemperaTuningStore.postProcessContrast = $0 }),
        10: SliderSpec(title: "后处理 · 色版偏移", min: 0, max: 1,
                       read: { TemperaTuningStore.postProcessRgbShift },
                       write: { TemperaTuningStore.postProcessRgbShift = $0 }),
        11: SliderSpec(title: "后处理 · 暗角", min: 0, max: 2,
                       read: { TemperaTuningStore.postProcessVignette },
                       write: { TemperaTuningStore.postProcessVignette = $0 }),
        12: SliderSpec(title: "后处理 · 镜头畸变", min: 0, max: 2,
                       read: { TemperaTuningStore.postProcessLensDistortion },
                       write: { TemperaTuningStore.postProcessLensDistortion = $0 }),
    ]

    private lazy var switchSpecs: [Int: SwitchSpec] = [
        0: SwitchSpec(title: "整行歌词", note: "每行歌词占一个镜头，不切半句",
                      read: { TemperaTuningStore.wholeLineLyrics },
                      write: { TemperaTuningStore.wholeLineLyrics = $0 }),
        1: SwitchSpec(title: "文字反色", note: "歌词按底下色块逐像素选墨/纸色",
                      read: { TemperaTuningStore.textInversion },
                      write: { TemperaTuningStore.textInversion = $0 }),
        2: SwitchSpec(title: "色块", note: nil,
                      read: { TemperaTuningStore.showBlocks },
                      write: { TemperaTuningStore.showBlocks = $0 }),
        3: SwitchSpec(title: "装饰", note: "网点、水印大字与边角碎字",
                      read: { TemperaTuningStore.showDecor },
                      write: { TemperaTuningStore.showDecor = $0 }),
        4: SwitchSpec(title: "边角标记", note: nil,
                      read: { TemperaTuningStore.showCornerMarks },
                      write: { TemperaTuningStore.showCornerMarks = $0 }),
        5: SwitchSpec(title: "段落转场", note: nil,
                      read: { TemperaTuningStore.enableTransitions },
                      write: { TemperaTuningStore.enableTransitions = $0 }),
        6: SwitchSpec(title: "后处理", note: nil,
                      read: { TemperaTuningStore.postProcessEnabled },
                      write: { TemperaTuningStore.postProcessEnabled = $0 }),
        7: SwitchSpec(title: "后处理纹理压缩", note: "后处理降到 1× 再拉伸，省填充率",
                      read: { TemperaTuningStore.postProcessTextureCompression },
                      write: { TemperaTuningStore.postProcessTextureCompression = $0 }),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "凝彩 · 调参"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
    }

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

        stack.addArrangedSubview(sectionLabel("色彩与文字"))
        // colorMode 分段：duo / mono / gradient
        let colorSegment = UISegmentedControl(items: ["双色", "单色", "渐变"])
        colorSegment.tag = 0
        colorSegment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        segments[0] = colorSegment
        stack.addArrangedSubview(makeRow(title: "色彩模式", note: nil, control: colorSegment))
        for tag in [1] {
            let spec = switchSpecs[tag]!
            stack.addArrangedSubview(makeSwitchRow(tag: tag, spec: spec))
        }

        stack.addArrangedSubview(sectionLabel("镜头与字形"))
        for tag in [0, 1, 2] {
            stack.addArrangedSubview(makeSliderRow(tag: tag))
        }
        stack.addArrangedSubview(makeSwitchRow(tag: 0, spec: switchSpecs[0]!))

        stack.addArrangedSubview(sectionLabel("墨染奥行景深（需鼓点数据，原生暂以视差近似）"))
        for tag in [3, 4, 5] {
            stack.addArrangedSubview(makeSliderRow(tag: tag))
        }

        stack.addArrangedSubview(sectionLabel("构图显示"))
        for tag in [2, 3, 4, 5] {
            stack.addArrangedSubview(makeSwitchRow(tag: tag, spec: switchSpecs[tag]!))
        }

        stack.addArrangedSubview(sectionLabel("图片池（原生暂无图片源，仅存设置）"))
        let depthSegment = UISegmentedControl(items: ["歌词下", "歌词上"])
        depthSegment.tag = 1
        depthSegment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        segments[1] = depthSegment
        stack.addArrangedSubview(makeRow(title: "图片层次", note: nil, control: depthSegment))
        stack.addArrangedSubview(makeSliderRow(tag: 6))
        let poolNote = UILabel()
        poolNote.text = "当前图片池 \(TemperaTuningStore.layerImagesCount) 张（上限 16）。原生暂无图片导入入口，图片不会显示；频率与层次已保存，待图片链补齐后生效。"
        poolNote.font = .systemFont(ofSize: 12)
        poolNote.textColor = .secondaryLabel
        poolNote.numberOfLines = 0
        stack.addArrangedSubview(poolNote)

        stack.addArrangedSubview(sectionLabel("渲染与后处理"))
        let scaleSegment = UISegmentedControl(items: ["跟随全局", "0.5×", "0.75×", "1×", "1.5×", "2×"])
        scaleSegment.tag = 2
        scaleSegment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        segments[2] = scaleSegment
        stack.addArrangedSubview(makeRow(title: "分辨率覆盖", note: nil, control: scaleSegment))
        let aaSegment = UISegmentedControl(items: ["跟随全局", "自动", "开", "关"])
        aaSegment.tag = 3
        aaSegment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        segments[3] = aaSegment
        stack.addArrangedSubview(makeRow(title: "抗锯齿覆盖", note: nil, control: aaSegment))
        stack.addArrangedSubview(makeSliderRow(tag: 7))
        stack.addArrangedSubview(makeSwitchRow(tag: 6, spec: switchSpecs[6]!))
        stack.addArrangedSubview(makeSwitchRow(tag: 7, spec: switchSpecs[7]!))
        for tag in [8, 9, 10, 11, 12] {
            stack.addArrangedSubview(makeSliderRow(tag: tag))
        }

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(resetButton)
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }

    private func makeRow(title: String, note: String?, control: UIControl) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        var constraints: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            container.heightAnchor.constraint(equalToConstant: note == nil ? 48 : 56),
        ]
        if let note {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = .systemFont(ofSize: 12)
            noteLabel.textColor = .secondaryLabel
            noteLabel.numberOfLines = 1
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(noteLabel)
            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                noteLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            ])
        } else {
            constraints.append(titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func makeSwitchRow(tag: Int, spec: SwitchSpec) -> UIView {
        let toggle = UISwitch()
        toggle.tag = tag
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        switches[tag] = toggle
        return makeRow(title: spec.title, note: spec.note, control: toggle)
    }

    private func makeSliderRow(tag: Int) -> UIView {
        guard let spec = sliderSpecs[tag] else { return UIView() }
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = spec.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let slider = UISlider()
        slider.tag = tag
        slider.minimumValue = Float(spec.min)
        slider.maximumValue = Float(spec.max)
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        sliders[tag] = slider
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderValueLabels[tag] = valueLabel
        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 44),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func refreshFromStore() {
        for (tag, slider) in sliders {
            guard let spec = sliderSpecs[tag] else { continue }
            let value = spec.read()
            slider.value = Float(value)
            sliderValueLabels[tag]?.text = String(format: "%.2f", value)
        }
        for (tag, toggle) in switches {
            guard let spec = switchSpecs[tag] else { continue }
            toggle.isOn = spec.read()
        }
        segments[0]?.selectedSegmentIndex =
            TemperaColorMode.allCases.firstIndex(of: TemperaTuningStore.colorMode) ?? 0
        segments[1]?.selectedSegmentIndex =
            TemperaTuningStore.layerImageDepth == "front" ? 1 : 0
        let scaleValues = ["global", "0.5", "0.75", "1", "1.5", "2"]
        segments[2]?.selectedSegmentIndex =
            scaleValues.firstIndex(of: TemperaTuningStore.renderScale) ?? 0
        let aaValues = ["global", "auto", "on", "off"]
        segments[3]?.selectedSegmentIndex =
            aaValues.firstIndex(of: TemperaTuningStore.renderAntialias) ?? 0
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        guard let spec = sliderSpecs[slider.tag] else { return }
        let value = Double(slider.value)
        spec.write(value)
        sliderValueLabels[slider.tag]?.text = String(format: "%.2f", value)
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        guard let spec = switchSpecs[toggle.tag] else { return }
        spec.write(toggle.isOn)
    }

    @objc private func segmentChanged(_ segment: UISegmentedControl) {
        switch segment.tag {
        case 0:
            let modes = TemperaColorMode.allCases
            if modes.indices.contains(segment.selectedSegmentIndex) {
                TemperaTuningStore.colorMode = modes[segment.selectedSegmentIndex]
            }
        case 1:
            TemperaTuningStore.layerImageDepth =
                segment.selectedSegmentIndex == 1 ? "front" : "back"
        case 2:
            let values = ["global", "0.5", "0.75", "1", "1.5", "2"]
            if values.indices.contains(segment.selectedSegmentIndex) {
                TemperaTuningStore.renderScale = values[segment.selectedSegmentIndex]
            }
        case 3:
            let values = ["global", "auto", "on", "off"]
            if values.indices.contains(segment.selectedSegmentIndex) {
                TemperaTuningStore.renderAntialias = values[segment.selectedSegmentIndex]
            }
        default:
            break
        }
    }

    @objc private func resetTapped() {
        TemperaTuningStore.resetToDefaults()
        refreshFromStore()
    }
}
