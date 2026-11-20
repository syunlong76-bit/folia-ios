import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Breadcrumbs.log("scene.connect")

        // 0) 样式防卡死守卫（3.7 (44)）：必须在任何舞台呈现
        //    之前跑完——上次会话若有样式开台未及证明存活就
        //    进程消亡（pending 未清），本次启动先把该样式回
        //    退 classic，点歌台/route 哪条入口开台都安全。
        StageStyleStore.runLaunchStyleGuard()

        // 1) 准备 Web 根目录：首次拷贝内置版本；如有已下载待生效的新版本且目录完整，切换生效
        WebRootManager.shared.prepare()

        // M1 阶段 2：启动登录 Cookie 同步观察（原生数据链的前置）。
        CookieSync.shared.start()

        // 2) 主界面（内含 WKWebView + 本地服务器启动）；窗口底色纯黑，
        //    避免全屏沉浸时系统窗口在边缘透出白底
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = MainViewController()
        window.makeKeyAndVisible()
        self.window = window

        // 灵动岛宠物承载层（3.7 (32)）：独立穿透窗挂根级，
        // 导航不消失；宠物由墙台告别分流送达（PetIslandLayer）。
        // 3.7 (35) 二分：岛窗整层短路不装（FoliaBisect），判
        // 读后再恢复。
        if FoliaBisect.islandWindowDisabled {
            Breadcrumbs.log("island.install skipped=bisect35")
        } else {
            PetIslandLayer.install(in: windowScene)
        }

        // 宠物全屏停靠层（3.7 (43) 路4）：岛层之后安装，z-order
        // 岛层 > 停靠层 > 呈现内容；同为单窗子视图，不建窗。
        PetDockLayer.install(in: windowScene)

        // 点卡 route 闸门回调接线（3.7 (46)）：StageExitGate 的
        // 正当退出落定 / 守卫期重入 / giveup 三路回调进本状态机。
        wireRouteGateCallbacks()

        // 2.5) 入场视频不在冷启动挂（3.7 (17) 挪位）：冷启直落
        //     Web 主界面；v5 油画视频改由主页墙进入页触发（见
        //     HomeWallViewController 的入场槽位），替换原电影长卷。

        // 3) 冷启动自动检查更新（开关开启时，后台队列执行，不阻塞启动）
        if UpdateManager.shared.autoUpdateEnabled {
            DispatchQueue.global(qos: .utility).async {
                UpdateManager.shared.checkNow(completion: nil)
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {
        // 状态机 armed → foregroundPending：呈现决策等
        // didBecomeActive 后场景稳定再做（DS 定案时机）。
        guard routeState == .armed else { return }
        routeState = .foregroundPending
        Breadcrumbs.log("nowplaying.route pending gen=\(routeGeneration) armedVia=\(routeArmedVia)")
        installRouteTouchObserver()
    }

    // MARK: - 后台点入直达播放详情页（3.7 (31) → (46) 状态机）

    /// 本 delegate 实例是否已处理过首次激活：冷启动与 scene
    /// 重连都是新实例、首次激活时 route 未武装，靠进程年龄分岔
    /// （见 sceneDidBecomeActive）：进程新生绝不 route（(43)
    /// 冷启劫持定案），活进程 scene 重连按后台点入合成武装。
    private var didHandleFirstActivation = false

    /// 点卡 route 代际（3.7 (46)）：每次进后台 +1、重连合成武装
    /// 也 +1；一切 route 异步步骤与闸门回调都按它对齐，防上一
    /// 轮的步骤在新一轮里误触发。
    private var routeGeneration = 0

    // MARK: 点卡 route 状态机（3.7 (46)，DS route-final 定案）
    //
    // disarmed →（进后台/重连武装）armed →（willEnterForeground）
    // foregroundPending →（didBecomeActive）routing →（呈现校验
    // 通过）stageVisible →（3 秒守卫到期舞台仍在）settled；终局
    // 失败 → giveup。呈现时机 = 场景稳定（foregroundActive、根
    // 已 attached、链上无进行中转场）后短重试（0.12s × ≤10，
    // 废除 (45) 的 10s 长重试）。用户意图只认显式信号：
    // pending/routing 期间窗口内任一 touch 即 cancel route；
    // (45) 的 gateEventSeq 推断式自弃已废除。舞台退出全经
    // StageExitGate，route 成功后由其 RouteGuard 守 3 秒。

    private enum RouteState {
        case disarmed, armed, foregroundPending, routing, stageVisible, settled, giveup
    }
    private var routeState: RouteState = .disarmed
    /// 武装来源与武装时刻现场快照（route.begin 落痕用，DS 2.4）。
    private var routeArmedVia = "-"
    private var routeBgTopName = "-"
    private var routeBgStageToken = "-"
    private var routeBgEngineTrackId: String?
    private var routeAttempts = 0
    private var routeLastRetryReason = ""
    private var routeTouchObserver: TouchDownObserverRecognizer?

    func sceneDidEnterBackground(_ scene: UIScene) {
        // 武装新一轮 route（3.7 (46) 状态机）：代际 +1、快照
        // 武装现场（当时链顶/stageToken/引擎装载），回前台时
        // route.begin 带出对账。锁屏场景的武装时机在此覆盖两
        // 路——前台时锁屏走 willResignActive→本回调；已在后台
        // 时锁屏无新事件，但武装早在本次进后台时已置位，锁屏
        // 期间不消费，点卡激活时仍有效。
        routeGeneration += 1
        recordRouteArmament(via: "background")
        // 进后台即解除上一轮 RouteGuard：后台期间不存在需要
        // 守的呈现，防守卫跨周期误 veto 正当 dismiss。
        StageExitGate.shared.disarmGuard(reason: "scenePhase-background")
        removeRouteTouchObserver()
    }

    /// 武装快照：当前呈现链顶类名、canonical 舞台 token、引擎
    /// 真装载 track id（纸面队列不算，(45) R-1 口径延续）。
    private func recordRouteArmament(via: String) {
        routeArmedVia = via
        if let root = window?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            routeBgTopName = String(describing: type(of: top))
        } else {
            routeBgTopName = "no-root"
        }
        routeBgStageToken = StageExitGate.shared.canonicalStageToken
        routeBgEngineTrackId = PlaybackEngine.shared.currentTrack?.id
        routeState = .armed
        Breadcrumbs.log("nowplaying.route armed gen=\(routeGeneration) via=\(via) top=\(routeBgTopName) stageToken=\(routeBgStageToken) engineTrack=\(routeBgEngineTrackId ?? "nil")")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 岛层即时置顶（3.7 (41) 组1）：回前台先把岛层送回
        // 主窗最顶，不等 0.5s 守护拍；未安装时为空操作。
        PetIslandLayer.shared.refrontIfNeeded()
        if routeState == .armed || routeState == .foregroundPending {
            didHandleFirstActivation = true
            beginRoute()
            return
        }
        if !didHandleFirstActivation {
            didHandleFirstActivation = true
            // 首次激活分岔（Miller 定案口径）：①进程新生（距
            // AppProcessMark 启动标记 <5s）= 真冷启：(43) 日志
            // 实锤冷启 route 在普通图标启动时也触发、绕过入场
            // 与墙直落舞台，是「进不去软件」死循环主犯——绝不
            // route，走正常入场→墙；恢复队列留在迷你台，用户
            // 开台时由 StageViewController 触发装载。②进程已
            // 存活而 scene 是新实例 = scene 在后台被断开后点
            // 卡/点图标重连：与点卡在系统层不可区分，按后台点
            // 入合成武装后 route。进程年龄是唯一可靠区分（二
            // 者都是新 delegate、首次激活未武装，外观一致）。
            let processAge = ProcessInfo.processInfo.systemUptime
                - AppProcessMark.launchUptime
            if processAge >= 5 {
                routeGeneration += 1
                recordRouteArmament(via: "scene-reconnect")
                beginRoute()
            } else {
                Breadcrumbs.log("nowplaying.route action=skip reason=cold-start-route-removed")
            }
            return
        }
        // 未武装的普通激活（控制中心下拉、来电打断恢复等）：
        // 不直达，但从此留痕（3.7 (41) 组2，消灭静默 return）。
        Breadcrumbs.log("nowplaying.route action=skip reason=not-armed state=\(routeState)")
    }

    // 冷启自动 route 已于 3.7 (44) 整体取消：理由见
    // sceneDidBecomeActive 首次激活分支，本状态机只有热路径
    // （background / scene-reconnect 两路武装同汇）。

    // MARK: route 状态机本体（3.7 (46)）

    /// routing 入口：落 route.begin（带 origin 链快照与武装现
    /// 场，DS 2.4），下一拍进 routeStep 等场景稳定。
    private func beginRoute() {
        routeState = .routing
        routeAttempts = 0
        routeLastRetryReason = ""
        installRouteTouchObserver()
        let engine = PlaybackEngine.shared
        Breadcrumbs.log("nowplaying.route begin gen=\(routeGeneration) armedVia=\(routeArmedVia) origin=\(chainDescription()) bgTop=\(routeBgTopName) bgStageToken=\(routeBgStageToken) bgEngineTrack=\(routeBgEngineTrackId ?? "nil") engineTrack=\(engine.currentTrack?.id ?? "nil") playState=\(engine.playbackState)")
        DispatchQueue.main.async { [weak self] in self?.routeStep() }
    }

    /// 呈现决策一步：场景未稳定/引擎未装载/模态占顶 → 短重试；
    /// 链判定与 (44)/(45) 同口径（already-on-stage 收紧判定、
    /// restore-stage 只解盖层、墙面出发走既有门禁 enter、根直
    /// 接 present），成功后一律过 verifyPresentedStage /
    /// routeSucceed 校验并开 RouteGuard。
    private func routeStep() {
        guard routeState == .routing else { return }
        let generation = routeGeneration
        routeAttempts += 1
        guard let window, let root = window.rootViewController else {
            routeRetryOrGiveUp(generation: generation, reason: "no-window")
            return
        }
        if let unstable = sceneInstabilityReason(root: root) {
            routeRetryOrGiveUp(generation: generation, reason: unstable)
            return
        }
        // 前置 = 引擎真装载（(45) R-1 口径）：短重试窗内等装载
        // 落地，窗尽仍空按纸面队列细分终局原因，不开空舞台。
        guard PlaybackEngine.shared.currentTrack != nil else {
            if routeAttempts < 10 {
                routeRetryOrGiveUp(generation: generation, reason: "no-current-track")
            } else {
                let paper = QueueManager.shared.currentTrack != nil
                routeGiveUp(generation: generation,
                            reason: paper ? "paper-queue-only" : "no-queue")
            }
            return
        }
        let chain = presentedChain(from: root)
        let top = chain.last ?? root
        // 舞台已在链：可见顶层 → alreadyOnStage 成功；被盖住 →
        // restore（只对舞台 dismiss 解其上盖层，不带下舞台本
        // 体——StageExitGate 对「舞台上有盖层」的 dismiss 放行）。
        if let stage = chain.first(where: { $0 is StageViewController }) as? StageViewController {
            let stageIndex = chain.firstIndex(where: { $0 === stage }) ?? 0
            let aboveStage = chain[(stageIndex + 1)...]
            let stageIsVisibleTop = aboveStage.isEmpty
                || aboveStage.allSatisfy { $0 is StageStylePickerViewController }
            if stageIsVisibleTop {
                routeSucceed(generation: generation, stage: stage, alreadyOnStage: true)
            } else {
                Breadcrumbs.log("nowplaying.route action=restore-stage gen=\(generation) coveredBy=\(type(of: top)) chain=\(chainDescription())")
                StageViewController.routeExitProbeArmedAt = Date()
                stage.dismiss(animated: true) { [weak self] in
                    guard let self, self.routeState == .routing,
                          self.routeGeneration == generation,
                          let root = self.window?.rootViewController else { return }
                    let chainNow = self.presentedChain(from: root)
                    if let stageNow = chainNow.first(where: { $0 is StageViewController }) as? StageViewController,
                       chainNow.last === stageNow {
                        self.routeSucceed(generation: generation, stage: stageNow,
                                          alreadyOnStage: true)
                    } else {
                        self.routeGiveUp(generation: generation, reason: "restore-unverified")
                    }
                }
            }
            return
        }
        // 墙面出发：走既有 WallPrototype→Stage 门禁 enter（墙内
        // 部 openNativeStage），route 不另造呈现路径。
        if let wall = top as? WallPrototypeViewController {
            Breadcrumbs.log("nowplaying.route action=present-stage gen=\(generation) via=playlist-wall chain=\(chainDescription())")
            StageViewController.routeExitProbeArmedAt = Date()
            wall.openNativeStageForBackgroundReturn()
            verifyPresentedStage(generation: generation)
            return
        }
        if let home = top as? HomeWallViewController {
            Breadcrumbs.log("nowplaying.route action=present-stage gen=\(generation) via=home-wall chain=\(chainDescription())")
            StageViewController.routeExitProbeArmedAt = Date()
            home.openNativeStageForBackgroundReturn()
            verifyPresentedStage(generation: generation)
            return
        }
        if top === root {
            Breadcrumbs.log("nowplaying.route action=present-stage gen=\(generation) via=main chain=\(chainDescription())")
            StageViewController.routeExitProbeArmedAt = Date()
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            root.present(stage, animated: true)
            verifyPresentedStage(generation: generation)
            return
        }
        // 顶层被其它模态（设置页等）占着：不粗暴打断，短重试
        // 等其散场，窗尽 giveup（modal-presented）。
        routeRetryOrGiveUp(generation: generation, reason: "modal-presented")
    }

    /// 场景稳定判据（DS 定案）：foregroundActive、根已挂窗、
    /// 链上无进行中的 present/dismiss/转场。不稳只短重试。
    private func sceneInstabilityReason(root: UIViewController) -> String? {
        if (window?.windowScene?.activationState ?? .foregroundActive) != .foregroundActive {
            return "scene-not-active"
        }
        if root.view.window == nil { return "root-detached" }
        var cursor: UIViewController? = root
        while let vc = cursor {
            if vc.isBeingPresented || vc.isBeingDismissed { return "chain-transition" }
            if vc.transitionCoordinator != nil { return "chain-transition" }
            cursor = vc.presentedViewController
        }
        return nil
    }

    /// 短重试：0.12s 一拍、上限 10 拍（≈1.2s + 决策耗时），同
    /// 原因只落一行 retry 痕防刷屏；窗尽 giveup。
    private func routeRetryOrGiveUp(generation: Int, reason: String) {
        guard routeState == .routing, generation == routeGeneration else { return }
        if routeAttempts >= 10 {
            routeGiveUp(generation: generation, reason: "unstable-\(reason)")
            return
        }
        if reason != routeLastRetryReason {
            routeLastRetryReason = reason
            Breadcrumbs.log("nowplaying.route retry gen=\(generation) reason=\(reason) attempt=\(routeAttempts)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.routeState == .routing,
                  self.routeGeneration == generation else { return }
            self.routeStep()
        }
    }

    /// 呈现成功校验（DS 成功标准）：present 动画后链顶必须是
    /// canonical 登记的同一舞台实例（同 token）、view.window
    /// 非 nil；不过 → giveup present-unverified（不再盲目重试
    /// 叠台）。
    private func verifyPresentedStage(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.routeState == .routing,
                  self.routeGeneration == generation,
                  let root = self.window?.rootViewController else { return }
            let chain = self.presentedChain(from: root)
            guard let stage = chain.last as? StageViewController,
                  StageExitGate.shared.canonicalStage === stage,
                  stage.view.window != nil else {
                self.routeGiveUp(generation: generation, reason: "present-unverified")
                return
            }
            self.routeSucceed(generation: generation, stage: stage, alreadyOnStage: false)
        }
    }

    /// route 成功终点：落 presented/alreadyOnStage（带舞台侧快
    /// 照）、开 3 秒 RouteGuard、守卫到期舞台仍在则 settle。
    private func routeSucceed(generation: Int, stage: StageViewController,
                              alreadyOnStage: Bool) {
        routeState = .stageVisible
        removeRouteTouchObserver()
        Breadcrumbs.log("nowplaying.route \(alreadyOnStage ? "alreadyOnStage" : "presented") gen=\(generation) token=\(stage.stageToken) window=\(stage.view.window != nil ? "yes" : "nil") alpha=\(stage.view.alpha) hidden=\(stage.view.isHidden) frame=\(stage.view.frame)")
        StageExitGate.shared.armRouteGuard(generation: generation,
                                           stageToken: stage.stageToken,
                                           alreadyOnStage: alreadyOnStage)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in
            guard let self, self.routeState == .stageVisible,
                  self.routeGeneration == generation else { return }
            self.routeState = .settled
            Breadcrumbs.log("nowplaying.route settle gen=\(generation) reason=guard-expired stage-kept")
        }
    }

    private func routeGiveUp(generation: Int, reason: String) {
        routeState = .giveup
        removeRouteTouchObserver()
        Breadcrumbs.log("nowplaying.route giveup gen=\(generation) reason=\(reason) attempts=\(routeAttempts)")
    }

    // MARK: route 闸门回调与用户接管

    /// StageExitGate 回调接线（willConnectTo 调一次）：用户/程
    /// 序化正当退出 → route 落定 settled；守卫期内被未知路径
    /// 带下 → 同代际 reenter 一次（状态回 routing 重走决策）。
    fileprivate func wireRouteGateCallbacks() {
        let gate = StageExitGate.shared
        gate.onRouteResolvedByExit = { [weak self] in
            guard let self else { return }
            if self.routeState == .stageVisible || self.routeState == .routing {
                self.routeState = .settled
                self.removeRouteTouchObserver()
                Breadcrumbs.log("nowplaying.route settle gen=\(self.routeGeneration) reason=stage-exit-approved")
            }
        }
        gate.onGuardReenter = { [weak self] generation in
            guard let self, self.routeGeneration == generation,
                  self.routeState == .stageVisible else { return }
            self.routeState = .routing
            self.routeAttempts = 0
            self.routeLastRetryReason = ""
            Breadcrumbs.log("nowplaying.route begin gen=\(generation) reason=guard-reenter")
            DispatchQueue.main.async { [weak self] in self?.routeStep() }
        }
        gate.onRouteGaveUp = { [weak self] generation in
            guard let self, self.routeGeneration == generation else { return }
            self.routeState = .giveup
            self.removeRouteTouchObserver()
        }
    }

    /// route pending/routing 期间的用户接管观察：窗口内任一
    /// touch down = 用户已拿回控制权，route 当即 cancel 落
    /// reason（DS：用户意图只认显式信号）。点卡本身的触摸发
    /// 生在锁屏（系统进程），不会进本窗，不误杀。
    private func installRouteTouchObserver() {
        guard routeTouchObserver == nil, let window else { return }
        let recognizer = TouchDownObserverRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.onTouchDown = { [weak self] in
            guard let self else { return }
            guard self.routeState == .foregroundPending
                    || self.routeState == .routing else { return }
            self.routeState = .settled
            self.removeRouteTouchObserver()
            Breadcrumbs.log("nowplaying.route settle gen=\(self.routeGeneration) reason=user-interaction-cancel")
        }
        window.addGestureRecognizer(recognizer)
        routeTouchObserver = recognizer
    }

    private func removeRouteTouchObserver() {
        if let recognizer = routeTouchObserver {
            recognizer.view?.removeGestureRecognizer(recognizer)
            routeTouchObserver = nil
        }
    }

    // MARK: 呈现链小工具

    private func presentedChain(from root: UIViewController) -> [UIViewController] {
        var chain: [UIViewController] = [root]
        while let presented = chain.last?.presentedViewController {
            chain.append(presented)
        }
        return chain
    }

    private func chainDescription() -> String {
        guard let root = window?.rootViewController else { return "no-root" }
        return presentedChain(from: root)
            .map { String(describing: type(of: $0)) }
            .joined(separator: ">")
    }
}

/// 窗口级 touch down 观察器（route 用户接管判据专用）：不消费
/// 触摸、不阻断任何手势，只在 touchesBegan 时回调一次/每触。
final class TouchDownObserverRecognizer: UIGestureRecognizer {
    var onTouchDown: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onTouchDown?()
    }
}
