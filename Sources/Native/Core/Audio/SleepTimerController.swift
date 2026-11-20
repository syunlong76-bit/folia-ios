import Foundation

/// 睡眠定时（3.7 (48) 点播台管理搬入，网页版 useSleepTimer 对应面）。
///
/// 预设档位制（关 / 10 / 20 / 30 / 45 / 60 分钟）；到期自动暂停播放。
/// 状态经 `changedNotification` 广播，墙面/舞台两处面板同源刷新。
/// 定时器走主 RunLoop 的 .common 模式，面板滚动期间不丢拍。
final class SleepTimerController {

    static let shared = SleepTimerController()
    static let changedNotification = Notification.Name("folia.sleepTimer.changed")

    /// 预设档位（分钟），0 = 关闭。
    static let presets: [Int] = [0, 10, 20, 30, 45, 60]

    private(set) var endDate: Date?
    private var timer: Timer?

    private init() {}

    var isActive: Bool { endDate != nil }

    /// 当前选中的预设档（按到期时刻反推最接近的档位，仅供 UI 高亮；
    /// 到期前会随时间漂移，UI 以 isActive + 剩余时间文案为准）。
    var activePresetMinutes: Int? {
        guard let remaining = remainingSeconds else { return nil }
        let minutes = Int((remaining / 60).rounded())
        return Self.presets.first(where: { $0 > 0 && abs($0 - minutes) <= 1 }) ?? minutes
    }

    var remainingSeconds: TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSinceNow) }
    }

    /// 设档：minutes <= 0 关闭，其余按分钟起计。
    func set(minutes: Int) {
        timer?.invalidate()
        timer = nil
        if minutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            endDate = end
            let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
                self?.expire()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            Breadcrumbs.log("sleepTimer.set minutes=\(minutes)")
        } else {
            endDate = nil
            Breadcrumbs.log("sleepTimer.off")
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func cancel() { set(minutes: 0) }

    private func expire() {
        timer = nil
        endDate = nil
        if PlaybackEngine.shared.isPlaying {
            PlaybackEngine.shared.pause()
        }
        Breadcrumbs.log("sleepTimer.expire")
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }
}
