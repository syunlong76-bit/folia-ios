import UIKit

// 灵动岛宠物层（3.7 (32)，Miller 2026-11-20 01:05 定案的障眼
// 法版 + 01:55 三地流转）：宠物不进真灵动岛（Live Activity
// 不给逐帧动画）——墙台宠物说完告别词后分流至此，沿屏幕往
// 上蹦到灵动岛位置落座；灵动岛由系统渲染、恒在本层之上，
// 宠物下半身被岛的黑框天然遮住、上半身露出，像坐在岛里。
//
// 承载：3.7 (39) 改挂主窗根视图顶层（单窗）——独立
// UIWindow 形态经 (36)/(37)/(38) 三轮真机二分定案为冻死
// 充分条件（与 level、岛上内容无关），障眼法几何只依赖
// 屏幕坐标、不依赖独立窗口，故取消建窗。
// 3.7 (41) 组1（审计 folia40-failures A1 定案）：(39) 的根
// 视图宿主被呈现栈整体盖住——主页/曲目墙/舞台/设置页全是
// 一层层 present 上去的，被 present 的视图恒在根视图之上，
// install 时那一次 bringSubviewToFront 对呈现栈无效，宠物
// 爬升/落座/停聊全程在被盖住的层里空跑（日志机制全活、
// Miller 从未看见）。改挂**主窗本体**的顶层子视图（仍是同
// 一个窗的子视图，不新建独立 UIWindow，不碰 (39) 冻案红
// 线），并设 0.5s 置顶守护：任一呈现/散场后窗口子视图顺序
// 有变，下一拍即把本层重新置顶；呈现完成时刻另有事件驱动
// 的即时置顶（install/激活/收宠物）。墙↔舞台↔主页之间导
// 航时不消失、不重建。hitTest 只认领宠物本体，其余全穿
// 透。仅 App 前台有效；横屏时岛位不在顶部，本层保守隐藏
// 宠物（状态保留，回竖屏恢复）。
//
// 几何（iPhone 14 Pro 竖屏，窗口坐标）：岛黑框约宽 126、
// 高 37、顶距屏幕上沿约 11pt。宠物 46pt，脚底落在 y≈45
// （岛下沿内侧），头顶探出岛上沿之上；双宠时分坐岛心左右
// ±40pt。落座后常驻闲晃（小幅位移）、偶尔冒「到家库」气
// 泡；住满 2 只时按人格停聊（细修 5，轮流冒泡）。点岛上
// 宠物 → 蹦回当前最前点播台（舞台优先，其次墙台）；被墙
// 台召回时经 PetHomeRegistry.onIslandDeparture 通知撤下。
//
// 已知边界：岛被系统事件（来电/Face ID 等）展开时无公开
// 信号可测，宠物落点会短暂错位，事件结束岛恢复原尺寸后
// 宠物仍在原座位（不穿帮成悬空——宠物始终贴在岛原几何上）。

private final class IslandPetView: UIView {
    let stickerView = StickerView()
    let asset: String
    var personality: PetPersonality { PetPersonalities.of(asset) }
    /// 落座基准点（脚底中心），闲晃在其周围小幅漂移。
    var seatFeet = CGPoint.zero
    weak var islandLayer: PetIslandLayer?

    init(asset: String, size: CGFloat) {
        self.asset = asset
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        stickerView.frame = bounds
        stickerView.crumbScene = "island-pet"
        stickerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stickerView)
        stickerView.setSticker(asset, mode: .loop)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    @objc private func handleTap() { islandLayer?.islandPetTapped(self) }
    @objc private func handleDoubleTap() { islandLayer?.islandPetDoubleTapped(self) }

    var feetY: CGFloat {
        get { center.y + bounds.height / 2 }
        set { center.y = newValue - bounds.height / 2 }
    }
}

final class PetIslandLayer: UIView {

    static let shared = PetIslandLayer()

    private static let petSize: CGFloat = 46
    /// 岛下沿内侧（脚底线）：岛顶 11 + 岛高 37 ≈ 48，脚底
    /// 压在 45 使下半身落在岛框内被遮、上半身探出。
    private static let seatFeetY: CGFloat = 45

