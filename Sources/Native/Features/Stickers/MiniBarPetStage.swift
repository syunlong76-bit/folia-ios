import UIKit

// 迷你台宠物层（3.7 (27)，Miller 22:15 附图纠正主场 + 22:23
// 流转改版 + 22:24 升降衔接）：表情包互动的主场是墙面底部
// 的迷你台（播放台），不是舞台歌词框——(25) 的舞台框内陪
// 伴已按 Miller 定案整体删除，宠物/台词/解码基建迁来此处
// 复用。本层是纯新增覆盖层，骑在迷你台之上：
//
// - 台上玩耍：展开态（70pt 胶囊）时宠物站在台面顶部一带
//   （Miller 附图红线所示上沿）沿一线走动：常驻 1 只（按曲
//   轮换，狗池为主、每 5 首猫客串）+ 嘉宾 1 只（未露面者
//   优先的全池轮换，约 18s 一换）。
// - 升降衔接（22:24 定案）：宠物吸附在台面运动坐标上——
//   地面（台上沿）逐帧读迷你台演示层帧，台子展开/收起走
//   什么曲线（现行 0.5s、弹簧 damping 0.85、easeOut），宠
//   物就走什么曲线、同时长，不瞬移、不另走一条线。收起时
//   随沉到底、展开时随台升回。
// - 告别流转（22:23 定案）：展开台宠物随沉落地后，逐个弹
//   告别气泡说一句离开词再淡出消失（不是留在条上）。随后
//   进度条上换「未露面者」批次上场：一次 5–8 只小宠物沿
//   条活动/玩耍/互聊，一批约 40s 后逐个说离开词退场，下
//   一批未露面者优先补位；53 只全露过面后重置名单转全池
//   轮换（名单跨启动持久）。展开时条上宠物随台升起，落定
//   后班底重整为台上规格（常驻 + 一位嘉宾），其余淡出。
// - 语言系统：与 (25) 同一套交互语法与台词库（PetLines 为
//   唯一真源）——点头顶冒反应小贴纸（1.5s 淡出）、点本体
//   弹对话框（被点贴纸本体 + 一句台词，点气泡/点别处关、
//   5s 自动关）、长按 0.35s 拖动安置（停在落点、不参加漫
//   游与编排，直到切歌/形态切换）。宠物之间自主互动沿
//   (25) 编排：相遇打招呼一问一答、追逐，约每 10–16s 一
//   轮；气泡不压台上控件（都在台面之上的墙面空区）。
// - 关心用户（22:23 新增）：宠物不时冒关心气泡（按时段
//   分池：早/午/下午/晚/深夜），点气泡出回应选项（摸摸
//   头/亲亲/抱抱），点选后宠物冒对应反应贴纸 + 回一句开
//   心的话，随后收起。
// - 开关：设置页「迷你台小宠物」（StickerSettings.
//   miniPetsEnabled——(29) 起的宠物专用新键；旧键
//   companionEnabled 曾被 (24)/(25) 两个无提示手势静默
//   写 false、(27) 沿用同键被关死，DS R45 定案后分家、
//   不继承旧值）统管本层；关掉时台上与条上宠物全停
//   （整层隐藏、演员清空）。
// - 触摸面：hitTest 只认领宠物本体、对话框、关心气泡与
//   选项按钮，其余全部透传（点细条展开、台上按键、拖墙
//   平移零影响）。
// - 帧/解码：沿用 StickerView/StickerStore（80MB 共享解码
//   缓存）；本层同时存活的 StickerView 上限 = 演员 8（条
//   上批次）+ 对话框 1 + 反应 ≤2 + 关心回话贴纸 1 ≈ 12。
// - 状态只读 PlaybackEngine，不回写播放状态机；暂停时帧
//   冻结、走动与编排时钟停摆（吸附与批次墙钟照常结算）。

// MARK: - 迷你台宠物演员

private final class MiniPetActor: UIView {
    let stickerView = StickerView()
    private(set) var asset: String = ""
    var isCat: Bool { asset.hasPrefix("cat") }
    /// 安置中（长按拖动落位）：不参加漫游与互动编排。
    var placed = false
    /// 朝向：1 = 素材原向，-1 = 整只水平镜像。
    var facing: CGFloat = 1
    var hopStart: TimeInterval = -1

    enum Mode {
        case idle, walk, peek, meetWalk, meetArrived, meetHold
        case flee, pursue, dragged, farewell
    }
    var mode: Mode = .idle
    var targetX: CGFloat = 0
    var until: TimeInterval = 0

    weak var stage: MiniBarPetStage?

    init(asset: String, size: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        stickerView.frame = bounds
        stickerView.crumbScene = "minibar-pet"
        stickerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stickerView)
        setAsset(asset)
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(
            target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.35
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setAsset(_ name: String) {
        asset = name
        stickerView.setSticker(name, mode: .loop)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let head = point.y < bounds.height * 0.42
        stage?.petTapped(self, head: head)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard let stage else { return }
        let point = gesture.location(in: stage)
        switch gesture.state {
        case .began: stage.petDragBegan(self)
        case .changed: stage.petDragChanged(self, to: point)
        case .ended: stage.petDragEnded(self, at: point)
        case .cancelled, .failed: stage.petDragCancelled(self)
        default: break
        }
    }

    /// 朝向 + 蹦跳位移合成（与 (25) 同口径：整只镜像是允许
    /// 的朝向编排，蹦跳只是位移，不改帧）。
    func applyTransform(hopOffset: CGFloat) {
        stickerView.transform = CGAffineTransform(
            a: facing, b: 0, c: 0, d: 1, tx: 0, ty: -hopOffset)
    }

    /// 脚底 y（本层坐标）。
    var feetY: CGFloat {
        get { center.y + bounds.height / 2 }
        set { center.y = newValue - bounds.height / 2 }
    }
}

// MARK: - 台词库（生活口吻，猫狗分声口；纯 UI 文案）
// 原 (25) CompanionPetView 内的台词真源，(27) 随主场迁到
// 此处并扩充离开词与关心词；内容与声口以此为唯一出处。

enum PetLines {
    static let catSingles = [
        "这首我听过，勉强入耳。",
        "别光听歌，记得喝水。",
        "我刚睡醒，陪你听一会儿。",
        "今天风不错，适合发呆。",
        "你晚饭吃了没？别饿着。",
        "听完这首，早点去洗澡。",
        "我尾巴有点痒……没事了。",
        "周末就该这么躺着听歌。",
        "这旋律，让我想小睡一下。",
        "你看起来有点累，靠一会儿吧。",
        "嗯？叫我？……没事就好。",
        "歌不错，勉强给你点个赞。",
    ]
    static let dogSingles = [
        "这首好听！我尾巴都摇起来了！",
        "你回来啦！等你好久了！",
        "听歌听歌！我陪着你！",
        "今天天气好，适合出去跑一圈！",
        "你吃饭了吗？我刚吃饱！",
        "累了就休息，我守着你。",
        "这首我喜欢！再听一遍吧！",
        "晚上别熬太晚，早点睡哦。",
        "我刚打了个盹，精神好多了。",
        "有你在，放什么歌都好听。",
        "要不要起来活动一下，坐太久啦。",
        "嘿嘿，被你发现我了。",
    ]
    /// 猫问狗答。
    static let catAsksDog: [(String, String)] = [
        ("你怎么又这么精神？", "因为你在听歌呀，我就开心！"),
        ("晚饭吃什么好呢……", "肉！肯定吃肉！你也多吃点。"),
        ("今天好累，只想躺着。", "那我陪你躺，啥也不干。"),
        ("外面好像要下雨了。", "下雨天在家听歌，最好不过了。"),
        ("你说，周末干点什么？", "睡个懒觉，再出去散步！"),
        ("这首歌，听得我想睡了。", "睡吧睡吧，我帮你守着歌单。"),
        ("都十点了，还不困？", "再听一首！最后一首！"),
        ("你刚是不是偷吃东西了？", "就一小口……你也来点？"),
        ("洗澡去吧，别拖了。", "知道啦，你先去，我殿后。"),
        ("今天天气，适合出门吗？", "适合！阳光刚好，不冷不热。"),
        ("怎么才能不犯困呢？", "起来走两圈，或者……吃点东西！"),
    ]
    /// 狗问猫答。
    static let dogAsksCat: [(String, String)] = [
        ("你今天怎么不理我？", "在听歌呢……现在理你了。"),
        ("晚饭吃鱼好不好？", "……勉强可以，多给我留点。"),
        ("出去玩吗出去玩吗？", "等这首听完，陪你走一圈。"),
        ("你冷不冷？我靠过来点。", "……随你吧，就一会儿。"),
        ("明天要早起吗？", "能睡多晚睡多晚，别问了。"),
        ("我学会新本事了，看不看？", "哦？……那你表演一下。"),
        ("这首歌你喜欢吗？", "还行吧，循环三遍了都。"),
        ("你肚子饿不饿？", "有点。去看看冰箱里有什么。"),
        ("晚上吃什么夜宵？", "小鱼干就行，别整太油腻。"),
        ("你怎么总这么淡定？", "急也没用，不如听歌。"),
        ("陪我玩一会儿嘛！", "……就五分钟，计时开始。"),
    ]

