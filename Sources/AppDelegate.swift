import AVFoundation
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// 音频打断结束的监听令牌（AppDelegate 与应用同寿，持有它即可）
    private var interruptionObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 音乐播放器的音频会话：.playback 让 WKWebView 的网页音频不受静音拨片影响、
        // 锁屏/后台继续出声。此前（含 1.0 壳）从未配置，WebKit 只能用默认会话。
        // 启动时只定类别、不激活：激活会立刻打断其他 App 正在放的声音，而用户可能
        // 只是打开 Folia 浏览歌单；真正起播时由 WebKit 按类别激活会话。
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
        } catch {
            NSLog("[AppDelegate] AVAudioSession setCategory failed: \(error.localizedDescription)")
        }
        // 来电/Siri 等打断结束后系统不会自动把会话恢复为激活状态，网页音频可能就此
        // 没声：只在打断结束这一刻补一次激活（此时用户正在与本应用交互，合情合理）。
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                NSLog("[AppDelegate] AVAudioSession reactivate failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
