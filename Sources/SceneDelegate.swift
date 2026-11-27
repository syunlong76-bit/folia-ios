import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// (87) 烟花收尾「今日推荐」的待播曲（推荐回调与播
    /// 放回调之间传递；进程级单份即可）。
    static var fxRecommended87: FoliaTrack?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Breadcrumbs.log("scene.connect")
        // (87) 四特效全局叠加层装配：独立穿透窗（level
        // 1500），覆盖全屏全场景、不绑控制台开合；渲染层
        // 每帧只清自己、绝不压暗/染色照片墙背景。
        GlobalFx87.shared.install(in: windowScene)
        // (92) 任务 2：四特效冷启默认全关（推翻 (88) 的下雪
        // 默认开——那是工坊「下雪 开」存值被写成冷启默认的
        // 误落，审计 Q2 定案）；样式值（淡蓝）保留、手动开
        // 仍可用、12 秒自融保留。
        GlobalFx87.shared.applyDefaultSnow88()
        GlobalFx87.shared.recommendationProvider = {
            // 今日推荐：队列里挑当前曲之外的一首（优先下
            // 一首），封面走缓存同步取、取不到传 nil。
            let queue = QueueManager.shared
            let tracks = queue.queue
            guard !tracks.isEmpty else { return nil }
            let current = queue.currentIndex
            var candidate: FoliaTrack?
            if tracks.count > 1 {
                let next = (current + 1) % tracks.count
                candidate = tracks[next]
            } else if current != 0 {
                candidate = tracks[0]
            }
            guard let track = candidate else { return nil }
            SceneDelegate.fxRecommended87 = track
            var cover: UIImage?
            if let raw = track.artworkURL?.absoluteString {
                cover = NativeCoverLoader.shared.cachedImage(for: raw)
                    ?? NativeCoverLoader.shared.cachedImageAnyTier(raw: raw, excludingTier: -1)
            }
            return (title: track.title, artist: track.artist, cover: cover)
        }
        GlobalFx87.shared.onPlayRecommendation = {
            guard let track = SceneDelegate.fxRecommended87,
                  let index = QueueManager.shared.queue.firstIndex(where: { $0.id == track.id })
            else { return }
            QueueManager.shared.playAtIndex(index)
            Breadcrumbs.log("fx87 rec play idx=\(index)")
        }
        // (75) 真 Live Activity 协调器装配（认领既有活动+
        // 订阅播放/名单边沿；拉起在 sceneDidBecomeActive
        // 的闸上裁决，此处只装配不拉起）。
        IslandLiveActivityManager.shared.start()

        // 0) 样式防卡死守卫（3.7 (44)）：必须在任何舞台呈现
        //    之前跑完——上次会话若有样式开台未及证明存活就
        //    进程消亡（pending 未清），本次启动先把该样式回
        //    退 classic，点歌台/route 哪条入口开台都安全。
        StageStyleStore.runLaunchStyleGuard()

        // 1) WebRootManager 冷启拷贝已退役（3.7 (51) 换根）：网页
        //    三包不再是冷启路径的前置，prepare() 调用删除；类本体
        //    与 UpdateManager 本体由 (51) C 组删除。

        // 1.5) 本地服务器显式启动（3.7 (52) 热修）：(50) 时代服务
        //    器由根 MainViewController 触达 WebEffectBridge 时副作
        //    用启动（bridge init → loadLocalEffectBundle →
        //    server.start()），墙是后入表面、从不抢跑；(51) 换根
        //    后无人再触达桥，start() 零调用、服务器永不就绪，主
        //    页墙冷启两轮 serverNotReady 永久失败（(51) 真机实
        //    证）。修法：建窗前显式启动；就绪是异步事件，墙侧另
        //    有 waitUntilReady 宽限等待兜底（见 HomeWall 的
        //    loadEntries），两路叠加不许再抢跑。
        LocalServer.shared.start()

        // 队列快照恢复时机对齐 (50)：restoreQueueSnapshotIfNeeded
        // 在 QueueManager init 内、单例首次被触达时执行；(50) 由
        // 桥在冷启触达，(51) 后触达时机漂移（本段日志里 crumb
        // 缺席即因此，快照过期时为静默清除、无回归）。在此显式
        // 触达，保证首激活 hasQueue 判定读到恢复态（QueueManager
        // init 注释的既有口径）。
        _ = QueueManager.shared

        // M1 阶段 2：启动登录 Cookie 同步观察（原生数据链的前置）。
        // (51) 保留 start() 的理由：CookieSync 观察的是共享
        // WKWebsiteDataStore 的 Cookie 罐（不依赖根 WebView 存
        // 在），其副本仍经 NativeDataClient 注入发往 LocalServer
        // 的原生请求头；它不是登录态载体（登录串在 localStorage，
        // A 组迁移走 WebSession 一次性读取，与本观察无关）。待
        // (52) 桥/LocalServer 瘦身时再随之退役。
        CookieSync.shared.start()

        // 2) 主界面（3.7 (51) 换根）：根控制器 = 原生主页墙，
        //    冷启直达原生墙（建法与原长按入口/回程呈现场景同构：
        //    裸 HomeWallViewController、无导航壳）。网页 WebView
        //    不再铺满全屏作主界面，只剩未迁样式的网页舞台兜底
        //    通道（WebStageHostViewController 按需承载）。窗口底
        //    色 = 纯黑（3.7 (60) 第 1 条）：与启动屏纯黑口径
        //    对齐——冷启第一帧起全程黑下完成旋转/就绪，入场
        //    再缓动淡入（(59) Miller 规格）；缝隙露黑即规格
        //    本身，不再露油画色。EntryPosterArt 本体保留供
        //    播放期海报垫底使用。
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        Breadcrumbs.log("scene.launchchrome bg=black poster=removed")
        window.rootViewController = HomeWallViewController()
        // (62) 明暗模式统一应用点：窗口级 overrideUserInterfaceStyle
        // 读 SettingsStore.daylightMode（跟随系统/恒深色/恒浅色）；
        // 设置变更经 foliaSettings62AChanged 即时重应用（观察者以
        // 本 delegate 为 owner、随 scene 生命周期存活）。
        ThemeSystem62.applyInterfaceStyle(to: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(daylight62Changed),
            name: .foliaSettings62AChanged, object: nil)
        window.makeKeyAndVisible()
        self.window = window
        // (92) 任务 1：Fx 浮层宿主与被动点按识别器改挂真主
        // 窗——install 时主窗未建、(91) 挂到了 Fx 窗自身
        // （审计 Q4 定案），主窗就绪后在此重挂并落 p92 自证。
        GlobalFx87.shared.attachOverlay92(to: window)
        // (77) ⑤：窗口右下角浮动爪印退役（Miller 定：爪印
        // 上点播台、替换随机播放键位）——不再 install；
        // PetSummonButton70 本体保留为共享切换核
        // （performPawToggle77），EntryIntro 的
        // setEntrySuppressed 调用随之恒为空操作。

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

        // 入场播放器预热（3.7 (54) 工作流 O）：建窗阶段先把
        // 入场 player/item 建好并异步加载至可播（EntryPlayer
        // Preheat.warmUp），入场呈现时 VC 接管同一实例直接
        // play，消除「呈现后才装配/加载」的海报静帧停留。
        // 全程异步、不阻塞建窗；失败静默降级回 VC 现装配路
        // 径。本调用为旁新增，不动上方 LocalServer.start()、
        // QueueManager 触达、PetIslandLayer.install 三处既有
        // 调用及其顺序。
        EntryPlayerPreheat.warmUp()

        // 2.5) 入场视频（3.7 (17) 挪位、(51) 随墙作根自然生效）：
        //     冷启直达原生墙，v5 油画视频由主页墙进入页触发（见
        //     HomeWallViewController 的入场槽位：进墙首露面播、
        //     播完/关闭落墙、数据未就绪循环），冷启路径上不再有
        //     任何 WebView 第一屏。

        // 3) 冷启动自动检查更新已退役（3.7 (51)）：OTA 产物在现
        //    行拓扑里从未被服务（审计 §5 空转链），冷启自动检查
        //    段删除；UpdateManager 本体由 (51) C 组删除。
    }

    /// (62) 明暗模式变更重应用（窗口级）。
    @objc private func daylight62Changed() {
        ThemeSystem62.applyInterfaceStyle(to: window)
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {
        // (75) LA 协调器场景边沿（拉起闸的 sceneActive 旗）。
        IslandLiveActivityManager.shared.sceneWillResignActive()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // (83) 第 3 条：每次从后台重新进入 App 自动恢复开
        // 灯（白天）模式——关灯态不跨「退出再进入」保留
        // （冷启一路在 AppDelegate，两路幂等）。
        WallLight82.resetOnEntry83(source: "fg")
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
        // (75) LA 回前台对账（活动被系统收走则清抑制回落
        // 障眼法、按闸重拉；详见 IslandLiveActivityManager）。
        IslandLiveActivityManager.shared.sceneBecameActive()
        // (73) 本地服务器回前台探活：监听的静默死亡正发生
        // 在挂起期（(72) 真机实证），回前台第一时间实测——
        // 活着零成本（一发回环连接），死了不等用户点歌单
        // 撞 -1004 才修，当场 restart 重建。
        Task { _ = await LocalServer.shared.ensureAlive(timeout: 4) }
        // 岛层即时置顶（3.7 (41) 组1）：回前台先把岛层送回
        // 主窗最顶，不等 0.5s 守护拍；未安装时为空操作。
        PetIslandLayer.shared.refrontIfNeeded()
        // (72)：回前台是岛民对账的稳定事件（入场未完成时
        // 登记表内 isl.gate why=intro 挡下，不抢油画）。
        PetHomeRegistry.shared.reconcileIsland(reason: "active")
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
                // 启动续播自动播放（3.7 (55) 工作流 G，网页
                // autoPlayOnLaunch 消费点）：仅用户在设置里显
                // 式开启时，冷启恢复队列直接装载起播（不进舞
                // 台、不走 route，与 (43) 冷启劫持禁令不冲突
                // ——那禁的是未经用户设置的自动直达播放页）。
                if SettingsStore.autoPlayOnLaunch {
                    QueueManager.shared.playRestoredQueueIfNeeded()
                }
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
        // (77) ⑥认领先行：细条触摸在飞（用户正在点播放条）
        // 时 route 不许呈现——呈现转场会取消在飞触摸（(76)
        // 日志实证 tap 与 settle 同毫秒相撞、点按死于
        // at=cancel）。hold 期间短延迟让行、不计 attempts，
        // 触摸落定（点按展开或取消）后 route 自行续步。
        if RouteInteractionHold.shared.isHeld {
            if routeLastRetryReason != "user-hold" {
                routeLastRetryReason = "user-hold"
                Breadcrumbs.log("nowplaying.route retry gen=\(generation)"
                    + " reason=user-hold attempt=\(routeAttempts)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                [weak self] in
                guard let self, self.routeState == .routing,
                      self.routeGeneration == generation else { return }
                self.routeStep()
            }
            return
        }
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
            if routeAttempts < 6 {
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
        // 根直达兜底（3.7 (51) 换根后口径）：根已是 HomeWall，
        // 本分支在现行根链下被上方 home-wall 分支先行接住（top
        // === root 且 root 为 HomeWall 时先命中），仅作根形态
        // 变更时的通用兜底保留；chain 字段仍由 chainDescription
        // 按真实类名链生成（如 HomeWallViewController>…），判
        // 定不依赖任何硬编码类名串。
        if top === root {
            Breadcrumbs.log("nowplaying.route action=present-stage gen=\(generation) via=root chain=\(chainDescription())")
            StageViewController.routeExitProbeArmedAt = Date()
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            root.present(stage, animated: true)
            verifyPresentedStage(generation: generation)
            return
        }
        // (93) A1：顶层是控制台（瞬时面板）时不再重试到
        // giveup——(92) 日志实锤：ConsolePanel82 自弹出后
        // 长期占顶，route 以 modal-presented 重试 6 次后
        // giveup（gen=4 attempts=6）。改：armed 路由先无
        // 动画 dismiss 控制台、落痕后同代际续步路由；其
        // 它模态（设置页等）仍走下方短重试口径不动。
        if let console = top as? ConsolePanel82 {
            Breadcrumbs.log("p93 route thru gen=\(generation)")
            console.dismiss(animated: false) { [weak self] in
                guard let self, self.routeState == .routing,
                      self.routeGeneration == generation else { return }
                self.routeStep()
            }
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

    /// 短重试（(77) ⑥收敛）：退避 0.12/0.25/0.5s、上限 6
    /// 拍——(76) 日志里 gen=9–12 反复以 0.12s×10 拍烧完再
    /// giveup 的重试风暴收口为退避＋减拍，同原因仍只落一
    /// 行 retry 痕；窗尽 giveup。
    private func routeRetryOrGiveUp(generation: Int, reason: String) {
        guard routeState == .routing, generation == routeGeneration else { return }
        if routeAttempts >= 6 {
            routeGiveUp(generation: generation, reason: "unstable-\(reason)")
            return
        }
        if reason != routeLastRetryReason {
            routeLastRetryReason = reason
            Breadcrumbs.log("nowplaying.route retry gen=\(generation) reason=\(reason) attempt=\(routeAttempts)")
        }
        let delay: TimeInterval = routeAttempts <= 2 ? 0.12
            : (routeAttempts <= 4 ? 0.25 : 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
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

/// (77) ⑥条触摸认领旗：收起态播放条触摸在飞期间置位，
/// nowplaying.route 的呈现步骤咨询本旗让行（认领先于路由
/// 仲裁）。引用计数配对 begin/end，另设 1.5s 自动过期兜
/// 底——任何路径漏 end 都不会把 route 永久堵死。
final class RouteInteractionHold {
    static let shared = RouteInteractionHold()
    private var count = 0
    private var lastBegin: CFTimeInterval = 0

    func begin() {
        count += 1
        lastBegin = CACurrentMediaTime()
    }

    func end() {
        count = max(0, count - 1)
    }

    var isHeld: Bool {
        guard count > 0 else { return false }
        if CACurrentMediaTime() - lastBegin > 1.5 {
            count = 0
            return false
        }
        return true
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
