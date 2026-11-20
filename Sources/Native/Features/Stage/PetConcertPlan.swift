import UIKit
import Foundation

// 汪汪队开大会 petconcert（3.7 (53) 工作流 J）：演唱会计划层。
//
// 全部编排在构建期由歌词行时间轴预计算（ConcertPlan），运行期
// 只查表：七态状态机是歌词时间轴的纯函数 phase(at:)——同一
// (曲目, t) 永远同结果，seek/暂停/切歌后由 t 直接重建，不依
// 赖任何运行期累积状态。队长由 hash(曲目 id) 定 C 位、每首歌
// 固定；轮唱走蛇形序 + 每首 seed 偏移 + 同轮不重复；间奏只
// 取全曲最大空档（≥3.0s）全强度爆发，>30s 分档降强度。
//
// 数值真源 = concert-v3-render.py（Miller 2026-11-20/21 验收
// 的 v3 样片：手绘贴纸风幕布 + 独唱跑位）。参考画布 1080×1920，
// 本文件常量一律存参考值，渲染方按舞台实际尺寸等比换算
// （× stageW/1080 或 stageH/1920，见 PetConcertRenderer 的
// sx/sy）。可调常量集中在 PetConcertConst，报告里逐项列明。

enum PetConcertConst {
    /// 参考画布（v3 样片）。
    static let refW: CGFloat = 1080
    static let refH: CGFloat = 1920

    // MARK: 队形（(54) Q 纵深重排 + (55) B 格位纪律：7 列 × 8 行）
    static let gridCols = 7
    static let gridRows = 8
    /// 列 x = 540 + (c−3)×120（参考 px）。(55) B 第 4/5 项：
    /// 列距自 132 收至 120——格位矩形（宽 = 列距、相邻格共
    /// 边平铺，见 slotCellRect）整体收进幕布开口：首格左缘
    /// 120 ≥ 开口有效左缘 103.8（开口 84 + 摆动极值 19.8），
    /// 末格右缘 960 ≤ 976.2，两侧各留 16.2 参考 px 余量，
    /// 侧幕任何相位都切不到格位（脚本断言见 (55) B 报告）。
    static let gridX0: CGFloat = 540
    static let gridDX: CGFloat = 120
    /// 行 y 改透视表（(54) Q）：行距自后排 88 递增到前排 136，
    /// 队形整体后移到舞台后 2/3（首行 588、末行 1372），中央
    /// 前方留给独唱区。gridDY 仅作旧口径留存，站位以表为准。
    static let gridY0: CGFloat = 588
    static let gridDY: CGFloat = 116
    static let gridRowY: [CGFloat] = [588, 676, 772, 876, 988, 1108, 1236, 1372]
    /// 透视行缩放：后排（row 0）0.70 → 前排（row 7）1.00 线性。
    static func formationScale(row: Int) -> CGFloat {
        let r = min(max(row, 0), gridRows - 1)
        return 0.70 + 0.30 * CGFloat(r) / CGFloat(gridRows - 1)
    }
    /// 空槽（v3 EMPTY）：后排三处留空透气。
    static let emptySlots: Set<Int> = [0 * 7 + 0, 0 * 7 + 3, 0 * 7 + 6]
    /// 队长槽（行 7、列 3，前排正中）。
    static let captainSlotRow = 7
    static let captainSlotCol = 3
    /// 宠物基准边长（参考 px，fit-box 口径）。(55) B：124 →
    /// 116，使每行贴纸边长 ≤ 相邻行距（后排 81.2 < 88 起逐
    /// 行成立）且前排边长 116 < 列距 120——贴纸本体不跨格、
    /// 不压相邻格界（脚本逐行断言）。
    static let petBase: CGFloat = 116
    /// 队长放大倍率。(55) B：1.6 → 1.03——旧值队长边长
    /// 198.4 横跨近两格、压住左右邻格（真机「挤格/压线」
    /// 主因之一）；新值队长边长 119.5 ≤ 列距 120，与邻格
    /// 贴纸半宽和 117.7 < 120，严格一格一只。队长身份改由
    /// C 位 + 口令 + 前排最大行缩放承载。
    static let captainScale: CGFloat = 1.03

    // MARK: 独唱跑位（(54) Q：独唱区前移留大）
    /// 独唱位（参考 px），渲染方按舞台尺寸等比换算。(55) B
    /// 复核：队长格底 1440（队长贴纸底 1431.7）与独唱顶
    /// 1514.5 之间留 74.5 空隙，独唱底 1717.5 在脚灯行
    /// 1766 之上。独唱位是独立位、不占任何队形格：独唱者
    /// 离队期间其格位保持空置（slotOf 构建期定死、无人递
    /// 补），归队回到原格（(55) B 第 4 项处理口径）。
    static let soloX: CGFloat = 540
    static let soloY: CGFloat = 1616
    static let soloScale: CGFloat = 1.75
    /// 贝塞尔控制点 = 起终点中点 + y −150（参考 px，向上拱）。
    static let bezierLift: CGFloat = 150
    /// 出发提前量与跑程：常速行 lead 0.28 / 跑 0.50；快行
    /// lead 0.10 / 跑 0.25（v3 TRIPS 口径，到达点因此落在行
    /// 首后 0.22 / 0.15s，与样片一致）。
    static let leadNormal: TimeInterval = 0.28
    static let travelNormal: TimeInterval = 0.50
    static let leadQuick: TimeInterval = 0.10
    static let travelQuick: TimeInterval = 0.25
    /// 快行判定：行时长 < 1.05s（v3 样片 QUICK 行 0.9/1.0s）。
    static let quickLineThreshold: TimeInterval = 1.05
    /// 连唱下限：行时长 < 0.9s 时不换人、上一位续唱。
    static let minSingerHold: TimeInterval = 0.9
    /// 群唱兜底：行时长 < 0.45s（跑位物理上不可能）整行群唱。
    static let chorusLineThreshold: TimeInterval = 0.45
    /// 呼吸块目标跨度：长行按词戳切 ~2.4s 一块换气。
    static let breathBlockSpan: TimeInterval = 2.4

