import UIKit

// 迷你台宠物层（3.7 (27)，Miller 22:15 附图纠正主场）：表情包
// 互动的主场是墙面底部的迷你台（播放台），不是舞台歌词框。
// 本层是纯新增覆盖层，骑在迷你台之上：
//
// - 台上玩耍：展开态（70pt 胶囊）时宠物站在台面顶部一带
//   （Miller 附图红线所示上沿）沿一线走动；常驻 1 只（按曲
//   轮换，与 (25) 同池同规则）+ 嘉宾 1 只（全池轮换）。
// - 随沉掉落：迷你台 5 秒无操作收成 16pt 细条时，宠物不跟
//   台面刚性下移，而是走一段简易重力物理——地面（台上沿）
//   下沉快于宠物下落时宠物离地、加速下落、落点按冲击速度
//   小弹一次；展开（地面上升）时宠物被台面顶着升回（骑乘）。
//   台子的收起逻辑/计时/形态本层一概不碰，只订阅墙侧的一
//   行钩子（形态/显隐/切歌边沿）。
// - 进度条嬉戏 + 全员集合：收起态宠物缩到 30pt 在细条上沿
//   活动，在场扩到 4 只；其余成员按全池（53 只）洗牌队列
//   每约 12s 轮换一只进出，保证每只都有露面机会。展开时
//   只留常驻 + 最久嘉宾随台升回，其余淡出散去。
// - 语言系统：与 (25) 同一套交互语法与台词库（PetLines 为
//   唯一真源，本文件不另抄台词）——点头顶冒反应小贴纸
//   （1.5s 淡出）、点本体弹对话框（被点贴纸本体 + 一句台
//   词，点气泡/点别处关、5s 自动关）、长按 0.35s 拖动（松
//   手从落点掉回地面并「安置」：在原地停留、不参加漫游与
//   编排，直到切歌/形态切换）。宠物之间自主互动沿 (25) 编
//   排：相遇打招呼一问一答、追逐，约每 10–16s 一轮。
// - 触摸面：hitTest 只认领宠物本体与对话框，其余全部透传
//   （点细条展开、台上按键、拖墙平移零影响）。
// - 帧/解码：沿用 StickerView/StickerStore（80MB 共享解码
//   缓存）；本层同时存活的 StickerView 上限 = 演员 4 + 对
//   话框 1 + 反应 ≤2 ≈ 7。舞台框内陪伴（(25) CompanionPet
//   View）原样保留，两处只共用台词/解码基建，互不改动。
// - 状态只读 PlaybackEngine（isPlaying/进度端点），不回写
//   播放状态机；暂停时帧冻结、走动与编排时钟停摆（物理仍
//   结算，宠物不会悬空）。

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
    /// 竖直速度（pt/s，正 = 向下）与着地标志（地面物理用）。
    var vy: CGFloat = 0
    var grounded = true

    enum Mode {
        case idle, walk, peek, meetWalk, meetArrived, meetHold
        case flee, pursue, dragged
    }
    var mode: Mode = .idle
    var targetX: CGFloat = 0
    var until: TimeInterval = 0

    weak var stage: MiniBarPetStage?

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

    /// 朝向 + 蹦跳位移合成（与 (25) 同口径：整只镜像是允许的
    /// 朝向编排，蹦跳只是位移，不改帧）。
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

// MARK: - 迷你台宠物层（管理器）

final class MiniBarPetStage: UIView {

    /// 覆盖层总高：展开台高 70 + 台面上方活动带 176。地面
    /// （台上沿）在本层坐标里随台子形态/动画逐帧由演示层
    /// 帧推导（见 currentGroundY），本常量只定层框。
    private static let overlayHeight: CGFloat = 246
    private static let expandedPetSize: CGFloat = 48
    private static let collapsedPetSize: CGFloat = 30
    private static let expandedCast = 2
    private static let collapsedCast = 4
    private static let gravity: CGFloat = 2600

