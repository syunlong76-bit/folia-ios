import UIKit
import QuartzCore

// LyricStage 协议（3.7 (14)，M2' 冻结面，DS R40 对账 Q2 定版）
//
// 这是原生舞台与歌词特效之间的唯一接口。冻结纪律：
//  - 本文件的冻结面（锚点模型、LyricLine、TrackMeta、PaletteTokens、
//    生命周期状态机、控制回传、styleId/styleVersion、视口）变更必须
//    走版本评审：LyricStageProtocolInfo.version 递增并在评审记录里
//    写明增删字段与受影响的已迁样式；已迁样式不得因协议变更被迫
//    返工渲染逻辑之外的部分。
//  - 只增不删：新字段一律给默认值或放进 ext 扩展字典；逐字 words 与
//    频谱 FFT 只留 capability/扩展位，本期不冻结数据形状。
//  - 语义继承自桥协议已验证的时间模型：anchor+rate 本地插值，禁止
//    逐帧跨界取时间；rate 定义域 [0, 2]，现引擎只有 0/1 两态。

/// 协议版本与全局能力声明。
enum LyricStageProtocolInfo {
    static let version = 1
    /// 宿主当前能提供的数据能力：逐行歌词有（lines），逐字无数据源
    /// （words 恒 nil）、频谱无数据源（spectrum 恒不提供）。
    static let hostCapabilities = LyricStageCapabilities(
        supportsWordSync: false,
        requiresSpectrum: false,
        supportsLineSeek: true)
}

/// 播放锚点：某一刻的曲目内位置 + 采样墙钟 + 速率。
/// 渲染方用 position(atWallTime:) 在本地逐帧插值，不回问宿主。
struct PlaybackAnchor: Equatable {
    var trackId: String
    var positionAtAnchor: TimeInterval
    var wallTimeAtAnchor: TimeInterval   // CACurrentMediaTime() 基准
    var rate: Double                     // 0 = 暂停，1 = 播放
    var anchorSeq: Int                   // 每次重锚 +1，渲染方据此辨锚点代次

    func position(atWallTime wallTime: TimeInterval) -> TimeInterval {
        guard rate > 0 else { return positionAtAnchor }
        return positionAtAnchor + (wallTime - wallTimeAtAnchor) * rate
    }
}

/// 逐字时间戳（扩展位：本期数据源缺失，恒为 nil；形状先定，防日后
/// 逐字样式接入时改 LyricLine 本体）。
struct LyricWord: Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// 一行歌词。id 为行序号（自 0 起、稳定）；end = 下一行 start，
/// 末行为曲目时长（解析器负责填满，渲染方不猜）。
struct LyricLine: Equatable {
    var id: Int
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var words: [LyricWord]? = nil
}

/// 曲目元数据（渲染面需要的最小集；封面只给 URL，位图由宿主经
/// NativeCoverLoader 解码后以调色板 token 与背景图分别下发）。
struct TrackMeta: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkURL: String?

    init(track: FoliaTrack) {
        id = track.id
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration
        artworkURL = track.artworkURL?.absoluteString
    }
}

/// 调色板 token：只传语义色，不传原始像素（Q2 冻结面）。
/// 由宿主从封面提取（见 StagePalette），无封面时为中性深色缺省。
struct PaletteTokens: Equatable {
    var background: UIColor
    var primary: UIColor
    var secondary: UIColor
    var text: UIColor
    var accent: UIColor
    var isDark: Bool

    static let neutralDark = PaletteTokens(
        background: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1),
        primary: UIColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1),
        secondary: UIColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1),
        text: .white,
        accent: UIColor(red: 0.98, green: 0.75, blue: 0.35, alpha: 1),
        isDark: true)

    static func == (lhs: PaletteTokens, rhs: PaletteTokens) -> Bool {
        lhs.background == rhs.background && lhs.primary == rhs.primary
            && lhs.secondary == rhs.secondary && lhs.text == rhs.text
            && lhs.accent == rhs.accent && lhs.isDark == rhs.isDark
    }
}

/// 渲染方生命周期状态机（冻结面）。迁移规则由宿主驱动：
/// created → mounted →（playing ⇄ paused）→ destroyed。
/// active/inactive 是正交的渲染启停（renderState 等价物）：inactive
/// 时渲染方必须停掉自己的逐帧工作（舞台被遮挡/退到后台）。
enum LyricStageLifecycleState: Equatable {
    case created
    case mounted
    case playing
    case paused
    case destroyed
}

/// 控制回传（冻结面）：渲染方 → 宿主。带来源与时间戳，宿主据此
/// 落面包屑并分发到与迷你台/展开卡同一命令入口。
struct LyricStageCommand {
    enum Kind: Equatable {
        case toggle
        case seek(to: TimeInterval)
        case next
        case prev
        case like
        case close
    }
    var kind: Kind
    var source: String          // 如 "stage.classic" / "stage.partita"
    var timestamp: Date

    init(kind: Kind, source: String, timestamp: Date = Date()) {
        self.kind = kind
        self.source = source
        self.timestamp = timestamp
    }
}