    private var pets: [IslandPetView] = []
    private var tickTimer: Timer?
    /// 宿主主窗（3.7 (41) 组1）：本层是它的直接子视图；scene
    /// 重连会换新窗，install 时按当前窗重新挂载。
    private weak var hostWindow: UIWindow?
    /// 置顶守护（3.7 (41) 组1）：0.5s 一拍核对本层是否仍是
    /// 主窗最顶子视图，不是则重新置顶并落 island.refront。
    private var refrontTimer: Timer?
    private var nextBubbleAt: TimeInterval = 0
    private var nextChatAt: TimeInterval = 0
    private var chatLines: [(pet: IslandPetView, text: String)] = []
    private var chatLineIndex = -1
    private var chatLineUntil: TimeInterval = 0
    private var bubbleLabel: UILabel?
    private var bubbleUntil: TimeInterval = 0
    private var reactionView: StickerView?

    private init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: 安装（SceneDelegate 建窗后一行）

    static func install(in windowScene: UIWindowScene) {
        let layer = PetIslandLayer.shared
        // 3.7 (41) 组1：宿主改主窗本体（SceneDelegate 的 window
        // 优先，key window 兜底）。superview 不是当前主窗（首
        // 装/scene 重连换了新窗）就重新挂载；frame 与
        // autoresizing 跟随窗口 bounds，落座几何口径不变。
        let hostWindow = (windowScene.delegate as? SceneDelegate)?.window
            ?? windowScene.windows.first(where: { $0.isKeyWindow })
            ?? windowScene.windows.first
        guard let window = hostWindow else {
            Breadcrumbs.log("island.install skipped=no-host")
            return
        }
        if layer.superview !== window {
            layer.removeFromSuperview()
            layer.frame = window.bounds
            layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(layer)
            window.bringSubviewToFront(layer)
            layer.hostWindow = window
            Breadcrumbs.log("island.install host=window"
                + " residents=\(PetHomeRegistry.shared.islandResidents.count)")
            PetHomeRegistry.shared.onIslandDeparture = { [weak layer] asset in
                layer?.releasePet(asset: asset)
            }
        }
        layer.startRefrontGuard()
        // 冷启动时登记表为空；若已有岛民（重连场景）补落座。
        for asset in PetHomeRegistry.shared.islandResidents
        where !layer.pets.contains(where: { $0.asset == asset }) {
            layer.seatPet(asset: asset, animated: false, fromRect: nil)
        }
        layer.updateVisibility()
    }

    // MARK: 置顶守护（3.7 (41) 组1）

