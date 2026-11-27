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
//
// 协议变更记录（版本评审留痕，冻结纪律要求）：
//  - v1（3.7 (14)）：初版冻结面。hostCapabilities.supportsWordSync
//    = false（当时口径：逐字无数据源、words 恒 nil）。
//  - v2（3.7 (50)，DS YRC50 评审对账）：supportsWordSync 改 true。
//    语义 = 宿主可提供逐字数据（来源 /lyric/new 的 YRC，经
//    LyricRepository 合并 rebase 后逐行下发），但逐行可选：有
//    YRC 覆盖的行带真戳、无覆盖行 words=nil，消费方必须按既
//    有均分口径降级，不得假设整首全行有戳。不增删任何字段、
//    不改任何结构；全仓无代码读 host 侧该能力位（仅声明处），
//    Web 桥与网页源码亦无该键消费者（2026-11-20 grep 实查）。

/// 协议版本与全局能力声明。
enum LyricStageProtocolInfo {
    static let version = 2
    /// 宿主当前能提供的数据能力：逐行歌词有（lines）；逐字数据
    /// 可提供（v2 起，YRC 逐行可选，无戳行 words=nil）；频谱无
    /// 数据源（spectrum 恒不提供）。
    static let hostCapabilities = LyricStageCapabilities(
        supportsWordSync: true,
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

/// 逐字时间戳（形状自 v1 冻结；数据源自 (19)/(20) 接通 /lyric/new
/// 的 YRC、经仓库合并 rebase 到 LRC 行界内，逐行可选——无 YRC 覆
/// 盖的行 LyricLine.words 为 nil，见 v2 变更记录）。
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
    /// 演唱跨度压缩比（3.7 (43) 路3，只增不删的默认字段）：
    /// words=nil 行的逐字均分 span 乘此值（行尾气口不摊进
    /// 每个字）；来源 = LyricRepository 标定（同曲有戳行中
    /// 位），缺省 1 = 不压缩（旧口径）。翻行不读此值。
    var singingRatio: Double = 1
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
    /// chrome 占用下发（3.7 (60) 第 4 条，只增不删的可选钩子）：
    /// 舞台全样式全幅后，宿主在每次 layoutStage 时把顶栏/点播台
    /// 的当前占用算成 insets 下发；只有构图重心在下部的样式才
    /// 需要实现（按 bottom inset 内缩焦点），其余走协议扩展的
    /// 默认空实现 = 忽略。insets 坐标系为宿主 view 坐标。
    func applyChromeInsets(_ insets: UIEdgeInsets)
}

extension LyricStageRenderer {
    /// 默认空实现：不消费 chrome insets（全幅画面任 chrome 浮压）。
    func applyChromeInsets(_ insets: UIEdgeInsets) {}
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
    /// 逐样式调参面板工厂（3.7 (57) 接线）：非空时选择器在该
    /// 样式行给出「调参」入口。只增字段（默认 nil），不属渲
    /// 染方冻结面（渲染器不消费本结构体），故不递增协议版本。
    var tuningPanelFactory: (() -> UIViewController)? = nil
    /// 锁定禁用位（3.7 (60) 第 4 条，只增字段、缺省 false）：
    /// 锁定样式代码与资源全保留，但用户选不到、用不了——选择
    /// 器置灰带锁禁点选/禁调参、洗牌袋过滤、持久化回退。注意
    /// 不许用 isNativeAvailable=false 冒充锁定：那会把样式分
    /// 流去网页舞台，等于换个地方能用。
    var isLocked: Bool = false

    /// 网页运行位（3.7 (67) A3，只增计算属性）：本样式在网页
    /// 端有原版实现（网页 17 式），在原生台面内嵌网页运行。
    /// 自有样式（原创三稿＋汪汪队）无网页实现，恒原生。
    /// (70) 起 17 式的原生移植渲染已整删、运行位切换退役：
    /// hasWebRuntime 为真即恒网页运行（StageRuntimeStore）。
    var hasWebRuntime: Bool {
        !["tuning", "corridor", "afterglow", "petconcert", "christmas"].contains(id)
    }

    /// 本台可呈现（3.7 (70)，只增计算属性）：有原生渲染器
    /// （factory 非空），或有网页运行（台面内嵌）——二者皆
    /// 无才走全屏网页舞台兜底。(70) 后注册表内已无此情形，
    /// 兜底仅作防御保留。
    var isStagePresentable: Bool { isNativeAvailable || hasWebRuntime }