/// 视口（冻结面）：尺寸、安全区、动态字号缩放。宿主在挂载与
/// 布局变化时经快照重发。
struct LyricStageViewport: Equatable {
    var size: CGSize
    var safeAreaInsets: UIEdgeInsets
    var dynamicTypeScale: CGFloat   // 相对系统字号的缩放（本期恒 1，留位）
}

/// 能力声明（冻结面）：渲染方在注册时声明、宿主在快照里回告
/// 自己的数据能力；不匹配时渲染方自行降级（如逐字缺失退逐行）。
struct LyricStageCapabilities: Equatable {
    var supportsWordSync: Bool
    var requiresSpectrum: Bool
    var supportsLineSeek: Bool
}

/// 宿主 → 渲染方的全量快照。挂载、切歌、歌词/调色板到货、视口
/// 变化时重发；渲染方按 track.id + lines 计数自行 diff。
struct LyricStageSnapshot {
    var protocolVersion: Int
    var track: TrackMeta?
    var lines: [LyricLine]
    var palette: PaletteTokens
    var styleId: String
    var styleVersion: Int
    var viewport: LyricStageViewport
    var anchor: PlaybackAnchor
    var hostCapabilities: LyricStageCapabilities
    var ext: [String: String]
}

/// 渲染方与宿主之间的运行期通道：命令上行 + 锚点读取。
/// 由宿主（StageViewController）实现并在 mount 时交给渲染方。
final class LyricStageContext {
    let sendCommand: (LyricStageCommand) -> Void
    let currentAnchor: () -> PlaybackAnchor

    init(sendCommand: @escaping (LyricStageCommand) -> Void,
         currentAnchor: @escaping () -> PlaybackAnchor) {
        self.sendCommand = sendCommand
        self.currentAnchor = currentAnchor
    }

    /// 当前应显示的曲目内位置（本地插值）。
    func positionNow() -> TimeInterval {
        currentAnchor().position(atWallTime: CACurrentMediaTime())
    }
}

/// 歌词特效渲染方协议（冻结面）。实现为一个自持视图的类：
/// 宿主只经本协议与之对话，不碰其内部视图层级。
protocol LyricStageRenderer: AnyObject {
    var view: UIView { get }
    var capabilities: LyricStageCapabilities { get }
    /// 挂载：拿到运行期通道。只调一次。
    func mount(context: LyricStageContext)
    /// 全量快照下发（见 LyricStageSnapshot 的重发时机）。
    func applySnapshot(_ snapshot: LyricStageSnapshot)
    /// 生命周期迁移 + 渲染启停。
    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool)
    /// 逐帧回调（宿主 CADisplayLink 驱动）：position 为锚点插值后
    /// 的曲目内位置。渲染方在这里推进扫光/滚动，不得自建时钟源。
    func frameTick(position: TimeInterval)
    /// 卸载：停掉一切逐帧工作、释放大图。只调一次。
    func unmount()
}

/// 样式注册条目：17 种样式全量登记（id/显示名/展示序与网页侧
/// 注册表一致，见 LyricStageRegistry）；isNativeAvailable 为真时
/// factory 非空。styleVersion 随单个样式的视觉迭代递增。
struct LyricStageStyleInfo {
    let id: String
    let displayName: String
    let order: Int
    let styleVersion: Int
    let isNativeAvailable: Bool
    let factory: (() -> LyricStageRenderer)?

    var sourceTag: String { "stage.\(id)" }
}

/// 样式注册表（本期已迁：classic 静态排版型、partita 滚动同步型；
/// 其余 15 个只登记元数据，供选择器全量展示与「网页版」跳转）。
enum LyricStageRegistry {
    static let allStyles: [LyricStageStyleInfo] = [
        .init(id: "sonnet",   displayName: "商籁", order: 10,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "tempera",  displayName: "凝彩", order: 20,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "lumiere",  displayName: "绘光", order: 25,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "hanabi",   displayName: "花火", order: 26,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "machi",    displayName: "町景", order: 27,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "nebbia",   displayName: "雾笺", order: 29,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "classic",  displayName: "流光", order: 30,  styleVersion: 1, isNativeAvailable: true,
              factory: { ClassicStageRenderer() }),
        .init(id: "cadenza",  displayName: "心象", order: 40,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "partita",  displayName: "云阶", order: 50,  styleVersion: 1, isNativeAvailable: true,
              factory: { PartitaStageRenderer() }),
        .init(id: "fume",     displayName: "浮名", order: 60,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "tilt",     displayName: "倾诉", order: 70,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "claddagh", displayName: "回环", order: 80,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "monet",    displayName: "莫奈", order: 90,  styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "pendolo",  displayName: "时计", order: 100, styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "cappella", displayName: "群唱", order: 110, styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "diorama",  displayName: "镜台", order: 120, styleVersion: 1, isNativeAvailable: false, factory: nil),
        .init(id: "still",    displayName: "静止", order: 130, styleVersion: 1, isNativeAvailable: false, factory: nil),
    ]

    static func info(for styleId: String) -> LyricStageStyleInfo? {
        allStyles.first { $0.id == styleId }
    }

    static var nativeStyleIds: [String] {
        allStyles.filter { $0.isNativeAvailable }.map { $0.id }
    }

    /// 协议默认样式（与网页侧 DEFAULT_VISUALIZER_MODE 对齐）。
    static let defaultStyleId = "classic"
}
