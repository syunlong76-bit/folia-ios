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
//   5s 自动关）、长按阶梯（(60) 第 8 条：单个长按识别器
//   0.35s 起识别 + 自维护状态机，时序自 touch-down 起算——
//   0.35s 抓起反馈、1.0s 进入可拖、位移 >10pt 立即转拖动
//   并取消关闭计时、静止满 3.0s 触发关闭走 dismiss 告别
//   离场；拖动安置停在落点、不参加漫游与编排，直到切歌/
//   形态切换）。宠物之间自主互动沿
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

    /// (79) 第 10 条：小形态（收起 30pt）命中区对称放大
    /// 到 ≥44pt（iOS 最小命中口径），视觉帧与布局不变；
    /// 展开 48pt 不受影响。
    override func point(inside point: CGPoint,
                        with event: UIEvent?) -> Bool {
        let side = bounds.width
        guard side > 0, side < 44 else {
            return super.point(inside: point, with: event)
        }
        return bounds.insetBy(dx: -(44 - side) / 2,
                              dy: -(44 - side) / 2).contains(point)
    }
    let stickerView = StickerView()
    private(set) var asset: String = ""
    var isCat: Bool { asset.hasPrefix("cat") }
    /// 安置中（长按拖动落位）：不参加漫游与互动编排。
    var placed = false
    /// 视图宿主已迁到窗口级停靠层（3.7 (43) 路4）：placed
    /// 的全屏形态——演员仍在本台班底数组里（归属不变），
    /// 只有父视图在 PetDockLayer、center 为窗口坐标。拖动
    /// 坐标换算、切歌撤销、消亡扫尾都按此标志分支。
    var dockHosted = false
    /// 停靠计时锚（3.7 (32) 细修 4）：落位时刻的层墙钟；与
    /// 它互动（点/双击/再拖）刷新，满 5 秒无互动淡出回池。
    var parkedClock: TimeInterval = 0
    /// 告别分流标记（3.7 (32) 三地流转）：墙台告别流决策时
    /// 打标，真正离场瞬间才写去向登记——岛向的蹦去灵动岛
    /// 落座，详情页向的登记为 stageBar 在详情页台等候。
    var divertToIsland = false
    var divertToStageBar = false
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

    // MARK: 长按阶梯状态机（(60) 第 8 条，DS 定案）
    /// 单个 UILongPressGestureRecognizer（0.35s 起识别）＋本
    /// 状态机：时序自 touch-down 起算（基点/时刻在
    /// touchesBegan 捕获，识别器只负责 .began/.changed/.ended
    /// 的确认与兜底收尾）。pressing（<0.35s）→ grabbed
    /// （0.35s 抓起反馈，不算可拖）→ dragging（满 1.0s 或
    /// 累计位移 >10pt 立即转入，走 stage 既有 petDrag 链）；
    /// grabbed 静止满 3.0s → closed（触发关闭）。手势结束/
    /// 取消一律复位到 idle 并作废全部已排期迁移。
    private enum PressPhase { case idle, pressing, grabbed, dragging, closed }
    private var pressPhase: PressPhase = .idle
    private var pressStartPoint: CGPoint = .zero
    private var pressLastPoint: CGPoint = .zero
    /// 三个赛跑迁移各自独立句柄：1.0s 进入可拖不得连带取消
    /// 3.0s 关闭计时——静止按住满 1.0s 只是「可拖待命」，手
    /// 指不动继续到 3.0s 仍须触发关闭；只有真实位移 >10pt
    /// 才取消关闭（见 routePressMovement / enterDragging）。
    private var grabWork: DispatchWorkItem?
    private var dragWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

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
        // 双击（3.7 (32) 细修 3）：此前全层没有双击手势，双
        // 击只能落成两次单击（点本体双击 = 对话框重开，无反
        // 应），Miller 报「有些宠物双击不发表情」。新增专用
        // 双击认领 → 走点头顶同一反应通道；单击 require to
        // Fail 双击（iOS 系统级消歧口径，单击延迟一个双击
        // 窗口约 0.25s）。
        let doubleTap = UITapGestureRecognizer(
            target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        let press = UILongPressGestureRecognizer(
            target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.35
        // 位移门限由状态机自管（>10pt 转拖动态）：识别器自身
        // 的 allowableMovement 放开，防移动中途被系统判失败；
        // cancelsTouchesInView 关掉，本视图的 touches 流在识别
        // 后不断（识别前位移与结束收尾都靠它兜底）。
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        addGestureRecognizer(press)
    }

    deinit { cancelPressWork() }

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

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        stage?.petDoubleTapped(self)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard let stage else { return }
        let point = gesture.location(in: stage)
        switch gesture.state {
        case .began: enterGrabbed()
        case .changed: routePressMovement(to: point)
        case .ended: finishPress(cancelled: false)
        case .cancelled, .failed: finishPress(cancelled: true)
        default: break
        }
    }

    // MARK: 阶梯状态机（时序自 touch-down 起算）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard pressPhase == .idle, let stage,
              let touch = touches.first else { return }
        pressPhase = .pressing
        pressStartPoint = touch.location(in: stage)
        pressLastPoint = pressStartPoint
        // 三个赛跑迁移自 touch-down 排期：0.35s 抓起反馈、
        // 1.0s 进入可拖、3.0s 静止关闭。位移 >10pt 时由
        // routePressMovement 抢先转拖动并作废关闭计时。
        grabWork = schedulePressWork(after: 0.35) { [weak self] in
            self?.enterGrabbed()
        }
        dragWork = schedulePressWork(after: 1.0) { [weak self] in
            self?.enterDragging(source: "hold")
        }
        closeWork = schedulePressWork(after: 3.0) { [weak self] in
            self?.triggerClose()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let stage, let touch = touches.first else { return }
        routePressMovement(to: touch.location(in: stage))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        finishPress(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        finishPress(cancelled: true)
    }

    private func schedulePressWork(after delay: TimeInterval,
                                   _ body: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: body)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }

    private func cancelPressWork() {
        grabWork?.cancel(); grabWork = nil
        dragWork?.cancel(); dragWork = nil
        closeWork?.cancel(); closeWork = nil
    }

    /// 0.35s 抓起反馈：缩放 + 轻震动，不算可拖（mode 不动、
    /// petDrag 链不接通）。识别器 .began 与排期双路同到，
    /// 幂等只生效一次。
    private func enterGrabbed() {
        guard pressPhase == .pressing else { return }
        pressPhase = .grabbed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.18) {
            self.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        }
        stage?.petPressGrabbed(self)
    }

    /// 进入可拖：满 1.0s 静止（source=hold）或位移 >10pt
    /// （source=move）任一先到。接通既有 petDragBegan 链。
    /// hold 路径只作废待拖计时、保留关闭计时（静止续按到
    /// 3.0s 仍关闭）；move 路径同时作废关闭计时。
    private func enterDragging(source: String) {
        if pressPhase == .pressing { enterGrabbed() }
        guard pressPhase == .grabbed else { return }
        pressPhase = .dragging
        dragWork?.cancel(); dragWork = nil
        grabWork?.cancel(); grabWork = nil
        if source == "move" {
            closeWork?.cancel(); closeWork = nil
        }
        stage?.petPressDragActivated(self, source: source)
    }

    /// 位移路由：累计位移（自 touch-down 基点）>10pt 立即
    /// 转拖动态并取消关闭计时；已在拖动态（1.0s hold 转入）
    /// 后首次出现 >10pt 真实位移同样取消关闭计时，其余转发
    /// 既有 petDragChanged。
    private func routePressMovement(to point: CGPoint) {
        guard pressPhase == .pressing || pressPhase == .grabbed
            || pressPhase == .dragging else { return }
        pressLastPoint = point
        let drift = hypot(point.x - pressStartPoint.x,
                          point.y - pressStartPoint.y)
        if pressPhase != .dragging {
            if drift > 10 { enterDragging(source: "move") }
            return
        }
        if drift > 10, closeWork != nil {
            closeWork?.cancel(); closeWork = nil
        }
        stage?.petDragChanged(self, to: point)
    }

    /// 静止满 3.0s 触发关闭：在 grabbed 或「hold 转入可拖但
    /// 始终未真实位移」态生效（真实位移已把 closeWork 作废、
    /// 本函数根本不会被调）。写开关与 dismiss 告别离场全在
    /// stage 侧收口；演员 mode 若已 .dragged（hold 转入），
    /// 告别流 stepFarewell 会把 mode 改写为 .farewell。
    private func triggerClose() {
        guard pressPhase == .grabbed || pressPhase == .dragging else { return }
        pressPhase = .closed
        cancelPressWork()
        UIView.animate(withDuration: 0.2) { self.transform = .identity }
        stage?.petPressCloseTriggered(self)
    }

    /// 手势结束/取消复位：拖动态走既有 petDragEnded/
    /// Cancelled 落位；其余态只收抓起缩放。双路（识别器与
    /// touches）同到时凭 phase 幂等，后到者为空操作。
    private func finishPress(cancelled: Bool) {
        guard pressPhase != .idle else { return }
        let wasDragging = pressPhase == .dragging
        // (79) 第 9 条：grab 后被取消/抬手原静默复位零落痕
        // （(78) 判读盲区）——收尾恒落 pet.fin79 带相位与
        // 取消位，下轮日志可定案取消者。
        Breadcrumbs.log("pet.fin79 a=\(asset)"
            + " ph=\(wasDragging ? "drag" : "grab")"
            + " c=\(cancelled ? 1 : 0)")
        cancelPressWork()
        pressPhase = .idle
        if wasDragging {
            if cancelled { stage?.petDragCancelled(self) }
            else { stage?.petDragEnded(self, at: pressLastPoint) }
        } else {
            UIView.animate(withDuration: 0.2) { self.transform = .identity }
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
        // (32) 补 2 句
        "我听见开罐头的声音了，先走一步",
        "沙发那头有个好位置，我去占着",
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
        // (32) 补 2 句
        "我闻到饭香了，跟过去看看",
        "球还在院子里，我去叼回来",
    ]

    // MARK: 打招呼词（(60) 第 8 条新增：开关开启飘落入场专用池）
    /// 落地后 0.1–0.3s 由先落地的前 2 只说一句（showTransient-
    /// Bubble）。种子句自 singles 问候句迁入（dogSingles 的
    /// 「你回来啦！等你好久了！」「嘿嘿，被你发现我了。」），
    /// 其余按猫狗人格声口新写；singles 原池不动（对话框仍用）。

    static let greetingCat = [
        "你回来啦，我在这儿等你呢。",
        "嗯？你来了……那就陪你听一会儿。",
        "喵，我刚睡醒，你就来了。",
        "来了就坐吧，歌刚开始。",
        "等你好久了……才怪，我刚睡醒。",
        "你好呀，今天也一起听歌吧。",
        "抬头看看我，我一直都在。",
    ]
    static let greetingDog = [
        "你回来啦！等你好久了！",
        "嘿嘿，被你发现我了。",
        "你好呀！我来啦我来啦！",
        "我来陪你听歌啦！",
        "今天也要一起开心哦！",
        "汪！你终于来啦！",
        "我准备好了，放歌吧！",
    ]

    // MARK: 关心词（(27) 新增；按时段分池，种子句在各池内）

    static let careMorning = [
        "今天你累不累啊，昨晚睡好了没",
        "早上好呀，先喝杯水再听歌",
        "早饭吃了没？不吃早饭可不行",
        "新的一天，我陪你一起开始",
        "伸个懒腰，新的一天开始啦",
    ]
    static let careNoon = [
        "今天有没有好好吃饭",
        "午饭想吃什么？我陪你想想",
        "吃完饭歇一会儿，别急着忙",
        "今天你累不累啊，要不要眯一会儿",
        "吃点热乎的，胃会舒服点",
    ]
    static let careAfternoon = [
        "今天我给你捏捏肩",
        "下午容易困，起来走两圈吧",
        "喝口水，眼睛也休息一下",
        "坐一下午了，肩膀僵不僵",
        "起来接杯水，顺便透透气",
    ]
    static let careEvening = [
        "今天你累不累啊",
        "今天辛苦啦，晚饭要吃好一点",
        "洗个热水澡，解解乏吧",
        "晚饭有没有好好吃？别凑合",
        "忙了一天，回来就好好歇着",
    ]
    static let careLateNight = [
        "都这么晚了，早点睡吧",
        "这首听完就睡，好不好",
        "我要睡觉了，晚安……你也快睡",
        "深夜了，我陪你，但只能陪一小会儿哦",
        "眼睛都睁不开了吧，去睡吧",
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

/// 弱引用盒（(53) J 迁移实例注册表用；实例消亡自动失效）。
private final class WeakMiniBarPetStageBox {
    weak var stage: MiniBarPetStage?
    init(_ stage: MiniBarPetStage) { self.stage = stage }
}

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
    /// 反应池：灵动岛层双击反应共用同一份（3.7 (32) 放开
    /// private 供 PetIslandLayer 引用，值不变）。
    static let reactionPool =
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

    /// 宿主角色（3.7 (32)）：墙台 / 详情页台。取人来源、告别
    /// 分流与去向登记按角色分工（见 PetHomeRegistry）。
    enum Role {
        case wall, stage
    }
    let role: Role

    private weak var bar: UIView?
    private var barPresented = false
    /// 供去向登记判定「最前点播台」用。
    var isBarPresented: Bool { barPresented }
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
    /// 告别去向（(60) 第 8 条）：islandSplit = 现行收起分流
    /// （蹦岛/回详情页台待命）；dismiss = 开关关闭离场（无
    /// 分流、无落点、登记回池、淡出 0.9s）。tick 硬清场分
    /// 支对 dismiss 进行中的告别流让路（见 tick）。
    enum FarewellDestination {
        case islandSplit, dismiss
    }
    private var farewellDestination: FarewellDestination = .islandSplit
    /// 飘落入场进行中（(60) 第 8 条）：期间暂停 chat 轮转、
    /// 关心触发与停靠过期扫描，落地收尾后恢复。
    private var dropInActive = false
    private var lastGreetingIndex: [Bool: Int] = [:]
    private var transientBubbles: [UILabel] = []

    private var displayLink: CADisplayLink?
    private var lastTimestamp: TimeInterval = 0
    /// pet.tick.heartbeat 节流锚（3.7 (29)）。
    private var lastHeartbeatAt: TimeInterval = 0
    /// 首帧 tick 落痕（3.7 (35) 二分定位）：一次性。
    private var didLogFirstTick = false
    /// 墙钟：恒前进（批次/告别/关心过期用）。
    private var clockTime: TimeInterval = 0
    /// 编排时钟：只在播放中前进（走动/编排/轮换/关心触发用）。
    private var activeTime: TimeInterval = 0
    private var wasPlaying = false
    private var framesRunning = false

    private var trackSerial = 0
    private var lastTrackId: String?
    private var guestRotateAt: TimeInterval = 0
    // 停聊（3.7 (32) 细修 5 人格驱动版）：随机配对、个体冷
    // 却、轮流冒泡。旧 meet 双气泡同显与 chase 追逐编排退
    // 役（Miller 报「宠物一直在跑、从不停下来对话」），走
    // 位复用 meetWalk/meetArrived/meetHold 三态。
    private var chatPair: (MiniPetActor, MiniPetActor)?
    private var chatLines: [(actor: MiniPetActor, text: String)] = []
    private var chatLineIndex = -1
    private var chatLineUntil: TimeInterval = 0
    private var nextChatAt: TimeInterval = 14
    private var chatCooldowns: [ObjectIdentifier: TimeInterval] = [:]
    private var lastSingleIndex: [Bool: Int] = [:]
    private var lastFarewellIndex: [Bool: Int] = [:]
    private var lastCareIndex = -1

    private var bubbleA: UILabel?
    private var bubbleB: UILabel?

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

    /// 对话框点别处关闭（挂到宿主墙根视图；不取消触摸，与
    /// (25) 在舞台根视图上的做法同构）。
    private lazy var dismissTapRecognizer: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(handleDismissTap))
        tap.cancelsTouchesInView = false
        return tap
    }()

    init(bar: UIView, role: Role = .wall) {
        self.bar = bar
        self.role = role
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isHidden = true
        seenAssets = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        // (53) J 迁移注册：活实例登记，供 PetConcertRelocation
        // 经类方法够到全部迷你台（墙/舞台角色）。
        Self.registerLiveInstance(self)
        // (75) 爪印召唤广播兜底接收：召唤侧定位不到当前面
        // 层时改走广播，本层自查在场＋开关已开＋非迁移中
        // 才入场（performDropInEntrance 内另有同口径守卫
        // 与 skip 留痕，双保险）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(pawSummonBroadcast75),
            name: .foliaPawSummon75, object: nil)
    }

    /// (75) 召唤广播接收端（见 init 注册处注）。
    @objc private func pawSummonBroadcast75() {
        guard barPresented, StickerSettings.miniPetsEnabled,
              !concertRelocated else { return }
        Breadcrumbs.log("paw.act75 recv=stage role=\(role)")
        performDropInEntrance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        displayLink?.invalidate()
        dialogTimer?.invalidate()
        // 停靠扫尾（3.7 (43) 路4）：本层消亡时把仍挂在窗口停
        // 靠层里的自家演员视图摘掉，防孤儿视图残留全屏。
        for actor in allActors where actor.dockHosted {
            actor.removeFromSuperview()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if let host = superview {
            host.addGestureRecognizer(dismissTapRecognizer)
        }
    }

    // MARK: 演唱会迁移（(53) 工作流 J，仅迁移钩子）

    /// 活实例注册表：PetConcertRelocation 经类方法够到全部
    /// 迷你台（墙台/详情页台/原型墙台谁活着谁响应）。
    private static var liveInstanceBoxes: [WeakMiniBarPetStageBox] = []

    private static func registerLiveInstance(_ stage: MiniBarPetStage) {
        liveInstanceBoxes.removeAll { $0.stage == nil }
        liveInstanceBoxes.append(WeakMiniBarPetStageBox(stage))
    }

    static func concertRelocateAll() {
        for box in liveInstanceBoxes { box.stage?.concertRelocateOut() }
    }

    static func concertRestoreAll() {
        for box in liveInstanceBoxes { box.stage?.concertRestore() }
    }

    /// 迁移态：为真时本台宠物已撤下、一切自动重组被门控
    /// （tick 重生/形态落定/切歌/呈现钩子逐处查此标志）。
    private var concertRelocated = false
    /// 本次迁移撤下的名单（离场收口写去向登记用）。
    private var concertEvacuatedAssets: [String] = []

    /// 撤下（PetConcertRelocation 调用）：走既有告别流平滑
    /// 退场——逐个弹离开词气泡再淡出，不硬闪。不走三地分流
    /// （cancelFlow 已清 divert 标记）：宠物只属于演唱会了。
    func concertRelocateOut() {
        guard !concertRelocated else { return }
        concertRelocated = true
        guard barPresented else { return }
        Breadcrumbs.log("concert.pets.relocate surface=minibar role=\(role)")
        cancelFlow()
        pendingSpawns.removeAll()
        batchActive = false
        hideDialog()
        hideBubbles()
        closeCare()
        cancelChat()
        let leaving = allActors
        concertEvacuatedAssets = leaving.map { $0.asset }
        guard !leaving.isEmpty else {
            finishConcertRelocateOut()
            return
        }
        startFarewell(of: leaving) { [weak self] in
            self?.finishConcertRelocateOut()
        }
    }

    /// 离场收口：去向统一回池（墙台）/保留等候登记（详情页
    /// 台——恢复时原班底优先回台）；整层隐藏、班底清空。
    /// seen 名单/人格/冷却等状态一概不动（不丢的论证见
    /// PetConcertRelocation 文件头）。
    private func finishConcertRelocateOut() {
        if role == .wall {
            for asset in concertEvacuatedAssets
            where PetHomeRegistry.shared.home(of: asset) == .wallBar {
                PetHomeRegistry.shared.setHome(asset, .pool)
            }
        }
        concertEvacuatedAssets = []
        clearCast()
        petsActive = false
        isHidden = true
    }

    /// 恢复（切走演唱会样式/退出舞台时调用）：按当前形态走
    /// 既有取人重组（展开台班底/进度条批次），平滑入场。
    func concertRestore() {
        guard concertRelocated else { return }
        concertRelocated = false
        guard barPresented else { return }
        Breadcrumbs.log("concert.pets.restore surface=minibar role=\(role)")
        guard StickerSettings.miniPetsEnabled else { return }
        isHidden = false
        petsActive = true
        if collapsed { spawnBatch() } else { ensureExpandedCast() }
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
        // 去向登记：最前点播台登记（岛上宠物点按回台落点）。
        PetHomeRegistry.shared.noteFrontmost(stage: self, presented: presented)
        if presented {
            // 台子每次出现必是完整形态（resetMiniBarFormInstant
            // 保证），宠物层形态同步复位展开态。
            collapsed = false
            cancelFlow()
            startLink()
            if StickerSettings.miniPetsEnabled, !concertRelocated {
                isHidden = false
                petsActive = true
                syncFrame()
                // 详情页台：先记下「等在此处」的班底，入场后由
                // 其中一只冒「等你」库台词（细修 B 流转）。
                let waiting = role == .stage
                    ? Set(PetHomeRegistry.shared.stageBarResidents) : []
                ensureExpandedCast()
                if role == .stage,
                   let greeter = allActors.first(where: { waiting.contains($0.asset) }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        [weak self, weak greeter] in
                        guard let self, let greeter, self.petsActive,
                              self.allActors.contains(where: { $0 === greeter })
                        else { return }
                        self.showTransientBubble(
                            PetLines.stageWaiting.randomElement() ?? "",
                            above: greeter, duration: 2.6)
                    }
                }
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
        if concertRelocated {
            // (53) J：迁移中只同步形态状态，不打断迁移告别流
            // （cancelFlow 会作废其 completion）；恢复时按新
            // 形态重组班底。
            hideDialog()
            hideBubbles()
            closeCare()
            return
        }
        cancelFlow()
        hideDialog()
        hideBubbles()
        closeCare()
        cancelChat()
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
        guard barPresented, petsActive, !concertRelocated else { return }
        // 常驻按曲轮换只属墙台（3.7 (32)）：详情页台的班底是
        // 「等在此处」的具体宠物，换素材即换身份，流转模型
        // 下不许轮换；舞台只做探头反应。
        if role == .wall, let resident {
            let asset = trackSerial % 5 == 0
                ? "cat-09"
                : Self.residentDogPool[trackSerial % Self.residentDogPool.count]
            if resident.asset != asset {
                let oldAsset = resident.asset
                resident.setAsset(asset)
                seenAssets.insert(asset)
                persistSeen()
                // 去向随素材走：旧素材回幕后、新素材上墙台。
                let registry = PetHomeRegistry.shared
                if registry.home(of: oldAsset) == .wallBar {
                    registry.setHome(oldAsset, .pool)
                }
                registry.setHome(asset, .wallBar)
                syncLiveRegistry()
            }
        }
        // 切歌解除停靠（(32) 规格内口径）：逐个落 revoke 面
        // 包屑（3.7 (41) 组4），解停靠从此可判读；形态/告别
        // 两条旧解停靠路径已由本版 ②③ 堵掉，不再发生。
        // 停靠层演员例外（3.7 (43) 路4）：只清 placed 标志
        // 会让下一帧地面吸附把台层坐标的 feetY 写进停靠层
        // 视图（坐标系错位、瞬移乱跳）——改为整只回收回池。
        for actor in allActors where actor.placed {
            if actor.dockHosted {
                Breadcrumbs.log("pet.park.revoke asset=\(actor.asset) reason=track host=dock")
                removeActor(actor, animated: true, sendToPool: true)
            } else {
                actor.placed = false
                Breadcrumbs.log("pet.park.revoke asset=\(actor.asset) reason=track")
            }
        }
        if PlaybackEngine.shared.isPlaying {
            for actor in allActors where actor.mode != .dragged {
                // 停聊中的一对不被切歌探头打断（细修 5 让位）。
                if actor === chatPair?.0 || actor === chatPair?.1 { continue }
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

    /// (78) 第 8 条：该点是否已被宠物面认领（宠物本体/对话
    /// 框/关心气泡）——播放条根级认领（MiniBarRootTap78）
    /// 据此让行，宠物点按语义不被条展开抢走。与 hitTest
    /// 同口径。
    func claimsPoint(_ point: CGPoint) -> Bool {
        hitTest(point, with: nil) != nil
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
        var lo = half + 6
        var hi = max(lo + 1, bounds.width - half - 6)
        // (74) 第 5 项：收起态台面只剩居中 134pt 小横线，宠
        // 物步行域同步收进横线一带（中心 ±92），不在线外空中
        // 行走；展开态恢复整宽。
        if collapsed {
            let mid = bounds.width / 2
            lo = max(lo, mid - 92 + half)
            hi = min(hi, mid + 92 - half)
            if hi < lo { hi = lo }
        }
        return lo...hi
    }

    // MARK: 取人（未露面者优先，全员露面后重置名单）

    /// 在场名单同步去向登记（身份连续的互斥保证）：取人时
    /// 排除在别层在场的宠物。
    private func syncLiveRegistry() {
        PetHomeRegistry.shared.noteLiveAssets(
            stage: self, assets: Set(allActors.map { $0.asset }))
    }

    private func pickAssets(count: Int, excluding: Set<String>) -> [String] {
        let registry = PetHomeRegistry.shared
        var unavailable = excluding
        // 在别层在场的宠物不可取（同一只不在两处同时出现）。
        unavailable.formUnion(registry.liveAssetsElsewhere(excluding: self))
        var picked: [String] = []
        if role == .stage {
            // 详情页台班底 = 去向登记：等在此处（stageBar）的
            // 优先，其次幕后（pool）；墙台/岛上的不抢。舞台取
            // 人不写墙的未露面名单（新面孔先在墙上登场的规矩
            // 不被舞台消耗）。
            let waiting = Self.fullPool.filter {
                registry.home(of: $0) == .stageBar && !unavailable.contains($0)
            }.shuffled()
            let pool = Self.fullPool.filter {
                registry.home(of: $0) == .pool && !unavailable.contains($0)
            }.shuffled()
            for asset in waiting + pool {
                guard picked.count < count else { break }
                picked.append(asset)
                unavailable.insert(asset)
            }
            // (72) 选角占位：登记表 reconcile 凭 claim 跳过
            // 已被选走（预排/入场中）的资产，防岛台抢人。
            PetHomeRegistry.shared.claim(picked)
            return picked
        }
        // 墙台：未露面者优先（原口径）；灵动岛居民垫底——只
        // 有实在无人可派时才召回（回流，细修 B 第 4 条）。
        if seenAssets.count >= Self.fullPool.count {
            seenAssets.removeAll()
            persistSeen()
        }
        let onIsland: (String) -> Bool = { registry.home(of: $0) == .island }
        let unseen = Self.fullPool.filter {
            !seenAssets.contains($0) && !unavailable.contains($0) && !onIsland($0)
        }.shuffled()
        for asset in unseen {
            guard picked.count < count else { break }
            picked.append(asset)
            unavailable.insert(asset)
        }
        if picked.count < count {
            let rest = Self.fullPool.filter {
                !unavailable.contains($0) && !onIsland($0)
            }.shuffled()
            for asset in rest {
                guard picked.count < count else { break }
                picked.append(asset)
                unavailable.insert(asset)
            }
        }
        if picked.count < count {
            let islanders = Self.fullPool.filter {
                onIsland($0) && !unavailable.contains($0)
            }.shuffled()
            for asset in islanders {
                guard picked.count < count else { break }
                picked.append(asset)
                unavailable.insert(asset)
            }
        }
        for asset in picked { seenAssets.insert(asset) }
        persistSeen()
        // (72) 选角占位（同详情页台分支）。
        PetHomeRegistry.shared.claim(picked)
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
        // 去向登记：上台即变更去向（召回岛民/详情页待命者时
        // pet.move 在此落痕，岛层经回调同步撤下）。
        PetHomeRegistry.shared.setHome(asset, role == .wall ? .wallBar : .stageBar)
        syncLiveRegistry()
        return actor
    }

    private func ensureExpandedCast() {
        if !barPresented { noteGuardBlock("ensure.barNotPresented"); return }
        if bounds.width <= 40 { noteGuardBlock("ensure.stageTooNarrow"); return }
        Breadcrumbs.log("pet.spawn.begin role=\(role == .wall ? "wall" : "stage")"
            + " cast=\(allActors.count) width=\(Int(bounds.width))")
        let castBefore = allActors.map { $0.asset }
        if resident == nil {
            // 详情页台的常驻同样走取人（等在此处者优先），不
            // 用墙的狗池轮换（身份连续）；墙台沿用原口径，但
            // 跳过正在灵动岛落座的狗池成员（不硬召回岛民）。
            let wallResident: String = {
                let pool = Self.residentDogPool
                for offset in 0..<pool.count {
                    let candidate = pool[(trackSerial + offset) % pool.count]
                    if PetHomeRegistry.shared.home(of: candidate) != .island {
                        return candidate
                    }
                }
                return pool[trackSerial % pool.count]
            }()
            let asset = role == .stage
                ? (pickAssets(count: 1, excluding: []).first ?? wallResident)
                : wallResident
            let actor = makeActor(asset: asset)
            actor.center = CGPoint(x: bounds.width * 0.32,
                                   y: currentGroundY() - petSizeNow() / 2)
            resident = actor
            if role == .wall {
                seenAssets.insert(asset)
                persistSeen()
            }
        }
        while allActors.count < Self.expandedCast {
            guard let asset = pickAssets(
                count: 1, excluding: Set(allActors.map { $0.asset })).first
            else { break }
            spawnGuest(asset: asset, animated: true)
        }
        // 裁员跳过停靠中与停聊中的（细修 4/5 让位）；全员让
        // 位时允许临时超编，不硬裁。
        while allActors.count > Self.expandedCast,
              let extra = guests.first(where: {
                  !$0.placed && $0 !== chatPair?.0 && $0 !== chatPair?.1
              }) {
            removeActor(extra, animated: true, sendToPool: true)
        }
        if !framesRunning {
            for actor in allActors { actor.stickerView.pause() }
        }
        let castAfter = allActors.map { $0.asset }
        if castAfter != castBefore {
            Breadcrumbs.log("pet.cast.generate kind=expanded"
                + " assets=\(castAfter.joined(separator: ","))")
        }
        Breadcrumbs.log("pet.spawn.end cast=\(allActors.count)")
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

    // MARK: 飘落入场（(60) 第 8 条：仅「开关开启」入口）

    /// 开启入场：落点沿用现有槽位分配先算好（展开台＝常驻
    /// 位+嘉宾位、收起态＝批次槽位），演员入场期临时挂全高
    /// 承载层（PetDockLayer，与停靠同承载方式；未安装时退
    /// 回本层内落下），自屏幕顶端外 curveEaseIn 重力感加速
    /// 飘落（行程 ≈600pt 时 0.55–0.8s，距离短按比例缩短、
    /// 下限 0.45s）＋起始 x 微漂移，落地系统弹簧收尾
    /// （damping≈0.55、0.28s）后同坐标交回本层切常规行为
    /// 机、不跳位。逐只错峰 0.2s；先落地的前 2 只落地后
    /// 0.1–0.3s 冒打招呼气泡（greetingCat/greetingDog 池）；
    /// 入场期暂停 chat 轮转（cancelChat/hideBubbles 封口 +
    /// dropInActive 门控）。常规 spawn（切歌换班底/嘉宾轮
    /// 换/批次）不走此路、保持现行。
    func performDropInEntrance() {
        guard barPresented else {
            Breadcrumbs.log("pet.dropin skip reason=barNotPresented")
            return
        }
        guard StickerSettings.miniPetsEnabled else {
            Breadcrumbs.log("pet.dropin skip reason=petsDisabled")
            return
        }
        guard !concertRelocated else {
            Breadcrumbs.log("pet.dropin skip reason=concertRelocated")
            return
        }
        isHidden = false
        petsActive = true
        syncFrame()
        cancelChat()
        hideBubbles()
        closeCare()
        hideDialog()

        // 落点先行：与 ensureExpandedCast / spawnBatch 同口径
        // 取人与槽位，只建新人（在场者不重落）。
        let size = petSizeNow()
        let ground = currentGroundY()
        var newcomers: [(actor: MiniPetActor, landing: CGPoint)] = []
        if !collapsed {
            if resident == nil {
                let wallResident: String = {
                    let pool = Self.residentDogPool
                    for offset in 0..<pool.count {
                        let candidate = pool[(trackSerial + offset) % pool.count]
                        if PetHomeRegistry.shared.home(of: candidate) != .island {
                            return candidate
                        }
                    }
                    return pool[trackSerial % pool.count]
                }()
                let asset = role == .stage
                    ? (pickAssets(count: 1, excluding: []).first ?? wallResident)
                    : wallResident
                let actor = makeActor(asset: asset)
                resident = actor
                if role == .wall {
                    seenAssets.insert(asset)
                    persistSeen()
                }
                newcomers.append((actor, CGPoint(
                    x: bounds.width * 0.32, y: ground - size / 2)))
            }
            while allActors.count < Self.expandedCast {
                guard let asset = pickAssets(
                    count: 1, excluding: Set(allActors.map { $0.asset })).first
                else { break }
                let actor = makeActor(asset: asset)
                guests.append(actor)
                let range = walkRange(for: actor)
                newcomers.append((actor, CGPoint(
                    x: CGFloat.random(in: range), y: ground - size / 2)))
            }
        } else if allActors.isEmpty {
            let maxFit = max(3, Int(bounds.width / 44))
            let count = min(Int.random(in: 5...8), maxFit)
            let assets = pickAssets(count: count, excluding: [])
            batchActive = true
            batchEndsAt = clockTime + Double(assets.count) * 0.2 + 0.9
                + Self.batchDuration
            for (index, asset) in assets.enumerated() {
                let actor = makeActor(asset: asset)
                guests.append(actor)
                let slotX = bounds.width * (CGFloat(index) + 0.5)
                    / CGFloat(max(1, assets.count))
                let range = walkRange(for: actor)
                let x = min(max(slotX + .random(in: -8...8), range.lowerBound),
                            range.upperBound)
                newcomers.append((actor, CGPoint(x: x, y: ground - size / 2)))
            }
            Breadcrumbs.log("pet.cast.generate kind=batch-dropin"
                + " assets=\(assets.joined(separator: ","))")
        }
        guard !newcomers.isEmpty else {
            Breadcrumbs.log("pet.dropin skip reason=noNewcomers")
            return
        }
        if !framesRunning {
            for actor in allActors { actor.stickerView.pause() }
        }

        dropInActive = true
        let generation = flowGeneration
        let dock = PetDockLayer.shared
        let useDock = dock.superview != nil
        Breadcrumbs.log("pet.dropin begin cast=\(newcomers.count)"
            + " carrier=\(useDock ? "dock" : "stage-fallback")"
            + " form=\(collapsed ? "collapsed" : "expanded")")
        var landedCount = 0
        for (index, entry) in newcomers.enumerated() {
            let actor = entry.actor
            let landing = entry.landing
            let landingInCarrier = useDock ? convert(landing, to: dock) : landing
            // 入场期以 placed 豁免地面吸附与漫游（advance 的
            // idle 分支对 placed 直接返回）；parkedClock 同步
            // 刷新，防停靠过期扫描误伤（dropInActive 亦门控）。
            actor.placed = true
            actor.parkedClock = clockTime
            actor.mode = .idle
            if useDock {
                dock.addSubview(actor)
                actor.dockHosted = true
                dock.refrontIfNeeded()
            }
            let drift: CGFloat = .random(in: -4...4)
            actor.center = CGPoint(x: landingInCarrier.x - drift,
                                   y: -size / 2)
            actor.alpha = 1
            actor.transform = .identity
            let distance = max(0, landingInCarrier.y - actor.center.y)
            let fallDuration = min(0.8, max(0.45, distance * (0.7 / 600)))
            UIView.animate(withDuration: fallDuration,
                           delay: Double(index) * 0.2,
                           options: [.curveEaseIn], animations: {
                actor.center = CGPoint(x: landingInCarrier.x + drift * 0.5,
                                       y: landingInCarrier.y)
            }, completion: { [weak self, weak actor] finished in
                guard let self, let actor, finished,
                      generation == self.flowGeneration,
                      self.allActors.contains(where: { $0 === actor })
                else { return }
                // 落地交接：先按同坐标换回本层（落点帧精确对
                // 齐、不跳位），再走弹簧收尾（transform 与父
                // 视图无关，换父后继续播完）。
                if actor.dockHosted {
                    self.addSubview(actor)
                    actor.dockHosted = false
                }
                actor.center = landing
                actor.placed = false
                actor.mode = .idle
                actor.until = self.activeTime + 1 + .random(in: 0...2)
                actor.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                UIView.animate(withDuration: 0.28, delay: 0,
                               usingSpringWithDamping: 0.55,
                               initialSpringVelocity: 0.6, options: []) {
                    actor.transform = .identity
                }
                landedCount += 1
                Breadcrumbs.log("pet.dropin land asset=\(actor.asset)"
                    + " idx=\(landedCount)/\(newcomers.count)")
                // 打招呼：同批只让先落地的前 2 只说话。
                if landedCount <= 2 {
                    let delay = Double.random(in: 0.1...0.3)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        [weak self, weak actor] in
                        guard let self, let actor,
                              generation == self.flowGeneration,
                              self.allActors.contains(where: { $0 === actor })
                        else { return }
                        self.showGreetingBubble(above: actor)
                    }
                }
                if landedCount >= newcomers.count {
                    self.dropInActive = false
                    Breadcrumbs.log("pet.dropin done cast=\(newcomers.count)")
                }
            })
        }
    }

    /// 打招呼气泡（入场专用）：greetingCat/greetingDog 池，
    /// 防连抽去重与告别池同口径，走既有 showTransientBubble。
    private func showGreetingBubble(above actor: MiniPetActor) {
        let lines = actor.isCat ? PetLines.greetingCat : PetLines.greetingDog
        let key = actor.isCat
        var index = Int.random(in: 0..<lines.count)
        if lines.count > 1, index == lastGreetingIndex[key] {
            index = (index + 1) % lines.count
        }
        lastGreetingIndex[key] = index
        showTransientBubble(lines[index], above: actor, duration: 1.5)
    }

    /// 移除演员。sendToPool = 去向回幕后（轮换/裁员/停靠过
    /// 期）；告别流的移除不走这里回池——去向已由分流决策写
    /// 好（岛/stageBar），此处默认不动登记。
    private func removeActor(_ actor: MiniPetActor, animated: Bool,
                             sendToPool: Bool = false) {
        guests.removeAll { $0 === actor }
        if resident === actor { resident = nil }
        if chatPair?.0 === actor || chatPair?.1 === actor {
            cancelChat()
        }
        if dialogOwner === actor { hideDialog() }
        if carePet === actor { closeCare() }
        farewellQueue.removeAll { $0 === actor }
        if sendToPool {
            PetHomeRegistry.shared.setHome(actor.asset, .pool)
        }
        syncLiveRegistry()
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                actor.alpha = 0
            }, completion: { _ in actor.removeFromSuperview() })
        } else {
            actor.removeFromSuperview()
        }
    }

    private func clearCast() {
        // 台面撤场时的去向收口：墙台宠物回幕后；详情页台的
        // 宠物保留 stageBar 登记（关台后仍在详情页台等候，
        // 下次开台原班底回来）。
        // 停靠者（3.7 (43) 路4「台隐藏即回收」）：视图在窗口
        // 停靠层里，同样被下方 removeFromSuperview 摘除、班
        // 底清空——台不在屏时不留全屏浮宠；去向登记沿本函
        // 数既有分工（墙台回池、舞台台保留等候登记）。
        if role == .wall {
            for actor in allActors
            where PetHomeRegistry.shared.home(of: actor.asset) == .wallBar {
                PetHomeRegistry.shared.setHome(actor.asset, .pool)
            }
        }
        for actor in allActors { actor.removeFromSuperview() }
        resident = nil
        guests.removeAll()
        cancelChat()
        syncLiveRegistry()
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
        // 超额时从最新入场者裁起，保留最久的嘉宾随台留任；
        // 停靠中的不裁（细修 4 让位）。
        while allActors.count > Self.expandedCast,
              let extra = guests.last(where: { !$0.placed }) {
            removeActor(extra, animated: true, sendToPool: true)
        }
        ensureExpandedCast()
        for actor in allActors {
            // 停靠者只做尺寸弹簧、不解停靠（3.7 (41) 组4）：
            // placed/mode/until 全保留，与上方裁员循环的豁免
            // 对齐——此前此循环无条件清 placed，展开落定即全
            // 员解停靠、宠物 1–3 秒后恢复漫游（审计 pet-dock
            // 候选 2）。
            if !actor.placed {
                actor.mode = .idle
                actor.until = activeTime + 1 + .random(in: 0...2)
            }
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
        // 停靠中被点 = 互动，5 秒计时刷新（细修 4）。
        if actor.placed { actor.parkedClock = clockTime }
        // 停聊让位：点到参与者，对话先让给用户（细修 5）。
        cancelChatIfParticipant(actor)
        if head {
            showReaction(above: actor)
        } else {
            showDialog(for: actor)
        }
    }

    /// 双击（3.7 (32) 细修 3）：任何宠物双击 → 冒它自己的
    /// 反应贴纸，与点头顶同一通道；若单击的对话框刚被本只
    /// 打开（双击第一下触发的残留），先收掉再冒反应。
    fileprivate func petDoubleTapped(_ actor: MiniPetActor) {
        guard !isHidden, petsActive else { return }
        if actor.placed { actor.parkedClock = clockTime }
        cancelChatIfParticipant(actor)
        if dialogOwner === actor { hideDialog() }
        actor.hopStart = activeTime
        showReaction(above: actor)
    }

    /// 岛上宠物点按回台的落点（PetIslandLayer 调用）：在本台
    /// 以嘉宾身份入场（入场动画承接「蹦回」）；台不在场/宠
    /// 物关时不动登记，宠物留在岛上。
    func receiveReturningPet(asset: String) {
        guard barPresented, petsActive, !isHidden else { return }
        if let existing = allActors.first(where: { $0.asset == asset }) {
            existing.hopStart = activeTime
            return
        }
        spawnGuest(asset: asset, animated: true)
        if let actor = guests.first(where: { $0.asset == asset }) {
            actor.hopStart = activeTime
        }
    }

    fileprivate func petDragBegan(_ actor: MiniPetActor) {
        guard !isHidden, petsActive else { return }
        // 拖动链埋点（3.7 (41) 组4）：此前 begin/end 全无面
        // 包屑，落点被改写只能靠推断（审计 pet-dock 缺口）。
        Breadcrumbs.log("pet.drag.begin asset=\(actor.asset)")
        hideDialog()
        closeCare()
        cancelChatIfParticipant(actor)
        actor.mode = .dragged
        actor.placed = false
        bringSubviewToFront(actor)
        UIView.animate(withDuration: 0.18) {
            actor.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        }
    }

    fileprivate func petDragChanged(_ actor: MiniPetActor, to point: CGPoint) {
        // 停靠中的演员已在窗口级停靠层：手势点是本层坐标，
        // 须先换算到停靠层坐标再设 center（3.7 (43) 路4）。
        if actor.dockHosted {
            actor.center = convert(point, to: PetDockLayer.shared)
        } else {
            actor.center = point
        }
    }

    fileprivate func petDragEnded(_ actor: MiniPetActor, at point: CGPoint) {
        UIView.animate(withDuration: 0.2) { actor.transform = .identity }
        dropActor(actor, at: point, src: "ended")
    }

    fileprivate func petDragCancelled(_ actor: MiniPetActor) {
        UIView.animate(withDuration: 0.2) { actor.transform = .identity }
        dropActor(actor, at: actor.center, src: "cancelled")
    }

    // MARK: 长按阶梯回调（(60) 第 8 条；状态机在 MiniPetActor）

    /// 0.35s 抓起反馈已由演员自身完成（缩放+轻震动），此处
    /// 只落痕：grab 不算可拖、petDrag 链尚未接通。
    fileprivate func petPressGrabbed(_ actor: MiniPetActor) {
        Breadcrumbs.log("pet.gesture state=grab asset=\(actor.asset)")
    }

    /// 进入可拖（满 1.0s 或位移 >10pt）：接通既有 petDrag
    /// 链（petDragBegan 起、后续 Changed/Ended 由演员转发）。
    fileprivate func petPressDragActivated(_ actor: MiniPetActor, source: String) {
        Breadcrumbs.log("pet.gesture state=drag asset=\(actor.asset) src=\(source)")
        petDragBegan(actor)
    }

    /// 静止满 3.0s 触发关闭：写开关（SettingsStore 新键与
    /// StickerSettings 旧键同值双写，两读者同源）后走
    /// dismiss 告别离场——不走 tick 硬清场（tick 对进行中
    /// 的 dismiss 告别让路，全员走完 completion 才收尾）。
    fileprivate func petPressCloseTriggered(_ actor: MiniPetActor) {
        guard petsActive, !farewellActive else { return }
        Breadcrumbs.log("pet.gesture state=close-trigger asset=\(actor.asset)")
        StickerSettings.setMiniPetsEnabled(false, src: "petPress3s")
        // (73)：关台只辖台上 cast；岛民常驻不随全局关撤下
        // （reconcile 已解耦，见 PetHomeRegistry (73) 注），
        // 本调用仅作稳定事件对账（岛民维持落座自愈）。
        PetHomeRegistry.shared.reconcileIsland(reason: "switch")
        pendingSpawns.removeAll()
        batchActive = false
        pendingForm = nil
        let leaving = allActors
        Breadcrumbs.log("pet.switch off via=gesture farewell=dismiss"
            + " cast=\(leaving.count)")
        startFarewell(of: leaving, destination: .dismiss) { [weak self] in
            guard let self else { return }
            self.clearCast()
            self.petsActive = false
            self.isHidden = true
            Breadcrumbs.log("pet.switch off done farewell=dismiss")
        }
    }

    /// 全局召唤钮关闭落点（3.7 (70) B2 终版）：与长按宠物本
    /// 体关闭（petPressCloseTriggered）同路的全员 dismiss
    /// 告别离场，区别仅在触发源无具体演员。开关双写与
    /// via=corner3s 面包屑由召唤钮落，本方法只管离场本体
    /// （调用方须先写 off，否则 tick 会按开态重新补员）。
    func performFarewellDismissAll70() {
        guard petsActive, !farewellActive else { return }
        pendingSpawns.removeAll()
        batchActive = false
        pendingForm = nil
        let leaving = allActors
        startFarewell(of: leaving, destination: .dismiss) { [weak self] in
            guard let self else { return }
            self.clearCast()
            self.petsActive = false
            self.isHidden = true
            Breadcrumbs.log("pet.switch off done farewell=dismiss")
        }
    }

    /// 松手（3.7 (41) 组4 修订落位语义，Miller 2026-11-20
    /// 拍板「二维定格：放哪停哪」）：落点 x/y 都保真，不夹
    /// 回 walkRange、不把 y 钉回地面；主循环的地面吸附对
    /// placed 同步豁免（几何豁免与行为豁免对齐）。定格后
    /// 不被队形/轮换/批次/告别拽走；停靠后 5 秒内无任何与
    /// 它的互动（点/双击/再拖，互动刷新计时）→ 淡出消失
    /// 回池。停靠仅会话内有效；切歌仍按 (32) 口径解除。
    ///
    /// 3.7 (43) 路4 全屏化：(41) 版只夹进本层（恒高 246 的
    /// 台层）——Miller 实测拖到屏幕上半全被夹回（日志
    /// drop=(266,−323) → parked=(266,24)）。本版只在落定
    /// 瞬间迁移宿主：落点换窗口坐标、夹窗口 bounds，演员
    /// 视图迁入窗口级 PetDockLayer（先算坐标再换父视图、
    /// 同 runloop 完成，无可见跳变；演员 transform 在
    /// petDragEnded 已先归 identity）。拖动全程不换父视图
    /// ——手势中途 reparent 有被取消的风险，且 (41) 实测
    /// 拖动跟手在现结构下成立。归属/登记/过期路径不变：
    /// 演员仍在本台班底数组里，停靠层纯视图宿主。停靠层
    /// 未安装（异常路径）时退回 (41) 台层内夹取。
    private func dropActor(_ actor: MiniPetActor, at point: CGPoint, src: String) {
        let half = actor.bounds.width / 2
        let dock = PetDockLayer.shared
        guard dock.superview != nil else {
            let cx = min(max(point.x, half), max(half, bounds.width - half))
            let cy = min(max(point.y, half), max(half, bounds.height - half))
            actor.center = CGPoint(x: cx, y: cy)
            actor.placed = true
            actor.parkedClock = clockTime
            actor.mode = .idle
            actor.until = activeTime + 2
            actor.hopStart = activeTime
            Breadcrumbs.log("pet.drag.end asset=\(actor.asset) src=\(src)"
                + " drop=(\(Int(point.x)),\(Int(point.y)))"
                + " parked=(\(Int(actor.center.x)),\(Int(actor.center.y))) host=stage-fallback")
            Breadcrumbs.log("pet.park asset=\(actor.asset)"
                + " x=\(Int(actor.center.x)) y=\(Int(actor.center.y))"
                + " form=\(collapsed ? "collapsed" : "expanded") host=stage-fallback")
            return
        }
        let windowPoint = convert(point, to: dock)
        // (75) 第 4 项：拖到岛框区域松手＝换住落座（竖屏、
        // 落点 y≤100、x 在屏中 ±120 内；岛框几何与
        // PetIslandLayer 同源）。命中不走停靠：先释放演员
        // 回池（removeActor 同步在场表、sendToPool 写
        // .pool），再由登记表 dragSeat 裁决落座（顺序反了
        // .island 会被 sendToPool 冲掉）；dragSeat 拒收
        // （汪汪队期间）时演员留池、落痕 island-denied。
        if dock.bounds.width < dock.bounds.height,
           windowPoint.y <= 100,
           abs(windowPoint.x - dock.bounds.width / 2) <= 120 {
            let side = windowPoint.x < dock.bounds.width / 2 ? 0 : 1
            let asset = actor.asset
            removeActor(actor, animated: false, sendToPool: true)
            if PetHomeRegistry.shared.dragSeat(asset: asset, side: side) {
                Breadcrumbs.log("pet.drag.end asset=\(asset) src=\(src) host=island")
            } else {
                Breadcrumbs.log("pet.drag.end asset=\(asset) src=\(src) host=island-denied")
            }
            return
        }
        // (79) 第 9/11 条：落座未命中补落痕（原未命中分支
        // 零落痕是盲区）——放手点指向岛带（y≤140）却没进
        // 落座条件时落 isl.drop79 带坐标与拒因，换住链本
        // 体与窗口坐标判定不动。
        if windowPoint.y <= 140 {
            let reason = dock.bounds.width >= dock.bounds.height
                ? "landscape" : "outx"
            Breadcrumbs.log("isl.drop79 a=\(actor.asset)"
                + " x=\(Int(windowPoint.x)) y=\(Int(windowPoint.y))"
                + " r=\(reason)")
        }
        let cx = min(max(windowPoint.x, half), max(half, dock.bounds.width - half))
        let cy = min(max(windowPoint.y, half), max(half, dock.bounds.height - half))
        if actor.superview !== dock {
            dock.addSubview(actor)
        }
        actor.center = CGPoint(x: cx, y: cy)
        actor.dockHosted = true
        dock.refrontIfNeeded()
        actor.placed = true
        actor.parkedClock = clockTime
        actor.mode = .idle
        actor.until = activeTime + 2
        actor.hopStart = activeTime
        Breadcrumbs.log("pet.drag.end asset=\(actor.asset) src=\(src)"
            + " drop=(\(Int(windowPoint.x)),\(Int(windowPoint.y)))"
            + " parked=(\(Int(actor.center.x)),\(Int(actor.center.y))) host=dock")
        Breadcrumbs.log("pet.park asset=\(actor.asset)"
            + " x=\(Int(actor.center.x)) y=\(Int(actor.center.y))"
            + " form=\(collapsed ? "collapsed" : "expanded") host=dock")
    }

    // MARK: 反应小贴纸（点头顶；关心回应时按映射指定素材）

    /// 演员在本层坐标系里的帧（3.7 (43) 路4）：停靠者的父
    /// 视图是窗口停靠层、frame 为窗口坐标，对话框/反应贴
    /// 纸都加在本层，定位必须换算；未停靠者换算结果与
    /// actor.frame 恒等。
    private func stageFrame(of actor: MiniPetActor) -> CGRect {
        convert(actor.bounds, from: actor)
    }

    private func showReaction(above actor: MiniPetActor, asset specified: String? = nil) {
        let key = ObjectIdentifier(actor)
        reactionViews[key]?.removeFromSuperview()
        let view = StickerView()
        view.crumbScene = "minibar-reaction"
        let asset = specified ?? Self.reactionPool.randomElement() ?? "dog-11"
        let size: CGFloat = 40
        let actorFrame = stageFrame(of: actor)
        var x = actorFrame.midX - size / 2
            + CGFloat.random(in: -6...6)
        x = min(max(4, x), bounds.width - size - 4)
        var y = actorFrame.minY - size - 6
        if y < 4 { y = actorFrame.maxY + 6 }
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
        let actorFrame = stageFrame(of: actor)
        let x = min(max(4, actorFrame.midX - width / 2),
                    max(4, bounds.width - width - 4))
        var y = actorFrame.minY - height - 6
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
        let actorFrame = stageFrame(of: actor)
        let x = min(max(4, actorFrame.midX - w / 2), bounds.width - w - 4)
        var y = actorFrame.minY - h - 4
        if y < 4 { y = actorFrame.maxY + 4 }
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
        farewellDestination = .islandSplit
        dropInActive = false
        farewellQueue.removeAll()
        farewellRemaining = 0
        afterFarewell = nil
        pendingForm = nil
        clearTransientBubbles()
        for actor in allActors {
            actor.layer.removeAllAnimations()
            actor.alpha = 1
            // 分流标记只打在演员身上、离场瞬间才写登记：流
            // 被取消时清标即可，不留幽灵去向（细修 B）。
            actor.divertToIsland = false
            actor.divertToStageBar = false
            if actor.mode == .farewell { actor.mode = .idle }
        }
    }

    /// 告别分流决策（3.7 (32) 三地流转，仅墙台）：说完离开
    /// 词后不再直接回池——一部分蹦去灵动岛落座，其余去详
    /// 情页点播台等候。此处只打标，去向登记在离场瞬间写
    /// （见 stepFarewell），流被取消时标记随 cancelFlow 清除。
    ///
    /// (72) 选角归一（废 (43) 构成/活泼序）：(53) 起岛居民
    /// 恒为固定双人组，登记表与岛层两道闸都只放行双人组；
    /// 本处旧规按 {猫2狗1}+活泼序打标，与两道闸口径相反，
    /// 被标记者几乎必被改道/拒收、双人组几乎永不入选——
    /// (71) 真机日志 pet.farewell.dest 全程 0 次。本版：离
    /// 场班底中的双人组成员（岛有空位时）打 divertToIsland，
    /// 其余一律 divertToStageBar，三道闸口径归一。岛的常态
    /// 人口由登记表 reconcile 确定性落座维持（见
    /// PetHomeRegistry.reconcileIsland），本分流只负责「在台
    /// 上的双人组离台后直接回岛」的连续性。
    private func prepareFarewellDestinations(_ actors: [MiniPetActor]) {
        guard role == .wall else { return }
        let registry = PetHomeRegistry.shared
        let residents = registry.islandResidents
        var slots = max(0, PetHomeRegistry.islandCapacity - residents.count)
        var islandBound: [MiniPetActor] = []
        for actor in actors {
            if slots > 0, registry.islandTargetDuo.contains(actor.asset) {
                actor.divertToIsland = true
                islandBound.append(actor)
                slots -= 1
            } else {
                actor.divertToStageBar = true
            }
        }
        if !islandBound.isEmpty {
            Breadcrumbs.log("pet.farewell.dest slots=\(slots + islandBound.count)"
                + " island=\(islandBound.map { $0.asset }.joined(separator: ","))")
        }
    }

    private func startFarewell(of actors: [MiniPetActor],
                               destination: FarewellDestination = .islandSplit,
                               then completion: @escaping () -> Void) {
        guard !actors.isEmpty else { completion(); return }
        farewellDestination = destination
        if destination == .dismiss {
            // 关闭离场不分流：落点标记全清（防残留标记把演
            // 员送去岛/详情页台），去向在淡出收尾时回池。
            for actor in actors {
                actor.divertToIsland = false
                actor.divertToStageBar = false
            }
        }
        farewellQueue = actors
        farewellRemaining = actors.count
        farewellActive = true
        farewellNextAt = clockTime
        afterFarewell = completion
        cancelChat()
        hideBubbles()
        closeCare()
        hideDialog()
    }

    /// 告别推进（tick 墙钟驱动）：每 0.9s 送走一只——停步、
    /// 弹离开词气泡（1.5s）、1.1s 起淡出（islandSplit 0.35s；
    /// dismiss 0.9s curveEaseOut 慢淡出，(60) 第 8 条）。
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
            // 分流落点（细修 B）：岛向的在告别词说完后蹦去灵
            // 动岛（去向此刻才写登记，岛层从它当前窗口位置
            // 接走）；详情页向的登记为 stageBar 后淡出。
            if self.farewellDestination == .islandSplit, actor.divertToIsland {
                let rect = actor.convert(actor.bounds, to: nil)
                PetHomeRegistry.shared.setHome(actor.asset, .island)
                PetIslandLayer.shared.receive(asset: actor.asset, fromRect: rect)
                self.removeActor(actor, animated: false)
                actor.alpha = 1
                self.finishFarewellDeparture(generation: generation)
                return
            }
            if self.farewellDestination == .islandSplit, actor.divertToStageBar {
                PetHomeRegistry.shared.setHome(actor.asset, .stageBar)
            }
            if self.farewellDestination == .dismiss {
                // 关闭离场：无落点，去向登记回幕后池。
                PetHomeRegistry.shared.setHome(actor.asset, .pool)
            }
            let fadeDuration: TimeInterval =
                self.farewellDestination == .dismiss ? 0.9 : 0.35
            let fadeOptions: UIView.AnimationOptions =
                self.farewellDestination == .dismiss ? [.curveEaseOut] : []
            UIView.animate(withDuration: fadeDuration, delay: 0,
                           options: fadeOptions, animations: {
                actor.alpha = 0
            }, completion: { _ in
                guard generation == self.flowGeneration else { return }
                self.removeActor(actor, animated: false)
                actor.alpha = 1
                self.finishFarewellDeparture(generation: generation)
            })
        }
    }

    /// 告别离场收尾计数（淡出与岛转移共用）。
    private func finishFarewellDeparture(generation: Int) {
        guard generation == flowGeneration else { return }
        farewellRemaining -= 1
        if farewellRemaining <= 0, farewellActive {
            farewellActive = false
            let done = afterFarewell
            afterFarewell = nil
            done?()
            // (72) 稳定事件：告别流落定后请登记表对账岛民
            // （双人组若在本轮离台经分流回岛、或仍在池中待
            // 落座，reconcile 一次判清；内部合并去抖）。
            PetHomeRegistry.shared.reconcileIsland(reason: "farewell")
        }
    }

    // MARK: 关心用户系统

    private func maybeStartCare() {
        guard petsActive, dialogView == nil, chatPair == nil,
              !farewellActive, !dropInActive, pendingForm == nil, carePet == nil,
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
        let petFrame = stageFrame(of: pet)
        let x = min(max(4, petFrame.midX - bubble.bounds.width / 2),
                    max(4, bounds.width - bubble.bounds.width - 4))
        var y = petFrame.minY - totalH - 4
        if y < 4 { y = 4 }
        bubble.frame.origin = CGPoint(x: x, y: y)
        if let options = careOptionsView {
            options.frame = CGRect(
                x: min(max(4, petFrame.midX - options.bounds.width / 2),
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
        if !didLogFirstTick {
            didLogFirstTick = true
            Breadcrumbs.log("pet.tick.first role=\(role == .wall ? "wall" : "stage")"
                + " collapsed=\(collapsed)")
        }
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
        // (60) 第 8 条防抢跑：dismiss 告别进行中（长按关闭已
        // 先写 false 并起告别流）时本分支让路——不清场、不
        // isHidden、不 return（stepFarewell 还要靠 tick 推进），
        // 等告别 completion 落地收尾。
        let dismissFarewellInFlight = farewellActive
            && farewellDestination == .dismiss
        if !StickerSettings.miniPetsEnabled {
            if dismissFarewellInFlight {
                // 落到下方主循环继续推进告别；重生类分支已逐
                // 处以 farewellActive / petsActive 门控，不会
                // 在离场途中补人。
            } else {
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
        }
        if !petsActive, !concertRelocated, !dismissFarewellInFlight {
            petsActive = true
            isHidden = false
            if collapsed { spawnBatch() } else { ensureExpandedCast() }
        }
        if !collapsed, pendingForm == nil, resident == nil,
           !concertRelocated, !farewellActive {
            ensureExpandedCast()
        }

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
        // 子同曲线同时长；拖动中的演员除外。停靠中的演员同
        // 样豁免（3.7 (41) 组4）：二维定格的几何豁免与行为
        // 豁免对齐——否则落点保真只活一帧，下一帧即被拽回
        // 地面（审计 pet-dock 候选 1 的兜底一半）。
        let ground = currentGroundY()
        for actor in allActors where actor.mode != .dragged && !actor.placed {
            actor.feetY = ground
        }

        // 形态落定处理（台子动画走完后）。
        if let pending = pendingForm, clockTime >= pending.at {
            pendingForm = nil
            if pending.collapsed {
                // 停靠者不进告别流（3.7 (41) 组4）：分流打标与
                // 告别名单都先滤掉 placed，停靠者由自身 5 秒
                // 过期扫描退场（审计 pet-dock 候选 3）。
                let farewellActors = allActors.filter { !$0.placed }
                // 3.7 (35) 二分门：告别分流旁路（不打标，回池口径）。
                if !FoliaBisect.pet32SubsystemsBypassed {
                    prepareFarewellDestinations(farewellActors)
                }
                startFarewell(of: farewellActors) { [weak self] in
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
            // 停靠者不进告别流（3.7 (41) 组4，同收起落定处）。
            let farewellActors = allActors.filter { !$0.placed }
            // 3.7 (35) 二分门：告别分流旁路（不打标，回池口径）。
            if !FoliaBisect.pet32SubsystemsBypassed {
                prepareFarewellDestinations(farewellActors)
            }
            startFarewell(of: farewellActors) { [weak self] in
                self?.spawnBatch()
            }
        }

        // 停靠过期（细修 4）：定格满 5 秒无互动 → 淡出回池。
        // 3.7 (35) 二分门：旁路时不设过期（退回 (27)/(30) 安置语义）。
        if !FoliaBisect.pet32SubsystemsBypassed, !farewellActive, !dropInActive {
            for actor in allActors where actor.placed && actor.mode != .dragged
                && clockTime - actor.parkedClock >= 5 {
                Breadcrumbs.log("pet.park.expire asset=\(actor.asset)")
                removeActor(actor, animated: true, sendToPool: true)
            }
        }

        updateCare()

        guard playing else { return }
        activeTime += dt
        // 展开态嘉宾轮换（未露面者优先取人）；停靠中与停
        // 聊中的嘉宾不被轮换调走（细修 4/5 让位）。
        if !collapsed, !farewellActive, pendingForm == nil,
           activeTime >= guestRotateAt {
            guestRotateAt = activeTime + 18
            if let oldest = guests.first(where: {
                !$0.placed && $0 !== chatPair?.0 && $0 !== chatPair?.1
            }) {
                removeActor(oldest, animated: true, sendToPool: true)
                if let asset = pickAssets(
                    count: 1, excluding: Set(allActors.map { $0.asset })).first {
                    spawnGuest(asset: asset, animated: true)
                    Breadcrumbs.log("pet.cast.generate kind=rotate"
                        + " assets=\(allActors.map { $0.asset }.joined(separator: ","))")
                }
            }
        }
        maybeStartCare()
        // 3.7 (35) 二分门：人格停聊整体旁路（细修 5）。
        if !FoliaBisect.pet32SubsystemsBypassed { advanceChat() }
        for actor in allActors { advance(actor, dt: dt) }
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
                ? (chatPair?.1.center.x ?? actor.targetX) : actor.targetX
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

    // MARK: 双宠停聊（3.7 (32) 细修 5：人格驱动 + 随机配对）

    /// 停聊推进：进行中则按句推进（轮流冒泡，一句 1.2–1.8s，
    /// 气泡只在当前说话者头顶）；空闲且到了触发点则随机抽
    /// 一对空闲宠物走到一起开聊。触发间隔：上一场结束后
    /// 20–40s（编排时钟，暂停停摆）。让位：停靠/拖动/探头/
    /// 告别中的不参与；对话框开着、关心气泡在场时不开聊；
    /// 个体冷却 45s（同一只不连聊两轮）。
    private func advanceChat() {
        if let pair = chatPair {
            let (a, b) = pair
            if a.mode == .meetHold {
                if chatLineIndex >= 0, activeTime >= chatLineUntil {
                    chatLineIndex += 1
                    presentChatLine()
                }
            } else if a.mode == .meetArrived, b.mode == .meetArrived {
                beginChatHold(a: a, b: b)
            }
            return
        }
        guard activeTime >= nextChatAt, !farewellActive, !dropInActive,
              pendingForm == nil, carePet == nil, dialogView == nil
        else { return }
        let free = allActors.filter {
            !$0.placed && $0.mode != .dragged && $0.mode != .peek
                && $0.mode != .farewell
                && (chatCooldowns[ObjectIdentifier($0)] ?? 0) <= activeTime
        }
        guard free.count >= 2 else {
            nextChatAt = activeTime + 4
            return
        }
        let shuffled = free.shuffled()
        let a = shuffled[0], b = shuffled[1]
        chatPair = (a, b)
        // 走位复用相遇编排：走到中点两侧，面对面。
        let mid = (a.center.x + b.center.x) / 2
        let separation = (a.bounds.width + b.bounds.width) / 2 + 4
        a.targetX = min(max(mid - separation / 2, walkRange(for: a).lowerBound),
                        walkRange(for: a).upperBound)
        b.targetX = min(max(mid + separation / 2, walkRange(for: b).lowerBound),
                        walkRange(for: b).upperBound)
        a.mode = .meetWalk
        b.mode = .meetWalk
    }

    private func beginChatHold(a: MiniPetActor, b: MiniPetActor) {
        a.mode = .meetHold
        b.mode = .meetHold
        a.facing = a.center.x <= b.center.x ? 1 : -1
        b.facing = -a.facing
        a.hopStart = activeTime
        b.hopStart = activeTime + 0.12
        let dialogue = PetChat.generate(
            a: PetPersonalities.of(a.asset), b: PetPersonalities.of(b.asset))
        chatLines = dialogue.lines.map {
            (actor: $0.speakerIsA ? a : b, text: $0.text)
        }
        chatLineIndex = 0
        Breadcrumbs.log("pet.chat surface=\(role == .stage ? "stage" : "wall")"
            + " form=\(collapsed ? "collapsed" : "expanded")"
            + " a=\(a.asset)(\(PetPersonalities.of(a.asset).label))"
            + " b=\(b.asset)(\(PetPersonalities.of(b.asset).label))"
            + " topic=\(dialogue.topic.label)"
            + " combo=o\(dialogue.openerIndex)/r\(dialogue.responseIndex)"
            + " lines=\(dialogue.lines.count)")
        presentChatLine()
    }

    private func presentChatLine() {
        guard chatPair != nil, chatLineIndex >= 0 else { endChat(); return }
        guard chatLineIndex < chatLines.count else { endChat(); return }
        let line = chatLines[chatLineIndex]
        chatLineUntil = activeTime + .random(in: 1.2...1.8)
        showBubble(line.text, above: line.actor, slot: 0)
        bubbleB?.removeFromSuperview()
        bubbleB = nil
        line.actor.hopStart = activeTime
    }

    /// 对话自然收尾：双方进个体冷却（45s），下一场 20–40s
    /// 后（编排时钟）。
    private func endChat() {
        if let pair = chatPair {
            for actor in [pair.0, pair.1] {
                chatCooldowns[ObjectIdentifier(actor)] = activeTime + 45
                if actor.mode == .meetHold || actor.mode == .meetWalk
                    || actor.mode == .meetArrived {
                    actor.mode = .idle
                    actor.until = activeTime + 1 + .random(in: 0...1.5)
                }
            }
        }
        chatPair = nil
        chatLines = []
        chatLineIndex = -1
        hideBubbles()
        nextChatAt = activeTime + .random(in: 20...40)
    }

    /// 对话被打断（形态/显隐翻转、参与者被点按/拖走/移除）：
    /// 参与者回待机并记短冷却（10s），防刚打断又立刻开聊。
    private func cancelChat() {
        if let pair = chatPair {
            for actor in [pair.0, pair.1] {
                chatCooldowns[ObjectIdentifier(actor)] = activeTime + 10
                if actor.mode == .meetHold || actor.mode == .meetWalk
                    || actor.mode == .meetArrived {
                    actor.mode = .idle
                    actor.until = activeTime + 1
                }
            }
        }
        chatPair = nil
        chatLines = []
        chatLineIndex = -1
        hideBubbles()
    }

    private func cancelChatIfParticipant(_ actor: MiniPetActor) {
        if chatPair?.0 === actor || chatPair?.1 === actor {
            cancelChat()
        }
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