    // MARK: 离开词（(27) 新增；种子三句为 Miller 原话，猫狗各 8 句）

    static let farewellCat = [
        "我妈叫我回家吃饭了",
        "我要睡觉了，晚安",
        "我要去上厕所了",
        "我去睡个回笼觉，先走了",
        "窗台的太阳在等我，我去晒会儿",
        "我饿了，去看看碗里有啥",
        "今天的巡逻结束了，明天见",
        "我去磨磨爪子，回头见",
    ]
    static let farewellDog = [
        "我妈叫我回家吃饭了",
        "我要睡觉了，晚安",
        "我要去上厕所了",
        "我去门口看看有没有快递",
        "我得去埋我的骨头了，先撤",
        "晚饭时间到了，我先走一步",
        "我去院子里跑两圈，明天见",
        "困了困了，我去窝里睡了",
    ]

    // MARK: 关心词（(27) 新增；按时段分池，种子句在各池内）

    static let careMorning = [
        "今天你累不累啊，昨晚睡好了没",
        "早上好呀，先喝杯水再听歌",
        "早饭吃了没？不吃早饭可不行",
        "新的一天，我陪你一起开始",
    ]
    static let careNoon = [
        "今天有没有好好吃饭",
        "午饭想吃什么？我陪你想想",
        "吃完饭歇一会儿，别急着忙",
        "今天你累不累啊，要不要眯一会儿",
    ]
    static let careAfternoon = [
        "今天我给你捏捏肩",
        "下午容易困，起来走两圈吧",
        "喝口水，眼睛也休息一下",
        "坐一下午了，肩膀僵不僵",
    ]
    static let careEvening = [
        "今天你累不累啊",
        "今天辛苦啦，晚饭要吃好一点",
        "洗个热水澡，解解乏吧",
        "晚饭有没有好好吃？别凑合",
    ]
    static let careLateNight = [
        "都这么晚了，早点睡吧",
        "这首听完就睡，好不好",
        "我要睡觉了，晚安……你也快睡",
        "深夜了，我陪你，但只能陪一小会儿哦",
    ]

    static func carePool(forHour hour: Int) -> [String] {
        switch hour {
        case 5..<10: return careMorning
        case 10..<14: return careNoon
        case 14..<18: return careAfternoon
        case 18..<23: return careEvening
        default: return careLateNight
        }
    }

    // MARK: 关心回应（点选项后宠物回的开心话；选项序：0 摸摸头 / 1 亲亲 / 2 抱抱）

    static func careReplies(option: Int, isCat: Bool) -> [String] {
        switch (option, isCat) {
        case (0, true): return ["嗯……就摸一下哦。", "好啦好啦……舒服。", "摸头会长不高的……算了，继续吧。"]
        case (0, false): return ["嘿嘿，最喜欢摸头了！", "再摸一下，再摸一下！", "被摸头了，开心！"]
        case (1, true): return ["哎呀……偷袭我。", "亲、亲到了……", "哼，只许这一次哦。"]
        case (1, false): return ["亲到了！我也亲你！", "嘿嘿嘿，害羞……", "最喜欢你啦！"]
        case (2, true): return ["……就抱一小会儿。", "好暖和……不想动了。", "抱紧一点，风大。"]
        default: return ["抱抱！充电完成！", "呜呜，你最好了！", "抱着你就不累啦！"]
        }
    }
}

// MARK: - 迷你台宠物层（管理器）

final class MiniBarPetStage: UIView {

    /// 覆盖层总高：展开台高 70 + 台面上方活动带 176。地面
    /// （台上沿）在本层坐标里逐帧由台子演示层帧推导（见
    /// currentGroundY），本常量只定层框。
    private static let overlayHeight: CGFloat = 246
    private static let expandedPetSize: CGFloat = 48
    private static let collapsedPetSize: CGFloat = 30
    private static let expandedCast = 2
    /// 台子形态动画时长（现行值 0.5s）；宠物落定处理在动
    /// 画走完后 0.05s 触发，衔接不抢跑。
    private static let formSettleDelay: TimeInterval = 0.55
    private static let batchDuration: TimeInterval = 40

    private static let fullPool: [String] =
        (1...25).map { String(format: "cat-%02d", $0) } + ["cat-live"]
        + (1...27).map { String(format: "dog-%02d", $0) }
    private static let residentDogPool =
        ["dog-01", "dog-15", "dog-18", "dog-19", "dog-23", "dog-25"]
    private static let reactionPool =
        ["dog-11", "cat-15", "dog-25", "cat-01", "dog-20", "cat-24", "dog-17"]
    /// 关心回应选项 → 头顶反应贴纸（猫/狗）：0 摸摸头、
    /// 1 亲亲、2 抱抱。
    private static let careReactionAssets: [[String]] = [
        ["cat-15", "dog-25"],
        ["cat-24", "dog-11"],
        ["cat-01", "dog-20"],
    ]
    private static let careOptionTitles = ["摸摸头", "亲亲", "抱抱"]
    private static let seenKey = "folia.minipets.seenAssets"

