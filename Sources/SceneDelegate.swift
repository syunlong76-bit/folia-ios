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
    func sceneWillEnterForeground(_ scene: UIScene) {}

    // MARK: - 后台点入直达播放详情页（3.7 (31)）

    /// 是否经历过真正的后台驻留。只在 sceneDidEnterBackground 置位，
    /// 冷启动、控制中心下拉、来电打断等「未进后台」的激活不触发直达。
    private var enteredBackground = false

    /// 本 delegate 实例是否已处理过首次激活（3.7 (41) 组2）：
    /// 冷启动与 scene 重连都是新实例，首次激活时 enteredBackground
    /// 恒未武装——(40) 前 sceneDidBecomeActive 在此处静默 return，
    /// 点锁屏卡/灵动岛冷启进入全程无日志、无落点（审计
    /// folia40-failures B1 定案：必坏）。(41)/(43) 曾在此走冷
    /// 启自动 route，(44) 已取消；首次激活改按进程年龄分岔
    /// （见 sceneDidBecomeActive）：进程新生绝不 route，活进
    /// 程 scene 重连按后台点入处理。
    private var didHandleFirstActivation = false

    /// route 重试代际（3.7 (44)）：每次进后台 +1；重试环携带
    /// 武装时的代际，代际已被新一次进后台顶替则自弃（防陈
    /// 旧重试环在用户正常回前台后迟到触发）。
    private var routeGeneration = 0

    func sceneDidEnterBackground(_ scene: UIScene) {
        enteredBackground = true
        routeGeneration += 1
        // 武装留痕（3.7 (44)）：锁屏场景的武装时机在此覆盖
        // 两路——前台时锁屏走 willResignActive→本回调；已在
        // 后台时锁屏无新事件，但武装早在本次进后台时已置位，
        // 锁屏期间不消费，点卡激活时仍有效。
        Breadcrumbs.log("nowplaying.route armed src=didEnterBackground")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 岛层即时置顶（3.7 (41) 组1）：回前台先把岛层送回
        // 主窗最顶，不等 0.5s 守护拍；未安装时为空操作。
        PetIslandLayer.shared.refrontIfNeeded()
        if enteredBackground {
            enteredBackground = false
            didHandleFirstActivation = true
            // 等一拍让激活流程与视图层级落定，再进重试环做呈
            // 现决策（3.7 (44)：一拍定不了的进环重试，不丢弃）。
            let generation = routeGeneration
            let gateSeq = StageViewController.gateEventSeq
            DispatchQueue.main.async { [weak self] in
                self?.routeFromBackground(attempt: 0, generation: generation,
                                          armedVia: "background",
                                          gateSeqAtArm: gateSeq)
            }
            return
        }
        if !didHandleFirstActivation {
            didHandleFirstActivation = true
            // 首次激活分岔（3.7 (44)，Miller 定案口径）：
            // ①进程新生（距 AppProcessMark 启动标记 <5s）= 真
            //   冷启：(43) 日志实锤冷启 route 在普通图标启动
            //   时也触发、绕过入场与墙直落舞台，是「进不去软
            //   件」死循环主犯——绝不 route，走正常入场→墙；
            //   恢复队列留在迷你台，用户开台时由 StageView-
            //   Controller 触发 resumeRestoredQueue 装载。
            // ②进程已存活而 scene 是新实例 = scene 在后台被
            //   断开后点卡/点图标重连：与点卡在系统层不可区
            //   分，按后台点入处理（armed src=scene-reconnect
            //   ＋同一重试环）。进程年龄是唯一可靠区分（二者
            //   都是新 delegate、首次激活未武装，外观一致）。
            let processAge = ProcessInfo.processInfo.systemUptime
                - AppProcessMark.launchUptime
            if processAge >= 5 {
                Breadcrumbs.log("nowplaying.route armed src=scene-reconnect")
                let generation = routeGeneration
                let gateSeq = StageViewController.gateEventSeq
                DispatchQueue.main.async { [weak self] in
                    self?.routeFromBackground(attempt: 0, generation: generation,
                                              armedVia: "scene-reconnect",
                                              gateSeqAtArm: gateSeq)
                }
            } else {
                Breadcrumbs.log("nowplaying.route fromBackground=no action=skip reason=cold-start-route-removed")
            }
            return
        }
        // 未武装的普通激活（控制中心下拉、来电打断恢复等）：
        // 不直达，但从此留痕（3.7 (41) 组2，消灭静默 return）。
        Breadcrumbs.log("nowplaying.route action=skip reason=not-armed")
    }

    // 冷启自动 route 已于 3.7 (44) 整体取消（原
    // routeColdStartToStageIfNeeded）：理由见 sceneDidBecomeActive
    // 首次激活分支。原 performRoute 的 coldStart 分支随之删除，
    // 链判定收敛为 routeAttempt（热路径专用）。

    /// 后台点入重试环（3.7 (44) 热路径可靠性复审）：从锁屏点
    /// 卡激活的那一拍，视图层级可能未就绪（入场未散、模态在
    /// 退、链在变）——旧实现一拍判定、skip 即丢弃，点卡石沉
    /// 大海。本版：可重试原因（no-root/modal-presented）进
    /// 0.5s 重试环，每次重试留痕；presented/alreadyOnStage
    /// 即停；terminal（no-queue / paper-queue-only）与超限/
    /// 代际被顶替时落 giveup 及原因。
    ///
    /// 3.7 (45) R-3 收敛（审计候选 3）：(44) 上限 120 次
    /// （≈60s）太长——代际只被「再次进后台」顶替，用户在前
    /// 台自主开台又关台后，迟发的重试环会把刚关掉的舞台再
    /// 打开。本版：上限收至 20 次（≈10s）；且武装时记下舞
    /// 台 gate 事件序号（StageViewController.gateEventSeq，
    /// gate enter/exit 各 +1），本代际内序号变化 = 用户已
    /// 自主开/关过台，重试环自弃（giveup
    /// reason=superseded-by-user）。route 自己呈现成功即出
    /// 环（.presented），不会被自己的 gate enter 误杀。
    private func routeFromBackground(attempt: Int, generation: Int,
                                     armedVia: String, gateSeqAtArm: Int) {
        guard generation == routeGeneration else {
            Breadcrumbs.log("nowplaying.route action=giveup reason=superseded armedVia=\(armedVia)")
            return
        }
        guard StageViewController.gateEventSeq == gateSeqAtArm else {
            Breadcrumbs.log("nowplaying.route action=giveup reason=superseded-by-user armedVia=\(armedVia)")
            return
        }
        switch routeAttempt() {
        case .presented, .alreadyOnStage:
            return
        case .terminal(let reason):
            Breadcrumbs.log("nowplaying.route action=giveup reason=\(reason) armedVia=\(armedVia)")
        case .retryable(let reason):
            guard attempt < 20 else {
                Breadcrumbs.log("nowplaying.route action=giveup attempts=\(attempt) reason=\(reason) armedVia=\(armedVia)")
                return
            }
            Breadcrumbs.log("nowplaying.route retry attempt=\(attempt + 1) reason=\(reason) armedVia=\(armedVia)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.routeFromBackground(attempt: attempt + 1,
                                          generation: generation,
                                          armedVia: armedVia,
                                          gateSeqAtArm: gateSeqAtArm)
            }
        }
    }

    /// routeAttempt 的结果：presented/alreadyOnStage 为成功
    /// 终态；retryable 携带可重试原因进重试环；terminal 携
    /// 带放弃原因直接终结。
    private enum RouteOutcome {
        case presented
        case alreadyOnStage
        case retryable(String)
        case terminal(String)
    }

    /// 定版规则：从后台回到前台时，若有活跃队列（正在播或暂停着一首
    /// 歌）→ 直接呈现播放详情页（原生舞台）。护栏：已在舞台不重复
    /// 呈现；顶层被其它模态（设置页等）占着时不粗暴打断、进重
    /// 试环等其散场（3.7 (44)，旧版为一拍跳过）。每次决策记
    /// nowplaying.route 面包屑。
    ///
    /// 3.7 (40) 项6（审计 nowplaying-audit-2026-11-20 失败一）：原跳过
    /// 条件只看「舞台在呈现链中」，舞台被其它内容盖住时也误判
    /// already-on-stage、点锁屏卡/灵动岛毫无落点。本版收紧：仅当
    /// 舞台处于可见顶层（topmost 是舞台本人，或其上只盖着舞台自有
    /// 浮层 StageStylePickerViewController）才 skip；舞台在链但被
    /// 其它内容盖住时走归位分支——对舞台调 dismiss 解掉其上整摞
    /// 呈现（呈现链是线性的，舞台之上的层都由舞台转呈），舞台即
    /// 回到可见顶层。面包屑补记 chain 逐层类名与 top 类名，下次
    /// 再现凭链构成一击定案。enteredBackground 的武装/消费语义
    /// 不变；不引入任何「舞台开过」布尔缓存，判定只读活链。

    /// 链判定本体（热路径专用，3.7 (44) 自 performRoute 收
    /// 敛）：面包屑保持 fromBackground=yes 口径。present-stage
    /// / restore-stage 派发时武装舞台速退探针（(41) 组2取证：
    /// 开台后 3 秒内 dismiss 落 stage-exit-quick；探针只记日
    /// 志、不改任何呈现逻辑）。结果以 RouteOutcome 返回供重
    /// 试环分流，不再以 Bool 混同「已在台上」与「被跳过」。
    private func routeAttempt() -> RouteOutcome {
        // hasQueue 改读引擎真装载（3.7 (45) R-1，审计
        // folia44-crash-audit §一设备实测缺陷）：(43)/(44) 读
        // QueueManager.currentTrack 是纸面队列——冷启快照回
        // 填后恒非 nil，引擎里根本没装歌时 route 也一路绿
        // 灯，点回 App 落到「暂无播放」空舞台，违反 Miller
        // 规则前提（点卡直达的条件是「有歌在播/暂停」）。
        // PlaybackEngine.currentTrack 仅 load() 置位、stop()
        // 清除，非 nil ⟺ 引擎真有一首已装载的曲，恰合规则。
        // 纸面队列只用于终局原因细分（paper-queue-only），
        // 不再作放行条件；冷/热/reconnect 三路同汇于此，一
        // 并生效。
        let hasQueue = PlaybackEngine.shared.currentTrack != nil
        let paperQueue = QueueManager.shared.currentTrack != nil
        guard let root = window?.rootViewController else {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=\(hasQueue) action=skip reason=no-root")
            return .retryable("no-root")
        }
        // 展开呈现链：root → presented → … → 顶层。先展开再判
        // hasQueue，让 no-queue 的跳过面包屑也带链构成（纯读、无副作用，
        // 不改变原有判定顺序的语义）。
        var chain: [UIViewController] = [root]
        while let presented = chain.last?.presentedViewController {
            chain.append(presented)
        }
        let chainNames = chain.map { String(describing: type(of: $0)) }.joined(separator: ">")
        let topName = chain.last.map { String(describing: type(of: $0)) } ?? "none"
        guard hasQueue else {
            // 终局原因细分（3.7 (45) R-1）：引擎空但纸面非空
            // = 只有恢复队列没真装载（paper-queue-only）；两
            // 者皆空维持 no-queue。前置不成立 = terminal：等
            // 再久引擎也不会自己装上歌，不进重试环、不开台。
            let reason = paperQueue ? "paper-queue-only" : "no-queue"
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=no action=skip reason=\(reason) chain=\(chainNames) top=\(topName)")
            return .terminal(reason)
        }
        if let stageIndex = chain.firstIndex(where: { $0 is StageViewController }),
           let stage = chain[stageIndex] as? StageViewController {
            let aboveStage = chain[(stageIndex + 1)...]
            // 可见顶层判定：舞台之上为空，或只盖着舞台自有浮层
            // （样式选择器由舞台 present、关掉即回舞台本人）。
            let stageIsVisibleTop = aboveStage.isEmpty
                || aboveStage.allSatisfy { $0 is StageStylePickerViewController }
            if stageIsVisibleTop {
                Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=skip reason=already-on-stage chain=\(chainNames) top=\(topName)")
                // 落点本就在播放页：成功终态，不进重试环。
                return .alreadyOnStage
            }
            // 舞台在链但被其它内容盖住：归位分支。对舞台 dismiss
            // 会解掉它呈现的整摞（盖层及其转呈层），舞台回到顶层；
            // 不重新 present，避免另起一只舞台实例。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=restore-stage reason=stage-covered chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            stage.dismiss(animated: true)
            return .presented
        }
        let topmost = chain.last
        if let wall = topmost as? WallPrototypeViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=playlist-wall chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            wall.openNativeStageForBackgroundReturn()
            return .presented
        } else if let home = topmost as? HomeWallViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=home-wall chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            home.openNativeStageForBackgroundReturn()
            return .presented
        } else if topmost === root {
            // 无墙在场（停在 Web 主界面）：舞台本体自包含（关闭即
            // dismiss、跳网页舞台时 onRequestWebStage 为 nil 走
            // dismiss 兜底），直接由根呈现，不另造舞台内部逻辑。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=main chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            root.present(stage, animated: true)
            return .presented
        } else {
            // 墙上有模态（设置页等）或顶层是其它页面：不粗暴打
            // 断，进重试环等层级就绪（3.7 (44)；旧版一拍跳过）。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=skip reason=modal-presented top=\(type(of: topmost!)) chain=\(chainNames)")
            return .retryable("modal-presented")
        }
    }
}
