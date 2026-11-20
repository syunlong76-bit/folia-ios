import Combine
import UIKit

/// 点播台上排（网页 CapsuleQuickActions＋SongActions 设置键）的
/// UIKit 唯一实现（3.7 (54) 工作流 H）：(53) 已按网页功能矩阵在
/// SwiftUI 的 MiniPlayerView 里落过同一排，但三台真机台面是各
/// VC 手搭的 UIKit 玻璃台（主题层/5 秒收起细条/宠物台锚定/底
/// 缘 seek 全是 UIKit 定版规格），整排接入只能落 UIKit——本视
/// 图即接入面，功能与口径逐项与 MiniPlayerView 对齐（同一批
/// 既有 API、同一面包屑词根 minibar.webrow），不新造播放逻辑：
///
/// - 喜欢：LikesStore.toggle ＋ NativeDataClient.setLike 云端
///   同步（失败回滚），回显 = LikesStore 本地真源。
/// - 打乱队列：QueueManager.shuffleQueue，队列不足 2 首禁用。
/// - 播放模式：QueueManager.playMode 四档（顺序/循环/单曲/
///   随机）点按轮换，图标随档位。
/// - 睡眠定时：SleepTimerController 预设档轮换（关→10→20→
///   30→45→60→关），生效态高亮。
/// - 设置：宿主回调优先（各台用自家既有呈现方式），缺省走
///   MiniPlayerPanelPresenter.presentSettings。
///
/// 播放列表入口不在本排也不在台面（(53) H 修正定版）：舞台在
/// 顶栏隐藏排、曲目墙在顶部 chrome 排、主页墙台面无此钮。
/// 网页有而本体未迁的键（星标入歌单/格子样式/字幕/命令键/
/// 音量/歌词时间轴）不放假按钮（(53) H 报告缺项清单）。
///
/// 宿主接线三件：onUserInteraction（任一键点按先回调，宿主据
/// 此重置 5 秒无操作计时，与台面其他操作同口径续命）；
/// onLikeStateChanged（喜欢态变化后回调，舞台宿主据此刷新顶
/// 栏红心）；onOpenSettings（可空）。形态名单由宿主收口：宿
/// 主把本视图加入收起态 alpha 淡出名单、并以
/// isUserInteractionEnabled 整体开关交互（收起细条上不许点）。
final class MiniBarQuickRowView: UIView {

    var onUserInteraction: (() -> Void)?
    var onLikeStateChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let likeButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let sleepButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)

    private var cancellables = Set<AnyCancellable>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildButtons()
        bindState()
        refreshAll()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildButtons() {
        let buttons: [(UIButton, String, CGFloat)] = [
            (likeButton, "heart", 17),
            (shuffleButton, "shuffle", 16),
            (modeButton, "repeat", 16),
            (sleepButton, "timer", 16),
            (settingsButton, "gearshape", 16),
        ]
        for (button, symbol, pointSize) in buttons {
            button.setImage(UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize)),
                for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.75)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        likeButton.accessibilityLabel = "喜欢"
        shuffleButton.accessibilityLabel = "打乱队列"
        modeButton.accessibilityLabel = "播放模式"
        sleepButton.accessibilityLabel = "定时关闭"
        settingsButton.accessibilityLabel = "设置"
        NSLayoutConstraint.activate([
            likeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            shuffleButton.leadingAnchor.constraint(equalTo: likeButton.trailingAnchor),
            modeButton.leadingAnchor.constraint(equalTo: shuffleButton.trailingAnchor),
            sleepButton.leadingAnchor.constraint(equalTo: modeButton.trailingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        shuffleButton.addTarget(self, action: #selector(shuffleTapped), for: .touchUpInside)
        modeButton.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        sleepButton.addTarget(self, action: #selector(sleepTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
    }

    /// 状态订阅：切歌刷新喜欢、队列变化刷新打乱可用性、模式
    /// 变化刷新模式图标、睡眠通知刷新定时高亮——全部回主线程。
    private func bindState() {
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLike() }
            .store(in: &cancellables)
        QueueManager.shared.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMode() }
            .store(in: &cancellables)
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshShuffle() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sleepTimerChanged),
            name: SleepTimerController.changedNotification, object: nil)
    }

    func refreshAll() {
        refreshLike()
        refreshShuffle()
        refreshMode()
        refreshSleep()
    }

    // MARK: - 回显

    private func refreshLike() {
        let liked = PlaybackEngine.shared.currentTrack
            .map { LikesStore.shared.isLiked($0.id) } ?? false
        likeButton.setImage(UIImage(systemName: liked ? "heart.fill" : "heart",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        likeButton.tintColor = liked
            ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1)
            : UIColor.white.withAlphaComponent(0.75)
        likeButton.accessibilityLabel = liked ? "取消喜欢" : "喜欢"
        onLikeStateChanged?()
    }

    private func refreshShuffle() {
        let enabled = QueueManager.shared.queue.count >= 2
        shuffleButton.isEnabled = enabled
        shuffleButton.alpha = enabled ? 1 : 0.35
    }

    private func refreshMode() {
        let mode = QueueManager.shared.playMode
        let symbol: String
        switch mode {
        case .loopAll: symbol = "repeat"
        case .repeatOne: symbol = "repeat.1"
        case .shuffle: symbol = "shuffle"
        case .off: symbol = "repeat"
        }
        modeButton.setImage(UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)), for: .normal)
        modeButton.tintColor = mode == .off
            ? UIColor.white.withAlphaComponent(0.45) : .white
    }

    private func refreshSleep() {
        sleepButton.tintColor = SleepTimerController.shared.isActive
            ? .white : UIColor.white.withAlphaComponent(0.75)
    }

    @objc private func sleepTimerChanged() {
        refreshSleep()
    }

    // MARK: - 动作（与 MiniPlayerView 同路，面包屑同词根）

    @objc private func likeTapped() {
        onUserInteraction?()
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        refreshLike()
        Breadcrumbs.log("minibar.webrow like id=\(id) on=\(newState)")
        Task { [weak self] in
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                await MainActor.run { self?.refreshLike() }
            }
        }
    }

    @objc private func shuffleTapped() {
        onUserInteraction?()
        Breadcrumbs.log("minibar.webrow shuffleQueue")
        QueueManager.shared.shuffleQueue()
    }

    @objc private func modeTapped() {
        onUserInteraction?()
        let order: [QueueManager.PlayMode] = [.off, .loopAll, .repeatOne, .shuffle]
        let current = order.firstIndex(of: QueueManager.shared.playMode) ?? 1
        let next = order[(current + 1) % order.count]
        QueueManager.shared.playMode = next
        Breadcrumbs.log("minibar.webrow mode=\(next.rawValue)")
    }

    @objc private func sleepTapped() {
        onUserInteraction?()
        let presets = SleepTimerController.presets
        let current = SleepTimerController.shared.activePresetMinutes ?? 0
        let index = presets.firstIndex(of: current) ?? 0
        let next = presets[(index + 1) % presets.count]
        SleepTimerController.shared.set(minutes: next)
        refreshSleep()
    }

    @objc private func settingsTapped() {
        onUserInteraction?()
        if let onOpenSettings {
            onOpenSettings()
        } else {
            MiniPlayerPanelPresenter.presentSettings()
        }
    }
}