    private weak var bar: UIView?
    private var barPresented = false
    private var collapsed = false
    /// 开关开且班底在场（与 isHidden 分工：关开关时清空班底）。
    private var petsActive = false

    private var resident: MiniPetActor?
    private var guests: [MiniPetActor] = []
    private var allActors: [MiniPetActor] {
        (resident.map { [$0] } ?? []) + guests
    }

    /// 已露面名单（跨启动持久）：未露面者优先上场，全员露
    /// 过面后在下一次取人时重置。
    private var seenAssets: Set<String> = []
    /// 批次待入场名单（错峰 0.22s 一只）。
    private var pendingSpawns: [(asset: String, at: TimeInterval)] = []
    private var batchActive = false
    private var batchEndsAt: TimeInterval = 0

    /// 形态切换的落定处理（台子动画走完后执行）：收起 →
    /// 告别流；展开 → 班底重整。
    private var pendingForm: (collapsed: Bool, at: TimeInterval)?

    /// 告别流：逐个弹离开词气泡再淡出；代际号用于作废已
    /// 排期的异步淡出（形态/显隐翻转时整流取消）。
    private var farewellQueue: [MiniPetActor] = []
    private var farewellNextAt: TimeInterval = 0
    private var farewellActive = false
    private var farewellRemaining = 0
    private var afterFarewell: (() -> Void)?
    private var flowGeneration = 0
    private var transientBubbles: [UILabel] = []

    private var displayLink: CADisplayLink?
    private var lastTimestamp: TimeInterval = 0
    /// pet.tick.heartbeat 节流锚（3.7 (29)）。
    private var lastHeartbeatAt: TimeInterval = 0
    /// 墙钟：恒前进（批次/告别/关心过期用）。
    private var clockTime: TimeInterval = 0
    /// 编排时钟：只在播放中前进（走动/编排/轮换/关心触发用）。
    private var activeTime: TimeInterval = 0
    private var wasPlaying = false
    private var framesRunning = false

    private var trackSerial = 0
    private var lastTrackId: String?
    private var guestRotateAt: TimeInterval = 0
    private var nextInteractionAt: TimeInterval = 6
    private var scriptKind: ScriptKind = .meet
    private var scriptRunningKind: ScriptKind = .meet
    private var scriptPair: (MiniPetActor, MiniPetActor)?
    private var scriptUntil: TimeInterval = 0
    private var lastPairIndex = -1
    private var lastSingleIndex: [Bool: Int] = [:]
    private var lastFarewellIndex: [Bool: Int] = [:]
    private var lastCareIndex = -1

    private var bubbleA: UILabel?
    private var bubbleB: UILabel?
    private var bubblePairUntil: TimeInterval = 0

    private var dialogView: UIView?
    private var dialogSticker: StickerView?
    private var dialogOwner: MiniPetActor?
    private var dialogTimer: Timer?

    private var reactionViews: [ObjectIdentifier: StickerView] = [:]

    // 关心用户系统
    private var carePet: MiniPetActor?
    private var careBubbleView: UIView?
    private var careLabel: UILabel?
    private var careOptionsView: UIView?
    private var careShownAt: TimeInterval = 0
    private var careOptionsShown = false
    private var nextCareAt: TimeInterval = 25

    private enum ScriptKind { case meet, chase }

