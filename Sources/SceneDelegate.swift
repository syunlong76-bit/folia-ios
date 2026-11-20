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

    func sceneDidEnterBackground(_ scene: UIScene) {
        enteredBackground = true
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard enteredBackground else { return }
        enteredBackground = false
        // 等一拍让激活流程与视图层级落定，再做呈现决策。
        DispatchQueue.main.async { [weak self] in
            self?.routeToStageFromBackground()
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
        let hasQueue = PlaybackEngine.shared.currentTrack != nil
        guard let root = window?.rootViewController else {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=\(hasQueue) action=skip reason=no-root")
            return
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
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=no action=skip reason=no-queue chain=\(chainNames) top=\(topName)")
            return
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
                return
            }
            // 舞台在链但被其它内容盖住：归位分支。对舞台 dismiss
            // 会解掉它呈现的整摞（盖层及其转呈层），舞台回到顶层；
            // 不重新 present，避免另起一只舞台实例。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=restore-stage reason=stage-covered chain=\(chainNames) top=\(topName)")
            stage.dismiss(animated: true)
            return
        }
        let topmost = chain.last
        if let wall = topmost as? WallPrototypeViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=playlist-wall chain=\(chainNames) top=\(topName)")
            wall.openNativeStageForBackgroundReturn()
        } else if let home = topmost as? HomeWallViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=home-wall chain=\(chainNames) top=\(topName)")
            home.openNativeStageForBackgroundReturn()
        } else if topmost === root {
            // 无墙在场（停在 Web 主界面）：舞台本体自包含（关闭即
            // dismiss、跳网页舞台时 onRequestWebStage 为 nil 走
            // dismiss 兜底），直接由根呈现，不另造舞台内部逻辑。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=main chain=\(chainNames) top=\(topName)")
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            root.present(stage, animated: true)
        } else {
            // 墙上有模态（设置页等）或顶层是其它页面：跳过本次。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=skip reason=modal-presented top=\(type(of: topmost!)) chain=\(chainNames)")
        }
    }
}