    // MARK: 相位时序（相对首行 start 的样片锚点）
    /// 降落总时长上限（样片落位 0–1.5s；首行更早时等比压缩）。
    static let dropNominal: TimeInterval = 1.5
    /// 列队完成点（样片 2.5s；队长口令在此前）。
    static let formNominal: TimeInterval = 2.5
    /// 队长口令气泡时长。
    static let captainBubbleDuration: TimeInterval = 1.0
    /// 间奏入选门槛：最大空档 ≥ 3.0s。
    static let interludeMinGap: TimeInterval = 3.0
    /// 间奏全强度上限：空档 > 30s 起分档降强度（30/gap，下限 0.35）。
    static let interludeFullGap: TimeInterval = 30.0
    static let interludeMinIntensity: Double = 0.35
    /// 告别相位自然起点 = 末行 end + 0.4。
    static let farewellLead: TimeInterval = 0.4
    /// 告别保底可见时长（(54) T 第 3 条，01:38 修正后仍适用：
    /// 尾段短于此值时起点向前借位补足，借位上限见下）。
    static let farewellMinSpan: TimeInterval = 2.4
    /// 告别借位上限：最多侵入末行尾部 1.5s（此时歌词气泡在
    /// 上方专区、告别气泡在头顶，位置分区不打架；提词条仍
    /// 显示末行全文）。借位后仍不足保底的极端短尾按实长走。
    static let farewellMaxBorrow: TimeInterval = 1.5

    // MARK: 开场仪式（(54) T + 01:38 自适应口径）
    /// 无前奏判定：首行 start < 1.0s 视为一开头就唱，仪式
    /// 整段省去（intro=none），降落/列队压缩最快就位。
    static let introNoneThreshold: TimeInterval = 1.0
    /// 仪式可用时长分档：≥2.4 从容双段；1.2–2.4 按比例压缩
    /// 双段；0.5–1.2 只保留打招呼；<0.5 整段省去。仪式段
    /// 总时长恒 ≤ 前奏可用时间，绝不侵占演唱。
    static let introFullThreshold: TimeInterval = 2.4
    static let introDualThreshold: TimeInterval = 1.2
    static let introGreetOnlyThreshold: TimeInterval = 0.5
    /// 从容档打招呼上限（其余归交头接耳窗，cue 在窗内摊开）。
    static let greetingNominal: TimeInterval = 1.8
    /// 单条社交 cue 的最长展示（短窗等分压缩，长窗摊开留白）。
    static let socialCueMaxDuration: TimeInterval = 1.05
    static let farewellCueMaxDuration: TimeInterval = 1.2
    /// 演唱会本地文案（风格对齐 PetLines/PetChat 既有词库；
    /// 词库文件不在本工作流文件域内，故以本地常量收录）。
    /// 打招呼：面向观众，与队长对队内的「稍息，立正」分开。
    static let greetingLines: [String] = [
        "大家好，我们来啦",
        "大家好，谢谢你们来看我们",
        "晚上好，今天唱给大家听",
        "大家好，准备好了吗",
    ]
    /// 告别：面向观众的再见（区别于迷你台个人离开词）。
    static let farewellLines: [String] = [
        "谢谢大家，我们下次见",
        "今天就唱到这里啦，再见",
        "谢谢你们陪我们唱完",
        "再见啦，下次还要来听哦",
    ]
    /// 极短尾段的融合句（再见＋关心同句，单 cue 承载两义）。
    static let farewellFusedLine = "再见啦，回去早点休息哦"

    // MARK: 降落/列队动画（v3 base_anchor）
    static let dropStaggerMax: Double = 0.85   // 每只随机错峰 0–0.85s
    static let dropFallDuration: TimeInterval = 0.6  // easeOutQuad 下落
    static let formMoveStart: TimeInterval = 1.5     // 样片绝对值（计划里按比例缩放）
    static let formMoveDuration: TimeInterval = 0.8  // easeOutBack(c1=1.70158)
    static let formDelayMax: Double = 0.25

    // MARK: 幕布（v3 curtains；开幕速度/摆动幅度可调）
    /// 开幕时长 1.35s，easeOutBack(c1=2.2) 弹性拉开。
    static let curtainOpenDuration: TimeInterval = 1.35
    static let curtainOpenBackC1: Double = 2.2
    /// 侧幕内缘基准：收拢 x=566 → 拉开 x=84（参考 px，自左
    /// 缘量）。(55) B 第 5 项：126 → 84，幕布开口（名义
    /// [84, 996]）连同呼吸摆动极值（±19.8 = (6+3)×amp 上限
    /// 2.2，见 curtainSwayMax）都让开队形格位（[120, 960]）：
    /// 有效开口 [103.8, 976.2] ⊇ 格位横向全幅。
    static let curtainClosedX: CGFloat = 566
    static let curtainOpenX: CGFloat = 84
    /// 侧幕内缘摆动极值（参考 px）：波形幅值 (swayAmpA +
    /// swayAmpB) = 9 乘 sectionParams 的 amp 上限 2.2（间奏
    /// 全强度 1 + 1.2）。开口断言按此极值收紧，不按名义值。
    static let curtainSwayMax: CGFloat = 19.8
    /// 呼吸摆动：内缘波 6·sin(y·0.010 + 1.1t) + 3·sin(y·0.023 − 0.7t)
    /// （参考 px 幅值，随段落倍率 amp 缩放，见 sectionParams）。
    static let swayAmpA: CGFloat = 6
    static let swayAmpB: CGFloat = 3
    static let swayFreqA: Double = 1.1
    static let swayFreqB: Double = 0.7
    /// 垂幔：7 扇 scallop、基线 y=196、垂深 54（参考 px）。
    static let valanceSwags = 7
    static let valanceBaseY: CGFloat = 196
    static let valanceDepth: CGFloat = 54
    /// 点缀闪烁：scale = 1 + twinkleAmp·sin(twinkleFreq·t + phase)；
    /// 基准 freq 1.6 / amp 0.16，间奏 freq ×2、amp +0.10（样片口径
    /// 由 sectionParams 的 inter 平滑量驱动）。
    static let twinkleBaseFreq: Double = 1.6
    static let twinkleBaseAmp: Double = 0.16

    // MARK: 灯光/地板（v3 lights/floor）
    static let footlightCount = 11
    static let footlightY: CGFloat = 1766       // 参考 px
    /// 木地板地平线（(54) Q）：与后排顶 543 对齐，地板自此
    /// 向前（向下）透视延伸满屏。
    static let floorTopY: CGFloat = 540         // 参考 px
    /// 独唱位金色脚圈（(54) Q 放大）：中心 (540, 1712)、半径 (190, 42)。
    static let soloRingY: CGFloat = 1712
    static let soloRingRX: CGFloat = 190
    static let soloRingRY: CGFloat = 42
    /// 歌词气泡专区（(54) P+Q 的 bubbleZoneTop/Bottom）已
    /// 随 (55) B 第 2 项删除：Miller 点名改回跟人走——轮唱
    /// 气泡锚定当前独唱者头顶、钳制在舞台内、换人弹簧跟
    /// 随，无固定专区、无引导线（见 PetConcertBubbleView
    /// 的 showFollowingSinger）。

