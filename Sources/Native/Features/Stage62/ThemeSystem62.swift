import UIKit

/// 十六进制颜色互转（(62) WA：主题预设/自定义色/Lattice 叠色共用）。
enum FoliaColorHex62 {
    static func color(from hex: String) -> UIColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    static func hex(from color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// 配色主题预设（(62) §4.1）：主色/辅色/背景调三色一组。
struct ThemePreset62 {
    let id: String
    let name: String
    let accent: UIColor
    let secondary: UIColor
    let background: UIColor

    static let all: [ThemePreset62] = [
        ThemePreset62(id: "midnight", name: "午夜紫",
                      accent: UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 1),
                      secondary: UIColor(red: 0.37, green: 0.78, blue: 0.85, alpha: 1),
                      background: UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)),
        ThemePreset62(id: "ocean", name: "深海蓝",
                      accent: UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1),
                      secondary: UIColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 1),
                      background: UIColor(red: 0.05, green: 0.09, blue: 0.14, alpha: 1)),
        ThemePreset62(id: "ember", name: "余烬橙",
                      accent: UIColor(red: 0.98, green: 0.55, blue: 0.25, alpha: 1),
                      secondary: UIColor(red: 0.95, green: 0.80, blue: 0.40, alpha: 1),
                      background: UIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 1)),
        ThemePreset62(id: "forest", name: "森野绿",
                      accent: UIColor(red: 0.40, green: 0.80, blue: 0.50, alpha: 1),
                      secondary: UIColor(red: 0.75, green: 0.85, blue: 0.45, alpha: 1),
                      background: UIColor(red: 0.06, green: 0.11, blue: 0.08, alpha: 1)),
        ThemePreset62(id: "rose", name: "暮玫瑰",
                      accent: UIColor(red: 0.95, green: 0.45, blue: 0.60, alpha: 1),
                      secondary: UIColor(red: 0.85, green: 0.60, blue: 0.95, alpha: 1),
                      background: UIColor(red: 0.13, green: 0.07, blue: 0.10, alpha: 1)),
    ]

    static func preset(id: String) -> ThemePreset62 {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 主题系统（(62) §4.1 整组）：
///
/// - 生效主题解析序：优先自定义（preferCustomTheme 开且已选预设/自定义）
///   → 歌曲自动主题（autoSwitch+autoGenerate 开且有当前歌曲主题）
///   → 所选预设/自定义。currentAccent/currentBackground 为全应用
///   动态色入口：设置页强调色（Settings62ClusterA 行控件 tint）、
///   点播台主题底色（StageVC applyStageTheme62）、舞台 palette
///   accent（StageVC pushSnapshot 前覆写）三处真消费。
/// - 歌曲主题：切歌时由 StageVC/HomeWall 在封面到货后调
///   noteTrackArtwork(image:track:)——复用 StagePalette.tokens
///   （仓库既有封面主色通路）生成 PaletteTokens 存为当前歌曲主题；
///   来源=艺术家时原生无艺术家图源，诚实回退封面并落面包屑标注。
enum ThemeSystem62 {

    private(set) static var songPalette: PaletteTokens?
    private(set) static var songTrackId: String?

    static var selectedPreset: ThemePreset62 {
        if SettingsStore.themePresetId == "custom" {
            return ThemePreset62(
                id: "custom", name: "自定义",
                accent: FoliaColorHex62.color(from: SettingsStore.themeCustomAccentHex)
                    ?? ThemePreset62.all[0].accent,
                secondary: FoliaColorHex62.color(from: SettingsStore.themeCustomSecondaryHex)
                    ?? ThemePreset62.all[0].secondary,
                background: FoliaColorHex62.color(from: SettingsStore.themeCustomBackgroundHex)
                    ?? ThemePreset62.all[0].background)
        }
        return ThemePreset62.preset(id: SettingsStore.themePresetId)
    }

    /// 当前歌曲主题是否生效（自动切换+自动生成都开、且未被优先自定义压过）。
    static var songThemeActive: Bool {
        if SettingsStore.preferCustomTheme { return false }
        return SettingsStore.songThemeAutoSwitch
            && SettingsStore.songThemeAutoGenerate
            && songPalette != nil
    }

    static var currentAccent: UIColor {
        if songThemeActive, let p = songPalette { return p.accent }
        return selectedPreset.accent
    }
    static var currentSecondary: UIColor {
        if songThemeActive, let p = songPalette { return p.secondary }
        return selectedPreset.secondary
    }
    static var currentBackground: UIColor {
        if songThemeActive, let p = songPalette { return p.background }
        return selectedPreset.background
    }
    static var currentSourceLabel: String {
        if songThemeActive { return "歌曲主题（自动生成）" }
        return "预设 · \(selectedPreset.name)"
    }

    /// 切歌/封面到货钩子：按生成来源取图生成歌曲主题。
    /// source: 0 封面 / 1 专辑（原生曲目与专辑同用 artworkURL，同源）/
    /// 2 艺术家（无图源 → 回退封面，面包屑标注 fallback=cover）。
    static func noteTrackArtwork(image: UIImage?, trackId: String?) {
        guard SettingsStore.songThemeAutoGenerate else { return }
        guard let image else {
            songPalette = nil
            songTrackId = trackId
            return
        }
        let source = SettingsStore.themeSource
        songPalette = StagePalette.tokens(from: image)
        songTrackId = trackId
        Breadcrumbs.log("theme62.song generated src=\(source)"
            + (source == 2 ? " fallback=cover(no-artist-artwork)" : "")
            + " track=\(trackId ?? "nil") active=\(songThemeActive ? 1 : 0)")
        NotificationCenter.default.post(name: .foliaTheme62Changed, object: nil)
    }

    static func applyPreset(id: String) {
        SettingsStore.themePresetId = id
        Breadcrumbs.log("theme62.preset apply id=\(id)")
        NotificationCenter.default.post(name: .foliaTheme62Changed, object: nil)
        NotificationCenter.default.post(
            name: .foliaSettings62AChanged, object: nil,
            userInfo: ["key": SettingsStore.Key62A.themePresetId])
    }

    static func resetToDefault() {
        SettingsStore.themePresetId = "midnight"
        SettingsStore.preferCustomTheme = false
        songPalette = nil
        songTrackId = nil
        Breadcrumbs.log("theme62.reset default")
        NotificationCenter.default.post(name: .foliaTheme62Changed, object: nil)
    }

    /// 明暗模式 → overrideUserInterfaceStyle（SceneDelegate/根 VC 统一应用点）。
    static func interfaceStyleOverride() -> UIUserInterfaceStyle {
        switch SettingsStore.daylightMode {
        case 2: return .light
        case 1: return .dark
        default: return .unspecified
        }
    }
    static func applyInterfaceStyle(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = interfaceStyleOverride()
        Breadcrumbs.log("theme62.daylight mode=\(SettingsStore.daylightMode)")
    }
}

extension Notification.Name {
    static let foliaTheme62Changed = Notification.Name("foliaTheme62Changed")
}

/// 场景系统（(62) §4.1）：场景预设 → 舞台背景氛围层参数。
/// 消费点在 StageVC：暗角强度乘进 backdropTint alpha、氛围图
/// （backdropImageView）饱和/对比近似用 alpha 混合、对比保护基线
/// 记入面包屑（scrim 本体走 StagePalette 既有通路，此处只给基线值）。
struct SceneParams62 {
    let vignette: Double      // 暗角强度 0...1
    let atmosphereAlpha: Double // 氛围层不透明度
    let tintAlpha: Double     // 氛围 tint alpha 基线
    let contrastFloor: Double // 对比保护基线（亮度差下限参考）
    let label: String
}

enum SceneSystem62 {
    static func params() -> SceneParams62 {
        switch SettingsStore.scenePreset {
        case 1: // 影厅：强暗角、氛围压暗、对比基线高
            return SceneParams62(vignette: 0.85, atmosphereAlpha: 0.9,
                                 tintAlpha: 0.62, contrastFloor: 0.5, label: "影厅")
        case 2: // 现场：中暗角、氛围全开
            return SceneParams62(vignette: 0.55, atmosphereAlpha: 1.0,
                                 tintAlpha: 0.45, contrastFloor: 0.45, label: "现场")
        case 3: // 书房：弱暗角、氛围柔和
            return SceneParams62(vignette: 0.3, atmosphereAlpha: 0.8,
                                 tintAlpha: 0.35, contrastFloor: 0.45, label: "书房")
        default:
            return SceneParams62(vignette: 0.45, atmosphereAlpha: 1.0,
                                 tintAlpha: 0.5, contrastFloor: 0.45, label: "无")
        }
    }
}

/// 声线追踪线（(62) §4.1）：舞台右上小幅轨迹线。
/// 数据口径诚实标注：仓库无真实频谱/energy 数据源（Cadenza 头注
/// energy≡0），故本线画的是播放电平近似——播放中按 position 的
/// 平滑伪波形（确定性正弦叠加，非真实频谱），暂停时恒定基线。
/// 视图内自带图例小字「电平近似 · 非频谱」。
final class SoundTracingView62: UIView {
    private var phase: Double = 0
    private var playing = false
    private let caption = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.25)
        layer.cornerRadius = 8
        clipsToBounds = true
        caption.text = "声线 · 电平近似（非频谱）"
        caption.font = .systemFont(ofSize: 9)
        caption.textColor = UIColor.white.withAlphaComponent(0.55)
        addSubview(caption)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        caption.frame = CGRect(x: 8, y: bounds.height - 14, width: bounds.width - 16, height: 12)
    }

    func update(playing: Bool, position: TimeInterval) {
        self.playing = playing
        phase = position
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let midY = rect.height / 2 - 4
        let path = UIBezierPath()
        let steps = 48
        for i in 0...steps {
            let x = CGFloat(i) / CGFloat(steps) * rect.width
            var y = midY
            if playing {
                let t = Double(i) / Double(steps) * 6.28 + phase * 2.2
                y += CGFloat(sin(t) * 0.6 + sin(t * 2.7) * 0.4) * rect.height * 0.22
            }
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.setStrokeColor(ThemeSystem62.currentAccent.cgColor)
        path.lineWidth = 1.5
        path.stroke()
    }
}
