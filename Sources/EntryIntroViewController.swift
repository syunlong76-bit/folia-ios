import AVFoundation
import UIKit

/// 3.7 (16) 冷启动入场视频：v5 全油画入场动画（Miller 2026-11-19 定版）。
///
/// 口径（2026-11-19 12:04 Miller 改定，横屏全屏版）：
/// - 每进程只播一次：SceneDelegate 冷启 willConnectTo 时以全屏 VC 呈现；
///   热恢复不重播（静态守卫 + 热恢复根本不走 willConnectTo）。
/// - 呈现时把界面转到横屏（preferredInterfaceOrientationForPresentation +
///   windowScene.requestGeometryUpdate），单层 AVPlayerLayer
///   resizeAspectFill 铺满全屏（16:9 素材在 19.5:9 上下少量裁切，定版接受）。
/// - 退出：播完自动淡出（0.45s）；播放中点按跳过淡出；播放失败立即放行；
///   另设看门狗（时长 + 2.5s）兜底——数据未就绪也绝不把用户堵过视频时长。
///   退出同时请求转回竖屏；消失后彻底释放 player。
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
        guard let root = window.rootViewController else { return }
        hasPresented = true
        // 推迟一帧再呈现，确保 root 已进窗口层级，避免 willConnectTo 内直接 present 被系统拒绝
        DispatchQueue.main.async {
            let vc = EntryIntroViewController(url: url)
            vc.modalPresentationStyle = .fullScreen
            root.present(vc, animated: false) {
                // 呈现后再补一次几何请求，双保险把界面转到横屏
                window.windowScene?.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .landscapeRight)
                ) { error in
                    NSLog("[EntryIntro] requestGeometryUpdate landscape failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

final class EntryIntroViewController: UIViewController {

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

    private let playerView = PlayerLayerView()

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerView.playerLayer.videoGravity = .resizeAspectFill
        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)

        startPlayback()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerView.frame = view.bounds
    }

    // MARK: - 播放

    private func startPlayback() {
        Breadcrumbs.log("entry show")
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player
        playerView.playerLayer.player = player

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
            DispatchQueue.main.async { self?.dismissIntro(reason: "failed", animated: false) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.dismissIntro(reason: "finished", animated: true) }
        failObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.dismissIntro(reason: "failed", animated: false) }

        // 看门狗：时长 + 2.5s 兜底放行（时长未知时按 12.5s）
        let duration = item.duration.seconds
        let limit = (duration.isFinite && duration > 0) ? duration + 2.5 : 12.5
        let work = DispatchWorkItem { [weak self] in
            self?.dismissIntro(reason: "watchdog", animated: true)
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: work)

        player.play()
    }

    @objc private func handleTap() {
        dismissIntro(reason: "skipped", animated: true)
    }

    // MARK: - 退出与释放

    private func dismissIntro(reason: String, animated: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        Breadcrumbs.log("entry end \(reason)")
        watchdog?.cancel()
        watchdog = nil
        view.isUserInteractionEnabled = false

        // 退出即请求转回竖屏（与淡出并行，系统旋转动画自带节奏）
        view.window?.windowScene?.requestGeometryUpdate(
            .iOS(interfaceOrientations: .portrait)
        ) { error in
            NSLog("[EntryIntro] requestGeometryUpdate portrait failed: \(error.localizedDescription)")
        }

        let finish = { [weak self] in
            guard let self else { return }
            self.teardownPlayer()
            self.presentingViewController?.dismiss(animated: false)
        }
        if animated {
            UIView.animate(withDuration: 0.45, animations: { self.view.alpha = 0 }, completion: { _ in finish() })
        } else {
            finish()
        }
    }

    private func teardownPlayer() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = nil
        failObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        playerView.playerLayer.player = nil
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
    }
}