    var sourceTag: String { "stage.\(id)" }
}

/// 样式注册表（沿革：网页 17 样式曾于 (26)/(33)/(57) 全量
/// 原生化、原创三稿 tuning/corridor/afterglow（(40)）与
/// petconcert（(53)）为自有原生。(67) 网页 17 式加台面内嵌
/// 网页运行、与原生移植双运行并行；(70) Miller 真机验网页
/// 切换后下令：17 式原生移植渲染整删、只走网页嵌入单路——
/// 本表 17 式 factory=nil / isNativeAvailable=false /
/// 无调参面板（调参存储与面板同为原生专属链路，经核不经桥
/// 供网页运行，随渲染器一并删除，逐式清单见 (70) 交付
/// 报告）；自有四式原生一行不动。选择器
/// （StageStylePickerViewController）与 StageStyleStore 均直接
/// 读本表，StageViewController 对 17 式经 StageRuntimeStore
/// 分流网页嵌入、对自有四式经 info.factory 分发渲染器。
enum LyricStageRegistry {
    static let allStyles: [LyricStageStyleInfo] = [
        .init(id: "sonnet",   displayName: "商籁", order: 10,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "tempera",  displayName: "凝彩", order: 20,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "lumiere",  displayName: "绘光", order: 25,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "hanabi",   displayName: "花火", order: 26,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        // (60) 第 4 条曾锁定禁用、(70) 原生渲染删除后悬置；
        // (74) Miller 拍板恢复：解除锁定，按「网页运行」入列
        // （hasWebRuntime=true、WebEffect 资源 VisualizerMachi
        // 与 createMachiRuntime 在包内完好）——选择器可选、
        // 洗牌袋/三击/长按轮换经 selectableStyleIds 同源入
        // 袋、样式池全集 21 只，呈现走 StageRuntimeStore 网
        // 页嵌入通路，与其余 16 只网页特效同路。
        .init(id: "machi",    displayName: "町景", order: 27,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "nebbia",   displayName: "雾笺", order: 29,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "classic",  displayName: "流光", order: 30,  styleVersion: 2, isNativeAvailable: false,
              factory: nil),
        .init(id: "cadenza",  displayName: "心象", order: 40,  styleVersion: 3, isNativeAvailable: false,
              factory: nil),
        .init(id: "partita",  displayName: "云阶", order: 50,  styleVersion: 3, isNativeAvailable: false,
              factory: nil),
        .init(id: "fume",     displayName: "浮名", order: 60,  styleVersion: 3, isNativeAvailable: false,
              factory: nil),
        .init(id: "tilt",     displayName: "倾诉", order: 70,  styleVersion: 3, isNativeAvailable: false,
              factory: nil),
        .init(id: "claddagh", displayName: "回环", order: 80,  styleVersion: 3, isNativeAvailable: false,
              factory: nil),
        .init(id: "monet",    displayName: "莫奈", order: 90,  styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "pendolo",  displayName: "时计", order: 100, styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "cappella", displayName: "群唱", order: 110, styleVersion: 3, isNativeAvailable: false,
              factory: nil),
        .init(id: "diorama",  displayName: "镜台", order: 120, styleVersion: 1, isNativeAvailable: false,
              factory: nil),
        .init(id: "still",    displayName: "静止", order: 130, styleVersion: 2, isNativeAvailable: false,
              factory: nil),
        .init(id: "tuning",   displayName: "调频", order: 140, styleVersion: 1, isNativeAvailable: true,
              factory: { TuningStageRenderer() }),
        .init(id: "corridor", displayName: "深廊", order: 150, styleVersion: 1, isNativeAvailable: true,
              factory: { CorridorStageRenderer() }),
        .init(id: "afterglow", displayName: "残光", order: 160, styleVersion: 1, isNativeAvailable: true,
              factory: { AfterglowStageRenderer() }),
        // (53) J 组：宠物演唱会「汪汪队开大会」（七态状态机＋独唱跑位＋
        // v3 贴纸风幕布；样式生效期间迷你台/灵动岛宠物迁移回舞台）。
        .init(id: "petconcert", displayName: "汪汪队开大会", order: 170, styleVersion: 1, isNativeAvailable: true,
              factory: { PetConcertStageRenderer() }),
        // (93) 圣诞树：粒子圣诞树＋歌词聚字原生样式（样片
        // sheng-dan-ge-ci-te-xiao-yang-pian 口径移植）；无网页
        // 运行（hasWebRuntime 排除名单已加 christmas）。
        .init(id: "christmas", displayName: "圣诞树", order: 180, styleVersion: 1, isNativeAvailable: true,
              factory: { ChristmasTreeStageRenderer() }),
    ]

    static func info(for styleId: String) -> LyricStageStyleInfo? {
        allStyles.first { $0.id == styleId }
    }

    static var nativeStyleIds: [String] {
        allStyles.filter { $0.isNativeAvailable }.map { $0.id }
    }

    /// 样式是否被锁定禁用（3.7 (60) 第 4 条）：未登记 id 视为未锁。
    static func isLocked(_ styleId: String) -> Bool {
        info(for: styleId)?.isLocked ?? false
    }

    /// 样式能否在原生台面呈现（3.7 (70)）：原生渲染或网页
    /// 嵌入任一通路即可；未登记 id 视为不可呈现。
    static func isStagePresentable(_ styleId: String) -> Bool {
        info(for: styleId)?.isStagePresentable ?? false
    }

    /// 协议默认样式。(88) 改定：Miller 2026-11-25 工坊定案
    /// 歌词样式默认深廊（工坊存值 shenlang＝原生 id corridor，
    /// port88）——只改默认落点，与网页侧 DEFAULT_VISUALIZER_
    /// MODE 的对齐就此让位；用户已存的 currentStyleId 与逐
    /// 歌记忆不覆盖，洗牌袋/三击切换逻辑不动。
    static let defaultStyleId = "corridor"
}
