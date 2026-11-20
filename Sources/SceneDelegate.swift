import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Breadcrumbs.log("scene.connect")

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
    /// folia40-failures B1 定案：必坏）。本版首次激活单独走
    /// 冷启判定（routeColdStartToStageIfNeeded），此后未武装的
    /// 普通激活也必须打 skip 面包屑，消灭静默。
    private var didHandleFirstActivation = false

    func sceneDidEnterBackground(_ scene: UIScene) {
        enteredBackground = true
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 岛层即时置顶（3.7 (41) 组1）：回前台先把岛层送回
        // 主窗最顶，不等 0.5s 守护拍；未安装时为空操作。
        PetIslandLayer.shared.refrontIfNeeded()
        if enteredBackground {
            enteredBackground = false
            didHandleFirstActivation = true
            // 等一拍让激活流程与视图层级落定，再做呈现决策。
            DispatchQueue.main.async { [weak self] in
                self?.routeToStageFromBackground()
            }
            return
        }
        if !didHandleFirstActivation {
            didHandleFirstActivation = true
            // 冷启/scene 重连的首次激活：等一拍落定后判定。
            DispatchQueue.main.async { [weak self] in
                self?.routeColdStartToStageIfNeeded(attempt: 0)
            }
            return
        }
        // 未武装的普通激活（控制中心下拉、来电打断恢复等）：
        // 不直达，但从此留痕（3.7 (41) 组2，消灭静默 return）。
        Breadcrumbs.log("nowplaying.route action=skip reason=not-armed")
    }

    /// 冷启/scene 重连点卡进入（3.7 (41) 组2，审计 B1；落点
    /// Miller 2026-11-20 18:01 拍板「冷启点卡：有队列就直达
    /// 播放页」）：首次激活未武装时，若队列存在，视同后台点
    /// 入走同一条链判定 route，面包屑记 via=cold-start。
    ///
    /// 3.7 (43) 路2（审计 folia43 路2 F1/F2/F3 定案）：(41)
    /// 版第一关读 engine.currentTrack——冷启时队列从未落盘
    /// 恢复、engine 恒空，guard 100% 判死，修复结构上不可
    /// 能生效。本版：①判定改读 QueueManager.currentTrack
    /// （含启动回填的恢复态，见 QueueManager 队列快照）；
    /// ②队列未就绪与「呈现链含 EntryIntro」同进重试循环
    /// （(41) 版 no-queue 在 attempt 0 一次判死，异步恢复永
    /// 无机会）；③重试预算 20→120 次 ≈ 60s，与入场「数据
    /// 未就绪则循环播」规格同量级。route 派发成功后调
    /// resumeRestoredQueue 装载恢复队列（默认保持暂停）。
    private func routeColdStartToStageIfNeeded(attempt: Int) {
        let queueReady = QueueManager.shared.currentTrack != nil
        guard let root = window?.rootViewController else {
            Breadcrumbs.log("nowplaying.route fromBackground=no hasQueue=\(queueReady) action=skip reason=no-root via=cold-start")
            return
        }
        var chain: [UIViewController] = [root]
        while let presented = chain.last?.presentedViewController {
            chain.append(presented)
        }
        let entryPresent = chain.contains { $0 is EntryIntroViewController }
        if (!queueReady || entryPresent), attempt < 120 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.routeColdStartToStageIfNeeded(attempt: attempt + 1)
            }
            return
        }
        guard queueReady else {
            Breadcrumbs.log("nowplaying.route action=skip reason=not-armed-no-queue via=cold-start")
            return
        }
        if performRoute(coldStart: true) {
            // 落点已派发：恢复态队列现换地址装载（默认暂停）。
            QueueManager.shared.resumeRestoredQueue()
        }
    }

    /// 定版规则：从后台回到前台时，若有活跃队列（正在播或暂停着一首
    /// 歌）→ 直接呈现播放详情页（原生舞台）。护栏：已在舞台不重复
    /// 呈现；顶层被其它模态（设置页等）占着时跳过本次、不粗暴打断，
    /// 等下一次后台往返再触发。每次决策记 nowplaying.route 面包屑。
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
    private func routeToStageFromBackground() {
        performRoute(coldStart: false)
    }

    /// 链判定本体（后台点入与冷启共用，3.7 (41) 组2）：coldStart
    /// 时面包屑 fromBackground=no、via 记 cold-start 并附实际命
    /// 中的分支（branch=）；后台口径的面包屑格式逐字不变。
    /// present-stage / restore-stage 派发时武装舞台速退探针
    /// （组2取证：开台后 3 秒内 dismiss 落 stage-exit-quick，
    /// 供下轮定性 Miller 实测的「开台约 1 秒舞台消失」是手动
    /// 关还是自动退；探针只记日志、不改任何呈现逻辑）。
    /// 返回 true = 已派发落点（present/restore），false = skip。
    @discardableResult
    private func performRoute(coldStart: Bool) -> Bool {
        let fromBg = coldStart ? "no" : "yes"
        let srcSuffix = coldStart ? " via=cold-start" : ""
        func via(_ branch: String) -> String {
            coldStart ? "cold-start branch=\(branch)" : branch
        }
        // hasQueue 改读 QueueManager（3.7 (43) 路2）：含冷启
        // 恢复态——engine.currentTrack 在恢复态下恒 nil，两
        // 处判定必须同源（审计 F1 附带语义问题）。
        let hasQueue = QueueManager.shared.currentTrack != nil
        guard let root = window?.rootViewController else {
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=\(hasQueue) action=skip reason=no-root\(srcSuffix)")
            return false
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
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=no action=skip reason=no-queue chain=\(chainNames) top=\(topName)\(srcSuffix)")
            return false
        }
        if let stageIndex = chain.firstIndex(where: { $0 is StageViewController }),
           let stage = chain[stageIndex] as? StageViewController {
            let aboveStage = chain[(stageIndex + 1)...]
            // 可见顶层判定：舞台之上为空，或只盖着舞台自有浮层
            // （样式选择器由舞台 present、关掉即回舞台本人）。
            let stageIsVisibleTop = aboveStage.isEmpty
                || aboveStage.allSatisfy { $0 is StageStylePickerViewController }
            if stageIsVisibleTop {
                Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=yes action=skip reason=already-on-stage chain=\(chainNames) top=\(topName)\(srcSuffix)")
                // 冷启重连且舞台已在顶层：落点本就在播放页，
                // 恢复态装载仍应发生（调用方据 true 触发）。
                return coldStart
            }
            // 舞台在链但被其它内容盖住：归位分支。对舞台 dismiss
            // 会解掉它呈现的整摞（盖层及其转呈层），舞台回到顶层；
            // 不重新 present，避免另起一只舞台实例。
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=yes action=restore-stage reason=stage-covered chain=\(chainNames) top=\(topName)\(srcSuffix)")
            StageViewController.routeExitProbeArmedAt = Date()
            stage.dismiss(animated: true)
            return true
        }
        let topmost = chain.last
        if let wall = topmost as? WallPrototypeViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=yes action=present-stage via=\(via("playlist-wall")) chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            wall.openNativeStageForBackgroundReturn()
            return true
        } else if let home = topmost as? HomeWallViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=yes action=present-stage via=\(via("home-wall")) chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            home.openNativeStageForBackgroundReturn()
            return true
        } else if topmost === root {
            // 无墙在场（停在 Web 主界面）：舞台本体自包含（关闭即
            // dismiss、跳网页舞台时 onRequestWebStage 为 nil 走
            // dismiss 兜底），直接由根呈现，不另造舞台内部逻辑。
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=yes action=present-stage via=\(via("main")) chain=\(chainNames) top=\(topName)")
            StageViewController.routeExitProbeArmedAt = Date()
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            root.present(stage, animated: true)
            return true
        } else {
            // 墙上有模态（设置页等）或顶层是其它页面：跳过本次。
            Breadcrumbs.log("nowplaying.route fromBackground=\(fromBg) hasQueue=yes action=skip reason=modal-presented top=\(type(of: topmost!)) chain=\(chainNames)\(srcSuffix)")
            return false
        }
    }
}
