import Foundation

/// (77) ⑩灵动岛宠物专属对话引擎（Miller 23:12/23:14 定
/// 版）：app 外展开岛与锁屏面的台词线。app 在后台活着时
/// 由 IslandLiveActivityManager 以 45 秒一拍推进一句，
/// 每次推进与让位/夺回合并为同一发 Activity update，不
/// 单独高频发更新；暂停/挂起/回前台即停拍，台词停在最
/// 后一句、不伪造推进。
///
/// 一轮（chain）的编排（Miller 定）：①自嘲开场链（定稿
/// 四句逐字、顺序与说话者锁定）→ ②聊当前这首歌（模板
/// 句、歌名/歌手按推进到该段时的当前曲目动态填入，换
/// 歌即换内容）→ ③对主人一句关心话（复用点播台按时段
/// 分池的 PetLines.carePool）→ ④通用五人格词库垫场
/// （PetChat.generate 按左右住客人格拼链）。演完起新
/// 轮、链号 +1。每句带说话侧（isLeft）——呈现侧据此把
/// 台词放在说话者一侧（展开岛底行/锁屏行按侧对齐），
/// compact 与 minimal 不放文字。
///
/// 说话者口径：自嘲链按侧位演（左位说猫的句子、右位说
/// 狗的句子）——缺省住客正是猫左狗右、与定稿一致；住
/// 客被拖拽换位时按侧位续演（台词是岛上岗位的词，不是
/// 个体的词）。风格守 Miller 口径：幽默、装可怜、互相
/// 甩锅、短句口语、不煽情。
final class IslandDialogue77 {

    struct Line {
        let isLeft: Bool
        let text: String
        /// 段名（script/song/care/filler），la.say77 落痕用。
        let phase: String
    }

    /// 当前轮号（从 1 起；0 = 尚未开链）。
    private(set) var chainId = 0
    /// 本轮已递出的句数（la.say77 step）。
    private(set) var step = 0
    /// 当前停在岛上的那句（makeState 唯一读口）。
    private(set) var current: Line?
    private var pending: [Line] = []
    /// 当前段：0 自嘲 / 1 聊歌 / 2 关心 / 3 垫场。
    private var phaseIndex = 0

    // MARK: - 定稿自嘲链（Miller 23:14 亲拟，逐字不许改）

    static let scriptLines: [Line] = [
        Line(isLeft: true,  text: "哎，我们怎么不能动了", phase: "script"),
        Line(isLeft: false, text: "我也不知道，去问问主人吧", phase: "script"),
        Line(isLeft: true,  text: "主人怎么回事，快救救我啊，我想跳舞", phase: "script"),
        Line(isLeft: false, text: "是啊，主人，我被卡着好难受，头都被卡爆了", phase: "script"),
    ]

    // MARK: - 推进

    /// 开链并递出第一句（活动拉起时调；已开链返回 nil）。
    func startIfNeeded() -> Line? {
        guard chainId == 0 else { return nil }
        beginChain()
        return deliverNext()
    }

    /// 推进一句（节拍到点时由协调器调）。
    @discardableResult
    func advance() -> Line? {
        if chainId == 0 { return startIfNeeded() }
        return deliverNext()
    }

    /// 汪汪队期间台词线关闭：整机复位，下次拉起从新轮
    /// 自嘲链重开（活动本就已 end、口径一致）。
    func reset() {
        chainId = 0
        step = 0
        current = nil
        pending = []
        phaseIndex = 0
    }

    /// 换歌：正处聊歌段时按新曲目重建本段余句（换歌即
    /// 换内容）；其他段不受影响。
    func trackChanged() {
        if phaseIndex == 1 { pending = Self.songLines() }
    }

    private func beginChain() {
        chainId += 1
        step = 0
        phaseIndex = 0
        pending = Self.scriptLines
    }

    private func deliverNext() -> Line? {
        while pending.isEmpty {
            phaseIndex += 1
            if phaseIndex > 3 {
                beginChain()
            } else {
                pending = linesForPhase(phaseIndex)
            }
        }
        let line = pending.removeFirst()
        current = line
        step += 1
        return line
    }

    private func linesForPhase(_ phase: Int) -> [Line] {
        switch phase {
        case 1: return Self.songLines()
        case 2: return careLines()
        case 3: return Self.fillerLines()
        default: return Self.scriptLines
        }
    }

    // MARK: - ②聊当前这首歌（模板，动态填入）

    private static func songLines() -> [Line] {
        guard let track = PlaybackEngine.shared.currentTrack
        else { return [] }
        let title = track.title
        let artist = track.artist
        if artist.isEmpty {
            return [
                Line(isLeft: true,  text: "《\(title)》，这首我在听", phase: "song"),
                Line(isLeft: false, text: "嗯，别切，我喜欢这首", phase: "song"),
            ]
        }
        let pairs: [[Line]] = [
            [Line(isLeft: true,  text: "《\(title)》，这首我在听", phase: "song"),
             Line(isLeft: false, text: "\(artist) 唱的，记下了", phase: "song")],
            [Line(isLeft: true,  text: "现在放的是《\(title)》", phase: "song"),
             Line(isLeft: false, text: "嗯，别切，我喜欢这首", phase: "song")],
            [Line(isLeft: true,  text: "\(artist) 这首可以啊", phase: "song"),
             Line(isLeft: false, text: "同意，先单曲循环它", phase: "song")],
        ]
        return pairs.randomElement() ?? pairs[0]
    }

    // MARK: - ③对主人的关心句（时段分池，左右轮值）

    private func careLines() -> [Line] {
        let hour = Calendar.current.component(.hour, from: Date())
        let pool = PetLines.carePool(forHour: hour)
        guard let text = pool.randomElement() else { return [] }
        // 说话侧按轮号轮值：奇数轮左位、偶数轮右位。
        return [Line(isLeft: chainId % 2 == 1, text: text, phase: "care")]
    }

    // MARK: - ④通用人格词库垫场

    private static func fillerLines() -> [Line] {
        let duo = PetHomeRegistry.shared.islandTargetDuo
        let a = PetPersonalities.of(duo.first ?? "cat-live")
        let b = PetPersonalities.of(
            duo.count > 1 ? duo[1] : "dog-11")
        let dialogue = PetChat.generate(a: a, b: b)
        return dialogue.lines.map {
            Line(isLeft: $0.speakerIsA, text: $0.text, phase: "filler")
        }
    }
}