    // MARK: 横屏几何（(54) U 独立推导，覆盖 Q 的横屏等比口径）
    // 朝向判定：舞台容器 bounds 宽 ≥ 高判横屏（正方形归横屏，
    // 无状态滞回——判定是 bounds 的纯函数，旋转重排可复算）。
    // 横屏参考画布 1920×1080（与竖屏 1080×1920 分开两套表，
    // 竖屏数值一律不动）。推导约束（iPhone 14 Pro 横屏
    // 852×393pt，sxL=852/1920=0.444、syL=393/1080=0.364）：
    // 队形改 11 列 × 5 行用满横向；单只边长下限口径——
    // petBaseL×formationScaleL(0)=108×0.78=84.2 参考 px
    // ×0.444 = 37.4pt，不低于竖屏最小只（(55) B 后
    // 116×0.70×393/1080 = 29.5pt），且列距 144×0.444=64.0pt
    // > 前排边长 108×0.444=48.0pt，横向零重叠。(55) B：
    // 列距 150 → 144，格位 [168, 1752] 收进横屏有效开口
    // [115.8, 1804.2]（开口 96 + 摆动极值 19.8），余量 52.2。
    static let refWL: CGFloat = 1920
    static let refHL: CGFloat = 1080
    static func isLandscape(_ size: CGSize) -> Bool { size.width >= size.height }
    static let gridColsL = 11
    static let gridRowsL = 5
    static let gridX0L: CGFloat = 960
    static let gridDXL: CGFloat = 144
    static let gridRowYL: [CGFloat] = [330, 440, 550, 660, 770]
    static func formationScaleL(row: Int) -> CGFloat {
        let r = min(max(row, 0), gridRowsL - 1)
        return 0.78 + 0.22 * CGFloat(r) / CGFloat(gridRowsL - 1)
    }
    /// 横屏空槽：后排两角（55 槽 − 2 空 = 53 只正好满员）。
    static let emptySlotsL: Set<Int> = [0, 10]
    static let captainSlotRowL = 4
    static let captainSlotColL = 5
    static let petBaseL: CGFloat = 108
    /// 横屏单只边长归一化下限（占舞台宽）：84.2/1920 = 0.0439。
    static let petMinEdgeNormL: CGFloat = 0.0439
    static let soloXL: CGFloat = 960
    /// 横屏独唱位 y。(55) B：885 → 898——独唱顶 825.1 与末
    /// 行格底 825 相切（原值时独唱贴纸顶 812.1 压进末行格
    /// 13 参考 px）；独唱脚 970.9 在脚灯行 1005 之上、与提
    /// 词条顶 975 留 4.1 间隙。脚圈随脚位移到 965。
    static let soloYL: CGFloat = 898
    static let soloScaleL: CGFloat = 1.35
    static let soloRingYL: CGFloat = 965
    static let soloRingRXL: CGFloat = 150
    static let soloRingRYL: CGFloat = 30
    static let floorTopYL: CGFloat = 300
    static let valanceSwagsL = 11
    static let valanceBaseYL: CGFloat = 105
    static let valanceDepthL: CGFloat = 28
    static let curtainClosedXL: CGFloat = 1020
    /// 横屏侧幕拉开内缘。(55) B 第 5 项：140 → 96，横屏有
    /// 效开口 [115.8, 1804.2] ⊇ 横屏格位 [168, 1752]。
    static let curtainOpenXL: CGFloat = 96
    static let curtainBottomYL: CGFloat = 1020
    static let footlightYL: CGFloat = 1005
    static let teleBarYL: CGFloat = 975

    // MARK: 气泡/提词条（v3 bubbles/teleprompter，参考 px 字号）
    static let bubbleFontCaptain: CGFloat = 46
    static let bubbleFontChat: CGFloat = 36
    static let bubbleFontLyric: CGFloat = 44
    static let teleFontMax: CGFloat = 40
    static let teleFontMin: CGFloat = 28
    static let teleBarY: CGFloat = 1790
    static let teleBarH: CGFloat = 76

    // MARK: 内存红线（(53) J 规格 §6）
    /// 动图池：最多 8 只 StickerView，解码成本合计 ≤ 40MB
    /// （动画缓存硬上限 48MB 留 8MB 余量给反应/过渡）。
    static let animPoolMaxCount = 8
    static let animPoolBudgetBytes = 40 * 1024 * 1024
    /// 静帧 atlas：53 只首帧统一缩到 ≤160px 边长（≈5.4MB）。
    static let staticAtlasMaxPx: CGFloat = 160

    /// 全量班底（与 MiniBarPetStage.fullPool 同序：猫 25 + live + 狗 27）。
    static let allAssets: [String] =
        (1...25).map { String(format: "cat-%02d", $0) } + ["cat-live"]
        + (1...27).map { String(format: "dog-%02d", $0) }
    /// 带矩形底、已真抠图的素材（Resources/StickersCutout 有同名版，
    /// 加载优先级高于原贴纸；审计结论见 (53) J 报告）。
    static let cutoutAssets: Set<String> = ["cat-19", "dog-09", "dog-24"]
    /// 动图池优先序（活泼人格与样片 ANIM8 优先，成本准入由
    /// StickerStore 解码后 memoryCost 实测把关，见渲染方）。
    static let animPoolPriority: [String] = [
        "dog-01", "dog-11", "cat-15", "dog-07", "dog-08", "dog-05",
        "cat-20", "dog-25", "dog-03", "dog-06", "cat-05", "cat-07",
        "dog-23", "cat-17", "dog-02", "cat-01",
    ]
    /// 间奏换入的两只（v3 ANIM_EXTRA2 口径，池大小不变、换人不加人）。
    static let interludeSwapIn: [String] = ["cat-18", "dog-13"]
}

// MARK: - 确定性随机（FNV-1a + LCG，与 cappella 种子口径同族）

