import UIKit

/// 全局宠物召唤/关闭钮（3.7 (70) B2 终版，Miller 四度定版）。
/// (72) 修订：①全局可达做实——(71) 真机证伪「同位可达」：
/// 本钮是窗口子视图，presented 页的视图后入窗即盖住它，
/// 实际只在主页够得着；本版加 0.5s 序位守护恒提最上（见
/// frontGuardTimer）。②弱化存在感：36pt/静置 0.35/贴边
/// （见类内 (72) 弱化定版注）。
///
/// 沿革：点播台 4s 长按开启（(60) 第 8 条）与台面切主题长
/// 按同域打架、进度圆环干扰操作，(70) 整套撤除；召唤中途
/// 案（舞台长按、舞台双指下滑——墙面要拖动）均作废，终案
/// 为本钮：主窗口根层之上的右下角小爪印钮。
///
/// 状态相关双阈值开关（阈值按按下瞬间的开关态设定，不存
/// 在 3s 穿过 2s 的问题）：
///  - 宠物关态：长按 2.0s → 召唤（开关双写 on＋当前面宠物
///    掉落入场 performDropInEntrance＋中震动），面包屑
///    pet.switch on via=corner2s。
///  - 宠物开态：长按 3.0s → 关闭（开关双写 off＋当前面宠
///    物走 dismiss 告别离场 performFarewellDismissAll70，
///    与长按宠物本体关闭同路），面包屑 pet.switch off
///    via=corner3s。长按宠物本体 3s 关闭的老路保留不动。
///
/// 纪律：
///  - 短按不绑任何动作（防误触）；长按识别器
///    cancelsTouchesInView=false，不拦页面其他手势。
///  - 按压反馈只许钮自身：静置半透明低调；按压中随阈值时
///    长渐亮＋轻微放大（线性填充属计时反馈、非转场动画，
///    与旧进度环填充同口径），触发脉冲后系统弹簧回落。
///    不许用圆环。
///  - 几何：右下角、安全区内、底边在点播台展开态顶边
///    （安全区底 +10 间距 +70 台高 = 80）之上再留 8pt
///    （=88）；(68) 全宽条顶边为安全区底 +64，同被避开。
///    横竖屏同式成立（点播台横屏居中同宽同高）。
///  - 阈值新鲜度：开关无变更通知，阈值在每次 hitTest（触
///    摸管线最前端、先于识别器计时）现读开关刷新，另在安
///    装与每次触发后刷新——外部路径（设置/长按宠物）改过
///    开关后，下一次按下读到的恒为现态。
final class PetSummonButton70: UIView {

    // (72) 弱化定版（Miller (71) 验收：坐在右下角太突兀）：
    // 直径 44→36、静置 alpha 0.55→0.35、圆底 0.35→0.22、
    // 右距 14→8 贴边。长按阈值与反馈语义不变。
    // (74) 位置改版（Miller 图5 红圈定点）：落屏幕右下角本
    // 角——底距由 88（避点播台展开高）改为 10、右距 10，
    // 贴右下安全区。代价自知：点播台展开态（高 70、底距
    // 10）时本钮叠在台体右端之上（窗口层 z 序在本钮），
    // 收起态小横线居中不与本钮相干；按 Miller 定点执行。
    // (75) 第 5 项①口径更正（Miller 20:39）：钮位置恒定不
    // 动、改台让位——三宿主点播台底锚 −10→−54，台身下缘
    // 恒在本钮带（底 −10、高 36）之上 8pt，展开/细条两态
    // 均不与本钮重叠（上下邻居）。
    private static let diameter: CGFloat = 36
    private static let bottomClearance: CGFloat = 10
    private static let idleAlpha: CGFloat = 0.35

    /// (74) 入场抑制：开局油画呈现全程本钮不许出现（图4
    /// 它浮在油画右下被点名）。EntryIntro 呈现/消散两点调
    /// setEntrySuppressed 显式开关，frontGuard 每拍再按呈现
    /// 链里有无 EntryIntroViewController 兜底对账（漏挂钩
    /// 时自愈、误挂时不残留）。
    private static weak var sharedInstance: PetSummonButton70?
    private var entrySuppressed = false

