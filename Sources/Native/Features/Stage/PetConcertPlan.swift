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

    // MARK: 队形（v3 layout：7 列 × 8 行，队长 front-center）
    static let gridCols = 7
    static let gridRows = 8
    /// 列 x = 540 + (c−3)×132；行 y = 640 + r×116（参考 px）。
    static let gridX0: CGFloat = 540
    static let gridDX: CGFloat = 132
    static let gridY0: CGFloat = 640
    static let gridDY: CGFloat = 116
    /// 空槽（v3 EMPTY）：后排三处留空透气。
    static let emptySlots: Set<Int> = [0 * 7 + 0, 0 * 7 + 3, 0 * 7 + 6]
    /// 队长槽（行 7、列 3，前排正中）。
    static let captainSlotRow = 7
    static let captainSlotCol = 3
    /// 宠物基准边长（参考 px，fit-box 口径）。
    static let petBase: CGFloat = 124
    static let captainScale: CGFloat = 1.6

    // MARK: 独唱跑位（v2/v3 定版）
    /// 独唱位（参考 px），渲染方按舞台尺寸等比换算。
    static let soloX: CGFloat = 540
    static let soloY: CGFloat = 1560
    static let soloScale: CGFloat = 1.9
    /// 贝塞尔控制点 = 起终点中点 + y −120（参考 px，向上拱）。
    static let bezierLift: CGFloat = 120
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
    /// 告别相位起点 = 末行 end + 0.4（且至少留 1.2s 才成立）。
    static let farewellLead: TimeInterval = 0.4
    static let farewellMinSpan: TimeInterval = 1.2

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
    /// 侧幕内缘基准：收拢 x=566 → 拉开 x=126（参考 px，自左缘量）。
    static let curtainClosedX: CGFloat = 566
    static let curtainOpenX: CGFloat = 126
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
    static let footlightY: CGFloat = 1730       // 参考 px
    static let floorTopY: CGFloat = 556         // 参考 px
    /// 独唱位金色脚圈：中心 (540, 1656)、半径 (152, 34)。
    static let soloRingY: CGFloat = 1656

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
    case preludeChat // 前奏闲聊
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
    let chatAt: TimeInterval
    let firstLineStart: TimeInterval
    let farewellAt: TimeInterval?
    let chatCues: [ConcertChatCue]
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
        if t >= chatAt { return .preludeChat }
        if t >= formAt { return .formation }
        return .dropping
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

        // 相位边界（首行越早、压缩越狠；无歌词时全程降落→列队→告别缺省）。
        let firstStart = lines.first?.start ?? min(duration, 5)
        let formAt = min(PetConcertConst.dropNominal,
                         max(0.6, firstStart * 0.30))
        let chatAt = min(PetConcertConst.formNominal,
                         max(formAt + 0.3, firstStart * 0.55))
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
        var farewellAt: TimeInterval? = nil
        if let last = lines.last,
           duration - (last.end + PetConcertConst.farewellLead)
               >= PetConcertConst.farewellMinSpan {
            farewellAt = last.end + PetConcertConst.farewellLead
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

        // 前奏闲聊：两个人格对话（PetChat 拼装，种子句逐字在库
        // 内），cue 时刻在 [chatAt, firstStart) 内均布；窗口太
        // 短则只留第一句。
        var chatCues: [ConcertChatCue] = []
        let chatWindow = firstStart - chatAt
        if chatWindow >= 0.8, snake.count >= 2 {
            let a = snake[Int(seed >> 8) % snake.count]
            var b = snake[(Int(seed >> 16) + 3) % snake.count]
            if b == a { b = snake[(snake.firstIndex(of: a)! + 1) % snake.count] }
            let dialogue = PetChat.generate(
                a: PetPersonalities.of(a), b: PetPersonalities.of(b))
            let texts: [(String, String)] = dialogue.lines.map {
                ($0.speakerIsA ? a : b, $0.text)
            }
            let step = chatWindow / Double(texts.count + 1)
            for (i, cue) in texts.enumerated() {
                let s = chatAt + step * Double(i + 1) - 0.3
                chatCues.append(ConcertChatCue(
                    asset: cue.0, text: cue.1,
                    start: max(chatAt, s), end: min(firstStart, s + 0.75)))
            }
        }

        // 告别关心话：时段关心池（PetLines.carePool）取 3 句，
        // seed 定序，落三只不同宠物，告别窗内均布。
        var farewellCues: [ConcertChatCue] = []
        if let farewellAt {
            let span = duration - farewellAt
            let pool = PetLines.carePool(
                forHour: Calendar.current.component(.hour, from: Date()))
            if !pool.isEmpty, !snake.isEmpty {
                let offset = Int(seed >> 24) % pool.count
                for k in 0..<min(3, pool.count) {
                    let asset = snake[(Int(seed >> 12) + k * 7) % snake.count]
                    let s = farewellAt + span * Double(k + 1) / 4.0
                    farewellCues.append(ConcertChatCue(
                        asset: asset, text: pool[(offset + k) % pool.count],
                        start: s, end: min(duration, s + 1.05)))
                }
            }
        }

        // 动图池优先序按本曲 seed 旋转（跨曲轮换，准入按成本）。
        let priority = PetConcertConst.animPoolPriority
        let rot = priority.isEmpty ? 0 : Int(seed >> 4) % priority.count
        let animPriority = Array(priority[rot...]) + Array(priority[..<rot])

        return ConcertPlan(
            trackId: trackId, duration: duration, lines: lines,
            captain: captain, slotOf: slotOf, scatterOf: scatterOf,
            playOf: playOf, staggerOf: staggerOf, formDelayOf: formDelayOf,
            swayPhaseOf: swayPhaseOf, singerByLine: singerByLine,
            chorusLines: chorusLines, tripsByLine: tripsByLine,
            breathBlocksByLine: breathBlocksByLine, interlude: gap,
            formAt: formAt, chatAt: chatAt, firstLineStart: firstStart,
            farewellAt: farewellAt, chatCues: chatCues,
            farewellCues: farewellCues, animPriority: animPriority)
    }

    static func slotPoint(_ slot: Int) -> CGPoint {
        let row = slot / PetConcertConst.gridCols
        let col = slot % PetConcertConst.gridCols
        return CGPoint(
            x: PetConcertConst.gridX0 + CGFloat(col - 3) * PetConcertConst.gridDX,
            y: PetConcertConst.gridY0 + CGFloat(row) * PetConcertConst.gridDY)
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