struct ConcertRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0x1FFFFFFFFFFFFF) / Double(0x20000000000000)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }
    mutating func shuffled<T>(_ array: [T]) -> [T] {
        var a = array
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, through: 1, by: -1) {
            let j = Int(next() * Double(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}

func concertHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 14695981039346656037
    for unit in string.utf16 {
        hash ^= UInt64(unit)
        hash = hash &* 1099511628211
    }
    return hash
}

// MARK: - 相位

enum ConcertPhase: String {
    case dropping   // 降落散位
    case formation  // 列队 + 队长口令
    case greeting   // 向观众打招呼（(54) T 新增；无前奏歌不进入）
    case preludeChat // 前奏交头接耳
    case singing1   // 轮唱一
    case interlude  // 间奏爆发（全曲最大空档）
    case singing2   // 轮唱二
    case farewell   // 告别关心话
    case ended      // 曲终（告别姿态保持）
}

// MARK: - 计划

struct ConcertTrip {
    var lineIndex: Int
    var singer: String
    var depart: TimeInterval
    var arrive: TimeInterval
    var returnStart: TimeInterval
    var returnEnd: TimeInterval
    var isQuick: Bool
}

struct ConcertChatCue {
    var asset: String
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

struct ConcertPlan {
    let trackId: String
    let duration: TimeInterval
    let lines: [LyricLine]
    let captain: String
    /// asset → 槽位序号（row×7+col，row 0 = 后排）。
    let slotOf: [String: Int]
    /// 横屏槽位/散位/玩耍位（(54) U：11×5 网格、1920×1080
    /// 参考系，与竖屏表独立；轮唱蛇形序仍以竖屏 slotOf 为
    /// 准——换朝向不换演唱顺序，旋转不许打乱轮唱进度）。
    let slotOfLandscape: [String: Int]
    let scatterOfLandscape: [String: CGPoint]
    let playOfLandscape: [String: CGPoint]
    /// asset → 散位（归一化到参考画布 1080×1920 的点）。
    let scatterOf: [String: CGPoint]
    /// asset → 间奏玩耍位（参考画布点）。
    let playOf: [String: CGPoint]
    /// asset → 降落错峰/列队延迟/闲晃相位（确定性）。
    let staggerOf: [String: Double]
    let formDelayOf: [String: Double]
    let swayPhaseOf: [String: Double]
    /// 行 → 独唱者（群唱行不在表内）。
    let singerByLine: [Int: String]
    let chorusLines: Set<Int>
    let tripsByLine: [Int: ConcertTrip]
    /// 行 → 呼吸块（每块的起止与文本；气泡按块推进）。
    let breathBlocksByLine: [Int: [(start: TimeInterval, end: TimeInterval, text: String)]]
    let interlude: (start: TimeInterval, end: TimeInterval, intensity: Double)?
    let formAt: TimeInterval
    /// 列队移动全部落定的时刻（打招呼最早可在此刻开始）。
    let formationSettledAt: TimeInterval
    /// 打招呼窗起点；nil = 本曲无仪式段（intro=none）。
    let greetAt: TimeInterval?
    /// 打招呼/交头接耳各自的相位窗时长（面包屑对账口径；
    /// 两者之和恒 ≤ 首行前的可用时间）。
    let greetingDuration: TimeInterval
    let whisperDuration: TimeInterval
    /// 仪式安排结果：none / greeting-only / dual / full。
    let introKind: String
    let chatAt: TimeInterval
    let firstLineStart: TimeInterval
    let farewellAt: TimeInterval?
    let greetingCues: [ConcertChatCue]
    let chatCues: [ConcertChatCue]
    /// 交头接耳配对（asset → 相邻伙伴 asset，槽位相邻成对）。
    let whisperPartnerOf: [String: String]
    let farewellCues: [ConcertChatCue]
    /// 动图池优先序（按本曲 seed 旋转，准入由渲染方按成本把关）。
    let animPriority: [String]

    // MARK: 纯函数相位（seek/暂停/切歌由 t 重建的唯一依据）

    func phase(at t: TimeInterval) -> ConcertPhase {
        if t >= duration { return .ended }
        if let farewellAt, t >= farewellAt { return .farewell }
        if let interlude {
            if t >= interlude.end { return .singing2 }
            if t >= interlude.start { return .interlude }
        }
        if t >= firstLineStart { return .singing1 }
        if whisperDuration > 0, t >= chatAt { return .preludeChat }
        if let greetAt, t >= greetAt { return .greeting }
        if t >= formAt { return .formation }
        return .dropping
    }

    /// 相位窗 [start, end)（纯函数推导，供 concert.phase 面包
    /// 屑记录每段的计划起止/时长；与 phase(at:) 同一边界源）。
    func phaseSpan(_ phase: ConcertPhase) -> (start: TimeInterval, end: TimeInterval) {
        let greetStart = greetAt ?? chatAt
        switch phase {
        case .dropping: return (0, formAt)
        case .formation: return (formAt, greetAt ?? firstLineStart)
        case .greeting:
            return greetAt == nil ? (firstLineStart, firstLineStart)
                : (greetStart, greetStart + greetingDuration)
        case .preludeChat:
            return whisperDuration > 0 ? (chatAt, firstLineStart)
                : (firstLineStart, firstLineStart)
        case .singing1: return (firstLineStart, interlude?.start ?? (farewellAt ?? duration))
        case .interlude:
            return interlude.map { ($0.start, $0.end) } ?? (duration, duration)
        case .singing2:
            return interlude.map { ($0.end, farewellAt ?? duration) }
                ?? (duration, duration)
        case .farewell:
            return farewellAt.map { ($0, duration) } ?? (duration, duration)
        case .ended: return (duration, duration)
        }
    }

    /// 某时刻正在展示的社交 cue（闲聊/告别/招呼共用查表）。
    func cue(in cues: [ConcertChatCue], at t: TimeInterval) -> ConcertChatCue? {
        cues.first(where: { t >= $0.start && t < $0.end })
    }

    /// 当前独唱行（t 落在某行 [start, end) 内且该行有独唱者）。
    func activeSoloLine(at t: TimeInterval) -> Int? {
        for line in lines where t >= line.start && t < line.end {
            return singerByLine[line.id] != nil ? line.id : nil
        }
        return nil
    }

    /// 段落氛围参数（v3 section_params）：(摆幅倍率, 频率倍率,
    /// 闪烁频率, 闪烁幅度)。inter 量由间奏窗平滑进出驱动，
    /// farewell 量由告别相位平滑转暖降幅。
    func sectionParams(at t: TimeInterval)
        -> (amp: Double, freq: Double, twinkleFreq: Double, twinkleAmp: Double) {
        var inter = 0.0
        if let gap = interlude {
            let inU = min(max((t - gap.start) / 0.5, 0), 1)
            let outU = min(max((t - (gap.end - 0.5)) / 0.5, 0), 1)
            let sIn = inU * inU * (3 - 2 * inU)
            let sOut = outU * outU * (3 - 2 * outU)
            inter = sIn * (1 - sOut) * gap.intensity
        }
        var fare = 0.0
        if let farewellAt {
            let u = min(max((t - farewellAt) / 1.0, 0), 1)
            fare = u * u * (3 - 2 * u)
        }
        return (amp: 1 + 1.2 * inter - 0.5 * fare,
                freq: 1 + 0.6 * inter - 0.3 * fare,
                twinkleFreq: PetConcertConst.twinkleBaseFreq * (1 + inter),
                twinkleAmp: PetConcertConst.twinkleBaseAmp + 0.10 * inter)
    }

    // MARK: 构建

    static func build(trackId: String, title: String,
                      lines: [LyricLine], duration: TimeInterval) -> ConcertPlan {
        let seed = concertHash(trackId.isEmpty ? title : trackId)
        var rng = ConcertRNG(seed: seed)
        let assets = PetConcertConst.allAssets

        // 队长：hash 固定一只（每首歌不变），落 C 位槽。
        let captain = assets[Int(seed % UInt64(assets.count))]
        // 槽位：空槽跳过、队长槽留给队长，其余由 seed 洗牌填充
        // （v3 口径：fill 顺序自后排向先排，视觉无差，蛇形序在
        // 轮唱分配处单独算）。
        var slots: [Int] = []
        for row in stride(from: PetConcertConst.gridRows - 1, through: 0, by: -1) {
            for col in 0..<PetConcertConst.gridCols {
                let s = row * PetConcertConst.gridCols + col
                if PetConcertConst.emptySlots.contains(s) { continue }
                if row == PetConcertConst.captainSlotRow
                    && col == PetConcertConst.captainSlotCol { continue }
                slots.append(s)
            }
        }
        let fillOrder = rng.shuffled(assets.filter { $0 != captain })
        var slotOf: [String: Int] = [
            captain: PetConcertConst.captainSlotRow * PetConcertConst.gridCols
                + PetConcertConst.captainSlotCol,
        ]
        for (asset, slot) in zip(fillOrder, slots) { slotOf[asset] = slot }

        // 散位/玩耍位/错峰（v3 build_pets 的 scatter/play/stagger）。
        var scatterOf: [String: CGPoint] = [:]
        var playOf: [String: CGPoint] = [:]
        var staggerOf: [String: Double] = [:]
        var formDelayOf: [String: Double] = [:]
        var swayPhaseOf: [String: Double] = [:]
        let playSlots = rng.shuffled(slots)
        var playIndex: [String: Int] = [:]
        for (i, asset) in fillOrder.enumerated() { playIndex[asset] = i }
        for asset in assets {
            scatterOf[asset] = CGPoint(x: CGFloat(rng.next(in: 160...920)),
                                       y: CGFloat(rng.next(in: 620...1440)))
            if asset == captain {
                playOf[asset] = slotPoint(slotOf[asset]!)
            } else if let idx = playIndex[asset], idx < playSlots.count {
                let base = slotPoint(playSlots[idx])
                playOf[asset] = CGPoint(x: base.x + CGFloat(rng.next(in: -42...42)),
                                        y: base.y + CGFloat(rng.next(in: -30...30)))
            } else {
                playOf[asset] = slotPoint(slotOf[asset]!)
            }
            staggerOf[asset] = rng.next(in: 0...PetConcertConst.dropStaggerMax)
            formDelayOf[asset] = rng.next(in: 0...PetConcertConst.formDelayMax)
            swayPhaseOf[asset] = rng.next(in: 0...(2 * Double.pi))
        }

        // 横屏班底（(54) U）：同算法在 11×5 网格重演（空槽
        // L/队长槽 L），散位/玩耍位用独立 seed 的 rngL 在横屏
        // 参考系内生成，与竖屏表互不影响。
        var slotsL: [Int] = []
        for row in stride(from: PetConcertConst.gridRowsL - 1, through: 0, by: -1) {
            for col in 0..<PetConcertConst.gridColsL {
                let s = row * PetConcertConst.gridColsL + col
                if PetConcertConst.emptySlotsL.contains(s) { continue }
                if row == PetConcertConst.captainSlotRowL
                    && col == PetConcertConst.captainSlotColL { continue }
                slotsL.append(s)
            }
        }
        var slotOfLandscape: [String: Int] = [
            captain: PetConcertConst.captainSlotRowL * PetConcertConst.gridColsL
                + PetConcertConst.captainSlotColL,
        ]
        for (asset, slot) in zip(fillOrder, slotsL) { slotOfLandscape[asset] = slot }
        var rngL = ConcertRNG(seed: seed ^ 0x5EED_1A2B3C4D)
        var scatterOfLandscape: [String: CGPoint] = [:]
        var playOfLandscape: [String: CGPoint] = [:]
        let playSlotsL = rngL.shuffled(slotsL)
        var playIndexL: [String: Int] = [:]
        for (i, asset) in fillOrder.enumerated() { playIndexL[asset] = i }
        for asset in assets {
            scatterOfLandscape[asset] = CGPoint(
                x: CGFloat(rngL.next(in: 240...1680)),
                y: CGFloat(rngL.next(in: 330...760)))
            if asset == captain {
                playOfLandscape[asset] = Self.slotPointLandscape(slotOfLandscape[asset]!)
            } else if let idx = playIndexL[asset], idx < playSlotsL.count {
                let base = Self.slotPointLandscape(playSlotsL[idx])
                playOfLandscape[asset] = CGPoint(
                    x: base.x + CGFloat(rngL.next(in: -55...55)),
                    y: base.y + CGFloat(rngL.next(in: -35...35)))
            } else {
                playOfLandscape[asset] = Self.slotPointLandscape(slotOfLandscape[asset]!)
            }
        }

        // 相位边界（(54) T 自适应）：首行时刻是硬顶——降落/
        // 列队/仪式全部排在 [0, firstStart) 内，绝不侵占演唱。
        // 无前奏（firstStart < 1.0）：列队压缩到最快就位，
        // 仪式整段省去。无歌词时以 5s 锚点走完整开场缺省。
        let firstStart = lines.first?.start ?? min(duration, 5)
        let noIntro = !lines.isEmpty && firstStart < PetConcertConst.introNoneThreshold
        let formAt: TimeInterval
        if noIntro {
            formAt = min(0.45, max(0.15, firstStart * 0.5))
        } else {
            formAt = min(PetConcertConst.dropNominal,
                         max(0.6, firstStart * 0.30))
        }
        // 列队落定时刻：与渲染方 basePosition 同一缩放口径
        // （k = max(0.4, formAt/formNominal×1.667)，最晚一只在
        // formAt + (延迟上限+移动时长)×k 落定）。
        let formK = max(0.4, formAt / PetConcertConst.formNominal * 1.667)
        let formationSettledAt = formAt
            + (PetConcertConst.formDelayMax + PetConcertConst.formMoveDuration) * formK
        // 仪式分配：可用 = 首行前列队落定后的余量，分档见
        // PetConcertConst.intro* 注释；greetAt/chatAt 由此定。
        let introAvail = noIntro ? 0 : max(0, firstStart - formationSettledAt)
        var greetAt: TimeInterval? = nil
        var greetingDuration: TimeInterval = 0
        var whisperDuration: TimeInterval = 0
        var introKind = "none"
        if introAvail >= PetConcertConst.introFullThreshold {
            greetAt = formationSettledAt
            greetingDuration = min(PetConcertConst.greetingNominal,
                                   introAvail * 0.45)
            whisperDuration = introAvail - greetingDuration
            introKind = "full"
        } else if introAvail >= PetConcertConst.introDualThreshold {
            greetAt = formationSettledAt
            greetingDuration = introAvail * 0.55
            whisperDuration = introAvail - greetingDuration
            introKind = "dual"
        } else if introAvail >= PetConcertConst.introGreetOnlyThreshold {
            greetAt = formationSettledAt
            greetingDuration = introAvail
            introKind = "greeting-only"
        }
        let chatAt = greetAt.map { $0 + greetingDuration } ?? firstStart
        // 间奏：全曲最大空档（行间 + 首行前不算、末行后归告别）。
        var gap: (start: TimeInterval, end: TimeInterval, intensity: Double)? = nil
        if lines.count >= 2 {
            var best: (TimeInterval, TimeInterval)? = nil
            for i in 0..<(lines.count - 1) {
                let s = lines[i].end, e = lines[i + 1].start
                if e - s >= PetConcertConst.interludeMinGap,
                   best == nil || e - s > best!.1 - best!.0 {
                    best = (s, e)
                }
            }
            if let best {
                let len = best.1 - best.0
                let intensity = len > PetConcertConst.interludeFullGap
                    ? max(PetConcertConst.interludeMinIntensity,
                          PetConcertConst.interludeFullGap / len)
                    : 1.0
                gap = (best.0, best.1, intensity)
            }
        }
        // 告别起点（(54) T：再短也不缺席）：自然起点末行
        // end+0.4；尾段不足保底 2.4s 时向前借位补足，借位
        // 上限 1.5s 且不早于末行中点（见 farewellMaxBorrow）。
        var farewellAt: TimeInterval? = nil
        if let last = lines.last, duration > last.end {
            let natural = last.end + PetConcertConst.farewellLead
            let guaranteedStart = duration - PetConcertConst.farewellMinSpan
            let borrowFloor = max(last.start + (last.end - last.start) * 0.5,
                                  last.end - PetConcertConst.farewellMaxBorrow)
            farewellAt = min(natural, max(borrowFloor, guaranteedStart))
            if farewellAt! >= duration { farewellAt = nil }
        }

        // 蛇形轮唱序：前排（row 7）起逐排向上，奇偶排交替方向，
        // 队长不参加轮唱（口令位固定）。
        var snake: [String] = []
        let bySlot: [Int: String] = Dictionary(
            uniqueKeysWithValues: slotOf.map { ($0.value, $0.key) })
        for (rowOffset, row) in stride(from: PetConcertConst.gridRows - 1,
                                       through: 0, by: -1).enumerated() {
            let cols = rowOffset % 2 == 0
                ? Array(0..<PetConcertConst.gridCols)
                : Array((0..<PetConcertConst.gridCols).reversed())
            for col in cols {
                if let asset = bySlot[row * PetConcertConst.gridCols + col],
                   asset != captain {
                    snake.append(asset)
                }
            }
        }
        // 每首 seed 偏移 + 同轮不重复：游标走完一轮才重置已用集。
        var singerByLine: [Int: String] = [:]
        var chorusLines: Set<Int> = []
        var tripsByLine: [Int: ConcertTrip] = [:]
        if !snake.isEmpty {
            var cursor = Int(seed % UInt64(snake.count))
            var usedInRound: Set<String> = []
            var previousSinger: String? = nil
            for line in lines {
                let lineDur = line.end - line.start
                if lineDur < PetConcertConst.chorusLineThreshold {
                    chorusLines.insert(line.id)
                    continue
                }
                let singer: String
                if lineDur < PetConcertConst.minSingerHold,
                   let prev = previousSinger {
                    singer = prev // 连唱：快行不换人
                } else {
                    var candidate = snake[cursor % snake.count]
                    var hops = 0
                    while usedInRound.contains(candidate), hops < snake.count {
                        cursor += 1
                        candidate = snake[cursor % snake.count]
                        hops += 1
                    }
                    if usedInRound.contains(candidate) {
                        usedInRound.removeAll()
                    }
                    singer = candidate
                    usedInRound.insert(candidate)
                    cursor += 1
                }
                singerByLine[line.id] = singer
                previousSinger = singer
                let quick = lineDur < PetConcertConst.quickLineThreshold
                let lead = quick ? PetConcertConst.leadQuick
                    : PetConcertConst.leadNormal
                let travel = quick ? PetConcertConst.travelQuick
                    : PetConcertConst.travelNormal
                tripsByLine[line.id] = ConcertTrip(
                    lineIndex: line.id, singer: singer,
                    depart: line.start - lead, arrive: line.start - lead + travel,
                    returnStart: line.end, returnEnd: line.end + travel,
                    isQuick: quick)
            }
        }

        // 呼吸块：有 YRC 词戳按词界切 ~2.4s 块；无戳按行时长
        // 均分块数、文本按字素比例切（兜底口径与 StageLyricUnits
        // 的 even 口径一致，不吃词、不省略）。
        var breathBlocksByLine: [Int: [(TimeInterval, TimeInterval, String)]] = [:]
        for line in lines {
            breathBlocksByLine[line.id] = breathBlocks(for: line)
        }

        // 交头接耳配对：按槽位序两两成对（同排相邻列优先），
        // 全员配对表供渲染方做贴近微倾；主对话对 = 前排离
        // 队长最近的一对（气泡说话人）。
        var whisperPartnerOf: [String: String] = [:]
        var whisperPairs: [(String, String)] = []
        do {
            let bySlotSorted = slotOf.sorted { $0.value < $1.value }
            var i = 0
            while i + 1 < bySlotSorted.count {
                let (aAsset, aSlot) = (bySlotSorted[i].key, bySlotSorted[i].value)
                let (bAsset, bSlot) = (bySlotSorted[i + 1].key, bySlotSorted[i + 1].value)
                if aSlot / PetConcertConst.gridCols == bSlot / PetConcertConst.gridCols,
                   bSlot - aSlot == 1 {
                    whisperPairs.append((aAsset, bAsset))
                    whisperPartnerOf[aAsset] = bAsset
                    whisperPartnerOf[bAsset] = aAsset
                    i += 2
                } else {
                    i += 1
                }
            }
        }

        // 打招呼 cue：队长先说、前排第一位（snake 首位）接
        // 一句；窗内顺序排布、互不重叠（排布器见 spreadCues）。
        var greetingCues: [ConcertChatCue] = []
        if let greetAt, greetingDuration > 0 {
            let pool = PetConcertConst.greetingLines
            let first = pool[Int(seed >> 8) % pool.count]
            var second = pool[(Int(seed >> 8) + 1) % pool.count]
            if second == first { second = pool[(Int(seed >> 8) + 2) % pool.count] }
            var speakers = [captain]
            var texts = [first]
            if greetingDuration >= 0.9, let front = snake.first {
                speakers.append(front)
                texts.append(second)
            }
            greetingCues = Self.spreadCues(
                speakers: speakers, texts: texts,
                windowStart: greetAt, windowDuration: greetingDuration,
                maxDuration: PetConcertConst.socialCueMaxDuration)
        }

        // 前奏交头接耳：主对话对用 PetChat 既有词库按 seed
        // 确定性拼装（话题/开场/回应/收尾各按 seed 取位，不
        // 用随机数，计划可复算）；cue 在耳语窗内顺序摊开、
        // 互不重叠——旧实现 cue 互相重叠且渲染只取首条，
        // 第 2/3 句实际不可见，本版消除。
        var chatCues: [ConcertChatCue] = []
        if whisperDuration > 0, let mainPair = whisperPairs.last ?? whisperPairs.first {
            let (a, b) = mainPair
            let topics = PetChatTopic.allCases
            let topic = topics[Int(seed >> 6) % topics.count]
            let persA = PetPersonalities.of(a), persB = PetPersonalities.of(b)
            var speakers: [String] = []
            var texts: [String] = []
            if let pool = PetChat.openers[persA]?[topic], !pool.isEmpty {
                speakers.append(a)
                texts.append(pool[Int(seed >> 10) % pool.count])
            }
            if let pool = PetChat.responses[persB]?[topic], !pool.isEmpty {
                speakers.append(b)
                texts.append(pool[Int(seed >> 14) % pool.count])
            }
            if whisperDuration >= 1.4,
               let pool = PetChat.closers[persA]?[topic], !pool.isEmpty {
                speakers.append(a)
                texts.append(pool[Int(seed >> 18) % pool.count])
            }
            if whisperDuration < 0.9, texts.count > 1 {
                speakers = Array(speakers.prefix(1))
                texts = Array(texts.prefix(1))
            }
            chatCues = Self.spreadCues(
                speakers: speakers, texts: texts,
                windowStart: chatAt, windowDuration: whisperDuration,
                maxDuration: PetConcertConst.socialCueMaxDuration)
        }

        // 告别＋关心 cue（顺序不重叠）：第 1 句队长向观众
        // 说再见（本地 farewellLines），第 2 句时段关心池
        // （PetLines.carePool，既有分池规则复用），第 3 句
        // 另一只说再见；窗 <1.2s 时合并为融合句单 cue，
        // 再见与关心同句不缺席。
        var farewellCues: [ConcertChatCue] = []
        if let farewellAt, !snake.isEmpty {
            let span = duration - farewellAt
            let care = PetLines.carePool(
                forHour: Calendar.current.component(.hour, from: Date()))
            let bye = PetConcertConst.farewellLines
            var speakers: [String] = []
            var texts: [String] = []
            if span < 1.2 {
                speakers = [captain]
                texts = [PetConcertConst.farewellFusedLine]
            } else {
                speakers.append(captain)
                texts.append(bye[Int(seed >> 24) % bye.count])
                if !care.isEmpty {
                    speakers.append(snake[Int(seed >> 12) % snake.count])
                    texts.append(care[Int(seed >> 20) % care.count])
                }
                if span >= 2.4 {
                    speakers.append(snake[(Int(seed >> 12) + 7) % snake.count])
                    texts.append(bye[(Int(seed >> 24) + 1) % bye.count])
                }
            }
            farewellCues = Self.spreadCues(
                speakers: speakers, texts: texts,
                windowStart: farewellAt, windowDuration: span,
                maxDuration: PetConcertConst.farewellCueMaxDuration)
        }

        // 动图池优先序按本曲 seed 旋转（跨曲轮换，准入按成本）。
        let priority = PetConcertConst.animPoolPriority
        let rot = priority.isEmpty ? 0 : Int(seed >> 4) % priority.count
        let animPriority = Array(priority[rot...]) + Array(priority[..<rot])

        return ConcertPlan(
            trackId: trackId, duration: duration, lines: lines,
            captain: captain, slotOf: slotOf,
            slotOfLandscape: slotOfLandscape,
            scatterOfLandscape: scatterOfLandscape,
            playOfLandscape: playOfLandscape,
            scatterOf: scatterOf,
            playOf: playOf, staggerOf: staggerOf, formDelayOf: formDelayOf,
            swayPhaseOf: swayPhaseOf, singerByLine: singerByLine,
            chorusLines: chorusLines, tripsByLine: tripsByLine,
            breathBlocksByLine: breathBlocksByLine, interlude: gap,
            formAt: formAt, formationSettledAt: formationSettledAt,
            greetAt: greetAt, greetingDuration: greetingDuration,
            whisperDuration: whisperDuration, introKind: introKind,
            chatAt: chatAt, firstLineStart: firstStart,
            farewellAt: farewellAt, greetingCues: greetingCues,
            chatCues: chatCues, whisperPartnerOf: whisperPartnerOf,
            farewellCues: farewellCues, animPriority: animPriority)
    }

    /// 社交 cue 排布器：窗够长时每条 maxDuration、等距摊开
    /// （留白是停顿）；窗短时等分压缩。恒顺序、恒不重叠、
    /// 恒落在窗内——任何一条都不会被同窗其他 cue 挡住。
    private static func spreadCues(speakers: [String], texts: [String],
                                   windowStart: TimeInterval,
                                   windowDuration: TimeInterval,
                                   maxDuration: TimeInterval) -> [ConcertChatCue] {
        let n = min(speakers.count, texts.count)
        guard n > 0, windowDuration > 0 else { return [] }
        var cues: [ConcertChatCue] = []
        if Double(n) * maxDuration >= windowDuration {
            let each = windowDuration / Double(n)
            for i in 0..<n {
                cues.append(ConcertChatCue(
                    asset: speakers[i], text: texts[i],
                    start: windowStart + each * Double(i),
                    end: windowStart + each * Double(i + 1)))
            }
        } else if n == 1 {
            cues.append(ConcertChatCue(
                asset: speakers[0], text: texts[0],
                start: windowStart, end: windowStart + maxDuration))
        } else {
            let span = windowDuration - maxDuration
            for i in 0..<n {
                let s = windowStart + span * Double(i) / Double(n - 1)
                cues.append(ConcertChatCue(
                    asset: speakers[i], text: texts[i],
                    start: s, end: s + maxDuration))
            }
        }
        return cues
    }

    static func slotPoint(_ slot: Int) -> CGPoint {
        let row = min(max(slot / PetConcertConst.gridCols, 0),
                      PetConcertConst.gridRows - 1)
        let col = slot % PetConcertConst.gridCols
        return CGPoint(
            x: PetConcertConst.gridX0 + CGFloat(col - 3) * PetConcertConst.gridDX,
            y: PetConcertConst.gridRowY[row])
    }

    /// 横屏槽位点（1920×1080 参考系，11×5 网格）。
    static func slotPointLandscape(_ slot: Int) -> CGPoint {
        let row = min(max(slot / PetConcertConst.gridColsL, 0),
                      PetConcertConst.gridRowsL - 1)
        let col = slot % PetConcertConst.gridColsL
        return CGPoint(
            x: PetConcertConst.gridX0L + CGFloat(col - 5) * PetConcertConst.gridDXL,
            y: PetConcertConst.gridRowYL[row])
    }

    /// 朝向分发（渲染方按容器 bounds 判定后调用）。
    static func slotPoint(_ slot: Int, landscape: Bool) -> CGPoint {
        landscape ? slotPointLandscape(slot) : slotPoint(slot)
    }

    /// 格高递推（(55) B）：格以站位点为正中，相邻格共边平
    /// 铺的充要条件是 h[r] + h[r+1] = 2×行距[r]。取首行高
    /// = 行距[0] − (行距[1] − 行距[0])/2 后递推：竖屏行距
    /// 等差（88…136）→ 格高 84, 92, …, 140，逐行恰共边、
    /// 无缝无叠、格心 = 站位点（脚本首跑曾抓出中点平铺差
    /// 2 参考 px、均值高叠 2 参考 px 两版定义，均已弃）。
    /// 横屏行距恒 110 → 格高恒 110。
    private static func cellHeights(_ ys: [CGFloat]) -> [CGFloat] {
        guard ys.count > 1 else { return [0] }
        var heights: [CGFloat] = []
        var h = ys[1] - ys[0]
        if ys.count > 2 {
            h -= ((ys[2] - ys[1]) - (ys[1] - ys[0])) / 2
        }
        heights.append(h)
        for r in 1..<ys.count {
            h = 2 * (ys[r] - ys[r - 1]) - h
            heights.append(h)
        }
        return heights
    }

    /// 格位矩形（(55) B 第 4/5 项的几何真源，脚本断言同源
    /// 复刻）：以站位点为正中、宽 = 列距、高 = cellHeights
    /// 递推行高。独唱位不在格表内（独立位，见 soloX/soloY）。
    static func slotCellRect(_ slot: Int) -> CGRect {
        let row = min(max(slot / PetConcertConst.gridCols, 0),
                      PetConcertConst.gridRows - 1)
        let center = slotPoint(slot)
        let height = cellHeights(PetConcertConst.gridRowY)[row]
        return CGRect(x: center.x - PetConcertConst.gridDX / 2,
                      y: center.y - height / 2,
                      width: PetConcertConst.gridDX, height: height)
    }

    /// 横屏格位矩形（11×5）。
    static func slotCellRectLandscape(_ slot: Int) -> CGRect {
        let row = min(max(slot / PetConcertConst.gridColsL, 0),
                      PetConcertConst.gridRowsL - 1)
        let center = slotPointLandscape(slot)
        let height = cellHeights(PetConcertConst.gridRowYL)[row]
        return CGRect(x: center.x - PetConcertConst.gridDXL / 2,
                      y: center.y - height / 2,
                      width: PetConcertConst.gridDXL, height: height)
    }

    /// 朝向分发（格位矩形）。
    static func slotCellRect(_ slot: Int, landscape: Bool) -> CGRect {
        landscape ? slotCellRectLandscape(slot) : slotCellRect(slot)
    }

    private static func breathBlocks(
        for line: LyricLine
    ) -> [(start: TimeInterval, end: TimeInterval, text: String)] {
        let duration = line.end - line.start
        guard duration > PetConcertConst.breathBlockSpan * 1.4 else {
            return [(line.start, line.end, line.text)]
        }
        if let words = line.words, !words.isEmpty {
            var blocks: [(TimeInterval, TimeInterval, String)] = []
            var blockStart = line.start
            var blockText = ""
            for (i, word) in words.enumerated() {
                blockText += word.text
                let isLast = i == words.count - 1
                if isLast || word.end - blockStart >= PetConcertConst.breathBlockSpan {
                    blocks.append((blockStart, isLast ? line.end : word.end,
                                   blockText))
                    blockStart = word.end
                    blockText = ""
                }
            }
            return blocks.isEmpty ? [(line.start, line.end, line.text)] : blocks
        }
        // 无戳兜底：按时长定块数、字素均分（整字不拆半）。
        let blockCount = max(2, Int((duration / PetConcertConst.breathBlockSpan).rounded()))
        let graphemes = Array(line.text)
        guard graphemes.count >= blockCount else {
            return [(line.start, line.end, line.text)]
        }
        var blocks: [(TimeInterval, TimeInterval, String)] = []
        for k in 0..<blockCount {
            let g0 = graphemes.count * k / blockCount
            let g1 = graphemes.count * (k + 1) / blockCount
            let t0 = line.start + duration * Double(k) / Double(blockCount)
            let t1 = line.start + duration * Double(k + 1) / Double(blockCount)
            blocks.append((t0, t1, String(graphemes[g0..<g1])))
        }
        return blocks
    }
}
