import UIKit

// 播放页陪伴宠物（3.7 (24) 初版沿周界漫游，Miller 真机反馈
// 「没发现」；3.7 (25) 按新口径整体重做）：
//
// - 在框里：活动区 = 舞台歌词容器内部，主活动带为容器下半
//   区；常驻宠物 84pt 在场玩耍（漫游/停歇），放歌时活动、
//   暂停时停在原地且帧冻结待机，不消失。
// - 互动编排：≥2 只在场时周期性上演双宠互动——相向走近→
//   碰头弹跳→一问一答对话、追逐绕场。只编排位置与朝向
//   （整只可水平镜像），不改帧、不自编动作帧。
// - 双击召唤：双击歌词容器随机召唤一只入场，池 = 全部 53
//   只猫狗贴纸（含未装场景的素材）；场上上限 3 只，超限时
//   最先召唤的退场。陪伴开关关闭时召唤亦停用。
// - 交互语法三分（21:03 追加定案）：
//   · 点头顶区 → 头顶冒反应小贴纸，约 1.5s 淡出，纯表演；
//   · 单击本体 → 对话框：主体为被点贴纸本体（循环帧放大
//     展示）+ 一句它的台词（猫狗分声口、各 ≥10 句）；点
//     气泡/点别处关闭，5s 无操作自动关；对话框贴宠物侧方
//     同高区（下半活动带内），不压歌词当前行（容器中部）。
//   · 长按 0.35s → 拖动占座：拖到框内任意位置松手落位，
//     切歌不复位（常驻宠物的座位持久化）；拖出框外松手 =
//     送走（召唤宠物只走那只；常驻宠物被送走 = 陪伴关闭，
//     等同旧长按收起，设置页可重开）。
// - 听歌反应：切歌时在场宠物朝画面中央探头停顿 + 小跳；
//   歌曲自然播完时原地小蹦（仅位移编排）。
// - 触摸面：本层 hitTest 只认领宠物与对话框本体，其余全部
//   透传给歌词容器（行点按 seek 等既有交互零影响）；双击
//   识别器由 Stage VC 挂在容器上（不取消容器内触摸）。
// - 帧/状态只读 PlaybackEngine（isPlaying/进度端点判定），
//   不回写播放状态机；歌词/时钟/渲染零触碰。

// MARK: - 宠物演员

private final class PetActor: UIView {
    let stickerView = StickerView()
    private(set) var asset: String = ""
    var isCat: Bool { asset.hasPrefix("cat") }
    /// 占座中：不参加漫游与互动编排（座位是用户的安排）。
    var seated = false
    /// 朝向：1 = 素材原向，-1 = 整只水平镜像。
    var facing: CGFloat = 1
    var hopStart: TimeInterval = -1

    enum Mode {
        case idle, walk, peek, meetWalk, meetArrived, meetHold
        case flee, pursue, dragged
    }
    var mode: Mode = .idle
    var target: CGPoint = .zero
    var until: TimeInterval = 0

    weak var show: CompanionPetView?

    init(asset: String, size: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        stickerView.frame = bounds
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

    func requireTapToFail(_ other: UIGestureRecognizer) {
        for recognizer in gestureRecognizers ?? [] {
            if recognizer is UITapGestureRecognizer {
                recognizer.require(toFail: other)
            }
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let head = point.y < bounds.height * 0.42
        show?.petTapped(self, head: head)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard let show else { return }
        let point = gesture.location(in: show)
        switch gesture.state {
        case .began: show.petDragBegan(self)
        case .changed: show.petDragChanged(self, to: point)
        case .ended: show.petDragEnded(self, at: point)
        case .cancelled, .failed: show.petDragCancelled(self)
        default: break
        }
    }

    /// 朝向 + 蹦跳位移合成（整只镜像是允许的朝向编排）。
    func applyTransform(hopOffset: CGFloat) {
        stickerView.transform = CGAffineTransform(
            a: facing, b: 0, c: 0, d: 1, tx: 0, ty: -hopOffset)
    }
}

// MARK: - 台词库（生活口吻，猫狗分声口；纯 UI 文案）

private enum PetLines {
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
}

// MARK: - 陪伴舞台（管理器）

final class CompanionPetView: UIView {

    /// 常驻宠物被拖出送走时回调（= 陪伴已关闭）。
    var onResidentRetired: (() -> Void)?

    /// 舞台歌词容器在舞台视图坐标系中的框；本层 frame 与之
    /// 对齐，内部一律用 bounds 坐标。
    var roamRegion: CGRect = .zero {
        didSet {
            guard roamRegion.width > 40, roamRegion.height > 40 else { return }
            if superview != nil { frame = roamRegion }
            clampActorsInside()
            restoreSeatIfNeeded()
        }
    }

    /// 双击召唤识别器（Stage VC 挂到歌词容器上）。
    private(set) lazy var summonTapRecognizer: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(handleSummonTap))
        tap.numberOfTapsRequired = 2
        return tap
    }()