    private let circleView = UIView()
    private let iconView = UIImageView()
    private let pressRecognizer = UILongPressGestureRecognizer()
    private var rampAnimator: UIViewPropertyAnimator?
    /// (75) 第 6 项全链埋点：本次按压是否已触发长按动作
    /// （touchesEnded 落 up 行时对位短按/长按）。
    private var pressTriggered = false
    /// (72) 全局可达守护：本钮是窗口子视图，presented 页
    /// （舞台/详情/歌单/设置）的视图后加进来会把它盖住——
    /// (71) 真机「只在主页有、其他页面够不着」的根因。0.5s
    /// 一拍（.common）核序位、非最上即提回（与岛层 graft 守
    /// 护同思路；本钮只占右下角 36pt，与岛 proxy 的顶部带、
    /// 停靠层的宠物拖拽区不重叠，提顶不抢任何手势）。
    private var frontGuardTimer: Timer?

    static func install(in window: UIWindow) {
        let button = PetSummonButton70()
        sharedInstance = button
        window.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: diameter),
            button.heightAnchor.constraint(equalToConstant: diameter),
            button.trailingAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.trailingAnchor,
                constant: -10),
            button.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -bottomClearance),
        ])
        button.startFrontGuard()
    }

    /// (74) 入场抑制显式开关（EntryIntro 呈现/消散点调用）。
    static func setEntrySuppressed(_ on: Bool) {
        sharedInstance?.entrySuppressed = on
        sharedInstance?.refreshEntryVisibility()
        if on { Breadcrumbs.log("pet.btn74 entryhide") }
    }

    private func refreshEntryVisibility() {
        let introInChain = Self.introInPresentedChain(window: window)
        let shouldHide = entrySuppressed || introInChain
        if isHidden != shouldHide { isHidden = shouldHide }
    }

    /// 呈现链里有无入场页（frontGuard 兜底对账用）。
    private static func introInPresentedChain(window: UIWindow?) -> Bool {
        var vc = window?.rootViewController
        while let current = vc {
            if current is EntryIntroViewController { return true }
            vc = current.presentedViewController
        }
        return false
    }

    private func startFrontGuard() {
        guard frontGuardTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let window = self.window else { return }
            // (74) 每拍先对账入场抑制（呈现链兜底），再提层。
            self.refreshEntryVisibility()
            if window.subviews.last !== self {
                window.bringSubviewToFront(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frontGuardTimer = timer
    }

    private init() {
        super.init(frame: CGRect(x: 0, y: 0,
                                 width: Self.diameter, height: Self.diameter))
        backgroundColor = .clear
        alpha = Self.idleAlpha

        circleView.frame = bounds.insetBy(dx: 2, dy: 2)
        circleView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        circleView.layer.cornerRadius = circleView.bounds.width / 2
        circleView.layer.borderWidth = 1
        circleView.layer.borderColor =
            UIColor.white.withAlphaComponent(0.18).cgColor
        circleView.isUserInteractionEnabled = false
        addSubview(circleView)

        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        iconView.image = UIImage(systemName: "pawprint.fill",
                                 withConfiguration: config)
        iconView.tintColor = UIColor.white.withAlphaComponent(0.9)
        iconView.contentMode = .center
        iconView.frame = bounds
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

        pressRecognizer.minimumPressDuration = Self.currentThreshold()
        pressRecognizer.allowableMovement = 12
        pressRecognizer.cancelsTouchesInView = false
        pressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(pressRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func currentThreshold() -> TimeInterval {
        StickerSettings.miniPetsEnabled ? 3.0 : 2.0
    }

    private func refreshThreshold() {
        pressRecognizer.minimumPressDuration = Self.currentThreshold()
    }

    /// hitTest 在触摸管线最前端（先于识别器开始计时）：
    /// 每次按下前现读开关刷新阈值，阈值恒为按下瞬间的
    /// 开关态。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil { refreshThreshold() }
        return hit
    }

    // MARK: 按压反馈（只许钮自身渐亮＋轻微放大，不用圆环）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // (75) 到达自证：触摸真落到钮上即落一行（此前本钮
        // 按压全链零面包屑，(75) 第 6 项日志实锤：整轮分不
        // 清没按到/短按无语义/被门拒绝）。
        pressTriggered = false
        Breadcrumbs.log("paw.touch75 dn en=\(StickerSettings.miniPetsEnabled ? 1 : 0)")
        rampAnimator?.stopAnimation(true)
        let ramp = UIViewPropertyAnimator(
            duration: pressRecognizer.minimumPressDuration,
            curve: .linear) { [weak self] in
            guard let self else { return }
            self.alpha = 1
            self.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            self.circleView.backgroundColor =
                UIColor.black.withAlphaComponent(0.55)
        }
        rampAnimator = ramp
        ramp.startAnimation()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // (75) 抬手对位：trig=0 即短按（本钮短按无语义、只
        // 有渐亮反馈，长按 2s/3s 才触发）——日志自此能分清
        // 「用户短按了」与「压根没按到」。
        Breadcrumbs.log("paw.touch75 up trig=\(pressTriggered ? 1 : 0)")
        settleToIdle()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        Breadcrumbs.log("paw.touch75 cancel")
        settleToIdle()
    }

    private func settleToIdle() {
        rampAnimator?.stopAnimation(true)
        rampAnimator = nil
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) { [weak self] in
            guard let self else { return }
            self.alpha = Self.idleAlpha
            self.transform = .identity
            self.circleView.backgroundColor =
                UIColor.black.withAlphaComponent(0.22)
        }
    }

    // MARK: 触发（阈值到点，识别器 .began）

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        pressTriggered = true
        // 触发脉冲：先冲到最亮最大，弹簧回落静置态。
        rampAnimator?.stopAnimation(true)
        rampAnimator = nil
        alpha = 1
        transform = CGAffineTransform(scaleX: 1.22, y: 1.22)
        circleView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        settleToIdle()

        if StickerSettings.miniPetsEnabled {
            // 关闭：开关双写 off＋当前面 dismiss 告别离场。
            SettingsStore.miniPetsEnabled = false
            StickerSettings.miniPetsEnabled = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Breadcrumbs.log("pet.switch off via=corner3s")
            let stage = currentFacePetStage()
            Breadcrumbs.log("paw.act75 on=0 stage=\(stage != nil ? 1 : 0)")
            stage?.performFarewellDismissAll70()
            // (73)：岛民常驻不随全局关撤下（reconcile 已
            // 解耦），本调用仅作稳定事件对账。
            PetHomeRegistry.shared.reconcileIsland(reason: "switch")
        } else {
            // 召唤：开关双写 on＋当前面掉落入场（写入场门控
            // 读开关，故先写后调，与旧组件同序）。
            SettingsStore.miniPetsEnabled = true
            StickerSettings.miniPetsEnabled = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Breadcrumbs.log("pet.switch on via=corner2s")
            // (75) 第 6 项定案：召唤＝用户明确意图，开关已
            // 双写 on 在前，入场不许再被任何陈旧态拦死——
            // 当前面层找不到（stage=nil）时改走广播兜底，各
            // 宠物层自查在场且开关已开即自行入场（见
            // MiniBarPetStage 的 pawSummonObserver）。
            let stage = currentFacePetStage()
            Breadcrumbs.log("paw.act75 on=1 stage=\(stage != nil ? 1 : 0)")
            if let stage {
                stage.performDropInEntrance()
            } else {
                NotificationCenter.default.post(name: .foliaPawSummon75, object: nil)
            }
            // (72)：全局开后岛民确定性落座（稳定事件触发）。
            PetHomeRegistry.shared.reconcileIsland(reason: "switch")
        }
        refreshThreshold()
    }

    /// 当前面宠物层：自本钮所在窗口的根沿 presented 链走
    /// 到最顶层控制器，只在其视图子树内逆序（上层优先）
    /// 找 MiniBarPetStage——墙在舞台之下时只命中舞台那
    /// 只，模态页（无宠物层）时返回 nil（开关照写、入场/
    /// 离场由各面自身同步兜底）。
    private func currentFacePetStage() -> MiniBarPetStage? {
        guard let root = window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return Self.findPetStage(in: top.view)
    }

    private static func findPetStage(in view: UIView) -> MiniBarPetStage? {
        for subview in view.subviews.reversed() {
            if let stage = subview as? MiniBarPetStage { return stage }
            if let found = findPetStage(in: subview) { return found }
        }
        return nil
    }
}

extension Notification.Name {
    /// (75) 爪印召唤兜底广播：当前面宠物层定位失败时发，
    /// 各 MiniBarPetStage 自查在场＋开关已开后自行入场。
    static let foliaPawSummon75 = Notification.Name("folia.paw.summon75")
}
