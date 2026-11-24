import AVFoundation
import CryptoKit
import UIKit

/// 进程启动标记（3.7 (44)）：didFinishLaunching 时刻的系统
/// 运行时钟。SceneDelegate 据此区分「进程新生冷启」（新
/// delegate＋进程年龄≈0）与「活进程 scene 重连」（新 delegate
/// ＋进程已存活）——两者首次激活都未武装、外观一致，进程年
/// 龄是唯一可靠区分；冷启绝不 route、重连按点卡处理。
enum AppProcessMark {
    static var launchUptime: TimeInterval =
        ProcessInfo.processInfo.systemUptime
}

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
        AppProcessMark.launchUptime = ProcessInfo.processInfo.systemUptime
        // (76) ⑨一次性修复（审计与定案等级见 (76) 报告⑨）：
        // miniPets 持久 false 非设置页操作（Miller 22:17 确
        // 认从没动过设置开关）；双读取在键不存在时都默认
        // 开——false 只能是历史手势路径（爪印长按关/长按宠
        // 物静止 3 秒关，均无二次确认）的静默写入且跨版本
        // 持久至今。只修一次（标记键防重复）：当前为关则
        // 恢复为开并以 src=repair76 留名；修复后开关语义完
        // 全归用户、再关不自动恢复。置于 appStart 读痕之
        // 前，使启动行即为修复后值。
        let restoreKey76 = "folia.miniPets.restore76Done"
        if UserDefaults.standard.object(forKey: restoreKey76) == nil {
            UserDefaults.standard.set(true, forKey: restoreKey76)
            if !StickerSettings.miniPetsEnabled {
                StickerSettings.setMiniPetsEnabled(true, src: "repair76")
            }
        }
        Breadcrumbs.log("pet.settings.read src=appStart"
            + " miniPets=\(StickerSettings.miniPetsEnabled)"
            + " legacyCompanion=\(StickerSettings.companionEnabled)")
        // (77) 读侧见证（(76) 会话新警情：开关在日志缺口
        // 内又被写关且 switch76/restore76 均零条）：启动
        // 时把双键的原始存值（存在性＋值）各落一行——双
        // 键脱同步（导入旁路只写新键）或旧键被翻转，下次
        // 启动即对位；运行中翻转由 StickerSettings 读侧
        // 去重见证（pet.audit77 翻转行）钉时刻。
        let auditDefaults = UserDefaults.standard
        func rawKey(_ key: String) -> String {
            guard let obj = auditDefaults.object(forKey: key)
            else { return "-" }
            return (obj as? Bool).map { $0 ? "1" : "0" } ?? "?"
        }
        Breadcrumbs.log("pet.audit77 launch"
            + " new=\(rawKey("settings.general.miniPetsEnabled"))"
            + " legacy=\(rawKey("folia.stickers.miniPetsEnabled"))")
        // (78) 见证启动自检（见 Breadcrumbs.witnessBoot78）。
        Breadcrumbs.witnessBoot78()
        // (83) 第 3 条：灯光不跨启动保留——冷启即恢复开灯
        // （白天）模式（回前台一路在 SceneDelegate）。
        WallLight82.resetOnEntry83(source: "launch")
        // (83) 第 2 条取证回收：上一会话若在双击链中途消
        // 亡（闪退），尾巴里最后一条 dbltap83 的 step 即
        // 崩溃前最后一步——带回本会话日志头（crash83），
        // 不必等导出整份日志才判读。无双击痕迹则静默。
        let prevTail83 = FoliaBridgeLogStore.shared.prevTailText()
        let dblLines83 = prevTail83.split(separator: "\n")
            .filter { $0.contains("dbltap83") }
        if let lastDbl83 = dblLines83.last {
            let step83 = lastDbl83.split(separator: " ")
                .first { $0.hasPrefix("step=") } ?? "step=?"
            Breadcrumbs.log("crash83 prevDbl=1 n=\(dblLines83.count)"
                + " last=\(step83)")
        }
        // (80) 下一首预备协调器：进程级订阅当前曲/队列，播
        // 放期间为下一首预拉歌词＋预派生行表＋预热记忆样式。
        NextTrackPrep80.shared.startIfNeeded()
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