    /// 对话框点别处关闭（Stage VC 挂到舞台根视图；不取消触摸）。
    private(set) lazy var dismissTapRecognizer: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(handleDismissTap))
        tap.cancelsTouchesInView = false
        return tap
    }()

    private static let petSize: CGFloat = 84
    private static let maxPets = 3
    private static let summonPool: [String] =
        (1...25).map { String(format: "cat-%02d", $0) } + ["cat-live"]
        + (1...27).map { String(format: "dog-%02d", $0) }
    private static let residentDogPool =
        ["dog-01", "dog-15", "dog-18", "dog-19", "dog-23", "dog-25"]
    private static let reactionPool =
        ["dog-11", "cat-15", "dog-25", "cat-01", "dog-20", "cat-24", "dog-17"]

    private var resident: PetActor?
    private var summoned: [PetActor] = []
    private var allActors: [PetActor] {
        (resident.map { [$0] } ?? []) + summoned
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: TimeInterval = 0
    /// 活动时钟：只在播放中前进（暂停 = 全员原地待机）。
    private var activeTime: TimeInterval = 0
    private var wasPlaying = false
    private var framesRunning = false

    private var trackSerial = 0
    private var lastTrackId: String?
    private var nextInteractionAt: TimeInterval = 6
    private var scriptKind: ScriptKind = .meet
    private var scriptRunningKind: ScriptKind = .meet
    private var scriptPair: (PetActor, PetActor)?
    private var scriptUntil: TimeInterval = 0
    private var lastPairIndex = -1
    private var lastSingleIndex: [Bool: Int] = [:]

    private var bubbleA: UILabel?
    private var bubbleB: UILabel?
    private var bubblePairUntil: TimeInterval = 0

    private var dialogView: UIView?
    private var dialogSticker: StickerView?
    private var dialogLabel: UILabel?
    private var dialogOwner: PetActor?
    private var dialogTimer: Timer?

    private var reactionViews: [ObjectIdentifier: StickerView] = [:]
    private var seatRestorePending = false

    private enum ScriptKind { case meet, chase }

    // MARK: 生命周期（Stage VC 钩子，方法名沿用 (24)）

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        displayLink?.invalidate()
        dialogTimer?.invalidate()
    }

    func startRoaming() {
        guard StickerSettings.companionEnabled else {
            isHidden = true
            return
        }
        isHidden = false
        ensureResident()
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = 0
        }
    }

    func stopRoaming() {
        displayLink?.invalidate()
        displayLink = nil
        hideDialog()
        hideBubbles()
    }

    /// 切歌钩子：常驻宠物按曲轮换（狗池为主、每 5 首猫客串），
    /// 在场宠物探头 + 小跳（听歌反应）；占座位置不复位。
    func setTrack(id: String) {
        guard id != lastTrackId else { return }
        lastTrackId = id
        trackSerial += 1
        guard StickerSettings.companionEnabled, !isHidden else { return }
        ensureResident()
        if let resident {
            let asset = trackSerial % 5 == 0
                ? "cat-09"
                : Self.residentDogPool[trackSerial % Self.residentDogPool.count]
            if resident.asset != asset { resident.setAsset(asset) }
        }
        if PlaybackEngine.shared.isPlaying {
            for actor in allActors where actor.mode != .dragged {
                actor.mode = .peek
                actor.until = activeTime + 0.9
                actor.facing = actor.center.x <= bounds.midX ? 1 : -1
                actor.hopStart = activeTime
            }
        }
    }

    // MARK: 触摸认领（只认宠物/对话框，其余透传歌词容器）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        for sub in subviews.reversed() {
            guard !sub.isHidden, sub.isUserInteractionEnabled else { continue }
            let converted = sub.convert(point, from: self)
            if let hit = sub.hitTest(converted, with: event) { return hit }
        }
        return nil
    }

    // MARK: 常驻宠物与座位

    private func ensureResident() {
        guard resident == nil, bounds.width > 40 else { return }
        let defaults = UserDefaults.standard
        let seated = defaults.bool(forKey: StickerSeat.seatedKey)
        let asset = Self.residentDogPool[trackSerial % Self.residentDogPool.count]
        let actor = makeActor(asset: asset)
        actor.seated = seated
        if seated {
            seatRestorePending = true
            restoreSeatIfNeeded()
        } else {
            actor.center = CGPoint(x: bounds.width * 0.3,
                                   y: bandCenterY(at: 0.7))
        }
        resident = actor
    }

    private func restoreSeatIfNeeded() {
        guard seatRestorePending, let resident, bounds.width > 40 else { return }
        seatRestorePending = false
        let defaults = UserDefaults.standard
        let nx = defaults.double(forKey: StickerSeat.xKey)
        let ny = defaults.double(forKey: StickerSeat.yKey)
        resident.center = clampedCenter(
            CGPoint(x: nx * bounds.width, y: ny * bounds.height))
    }

    private func persistSeat(of actor: PetActor) {
        guard actor === resident, bounds.width > 0, bounds.height > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(actor.center.x / bounds.width), forKey: StickerSeat.xKey)
        defaults.set(Double(actor.center.y / bounds.height), forKey: StickerSeat.yKey)
        defaults.set(true, forKey: StickerSeat.seatedKey)
    }

    private func makeActor(asset: String) -> PetActor {
        let actor = PetActor(asset: asset, size: Self.petSize)
        actor.show = self
        actor.requireTapToFail(summonTapRecognizer)
        addSubview(actor)
        return actor
    }

    // MARK: 双击召唤

    @objc private func handleSummonTap() {
        guard StickerSettings.companionEnabled, !isHidden,
              bounds.width > 40 else { return }
        hideDialog()
        let onStage = Set(allActors.map { $0.asset })
        let candidates = Self.summonPool.filter { !onStage.contains($0) }
        guard let asset = candidates.randomElement() else { return }
        while allActors.count >= Self.maxPets, let oldest = summoned.first {
            removeActor(oldest, animated: true)
        }
        guard allActors.count < Self.maxPets else { return }
        let actor = makeActor(asset: asset)
        actor.center = randomBandPoint()
        summoned.append(actor)
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

    private func removeActor(_ actor: PetActor, animated: Bool) {
        summoned.removeAll { $0 === actor }
        if resident === actor { resident = nil }
        if scriptPair?.0 === actor || scriptPair?.1 === actor {
            scriptPair = nil
            hideBubbles()
        }
        if dialogOwner === actor { hideDialog() }
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                actor.alpha = 0
            }, completion: { _ in actor.removeFromSuperview() })
        } else {
            actor.removeFromSuperview()
        }
    }

    // MARK: 三分交互（演员回调）

    func petTapped(_ actor: PetActor, head: Bool) {
        guard !isHidden else { return }
        if head {
            showReaction(above: actor)
        } else {
            showDialog(for: actor)
        }
    }

    func petDragBegan(_ actor: PetActor) {
        guard !isHidden else { return }
        hideDialog()
        if scriptPair?.0 === actor || scriptPair?.1 === actor {
            scriptPair = nil
            hideBubbles()
        }
        actor.mode = .dragged
        bringSubviewToFront(actor)
        UIView.animate(withDuration: 0.18) {
            actor.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        }
    }

    func petDragChanged(_ actor: PetActor, to point: CGPoint) {
        actor.center = point
    }

    func petDragEnded(_ actor: PetActor, at point: CGPoint) {
        UIView.animate(withDuration: 0.2) { actor.transform = .identity }
        if !bounds.contains(point) {
            // 拖出框外松手 = 送走。
            if actor === resident {
                retireCompanion()
            } else {
                removeActor(actor, animated: true)
            }
            return
        }
        actor.center = clampedCenter(point)
        actor.seated = true
        actor.mode = .idle
        actor.until = activeTime + 2
        persistSeat(of: actor)
    }

    func petDragCancelled(_ actor: PetActor) {
        UIView.animate(withDuration: 0.2) { actor.transform = .identity }
        actor.center = clampedCenter(actor.center)
        actor.mode = .idle
        actor.until = activeTime + 1
    }

    /// 常驻宠物送走 = 陪伴关闭（等同旧长按收起的替代路径）。
    private func retireCompanion() {
        StickerSettings.companionEnabled = false
        for actor in allActors { actor.removeFromSuperview() }
        resident = nil
        summoned.removeAll()
        scriptPair = nil
        hideDialog()
        hideBubbles()
        isHidden = true
        onResidentRetired?()
    }

    // MARK: 反应小贴纸（点头顶）

    private func showReaction(above actor: PetActor) {
        let key = ObjectIdentifier(actor)
        reactionViews[key]?.removeFromSuperview()
        let view = StickerView()
        let asset = Self.reactionPool.randomElement() ?? "dog-11"
        view.setSticker(asset, mode: .loop)
        let size: CGFloat = 40
        var x = actor.frame.midX - size / 2
            + CGFloat.random(in: -6...6)
        x = min(max(4, x), bounds.width - size - 4)
        var y = actor.frame.minY - size - 6
        if y < 4 { y = actor.frame.maxY + 6 }
        view.frame = CGRect(x: x, y: y, width: size, height: size)
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

    // MARK: 单击对话框（本体 + 台词）

    private func showDialog(for actor: PetActor) {
        hideDialog()
        let panel = UIView()
        panel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        panel.layer.cornerRadius = 14
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.3
        panel.layer.shadowRadius = 10
        panel.layer.shadowOffset = CGSize(width: 0, height: 3)
        let sticker = StickerView()
        sticker.setSticker(actor.asset, mode: .loop)
        if !framesRunning { sticker.pause() }
        sticker.frame = CGRect(x: 10, y: 10, width: 64, height: 64)
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
        let width: CGFloat = 222, height: CGFloat = 84
        var x: CGFloat
        if actor.center.x <= bounds.midX {
            x = actor.frame.maxX + 8
            if x + width > bounds.width - 4 { x = actor.frame.minX - 8 - width }
        } else {
            x = actor.frame.minX - 8 - width
            if x < 4 { x = actor.frame.maxX + 8 }
        }
        x = min(max(4, x), max(4, bounds.width - width - 4))
        let y = min(max(4, actor.center.y - height / 2),
                    max(4, bounds.height - height - 4))
        panel.frame = CGRect(x: x, y: y, width: width, height: height)
        panel.addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(handleDismissTap)))
        addSubview(panel)
        dialogView = panel
        dialogSticker = sticker
        dialogLabel = label
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
        dialogLabel = nil
        dialogOwner = nil
    }

    @objc private func handleDismissTap() {
        if dialogView != nil { hideDialog() }
    }

    // MARK: 主循环

    @objc private func tick(_ link: CADisplayLink) {
        if !StickerSettings.companionEnabled {
            if !isHidden { retireCompanionSoft() }
            return
        }
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 0.016 : min(0.05, now - lastTimestamp)
        lastTimestamp = now
        let engine = PlaybackEngine.shared
        let playing = engine.isPlaying
        // 歌曲自然播完（进度落点在结尾且由播转停）→ 小蹦。
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
        guard playing else { return }
        activeTime += dt
        advanceScript()
        for actor in allActors { advance(actor, dt: dt) }
        if activeTime > bubblePairUntil, bubbleA != nil { hideBubbles() }
    }

    /// 开关在别处被关时收层（不触发回调，避免与设置页状态打架）。
    private func retireCompanionSoft() {
        for actor in allActors { actor.removeFromSuperview() }
        resident = nil
        summoned.removeAll()
        scriptPair = nil
        hideDialog()
        hideBubbles()
        isHidden = true
    }

    private func advance(_ actor: PetActor, dt: TimeInterval) {
        // 蹦跳位移（正弦半程 0.45s，仅位置编排）。
        var hop: CGFloat = 0
        if actor.hopStart >= 0 {
            let t = (activeTime - actor.hopStart) / 0.45
            if t >= 1 {
                actor.hopStart = -1
            } else {
                hop = CGFloat(sin(t * .pi)) * 10
            }
        }
        actor.applyTransform(hopOffset: hop)

        switch actor.mode {
        case .dragged:
            return
        case .peek:
            if activeTime >= actor.until {
                actor.mode = .idle
                actor.until = activeTime + 1.5 + .random(in: 0...2)
            }
        case .meetHold, .meetArrived:
            break // 编排器统一收尾
        case .idle:
            if actor.seated { return }
            if activeTime >= actor.until {
                actor.target = randomBandPoint()
                actor.mode = .walk
            }
        case .walk, .meetWalk, .flee, .pursue:
            let speed: CGFloat = actor.mode == .pursue ? 44
                : actor.mode == .flee ? 36 : 27
            let target = actor.mode == .pursue
                ? (scriptPair?.1.center ?? actor.target) : actor.target
            let dx = target.x - actor.center.x
            let dy = target.y - actor.center.y
            let dist = hypot(dx, dy)
            if abs(dx) > 2 { actor.facing = dx > 0 ? 1 : -1 }
            if dist < 3 {
                if actor.mode == .walk {
                    actor.mode = .idle
                    actor.until = activeTime + 1.5 + .random(in: 0...2.5)
                } else if actor.mode == .flee {
                    actor.target = randomBandPoint()
                } else if actor.mode == .meetWalk {
                    actor.mode = .meetArrived
                }
                // pursue 的到达由编排器按时收尾
            } else {
                let step = min(dist, speed * CGFloat(dt))
                actor.center = CGPoint(
                    x: actor.center.x + dx / dist * step,
                    y: actor.center.y + dy / dist * step)
            }
        }
    }

    // MARK: 双宠互动编排

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
        guard activeTime >= nextInteractionAt else { return }
        let free = allActors.filter {
            !$0.seated && $0.mode != .dragged && $0.mode != .peek
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
            let mid = CGPoint(x: (a.center.x + b.center.x) / 2,
                              y: bandCenterY(at: 0.72))
            let gap = Self.petSize / 2 + 3
            a.target = clampedCenter(CGPoint(x: mid.x - gap, y: mid.y))
            b.target = clampedCenter(CGPoint(x: mid.x + gap, y: mid.y))
            a.mode = .meetWalk
            b.mode = .meetWalk
        case .chase:
            a.mode = .pursue
            b.mode = .flee
            b.target = randomBandPoint()
            scriptUntil = activeTime + 3.2
        }
        scriptKind = scriptKind == .meet ? .chase : .meet
    }

    private func beginMeetHold(a: PetActor, b: PetActor) {
        a.mode = .meetHold
        b.mode = .meetHold
        a.facing = a.center.x <= b.center.x ? 1 : -1
        b.facing = -a.facing
        a.hopStart = activeTime
        b.hopStart = activeTime + 0.12
        scriptUntil = activeTime + 3.4
        // 一问一答：异物种用跨物种对答库（猫问狗答/狗问猫
        // 答，声口分明）；同物种时两人各说一句本物种单句，
        // 避免声口串台。两句同显（答句纵深错开 6pt）。
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

    // MARK: 对话气泡

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

    private func showBubble(_ text: String, above actor: PetActor, slot: Int) {
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

    // MARK: 几何工具

    /// 主活动带纵深（容器下半区）的参照 y，fraction 0..1 沿带。
    private func bandCenterY(at fraction: CGFloat) -> CGFloat {
        let top = bounds.height * 0.45
        return top + (bounds.height - 10 - top) * fraction
    }

    private func randomBandPoint() -> CGPoint {
        let half = Self.petSize / 2
        let x = CGFloat.random(in: (half + 6)...max(half + 7, bounds.width - half - 6))
        let top = bounds.height * 0.45 + half
        let y = CGFloat.random(in: top...max(top + 1, bounds.height - half - 6))
        return CGPoint(x: x, y: y)
    }

    private func clampedCenter(_ point: CGPoint) -> CGPoint {
        let half = Self.petSize / 2
        return CGPoint(
            x: min(max(half, point.x), max(half, bounds.width - half)),
            y: min(max(half, point.y), max(half, bounds.height - half)))
    }

    private func clampActorsInside() {
        for actor in allActors {
            actor.center = clampedCenter(actor.center)
        }
    }
}

// MARK: - 占座持久化键

private enum StickerSeat {
    static let xKey = "folia.companion.seat.x"
    static let yKey = "folia.companion.seat.y"
    static let seatedKey = "folia.companion.seat.seated"
}

// MARK: - 贴纸设置（设置页与舞台共用真源）

enum StickerSettings {
    private static let companionKey = "folia.stickers.companionEnabled"
    static var companionEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: companionKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: companionKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: companionKey) }
    }
}
