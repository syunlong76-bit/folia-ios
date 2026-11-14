import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // 1) 准备 Web 根目录：首次拷贝内置版本；如有已下载待生效的新版本且目录完整，切换生效
        WebRootManager.shared.prepare()

        // 2) 主界面（内含 WKWebView + 本地服务器启动）；窗口底色纯黑，
        //    避免全屏沉浸时系统窗口在边缘透出白底
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = MainViewController()
        window.makeKeyAndVisible()
        self.window = window

        // 3) 冷启动自动检查更新（开关开启时，后台队列执行，不阻塞启动）
        if UpdateManager.shared.autoUpdateEnabled {
            DispatchQueue.global(qos: .utility).async {
                UpdateManager.shared.checkNow(completion: nil)
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
