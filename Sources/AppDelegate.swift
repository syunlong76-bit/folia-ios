import AVFoundation
import CryptoKit
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// 音频打断结束的监听令牌（AppDelegate 与应用同寿，持有它即可）
    private var interruptionObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 启动留痕（3.7 (29)，走既有 crumb 通道）：版本号与包内
        // dog-11 的运行时 md5 一行入账——「装的到底是不是这个
        // 包、素材是不是这份」下次凭桥日志即可定案，不靠猜。
        let info = Bundle.main.infoDictionary
        let shortVer = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildVer = info?["CFBundleVersion"] as? String ?? "?"
        var dogDesc = "resource-missing"
        if let url = Bundle.main.url(forResource: "dog-11", withExtension: "png",
                                      subdirectory: "Stickers"),
           let data = try? Data(contentsOf: url) {
            let md5 = Insecure.MD5.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            dogDesc = "url=\(url.path) md5=\(md5) bytes=\(data.count)"
        }
        Breadcrumbs.log("app.build short=\(shortVer) build=\(buildVer) dog11 \(dogDesc)")
        Breadcrumbs.log("pet.settings.read src=appStart"
            + " miniPets=\(StickerSettings.miniPetsEnabled)"
            + " legacyCompanion=\(StickerSettings.companionEnabled)")
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
        // 锁屏远程命令在启动时就注册（3.6 (3)）：NowPlayingController 的注册
        // 原先靠单例首次被引擎/队列触碰时才发生，时机不确定；这里显式触碰，
        // 保证命令从冷启起就在位（处理闭包里对引擎的调用都是惰性的，安全）。
        _ = NowPlayingController.shared
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
