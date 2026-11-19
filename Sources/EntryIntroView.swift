import AVFoundation
import UIKit

/// 3.7 (16) 冷启动入场视频面：v5 全油画入场动画（Miller 2026-11-19 12:00 定版）。
///
/// 口径（定版，不许改）：
/// - 每进程只播一次：SceneDelegate 冷启 willConnectTo 时挂到 window 上；
///   热恢复不重播（静态守卫 + 热恢复根本不走 willConnectTo）。
/// - 全屏双层同源：一个 AVPlayer 挂两个 AVPlayerLayer——底层 aspectFill 放大
///   铺满 + 高斯模糊作氛围底，顶层 aspectFit 完整构图居中，构图一帧不裁。
/// - 退出：播完自动淡出（0.45s）；播放中点按跳过淡出；播放失败立即放行；
///   另设看门狗（时长 + 2.5s）兜底——数据未就绪也绝不把用户堵过视频时长。
///   淡出后彻底移除视图并释放 player。
/// - 音频：播放期临时切 .ambient（遵静音键、与其它 App 混播、不打断别人
///   正在听的音乐）；退出时恢复 AppDelegate 启动定的 .playback
///   （只定类别、不激活，与启动语义保持一致，不改变后续 Web 播放行为）。
enum EntryIntroPresenter {

    private static var hasPresented = false

    static func presentIfNeeded(in window: UIWindow) {
        guard !hasPresented else { return }
        guard let url = Bundle.main.url(forResource: "entry-v5",
                                        withExtension: "mp4",
                                        subdirectory: "EntryVideo") else {
            // 资源缺失：静默放行，绝不因入场面挡住主界面
            NSLog("[EntryIntro] entry-v5.mp4 missing from bundle, skip")
            return
        }
        hasPresented = true
        let view = EntryIntroView(url: url)
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
        view.start()
    }
}

final class EntryIntroView: UIView {

    /// 承载 AVPlayerLayer 的视图（layerClass 模式）
    private final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    private let url: URL
    private var player: AVPlayer?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var watchdog: DispatchWorkItem?
    private var isDismissing = false

    private let bottomView = PlayerLayerView()   // 氛围底：aspectFill + 模糊
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let dimView = UIView()               // 轻压暗，让顶层构图更聚
    private let topView = PlayerLayerView()      // 主画面：aspectFit 完整构图

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        backgroundColor = .black

        bottomView.playerLayer.videoGravity = .resizeAspectFill
        topView.playerLayer.videoGravity = .resizeAspect
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        dimView.isUserInteractionEnabled = false
        blurView.isUserInteractionEnabled = false
        addSubview(bottomView)
        addSubview(blurView)
        addSubview(dimView)
        addSubview(topView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 底层放大 25% 居中：模糊边缘不露黑边，氛围色取自画面本身
        bottomView.frame = bounds.insetBy(dx: -bounds.width * 0.125,
                                          dy: -bounds.height * 0.125)
        blurView.frame = bounds
        dimView.frame = bounds
        topView.frame = bounds
    }

    // MARK: - 播放

    func start() {
        Breadcrumbs.log("entry show")
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player
        bottomView.playerLayer.player = player
        topView.playerLayer.player = player

        // 音频：临时 .ambient（遵静音键、混播、不打断其它 App 音乐）
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            NSLog("[EntryIntro] AVAudioSession ambient failed: \(error.localizedDescription)")
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            NSLog("[EntryIntro] player item failed: \(item.error?.localizedDescription ?? "?")")
            DispatchQueue.main.async { self?.dismiss(reason: "failed", animated: false) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.dismiss(reason: "finished", animated: true) }
        failObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.dismiss(reason: "failed", animated: false) }

        // 看门狗：时长 + 2.5s 兜底放行（时长未知时按 12.5s）
        let duration = item.duration.seconds
        let limit = (duration.isFinite && duration > 0) ? duration + 2.5 : 12.5
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss(reason: "watchdog", animated: true)
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: work)

        player.play()
    }

    @objc private func handleTap() {
        dismiss(reason: "skipped", animated: true)
    }

    // MARK: - 退出与释放

    private func dismiss(reason: String, animated: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        Breadcrumbs.log("entry end \(reason)")
        watchdog?.cancel()
        watchdog = nil
        // 淡出期间放行点按，别让透明中的视图继续吞手势
        isUserInteractionEnabled = false

        let teardown = { [weak self] in self?.teardown() }
        if animated {
            UIView.animate(withDuration: 0.45, animations: { self.alpha = 0 }, completion: { _ in teardown() })
        } else {
            teardown()
        }
    }

    private func teardown() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = nil
        failObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        bottomView.playerLayer.player = nil
        topView.playerLayer.player = nil
        player = nil

        // 音频会话恢复：先停活并通知他人，再把类别改回启动定的 .playback
        //（只定类别、不激活，与 AppDelegate 启动语义一致）
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            NSLog("[EntryIntro] AVAudioSession deactivate failed: \(error.localizedDescription)")
        }
        do {
            try session.setCategory(.playback, mode: .default)
        } catch {
            NSLog("[EntryIntro] AVAudioSession restore category failed: \(error.localizedDescription)")
        }

        removeFromSuperview()
    }
}