    private static let fullPool: [String] =
        (1...25).map { String(format: "cat-%02d", $0) } + ["cat-live"]
        + (1...27).map { String(format: "dog-%02d", $0) }
    private static let residentDogPool =
        ["dog-01", "dog-15", "dog-18", "dog-19", "dog-23", "dog-25"]
    private static let reactionPool =
        ["dog-11", "cat-15", "dog-25", "cat-01", "dog-20", "cat-24", "dog-17"]

    private weak var bar: UIView?
    private var barPresented = false
    private var collapsed = false

    private var resident: MiniPetActor?
    private var guests: [MiniPetActor] = []
    private var allActors: [MiniPetActor] {
        (resident.map { [$0] } ?? []) + guests
    }
    private var paradeQueue: [String] = []

    private var displayLink: CADisplayLink?
    private var lastTimestamp: TimeInterval = 0
    /// 编排时钟：只在播放中前进（与 (25) 同口径）。
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

    private var bubbleA: UILabel?
    private var bubbleB: UILabel?
    private var bubblePairUntil: TimeInterval = 0

    private var dialogView: UIView?
    private var dialogSticker: StickerView?
    private var dialogOwner: MiniPetActor?
    private var dialogTimer: Timer?

    private var reactionViews: [ObjectIdentifier: StickerView] = [:]

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
        barPresented = presented
        if presented {
            // 台子每次出现必是完整形态（resetMiniBarFormInstant
            // 保证），宠物层形态同步复位展开态。
            collapsed = false
            isHidden = false
            syncFrame()
            ensureCast()
            startLink()
        } else {
            stopLink()
            hideDialog()
            hideBubbles()
            isHidden = true
        }
    }

    /// 迷你台形态边沿（collapseMiniBarIdle/expandMiniBar 内
    /// 一行钩子）。台子自身的计时与动画本层不碰：收起时演
    /// 员靠物理自己掉到细条上，展开时被台面顶回。
    func barFormChanged(collapsed newValue: Bool) {
        guard barPresented, newValue != collapsed else { return }
        collapsed = newValue
        for actor in allActors { resize(actor) }
        hideDialog()
        guestRotateAt = activeTime + rotateInterval
        ensureCast()
    }

    /// 切歌边沿（refreshMiniBar 内一行钩子）：常驻宠物按曲
    /// 轮换（狗池为主、每 5 首猫客串，与 (25) 同规则），在
    /// 场宠物探头 + 小跳；安置标志清除，座位不跨曲。
    func setTrack(id: String) {
        guard id != lastTrackId else { return }
        lastTrackId = id
        trackSerial += 1
        guard barPresented else { return }
        ensureCast()
        if let resident {
            let asset = trackSerial % 5 == 0
                ? "cat-09"
                : Self.residentDogPool[trackSerial % Self.residentDogPool.count]
            if resident.asset != asset { resident.setAsset(asset) }
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

    // MARK: 触摸认领（只认宠物/对话框，其余透传）

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

    /// 层框跟随台子模型帧（底边对齐、等宽）；地面（台上沿）
    /// 逐帧读台子演示层帧——收起/展开的弹簧过程里地面是连
    /// 续移动的，宠物物理据此掉落/骑乘。
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

    private var rotateInterval: TimeInterval { collapsed ? 12 : 18 }

    private func walkRange(for actor: MiniPetActor) -> ClosedRange<CGFloat> {
        let half = actor.bounds.width / 2
        let lo = half + 6
        let hi = max(lo + 1, bounds.width - half - 6)
        return lo...hi
    }

    // MARK: 演员班底（常驻 + 全池轮换）

    private func ensureCast() {
        guard barPresented, bounds.width > 40 else { return }
        if resident == nil {
            let asset = Self.residentDogPool[
                trackSerial % Self.residentDogPool.count]
            let actor = makeActor(asset: asset)
            actor.center = CGPoint(x: bounds.width * 0.32,
                                   y: currentGroundY() - petSizeNow() / 2)
            resident = actor
        }
        let target = collapsed ? Self.collapsedCast : Self.expandedCast
        while allActors.count < target, let asset = nextFromQueue() {
            spawnGuest(asset: asset)
        }
        while allActors.count > target, let oldest = guests.first {
            removeActor(oldest, animated: true)
        }
        // 暂停态下新建的演员帧冻结（与 framesRunning 口径对齐）。
        if !framesRunning {
            for actor in allActors { actor.stickerView.pause() }
        }
    }

    /// 全池洗牌队列：抽空即重洗（排除在场者），保证每只都
    /// 有露面机会；常驻当前素材不入队。
    private func nextFromQueue() -> String? {
        for _ in 0..<3 {
            if paradeQueue.isEmpty {
                paradeQueue = Self.fullPool.shuffled()
            }
            while let first = paradeQueue.first {
                paradeQueue.removeFirst()
                let onStage = Set(allActors.map { $0.asset })
                if !onStage.contains(first) { return first }
            }
        }
        return nil
    }

    private func makeActor(asset: String) -> MiniPetActor {
        let actor = MiniPetActor(asset: asset, size: petSizeNow())
        actor.stage = self
        addSubview(actor)
        return actor
    }

    /// 嘉宾从条/台的一端入场（淡入 + 落位），走进来。
    private func spawnGuest(asset: String) {
        let actor = makeActor(asset: asset)
        let range = walkRange(for: actor)
        let fromLeft = Bool.random()
        actor.center = CGPoint(
            x: fromLeft ? range.lowerBound : range.upperBound,
            y: currentGroundY() - petSizeNow() / 2)
        actor.targetX = CGFloat.random(in: range)
        actor.mode = .walk
        guests.append(actor)
        actor.alpha = 0
        UIView.animate(withDuration: 0.4) { actor.alpha = 1 }
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
        if animated {
            UIView.animate(withDuration: 0.3, animations: {
                actor.alpha = 0
            }, completion: { _ in actor.removeFromSuperview() })
        } else {
            actor.removeFromSuperview()
        }
    }

    private func resize(_ actor: MiniPetActor) {
        let size = petSizeNow()
        guard actor.bounds.width != size else { return }
        let feet = actor.feetY
        actor.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        actor.feetY = feet
        actor.center.x = min(max(actor.center.x, walkRange(for: actor).lowerBound),
                             walkRange(for: actor).upperBound)
    }

    // MARK: 三分交互（演员回调，语法与 (25) 同构）

    fileprivate func petTapped(_ actor: MiniPetActor, head: Bool) {
        guard !isHidden else { return }
        if head {
            showReaction(above: actor)
        } else {
            showDialog(for: actor)
        }
    }

    fileprivate func petDragBegan(_ actor: MiniPetActor) {
        guard !isHidden else { return }
        hideDialog()
        if scriptPair?.0 === actor || scriptPair?.1 === actor {
            scriptPair = nil
            hideBubbles()
        }
        actor.mode = .dragged
        actor.vy = 0
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

    /// 松手：横向落位（夹回活动范围）、竖直从当前位置掉回
    /// 地面（物理接管），并进入安置态——停在落点附近，不参
    /// 加漫游与编排，直到切歌/形态切换。
    private func dropActor(_ actor: MiniPetActor, at point: CGPoint) {
        let range = walkRange(for: actor)
        actor.center.x = min(max(point.x, range.lowerBound), range.upperBound)
        actor.center.y = min(point.y, currentGroundY() - actor.bounds.height / 2)
        actor.vy = 0
        actor.grounded = false
        actor.placed = true
        actor.mode = .idle
        actor.until = activeTime + 2
    }

    // MARK: 反应小贴纸（点头顶，与 (25) 同池同节奏）

    private func showReaction(above actor: MiniPetActor) {
        let key = ObjectIdentifier(actor)
        reactionViews[key]?.removeFromSuperview()
        let view = StickerView()
        let asset = Self.reactionPool.randomElement() ?? "dog-11"
        view.setSticker(asset, mode: .loop)
        if !framesRunning { view.pause() }
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

    // MARK: 单击对话框（本体 + 台词，台词库与 (25) 共用）

    private func showDialog(for actor: MiniPetActor) {
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
        // 落点：宠物正上方（台面之上是墙面空区，不压台上控
        // 件）；横向夹回层内。
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

    // MARK: 主循环（物理常开结算，走动/编排只在播放中）

    private func startLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard barPresented, window != nil else { return }
        syncFrame()
        if resident == nil { ensureCast() }
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 0.016 : min(0.05, now - lastTimestamp)
        lastTimestamp = now
        let engine = PlaybackEngine.shared
        let playing = engine.isPlaying
        // 歌曲自然播完（由播转停且进度落点在结尾）→ 小蹦，
        // 与 (25) 同判定。
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
        // 物理（着地/掉落/骑乘）不随暂停停摆，宠物不悬空。
        let ground = currentGroundY()
        for actor in allActors { settle(actor, ground: ground, dt: dt) }
        guard playing else { return }
        activeTime += dt
        rotateGuestIfNeeded()
        advanceScript()
        for actor in allActors { advance(actor, dt: dt) }
        if activeTime > bubblePairUntil, bubbleA != nil { hideBubbles() }
    }

    /// 地面物理：脚底低于地面（数值大 = 更靠下）即着地骑
    /// 乘；地面下沉快于下落 → 离地、重力加速、落点按冲击
    /// 速度小弹（衰减至阈值以下即停）。Reduce Motion 时直
    /// 接贴地，不演掉落。
    private func settle(_ actor: MiniPetActor, ground: CGFloat, dt: TimeInterval) {
        guard actor.mode != .dragged else { return }
        if UIAccessibility.isReduceMotionEnabled {
            actor.feetY = ground
            actor.vy = 0
            actor.grounded = true
            return
        }
        var feet = actor.feetY
        if feet >= ground - 0.5 && actor.vy >= 0 {
            // 着地或被上升的台面顶住：贴地。
            actor.feetY = ground
            actor.vy = 0
            actor.grounded = true
            return
        }
        actor.grounded = false
        actor.vy += Self.gravity * CGFloat(dt)
        feet += actor.vy * CGFloat(dt)
        if feet >= ground {
            feet = ground
            if actor.vy > 340 {
                actor.vy = -actor.vy * 0.26
            } else {
                actor.vy = 0
                actor.grounded = true
            }
        }
        actor.feetY = feet
    }

    private func advance(_ actor: MiniPetActor, dt: TimeInterval) {
        // 蹦跳位移（正弦半程 0.45s，仅位置编排，与 (25) 同）。
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
        guard actor.grounded else { return }

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
                    // 逃到一端就折返另一端（条面一线追逐）。
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

    // MARK: 嘉宾轮换（全员集合的节拍）

    private func rotateGuestIfNeeded() {
        guard activeTime >= guestRotateAt, !guests.isEmpty else {
            if guestRotateAt == 0 { guestRotateAt = activeTime + rotateInterval }
            return
        }
        guestRotateAt = activeTime + rotateInterval
        // 换下最久的嘉宾（常驻不换），新嘉宾从一端入场。
        let oldest = guests[0]
        removeActor(oldest, animated: true)
        if let asset = nextFromQueue() {
            spawnGuest(asset: asset)
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
        guard activeTime >= nextInteractionAt else { return }
        let free = allActors.filter {
            !$0.placed && $0.grounded && $0.mode != .dragged && $0.mode != .peek
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
        // 物种单句（防声口串台），与 (25) 同规则；台词真源
        // PetLines，两处共用。
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