    /// 启动置顶守护（幂等）：0.5s 一拍（.common 模式，转场/
    /// 滚动期间照常走）。守护只做一件事——本层不是主窗最顶
    /// 子视图时重新置顶；呈现栈怎么变都不需要逐个挂钩。
    private func startRefrontGuard() {
        guard refrontTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refrontIfNeeded(logged: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        refrontTimer = timer
    }

    /// 即时置顶（事件驱动入口：SceneDelegate 激活、收宠物
    /// 时调用）：守护拍之间的呈现变化不等下一拍。
    func refrontIfNeeded() {
        refrontIfNeeded(logged: false)
    }

    private func refrontIfNeeded(logged: Bool) {
        guard let window = hostWindow, superview === window else { return }
        guard window.subviews.last !== self else { return }
        window.bringSubviewToFront(self)
        if logged { Breadcrumbs.log("island.refront") }
    }

    // MARK: 触摸穿透（只认领宠物本体）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01 else { return nil }
        for sub in subviews.reversed() {
            guard !sub.isHidden, sub.isUserInteractionEnabled else { continue }
            let converted = sub.convert(point, from: self)
            if let hit = sub.hitTest(converted, with: event) { return hit }
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reseatAll(animated: false)
        updateVisibility()
    }

    private var isPortrait: Bool { bounds.width <= bounds.height }

    private func updateVisibility() {
        // 横屏保守隐藏（岛不在顶部）；竖屏恢复。
        let show = isPortrait
        for pet in pets { pet.isHidden = !show }
        if !show { hideBubble() }
    }

    // MARK: 落座 / 撤下

    /// 墙台分流送达：从出发点（主窗口坐标，与本层同屏几何）
    /// 蹦到岛上座位（弹簧 + 两下蹦跳）。爬升动画开始前先即
    /// 时置顶一次，不等守护拍（3.7 (41) 组1）。
    func receive(asset: String, fromRect: CGRect?) {
        refrontIfNeeded()
        seatPet(asset: asset, animated: true, fromRect: fromRect)
    }

    private func seatPet(asset: String, animated: Bool, fromRect: CGRect?) {
        guard !pets.contains(where: { $0.asset == asset }) else { return }
        guard pets.count < PetHomeRegistry.islandCapacity else { return }
        let pet = IslandPetView(asset: asset, size: Self.petSize)
        pet.islandLayer = self
        addSubview(pet)
        pets.append(pet)
        reseatAll(animated: false)
        if animated, let fromRect {
            let target = pet.center
            pet.center = CGPoint(x: fromRect.midX, y: fromRect.midY)
            pet.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            pet.alpha = 0.6
            UIView.animateKeyframes(withDuration: 0.85, delay: 0, options: []) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.35) {
                    pet.center = CGPoint(x: (fromRect.midX + target.x) / 2,
                                         y: min(fromRect.midY, target.y) - 60)
                    pet.alpha = 1
                }
                UIView.addKeyframe(withRelativeStartTime: 0.35, relativeDuration: 0.3) {
                    pet.center = CGPoint(x: target.x, y: target.y - 14)
                    pet.transform = .identity
                }
                UIView.addKeyframe(withRelativeStartTime: 0.65, relativeDuration: 0.35) {
                    pet.center = target
                }
            }
            showBubble(PetLines.islandHome.randomElement() ?? "", above: pet, duration: 2.4)
        }
        startTimerIfNeeded()
        if nextBubbleAt == 0 { nextBubbleAt = clockNow + 9 }
        if nextChatAt == 0 { nextChatAt = clockNow + 22 }
    }

    /// 撤下（被召回/点按回台）：小跳一下淡出。回台的「到场」
    /// 由目标台自己的入场动画承接。
    func releasePet(asset: String) {
        guard let pet = pets.first(where: { $0.asset == asset }) else { return }
        pets.removeAll { $0 === pet }
        if chatLines.contains(where: { $0.pet === pet }) { endChat() }
        if bubbleLabel != nil { hideBubble() }
        UIView.animate(withDuration: 0.3, animations: {
            pet.transform = CGAffineTransform(translationX: 0, y: -10)
                .scaledBy(x: 0.8, y: 0.8)
            pet.alpha = 0
        }, completion: { _ in pet.removeFromSuperview() })
        reseatAll(animated: true)
        if pets.isEmpty {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func reseatAll(animated: Bool) {
        guard isPortrait else { return }
        let cx = bounds.width / 2
        for (index, pet) in pets.enumerated() {
            let offset: CGFloat = pets.count == 1 ? 0 : (index == 0 ? -40 : 40)
            pet.seatFeet = CGPoint(x: cx + offset, y: Self.seatFeetY)
            let target = CGPoint(x: pet.seatFeet.x,
                                 y: pet.seatFeet.y - Self.petSize / 2)
            if animated {
                UIView.animate(withDuration: 0.5, delay: 0,
                               usingSpringWithDamping: 0.85,
                               initialSpringVelocity: 0.1, options: []) {
                    pet.center = target
                }
            } else if pet.center == .zero || !isAnimatingArrival(pet) {
                pet.center = target
            }
        }
    }

    private func isAnimatingArrival(_ pet: IslandPetView) -> Bool {
        pet.layer.animation(forKey: "position") != nil
    }

    // MARK: 点按回台 / 双击反应

    fileprivate func islandPetTapped(_ pet: IslandPetView) {
        if let target = PetHomeRegistry.shared.frontmostStage() {
            // 台侧入场动画承接「蹦回」；本层经登记回调撤下。
            target.receiveReturningPet(asset: pet.asset)
        } else {
            // 没有点播台在场：留在岛上，小跳 + 一句到家词。
            hop(pet)
            showBubble(PetLines.islandHome.randomElement() ?? "",
                       above: pet, duration: 1.8)
        }
    }

    fileprivate func islandPetDoubleTapped(_ pet: IslandPetView) {
        reactionView?.removeFromSuperview()
        let view = StickerView()
        view.crumbScene = "island-reaction"
        let asset = MiniBarPetStage.reactionPool.randomElement() ?? "dog-11"
        let size: CGFloat = 36
        var x = pet.frame.maxX + 2
        if x + size > bounds.width - 2 { x = pet.frame.minX - size - 2 }
        view.frame = CGRect(x: x, y: pet.frame.minY + 2, width: size, height: size)
        view.silhouetteHaloEnabled = (asset == "dog-11")
        view.setSticker(asset, mode: .loop)
        view.isUserInteractionEnabled = false
        addSubview(view)
        reactionView = view
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
                if self?.reactionView === view { self?.reactionView = nil }
            })
        }
    }

    private func hop(_ pet: IslandPetView) {
        let base = pet.center
        UIView.animateKeyframes(withDuration: 0.45, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                pet.center = CGPoint(x: base.x, y: base.y - 9)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                pet.center = base
            }
        }
    }

    // MARK: 闲晃 / 冒泡 / 停聊（1s 心跳驱动）

    private var clockNow: TimeInterval { CACurrentMediaTime() }

    private func startTimerIfNeeded() {
        guard tickTimer == nil else { return }
        nextBubbleAt = clockNow + 9
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in self?.tick()
        }
    }

    private func tick() {
        guard isPortrait, !pets.isEmpty else { return }
        let now = clockNow
        // 气泡过期。
        if bubbleLabel != nil, now >= bubbleUntil, chatLineIndex < 0 {
            hideBubble()
        }
        // 停聊推进（住满 2 只）：轮流冒泡，一句约 1.4s。
        if chatLineIndex >= 0 {
            if now >= chatLineUntil {
                chatLineIndex += 1
                presentChatLine()
            }
            return
        }
        // 闲晃：每拍随机一只小幅漂移（落座点 ±3pt）。
        if let pet = pets.randomElement(), Int.random(in: 0..<3) == 0 {
            let target = CGPoint(
                x: pet.seatFeet.x + .random(in: -3...3),
                y: pet.seatFeet.y - Self.petSize / 2 + .random(in: -1...1))
            UIView.animate(withDuration: 0.9, delay: 0,
                           usingSpringWithDamping: 0.7,
                           initialSpringVelocity: 0.4, options: []) {
                pet.center = target
            }
        }
        // 双宠停聊触发。
        if pets.count >= 2, now >= nextChatAt {
            startChat()
            return
        }
        // 单/双宠日常冒泡（到家库）。
        if now >= nextBubbleAt, let pet = pets.randomElement() {
            nextBubbleAt = now + .random(in: 16...30)
            showBubble(PetLines.islandHome.randomElement() ?? "",
                       above: pet, duration: 2.4)
        }
    }

    private func startChat() {
        guard pets.count >= 2 else { return }
        let a = pets[0], b = pets[1]
        let dialogue = PetChat.generate(a: a.personality, b: b.personality)
        chatLines = dialogue.lines.map {
            (pet: $0.speakerIsA ? a : b, text: $0.text)
        }
        chatLineIndex = 0
        Breadcrumbs.log("pet.chat surface=island"
            + " a=\(a.asset)(\(a.personality.label))"
            + " b=\(b.asset)(\(b.personality.label))"
            + " topic=\(dialogue.topic.label)"
            + " combo=o\(dialogue.openerIndex)/r\(dialogue.responseIndex)"
            + " lines=\(dialogue.lines.count)")
        presentChatLine()
    }

    private func presentChatLine() {
        guard chatLineIndex >= 0, chatLineIndex < chatLines.count else {
            endChat()
            return
        }
        let line = chatLines[chatLineIndex]
        chatLineUntil = clockNow + 1.4
        showBubble(line.text, above: line.pet, duration: 1.4)
        hop(line.pet)
    }

    private func endChat() {
        chatLines = []
        chatLineIndex = -1
        hideBubble()
        nextChatAt = clockNow + .random(in: 25...45)
    }

    // MARK: 气泡（挂在宠物下方：头顶上方是屏幕沿与岛框，
    // 气泡垂在岛下沿之下，像挂在岛上说话）

    private func showBubble(_ text: String, above pet: IslandPetView,
                            duration: TimeInterval) {
        hideBubble()
        guard !text.isEmpty else { return }
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
        let x = min(max(4, pet.frame.midX - w / 2), bounds.width - w - 4)
        label.frame = CGRect(x: x, y: pet.frame.maxY + 4, width: w, height: h)
        addSubview(label)
        bubbleLabel = label
        bubbleUntil = clockNow + duration
        label.alpha = 0
        label.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.7,
                       options: []) {
            label.alpha = 1
            label.transform = .identity
        }
    }

    private func hideBubble() {
        bubbleLabel?.removeFromSuperview()
        bubbleLabel = nil
    }
}