    /// 对话框点别处关闭（挂到宿主墙根视图；不取消触摸，与
    /// (25) 在舞台根视图上的做法同构）。
    private lazy var dismissTapRecognizer: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(handleDismissTap))
        tap.cancelsTouchesInView = false
        return tap
    }()

    init(bar: UIView) {
        self.bar = bar
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isHidden = true
        seenAssets = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        displayLink?.invalidate()
        dialogTimer?.invalidate()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if let host = superview {
            host.addGestureRecognizer(dismissTapRecognizer)
        }
    }

    // MARK: 墙侧钩子（一行级订阅：显隐/形态/切歌边沿）

    /// 迷你台显隐边沿（setMiniBarVisible 内一行钩子）。
    func barPresentationChanged(_ presented: Bool) {
        // 开关双键留痕（3.7 (29)）：新键决定本层生死，旧键只为
        // 诊断毒丸键是否仍在设备上留值。
        Breadcrumbs.log("pet.settings.read src=barPresentation presented=\(presented)"
            + " miniPets=\(StickerSettings.miniPetsEnabled)"
            + " legacyCompanion=\(StickerSettings.companionEnabled)")
        barPresented = presented
        if presented {
            // 台子每次出现必是完整形态（resetMiniBarFormInstant
            // 保证），宠物层形态同步复位展开态。
            collapsed = false
            cancelFlow()
            startLink()
            if StickerSettings.miniPetsEnabled {
                isHidden = false
                petsActive = true
                syncFrame()
                ensureExpandedCast()
            } else {
                isHidden = true
                petsActive = false
            }
        } else {
            stopLink()
            cancelFlow()
            clearCast()
            hideDialog()
            hideBubbles()
            closeCare()
            isHidden = true
            petsActive = false
        }
    }

    /// 迷你台形态边沿（collapseMiniBarIdle/expandMiniBar 内
    /// 一行钩子）。台子自身的计时与动画本层不碰：宠物吸附
    /// 台面随行，动画落定后才走告别/重整流程。
    func barFormChanged(collapsed newValue: Bool) {
        guard barPresented, newValue != collapsed else { return }
        collapsed = newValue
        cancelFlow()
        hideDialog()
        hideBubbles()
        closeCare()
        scriptPair = nil
        pendingSpawns.removeAll()
        batchActive = false
        pendingForm = (newValue, clockTime + Self.formSettleDelay)
    }

    /// 切歌边沿（refreshMiniBar 内一行钩子）：常驻宠物按曲
    /// 轮换（狗池为主、每 5 首猫客串），在场宠物探头 + 小
    /// 跳；安置标志清除，座位不跨曲。收起态批次不受影响。
    func setTrack(id: String) {
        guard id != lastTrackId else { return }
        lastTrackId = id
        trackSerial += 1
        guard barPresented, petsActive else { return }
        if let resident {
            let asset = trackSerial % 5 == 0
                ? "cat-09"
                : Self.residentDogPool[trackSerial % Self.residentDogPool.count]
            if resident.asset != asset {
                resident.setAsset(asset)
                seenAssets.insert(asset)
                persistSeen()
            }
        }
        for actor in allActors { actor.placed = false }
        if PlaybackEngine.shared.isPlaying {
            for actor in allActors where actor.mode != .dragged {
                actor.mode = .peek
                actor.until = activeTime + 0.9
                actor.facing = actor.center.x <= bounds.midX ? 1 : -1
                actor.hopStart = activeTime
            }
        }
    }

    // MARK: 触摸认领（只认宠物/对话框/关心 UI，其余透传）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        for sub in subviews.reversed() {
            guard !sub.isHidden, sub.isUserInteractionEnabled else { continue }
            let converted = sub.convert(point, from: self)
            if let hit = sub.hitTest(converted, with: event) { return hit }
        }
        return nil
    }

    // MARK: 层框与地面

    /// 层框跟随台子模型帧（底边对齐、等宽）；地面（台上
    /// 沿）逐帧读台子演示层帧——台子展开/收起走的是系统
    /// 弹簧演示曲线，宠物吸附其上即同曲线同时长。
    private func syncFrame() {
        guard let bar, superview != nil else { return }
        let model = bar.frame
        let target = CGRect(
            x: model.minX,
            y: model.maxY - Self.overlayHeight,
            width: model.width,
            height: Self.overlayHeight)
        if frame != target { frame = target }
    }

    private func currentGroundY() -> CGFloat {
        guard let bar else { return bounds.height }
        let pres = bar.layer.presentation()?.frame ?? bar.frame
        return pres.minY - frame.minY
    }

    private func petSizeNow() -> CGFloat {
        collapsed ? Self.collapsedPetSize : Self.expandedPetSize
    }

    private func walkRange(for actor: MiniPetActor) -> ClosedRange<CGFloat> {
        let half = actor.bounds.width / 2
        let lo = half + 6
        let hi = max(lo + 1, bounds.width - half - 6)
        return lo...hi
    }

    // MARK: 取人（未露面者优先，全员露面后重置名单）

    private func pickAssets(count: Int, excluding: Set<String>) -> [String] {
        var unavailable = excluding
        var picked: [String] = []
        if seenAssets.count >= Self.fullPool.count {
            seenAssets.removeAll()
            persistSeen()
        }
        let unseen = Self.fullPool.filter {
            !seenAssets.contains($0) && !unavailable.contains($0)
        }.shuffled()
        for asset in unseen {
            guard picked.count < count else { break }
            picked.append(asset)
            unavailable.insert(asset)
        }
        if picked.count < count {
            let rest = Self.fullPool.filter {
                !unavailable.contains($0)
            }.shuffled()
            for asset in rest {
                guard picked.count < count else { break }
                picked.append(asset)
                unavailable.insert(asset)
            }
        }
        for asset in picked { seenAssets.insert(asset) }
        persistSeen()
        return picked
    }

    private func persistSeen() {
        UserDefaults.standard.set(Array(seenAssets), forKey: Self.seenKey)
    }

    // MARK: 班底（展开台规格 / 进度条批次）

    /// pet.guard.block 节流（3.7 (29)）：同一原因 5 秒内只记
    /// 一行（tick 会高频重试 ensure，防刷屏），走 crumb 通道。
    private var guardBlockLast: [String: CFTimeInterval] = [:]
    private func noteGuardBlock(_ reason: String) {
        let now = CACurrentMediaTime()
        if let last = guardBlockLast[reason], now - last < 5 { return }
        guardBlockLast[reason] = now
        Breadcrumbs.log("pet.guard.block reason=\(reason)")
    }

    private func makeActor(asset: String) -> MiniPetActor {
        let actor = MiniPetActor(asset: asset, size: petSizeNow())
        actor.stage = self
        addSubview(actor)
        return actor
    }

    private func ensureExpandedCast() {
        if !barPresented { noteGuardBlock("ensure.barNotPresented"); return }
        if bounds.width <= 40 { noteGuardBlock("ensure.stageTooNarrow"); return }
        let castBefore = allActors.map { $0.asset }
        if resident == nil {
            let asset = Self.residentDogPool[
                trackSerial % Self.residentDogPool.count]
            let actor = makeActor(asset: asset)
            actor.center = CGPoint(x: bounds.width * 0.32,
                                   y: currentGroundY() - petSizeNow() / 2)
            resident = actor
            seenAssets.insert(asset)
            persistSeen()
        }
        while allActors.count < Self.expandedCast {
            guard let asset = pickAssets(
                count: 1, excluding: Set(allActors.map { $0.asset })).first
            else { break }
            spawnGuest(asset: asset, animated: true)
        }
        while allActors.count > Self.expandedCast, let oldest = guests.first {
            removeActor(oldest, animated: true)
        }
        if !framesRunning {
            for actor in allActors { actor.stickerView.pause() }
        }
        let castAfter = allActors.map { $0.asset }
        if castAfter != castBefore {
            Breadcrumbs.log("pet.cast.generate kind=expanded"
                + " assets=\(castAfter.joined(separator: ","))")
        }
    }

    /// 嘉宾入场：从一端走进来（弹簧淡入 + 落位）。
    private func spawnGuest(asset: String, animated: Bool) {
        let actor = makeActor(asset: asset)
        let range = walkRange(for: actor)
        let fromLeft = Bool.random()
        actor.center = CGPoint(
            x: fromLeft ? range.lowerBound : range.upperBound,
            y: currentGroundY() - petSizeNow() / 2)
        actor.targetX = CGFloat.random(in: range)
        actor.mode = .walk
        guests.append(actor)
        if animated {
            actor.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            actor.alpha = 0
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8,
                           options: []) {
                actor.transform = .identity
                actor.alpha = 1
            }
        }
        if !framesRunning { actor.stickerView.pause() }
    }

    /// 进度条批次上场：5–8 只（按条宽封顶），沿条均布错峰
    /// 入场；批次墙钟约 40s（自最后一只入场起算）。
    private func spawnBatch() {
        if !barPresented { noteGuardBlock("batch.barNotPresented"); return }
        if !petsActive { noteGuardBlock("batch.petsInactive"); return }
        if !collapsed { noteGuardBlock("batch.notCollapsed"); return }
        if bounds.width <= 40 { noteGuardBlock("batch.stageTooNarrow"); return }
        let maxFit = max(3, Int(bounds.width / 44))
        let size = min(Int.random(in: 5...8), maxFit)
        let assets = pickAssets(count: size, excluding: [])
        let now = clockTime
        for (index, asset) in assets.enumerated() {
            pendingSpawns.append((asset, now + Double(index) * 0.22))
        }
        batchActive = true
        batchEndsAt = now + Double(assets.count) * 0.22 + Self.batchDuration
        Breadcrumbs.log("pet.cast.generate kind=batch"
            + " assets=\(assets.joined(separator: ","))")
    }

    private func spawnBatchMember(asset: String, slot: Int, total: Int) {
        let actor = makeActor(asset: asset)
        let slotX = bounds.width * (CGFloat(slot) + 0.5) / CGFloat(max(1, total))
        actor.center = CGPoint(
            x: min(max(slotX + .random(in: -8...8), walkRange(for: actor).lowerBound),
                   walkRange(for: actor).upperBound),
            y: currentGroundY() - petSizeNow() / 2)
        actor.mode = .idle
        actor.until = activeTime + .random(in: 0.5...2.5)
        guests.append(actor)
        actor.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        actor.alpha = 0
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8,
                       options: []) {
            actor.transform = .identity
            actor.alpha = 1
        }
        if !framesRunning { actor.stickerView.pause() }
    }

    private func removeActor(_ actor: MiniPetActor, animated: Bool) {
        guests.removeAll { $0 === actor }
        if resident === actor { resident = nil }
        if scriptPair?.0 === actor || scriptPair?.1 === actor {
            scriptPair = nil
            hideBubbles()
        }
        if dialogOwner === actor { hideDialog() }
        if carePet === actor { closeCare() }
        farewellQueue.removeAll { $0 === actor }
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                actor.alpha = 0
            }, completion: { _ in actor.removeFromSuperview() })
        } else {
            actor.removeFromSuperview()
        }
    }

    private func clearCast() {
        for actor in allActors { actor.removeFromSuperview() }
        resident = nil
        guests.removeAll()
        scriptPair = nil
    }

    /// 展开落定后班底重整：条上宠物随台升起（吸附自动跟
    /// 随），留常驻（优先狗池/客串猫骑手充任）+ 最久嘉宾，
    /// 其余淡出；留任者弹簧放大到台上规格。
    private func reformExpandedCast() {
        let riders = allActors
        if let r = riders.first(where: {
            Self.residentDogPool.contains($0.asset) || $0.asset == "cat-09"
        }) {
            resident = r
            guests = riders.filter { $0 !== r }
        } else {
            guests = riders
        }
        // 超额时从最新入场者裁起，保留最久的嘉宾随台留任。
        while allActors.count > Self.expandedCast, let extra = guests.last {
            removeActor(extra, animated: true)
        }
        ensureExpandedCast()
        for actor in allActors {
            actor.placed = false
            actor.mode = .idle
            actor.until = activeTime + 1 + .random(in: 0...2)
            let size = Self.expandedPetSize
            if actor.bounds.width != size {
                UIView.animate(withDuration: 0.35, delay: 0,
                               usingSpringWithDamping: 0.75,
                               initialSpringVelocity: 0.5, options: []) {
                    let feet = actor.feetY
                    actor.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                    actor.feetY = feet
                }
            }
        }
        guestRotateAt = activeTime + 18
    }

    // MARK: 三分交互（演员回调，语法与 (25) 同构）

    fileprivate func petTapped(_ actor: MiniPetActor, head: Bool) {
        guard !isHidden, petsActive else { return }
        if head {
            showReaction(above: actor)
        } else {
            showDialog(for: actor)
        }
    }

    fileprivate func petDragBegan(_ actor: MiniPetActor) {
        guard !isHidden, petsActive else { return }
        hideDialog()
        closeCare()
        if scriptPair?.0 === actor || scriptPair?.1 === actor {
            scriptPair = nil
            hideBubbles()
        }
        actor.mode = .dragged
        actor.placed = false
        bringSubviewToFront(actor)
        UIView.animate(withDuration: 0.18) {
            actor.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        }
    }

    fileprivate func petDragChanged(_ actor: MiniPetActor, to point: CGPoint) {
        actor.center = point
    }

    fileprivate func petDragEnded(_ actor: MiniPetActor, at point: CGPoint) {
        UIView.animate(withDuration: 0.2) { actor.transform = .identity }
        dropActor(actor, at: point)
    }

    fileprivate func petDragCancelled(_ actor: MiniPetActor) {
        UIView.animate(withDuration: 0.2) { actor.transform = .identity }
        dropActor(actor, at: actor.center)
    }

    /// 松手：横向落位（夹回活动范围）、竖直吸附回地面并小
    /// 跳一下，进入安置态——停在落点，不参加漫游与编排，
    /// 直到切歌/形态切换。
    private func dropActor(_ actor: MiniPetActor, at point: CGPoint) {
        let range = walkRange(for: actor)
        actor.center.x = min(max(point.x, range.lowerBound), range.upperBound)
        actor.feetY = currentGroundY()
        actor.placed = true
        actor.mode = .idle
        actor.until = activeTime + 2
        actor.hopStart = activeTime
    }

    // MARK: 反应小贴纸（点头顶；关心回应时按映射指定素材）

    private func showReaction(above actor: MiniPetActor, asset specified: String? = nil) {
        let key = ObjectIdentifier(actor)
        reactionViews[key]?.removeFromSuperview()
        let view = StickerView()
        view.crumbScene = "minibar-reaction"
        let asset = specified ?? Self.reactionPool.randomElement() ?? "dog-11"
        let size: CGFloat = 40
        var x = actor.frame.midX - size / 2
            + CGFloat.random(in: -6...6)
        x = min(max(4, x), bounds.width - size - 4)
        var y = actor.frame.minY - size - 6
        if y < 4 { y = actor.frame.maxY + 6 }
        view.frame = CGRect(x: x, y: y, width: size, height: size)
        // 轮廓柔光（3.7 (28)）：反应贴纸若是 dog-11（亲亲回话
        // 指定素材/反应池成员），深色墙面上保轮廓可辨。
        // (29) 起 halo 与 frame 都先于 setSticker 就位，使
        // sticker.apply 留痕记到的是生效值。
        view.silhouetteHaloEnabled = (asset == "dog-11")
        view.setSticker(asset, mode: .loop)
        if !framesRunning { view.pause() }
        view.isUserInteractionEnabled = false
        addSubview(view)
        reactionViews[key] = view
        view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        view.alpha = 0
        UIView.animate(withDuration: 0.32, delay: 0,
                       usingSpringWithDamping: 0.55, initialSpringVelocity: 1,
                       options: []) {
            view.transform = .identity
            view.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak view] in
            guard let view else { return }
            UIView.animate(withDuration: 0.3, animations: {
                view.alpha = 0
            }, completion: { _ in
                view.removeFromSuperview()
                if self?.reactionViews[key] === view {
                    self?.reactionViews[key] = nil
                }
            })
        }
    }

    // MARK: 单击对话框（本体 + 台词，台词库 PetLines）

    private func showDialog(for actor: MiniPetActor) {
        hideDialog()
        closeCare()
        let panel = UIView()
        panel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        panel.layer.cornerRadius = 14
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.3
        panel.layer.shadowRadius = 10
        panel.layer.shadowOffset = CGSize(width: 0, height: 3)
        let sticker = StickerView()
        sticker.crumbScene = "minibar-dialog"
        sticker.frame = CGRect(x: 10, y: 10, width: 64, height: 64)
        sticker.setSticker(actor.asset, mode: .loop)
        if !framesRunning { sticker.pause() }
        panel.addSubview(sticker)
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .label
        label.numberOfLines = 3
        let lines = actor.isCat ? PetLines.catSingles : PetLines.dogSingles
        let lastKey = actor.isCat
        var index = Int.random(in: 0..<lines.count)
        if lines.count > 1, index == lastSingleIndex[lastKey] {
            index = (index + 1) % lines.count
        }
        lastSingleIndex[lastKey] = index
        label.text = lines[index]
        label.frame = CGRect(x: 84, y: 10, width: 128, height: 64)
        panel.addSubview(label)
        // 落点：宠物正上方（台面之上是墙面空区，不压台上控件）。
        let width: CGFloat = 222, height: CGFloat = 84
        let x = min(max(4, actor.center.x - width / 2),
                    max(4, bounds.width - width - 4))
        var y = actor.frame.minY - height - 6
        if y < 4 { y = 4 }
        panel.frame = CGRect(x: x, y: y, width: width, height: height)
        panel.addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(handleDismissTap)))
        addSubview(panel)
        dialogView = panel
        dialogSticker = sticker
        dialogOwner = actor
        panel.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        panel.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.75, initialSpringVelocity: 0.6,
                       options: []) {
            panel.transform = .identity
            panel.alpha = 1
        }
        dialogTimer?.invalidate()
        dialogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {
            [weak self] _ in self?.hideDialog()
        }
    }

    private func hideDialog() {
        dialogTimer?.invalidate()
        dialogTimer = nil
        dialogView?.removeFromSuperview()
        dialogView = nil
        dialogSticker = nil
        dialogOwner = nil
    }

    @objc private func handleDismissTap() {
        if dialogView != nil { hideDialog() }
    }

    // MARK: 一次性气泡（告别词 / 关心回话共用）

    private func showTransientBubble(_ text: String, above actor: MiniPetActor,
                                     duration: TimeInterval = 1.5) {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .darkText
        label.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.numberOfLines = 2
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.text = "  \(text)  "
        label.sizeToFit()
        let w = min(label.bounds.width + 12, 190)
        let h: CGFloat = 26
        let x = min(max(4, actor.frame.midX - w / 2), bounds.width - w - 4)
        var y = actor.frame.minY - h - 4
        if y < 4 { y = actor.frame.maxY + 4 }
        label.frame = CGRect(x: x, y: y, width: w, height: h)
        addSubview(label)
        transientBubbles.append(label)
        label.alpha = 0
        label.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.7,
                       options: []) {
            label.alpha = 1
            label.transform = .identity
        }
        let generation = flowGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak label] in
            guard let self, let label, generation == self.flowGeneration else { return }
            UIView.animate(withDuration: 0.3, animations: {
                label.alpha = 0
            }, completion: { _ in
                label.removeFromSuperview()
                self.transientBubbles.removeAll { $0 === label }
            })
        }
    }

    private func clearTransientBubbles() {
        for label in transientBubbles { label.removeFromSuperview() }
        transientBubbles.removeAll()
    }

    // MARK: 告别流（逐个说离开词再淡出）

    /// 取消一切进行中的流转（形态/显隐翻转时）：作废已排
    /// 期的异步淡出、清气泡、演员恢复不透明（随台升降的
    /// 演员不能带着半透明走）。
    private func cancelFlow() {
        flowGeneration += 1
        farewellActive = false
        farewellQueue.removeAll()
        farewellRemaining = 0
        afterFarewell = nil
        pendingForm = nil
        clearTransientBubbles()
        for actor in allActors {
            actor.layer.removeAllAnimations()
            actor.alpha = 1
            if actor.mode == .farewell { actor.mode = .idle }
        }
    }

    private func startFarewell(of actors: [MiniPetActor], then completion: @escaping () -> Void) {
        guard !actors.isEmpty else { completion(); return }
        farewellQueue = actors
        farewellRemaining = actors.count
        farewellActive = true
        farewellNextAt = clockTime
        afterFarewell = completion
        scriptPair = nil
        hideBubbles()
        closeCare()
        hideDialog()
    }

    /// 告别推进（tick 墙钟驱动）：每 0.9s 送走一只——停步、
    /// 弹离开词气泡（1.5s）、1.1s 起淡出（0.35s）。
    private func stepFarewell() {
        guard farewellActive, clockTime >= farewellNextAt,
              !farewellQueue.isEmpty else { return }
        let actor = farewellQueue.removeFirst()
        farewellNextAt = clockTime + 0.9
        actor.mode = .farewell
        let lines = actor.isCat ? PetLines.farewellCat : PetLines.farewellDog
        let key = actor.isCat
        var index = Int.random(in: 0..<lines.count)
        if lines.count > 1, index == lastFarewellIndex[key] {
            index = (index + 1) % lines.count
        }
        lastFarewellIndex[key] = index
        showTransientBubble(lines[index], above: actor, duration: 1.5)
        let generation = flowGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self, weak actor] in
            guard let self, let actor, generation == self.flowGeneration else { return }
            UIView.animate(withDuration: 0.35, animations: {
                actor.alpha = 0
            }, completion: { _ in
                guard generation == self.flowGeneration else { return }
                self.removeActor(actor, animated: false)
                actor.alpha = 1
                self.farewellRemaining -= 1
                if self.farewellRemaining <= 0, self.farewellActive {
                    self.farewellActive = false
                    let done = self.afterFarewell
                    self.afterFarewell = nil
                    done?()
                }
            })
        }
    }

    // MARK: 关心用户系统

    private func maybeStartCare() {
        guard petsActive, dialogView == nil, scriptPair == nil,
              !farewellActive, pendingForm == nil, carePet == nil,
              activeTime >= nextCareAt else { return }
        let candidates = allActors.filter {
            $0.mode != .dragged && $0.mode != .farewell
        }
        guard let pet = candidates.randomElement() else {
            nextCareAt = activeTime + 10
            return
        }
        nextCareAt = activeTime + .random(in: 50...80)
        carePet = pet
        careOptionsShown = false
        careShownAt = clockTime
        let pool = PetLines.carePool(forHour: Calendar.current.component(.hour, from: Date()))
        var index = Int.random(in: 0..<pool.count)
        if pool.count > 1, index == lastCareIndex {
            index = (index + 1) % pool.count
        }
        lastCareIndex = index
        let bubble = UIView()
        bubble.backgroundColor = UIColor.systemPink.withAlphaComponent(0.92)
        bubble.layer.cornerRadius = 13
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.25
        bubble.layer.shadowRadius = 8
        bubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 2
        label.text = pool[index]
        label.frame = CGRect(x: 10, y: 6, width: 168, height: 30)
        label.sizeToFit()
        bubble.addSubview(label)
        bubble.frame = CGRect(x: 0, y: 0,
                              width: label.bounds.width + 20,
                              height: label.bounds.height + 12)
        label.frame = CGRect(x: 10, y: 6,
                             width: label.bounds.width, height: label.bounds.height)
        bubble.addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(careBubbleTapped)))
        addSubview(bubble)
        careBubbleView = bubble
        careLabel = label
        positionCareUI()
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.32, delay: 0,
                       usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8,
                       options: []) {
            bubble.alpha = 1
            bubble.transform = .identity
        }
    }

    /// 关心气泡与选项跟随宠物头顶（宠物走动时不脱锚）。
    private func positionCareUI() {
        guard let pet = carePet, let bubble = careBubbleView else { return }
        let optionsH: CGFloat = careOptionsShown ? 34 : 0
        let totalH = bubble.bounds.height + optionsH + 10
        let x = min(max(4, pet.center.x - bubble.bounds.width / 2),
                    max(4, bounds.width - bubble.bounds.width - 4))
        var y = pet.frame.minY - totalH - 4
        if y < 4 { y = 4 }
        bubble.frame.origin = CGPoint(x: x, y: y)
        if let options = careOptionsView {
            options.frame = CGRect(
                x: min(max(4, pet.center.x - options.bounds.width / 2),
                       max(4, bounds.width - options.bounds.width - 4)),
                y: y + bubble.bounds.height + 5,
                width: options.bounds.width, height: 30)
        }
        bringSubviewToFront(bubble)
        if let options = careOptionsView { bringSubviewToFront(options) }
    }

    @objc private func careBubbleTapped() {
        guard carePet != nil, !careOptionsShown else { return }
        careOptionsShown = true
        careShownAt = clockTime
        let row = UIView()
        var x: CGFloat = 0
        for (index, title) in Self.careOptionTitles.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            button.setTitleColor(.darkText, for: .normal)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.96)
            button.layer.cornerRadius = 15
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.2
            button.layer.shadowRadius = 6
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
            button.frame = CGRect(x: x, y: 0, width: 64, height: 30)
            button.addTarget(self, action: #selector(careOptionTapped(_:)),
                             for: .touchUpInside)
            row.addSubview(button)
            x += 70
        }
        row.frame = CGRect(x: 0, y: 0, width: x - 6, height: 30)
        addSubview(row)
        careOptionsView = row
        positionCareUI()
        row.alpha = 0
        row.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.7,
                       options: []) {
            row.alpha = 1
            row.transform = .identity
        }
    }

    @objc private func careOptionTapped(_ sender: UIButton) {
        guard let pet = carePet else { closeCare(); return }
        let option = sender.tag
        let asset = Self.careReactionAssets[option][pet.isCat ? 0 : 1]
        let replies = PetLines.careReplies(option: option, isCat: pet.isCat)
        let reply = replies.randomElement() ?? ""
        closeCare()
        pet.hopStart = activeTime
        showReaction(above: pet, asset: asset)
        showTransientBubble(reply, above: pet, duration: 2.2)
    }

    private func closeCare() {
        careBubbleView?.removeFromSuperview()
        careOptionsView?.removeFromSuperview()
        careBubbleView = nil
        careLabel = nil
        careOptionsView = nil
        carePet = nil
        careOptionsShown = false
    }

    /// 关心 UI 过期与跟随（墙钟）：气泡未点 7s 自收，选项
    /// 展开后 6s 自收；宠物离场即收。
    private func updateCare() {
        guard let pet = carePet else { return }
        if !allActors.contains(where: { $0 === pet }) {
            closeCare()
            return
        }
        let limit: TimeInterval = careOptionsShown ? 6 : 7
        if clockTime - careShownAt > limit {
            closeCare()
            return
        }
        positionCareUI()
    }

    // MARK: 主循环

    private func startLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
        Breadcrumbs.log("pet.link.start")
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard barPresented, window != nil else { return }
        syncFrame()
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 0.016 : min(0.05, now - lastTimestamp)
        lastTimestamp = now
        clockTime += dt

        // 心跳（3.7 (29)）：1 秒节流，开关关时也照记——宠物
        // 全灭时凭这一行与 pet.settings.read 即可分清断点在
        // 开关、链未跑还是班底没生成。
        if now - lastHeartbeatAt >= 1 {
            lastHeartbeatAt = now
            Breadcrumbs.log("pet.tick.heartbeat petsActive=\(petsActive)"
                + " collapsed=\(collapsed) cast=\(allActors.count)"
                + " bounds=\(Int(bounds.width))x\(Int(bounds.height))")
        }

        // 开关统管：关 → 整层停（清空班底）；开 → 恢复在场。
        if !StickerSettings.miniPetsEnabled {
            if petsActive {
                cancelFlow()
                clearCast()
                hideDialog()
                hideBubbles()
                closeCare()
                petsActive = false
                isHidden = true
            }
            return
        }
        if !petsActive {
            petsActive = true
            isHidden = false
            if collapsed { spawnBatch() } else { ensureExpandedCast() }
        }
        if !collapsed, pendingForm == nil, resident == nil { ensureExpandedCast() }

        let engine = PlaybackEngine.shared
        let playing = engine.isPlaying
        // 歌曲自然播完（由播转停且进度落点在结尾）→ 小蹦。
        if wasPlaying, !playing, engine.duration > 0,
           engine.currentTime >= engine.duration - 2 {
            for actor in allActors { actor.hopStart = activeTime }
        }
        wasPlaying = playing
        if playing != framesRunning {
            framesRunning = playing
            for actor in allActors {
                if playing { actor.stickerView.play() }
                else { actor.stickerView.pause() }
            }
            if let sticker = dialogSticker {
                if playing { sticker.play() } else { sticker.pause() }
            }
        }

        // 吸附：脚底恒贴地面（台上沿演示层位置），升降与台
        // 子同曲线同时长；拖动中的演员除外。
        let ground = currentGroundY()
        for actor in allActors where actor.mode != .dragged {
            actor.feetY = ground
        }

        // 形态落定处理（台子动画走完后）。
        if let pending = pendingForm, clockTime >= pending.at {
            pendingForm = nil
            if pending.collapsed {
                startFarewell(of: allActors) { [weak self] in
                    self?.spawnBatch()
                }
            } else {
                reformExpandedCast()
            }
        }

        // 批次错峰入场与批次到期退场。
        if !pendingSpawns.isEmpty {
            let due = pendingSpawns.filter { clockTime >= $0.at }
            if !due.isEmpty {
                let total = pendingSpawns.count + guests.count
                for (index, item) in due.enumerated() {
                    spawnBatchMember(asset: item.asset,
                                     slot: guests.count + index, total: total)
                }
                pendingSpawns.removeAll { clockTime >= $0.at }
            }
        }
        stepFarewell()
        if batchActive, pendingSpawns.isEmpty, !farewellActive,
           clockTime >= batchEndsAt, !allActors.isEmpty {
            batchActive = false
            startFarewell(of: allActors) { [weak self] in
                self?.spawnBatch()
            }
        }

        updateCare()

        guard playing else { return }
        activeTime += dt
        // 展开态嘉宾轮换（未露面者优先取人）。
        if !collapsed, !farewellActive, pendingForm == nil,
           activeTime >= guestRotateAt {
            guestRotateAt = activeTime + 18
            if let oldest = guests.first {
                removeActor(oldest, animated: true)
                if let asset = pickAssets(
                    count: 1, excluding: Set(allActors.map { $0.asset })).first {
                    spawnGuest(asset: asset, animated: true)
                    Breadcrumbs.log("pet.cast.generate kind=rotate"
                        + " assets=\(allActors.map { $0.asset }.joined(separator: ","))")
                }
            }
        }
        maybeStartCare()
        advanceScript()
        for actor in allActors { advance(actor, dt: dt) }
        if activeTime > bubblePairUntil, bubbleA != nil { hideBubbles() }
    }

    private func advance(_ actor: MiniPetActor, dt: TimeInterval) {
        // 蹦跳位移（正弦半程 0.45s，仅位置编排）。
        var hop: CGFloat = 0
        if actor.hopStart >= 0 {
            let t = (activeTime - actor.hopStart) / 0.45
            if t >= 1 {
                actor.hopStart = -1
            } else {
                hop = CGFloat(sin(t * .pi)) * (collapsed ? 6 : 10)
            }
        }
        actor.applyTransform(hopOffset: hop)

        switch actor.mode {
        case .dragged, .farewell:
            return
        case .peek:
            if activeTime >= actor.until {
                actor.mode = .idle
                actor.until = activeTime + 1.5 + .random(in: 0...2)
            }
        case .meetHold, .meetArrived:
            break // 编排器统一收尾
        case .idle:
            if actor.placed { return }
            if activeTime >= actor.until {
                actor.targetX = CGFloat.random(in: walkRange(for: actor))
                actor.mode = .walk
            }
        case .walk, .meetWalk, .flee, .pursue:
            let speed: CGFloat = actor.mode == .pursue ? 52
                : actor.mode == .flee ? 44 : 30
            let target = actor.mode == .pursue
                ? (scriptPair?.1.center.x ?? actor.targetX) : actor.targetX
            let dx = target - actor.center.x
            if abs(dx) > 2 { actor.facing = dx > 0 ? 1 : -1 }
            if abs(dx) < 3 {
                if actor.mode == .walk {
                    actor.mode = .idle
                    actor.until = activeTime + 1.5 + .random(in: 0...2.5)
                } else if actor.mode == .flee {
                    let range = walkRange(for: actor)
                    actor.targetX = actor.center.x <= bounds.midX
                        ? range.upperBound : range.lowerBound
                } else if actor.mode == .meetWalk {
                    actor.mode = .meetArrived
                }
                // pursue 的到达由编排器按时收尾
            } else {
                let step = min(abs(dx), speed * CGFloat(dt))
                actor.center.x += dx > 0 ? step : -step
            }
        }
    }

    // MARK: 双宠互动编排（沿 (25)：相遇对答 / 追逐）

    private func advanceScript() {
        if let pair = scriptPair {
            let (a, b) = pair
            switch scriptRunningKind {
            case .meet:
                if a.mode == .meetHold {
                    if activeTime >= scriptUntil {
                        a.mode = .idle; a.until = activeTime + 1
                        b.mode = .idle; b.until = activeTime + 1.6
                        scriptPair = nil
                        nextInteractionAt = activeTime + 10 + .random(in: 0...6)
                    }
                } else if a.mode == .meetArrived, b.mode == .meetArrived {
                    beginMeetHold(a: a, b: b)
                }
            case .chase:
                if activeTime >= scriptUntil {
                    a.mode = .idle; a.until = activeTime + 1.2
                    b.mode = .idle; b.until = activeTime + 1.2
                    scriptPair = nil
                    nextInteractionAt = activeTime + 10 + .random(in: 0...6)
                }
            }
            return
        }
        guard activeTime >= nextInteractionAt, !farewellActive else { return }
        let free = allActors.filter {
            !$0.placed && $0.mode != .dragged && $0.mode != .peek && $0.mode != .farewell
        }
        guard free.count >= 2 else {
            nextInteractionAt = activeTime + 3
            return
        }
        let a = free[0], b = free[1]
        scriptPair = (a, b)
        scriptRunningKind = scriptKind
        switch scriptKind {
        case .meet:
            let mid = (a.center.x + b.center.x) / 2
            let separation = (a.bounds.width + b.bounds.width) / 2 + 4
            a.targetX = min(max(mid - separation / 2, walkRange(for: a).lowerBound),
                            walkRange(for: a).upperBound)
            b.targetX = min(max(mid + separation / 2, walkRange(for: b).lowerBound),
                            walkRange(for: b).upperBound)
            a.mode = .meetWalk
            b.mode = .meetWalk
        case .chase:
            a.mode = .pursue
            b.mode = .flee
            let range = walkRange(for: b)
            b.targetX = b.center.x <= bounds.midX
                ? range.upperBound : range.lowerBound
            scriptUntil = activeTime + 3.2
        }
        scriptKind = scriptKind == .meet ? .chase : .meet
    }

    private func beginMeetHold(a: MiniPetActor, b: MiniPetActor) {
        a.mode = .meetHold
        b.mode = .meetHold
        a.facing = a.center.x <= b.center.x ? 1 : -1
        b.facing = -a.facing
        a.hopStart = activeTime
        b.hopStart = activeTime + 0.12
        scriptUntil = activeTime + 3.4
        // 一问一答：异物种走跨物种对答库、同物种各说一句本
        // 物种单句（防声口串台），与 (25) 同规则。
        if a.isCat == b.isCat {
            let lines = a.isCat ? PetLines.catSingles : PetLines.dogSingles
            var first = Int.random(in: 0..<lines.count)
            var second = Int.random(in: 0..<lines.count)
            if second == first { second = (second + 1) % lines.count }
            if first == lastPairIndex { first = (first + 1) % lines.count }
            lastPairIndex = first
            showBubble(lines[first], above: a, slot: 0)
            showBubble(lines[second], above: b, slot: 1)
        } else {
            let asker = a.isCat ? a : b
            let answerer = asker === a ? b : a
            let pairs = asker.isCat ? PetLines.catAsksDog : PetLines.dogAsksCat
            var index = Int.random(in: 0..<pairs.count)
            if pairs.count > 1, index == lastPairIndex {
                index = (index + 1) % pairs.count
            }
            lastPairIndex = index
            showBubble(pairs[index].0, above: asker, slot: 0)
            showBubble(pairs[index].1, above: answerer, slot: 1)
        }
        bubblePairUntil = activeTime + 3.3
    }

    // MARK: 对话气泡（与 (25) 同样式同节奏）

    private func makeBubble() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .darkText
        label.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.numberOfLines = 2
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        return label
    }

    private func showBubble(_ text: String, above actor: MiniPetActor, slot: Int) {
        let label = slot == 0 ? (bubbleA ?? makeBubble()) : (bubbleB ?? makeBubble())
        if slot == 0 { bubbleA = label } else { bubbleB = label }
        label.text = "  \(text)  "
        label.sizeToFit()
        let w = min(label.bounds.width + 12, 168)
        let h: CGFloat = 26
        let x = min(max(4, actor.frame.midX - w / 2), bounds.width - w - 4)
        var y = actor.frame.minY - h - 4 - CGFloat(slot) * 6
        if y < 4 { y = actor.frame.maxY + 4 }
        label.frame = CGRect(x: x, y: y, width: w, height: h)
        if label.superview == nil { addSubview(label) }
        bringSubviewToFront(label)
        label.alpha = 0
        UIView.animate(withDuration: 0.25) { label.alpha = 1 }
    }

    private func hideBubbles() {
        bubbleA?.removeFromSuperview()
        bubbleB?.removeFromSuperview()
        bubbleA = nil
        bubbleB = nil
    }
}
