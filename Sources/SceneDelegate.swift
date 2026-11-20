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
    private func routeToStageFromBackground() {
        let hasQueue = PlaybackEngine.shared.currentTrack != nil
        guard let root = window?.rootViewController else {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=\(hasQueue) action=skip reason=no-root")
            return
        }
        guard hasQueue else {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=no action=skip reason=no-queue")
            return
        }
        // 展开呈现链：root → presented → … → 顶层。
        var chain: [UIViewController] = [root]
        while let presented = chain.last?.presentedViewController {
            chain.append(presented)
        }
        if chain.contains(where: { $0 is StageViewController }) {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=skip reason=already-on-stage")
            return
        }
        let topmost = chain.last
        if let wall = topmost as? WallPrototypeViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=playlist-wall")
            wall.openNativeStageForBackgroundReturn()
        } else if let home = topmost as? HomeWallViewController {
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=home-wall")
            home.openNativeStageForBackgroundReturn()
        } else if topmost === root {
            // 无墙在场（停在 Web 主界面）：舞台本体自包含（关闭即
            // dismiss、跳网页舞台时 onRequestWebStage 为 nil 走
            // dismiss 兜底），直接由根呈现，不另造舞台内部逻辑。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=present-stage via=main")
            let stage = StageViewController()
            stage.modalPresentationStyle = .fullScreen
            root.present(stage, animated: true)
        } else {
            // 墙上有模态（设置页等）或顶层是其它页面：跳过本次。
            Breadcrumbs.log("nowplaying.route fromBackground=yes hasQueue=yes action=skip reason=modal-presented top=\(type(of: topmost!))")
        }
    }
}
