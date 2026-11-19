import AVFoundation
import UIKit

/// 入场视频：v5 全油画入场动画（Miller 2026-11-19 定版）。
///
/// 口径（2026-11-19 12:04/12:07 定；13:04 挪位修正，3.7 (17) 落地）：
/// - 槽位归主页墙进入页（3.7 (17) 方案 B）：(16) 时挂在 SceneDelegate
///   冷启动、盖的是 Web 主界面，与墙脱钩——已撤销。现由
///   HomeWallViewController 在进入且数据在途时触发，以本文件整套
///   横屏 modal 机制呈现（触发点换、机制不重写）；冷启动进 App 的
///   路径就是进墙，效果上冷启仍先见视频，但所有权归墙进入页。
/// - 每进程只播一次：静态守卫；热恢复与重进主页墙都不重播。
/// - 呈现时把界面转到横屏（preferredInterfaceOrientationForPresentation +
///   windowScene.requestGeometryUpdate），单层 AVPlayerLayer
///   resizeAspectFill 铺满全屏（16:9 素材在 19.5:9 上下少量裁切，定版接受）。
/// - 关闭按钮（12:07 追加）：横屏安全区右上角，系统观感（半透明黑圆底 +
///   白色 ×，34pt），入场开始即显示可点；点它立即结束入场进墙——
///   墙数据未就绪时墙自呈既有加载态，不黑屏、不堵在入场面。
/// - 画面点按不再跳过（12:07 定）：只认关闭按钮与自动退出，避免误触。
/// - 退场语义（3.7 (18) 定版，覆盖 (17) 的数据落定退场）：退出只认
///   关闭按钮与自然播完；数据加载状态（完成/失败/未登录）一律不
///   触发退场——默认每次开局都把视频放完，用户不想看自己点关闭。
///   (17) 的 finishCurrent / finishEarly / finishRequested 数据落定
///   通道已整段删除。保留的安全出口（视频自身问题，非加载）：
///   播放失败立即放行、看门狗（时长 + 2.5s）兜底。
/// - 退出转场遮旋转（12:07 追加）：先把入场层淡出到垫在下面的黑幕
///   （0.3s），方向恢复（转回竖屏）在黑幕遮蔽下完成，用户看不到画面
///   硬转 90°；旋转走完后黑幕再淡出（0.35s）露出竖屏主页墙。
///   消失后彻底释放 player。
/// - 音频：播放期临时切 .ambient（遵静音键、混播不打断别人
///   正在听的音乐）；退出时恢复 AppDelegate 启动定的 .playback
///   （只定类别、不激活，与启动语义保持一致，不改变后续 Web 播放行为）。
enum EntryIntroPresenter {

    private static var hasPresented = false
    private static weak var current: EntryIntroViewController?

    /// 由主页墙进入页触发：在 presenter 之上呈现入场视频。
    /// 返回是否已受理（每进程一次、资源缺失、窗口未就绪均不受理）。
    @discardableResult
    static func presentIfNeeded(from presenter: UIViewController) -> Bool {
        guard !hasPresented else { return false }
        guard let url = Bundle.main.url(forResource: "entry-v5",
                                        withExtension: "mp4",
                                        subdirectory: "EntryVideo") else {
            // 资源缺失：静默放行，绝不因入场面挡住主页墙
            NSLog("[EntryIntro] entry-v5.mp4 missing from bundle, skip")
            return false
        }
        guard let window = presenter.view.window else { return false }
        hasPresented = true
        // 推迟一帧再呈现，确保 presenter 已进窗口层级
        DispatchQueue.main.async {
            // 黑幕：垫在入场 VC 之下、主页墙之上。退出时入场层先淡到它身上，
            // 转回竖屏在黑幕下完成，随后黑幕淡出露出主页墙。
            // 不拦截触摸：哪怕残留也不会挡住墙交互（另有兜底移除）。
            let veil = UIView(frame: window.bounds)
            veil.backgroundColor = .black
            veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            veil.isUserInteractionEnabled = false
            window.addSubview(veil)

            let vc = EntryIntroViewController(url: url)
            vc.exitVeil = veil
            vc.modalPresentationStyle = .fullScreen
            current = vc
            presenter.present(vc, animated: false) {
                // 呈现后再补一次几何请求，双保险把界面转到横屏
                window.windowScene?.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .landscapeRight)
                ) { error in
                    NSLog("[EntryIntro] requestGeometryUpdate landscape failed: \(error.localizedDescription)")
                }
            }
        }
        return true
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
    private let closeButton = UIButton(type: .custom)

    /// 退出黑幕（由 Presenter 垫在 window 里、入场 VC 之下），退出序列用
    var exitVeil: UIView?

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

        // 关闭按钮：横屏安全区右上角，入场开始即显示；点按 = 立即结束入场。
        // 画面其它位置点按不跳过（防误触），退出只认此按钮与自动到点。
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbol), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 17
        closeButton.clipsToBounds = true
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        ])

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

    @objc private func handleCloseTap() {
        dismissIntro(reason: "closed", animated: true)
    }

    // MARK: - 退出与释放

    private func dismissIntro(reason: String, animated: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        Breadcrumbs.log("entry end \(reason)")
        watchdog?.cancel()
        watchdog = nil
        view.isUserInteractionEnabled = false

        // 先把退出要用的对象都摘出来，动画回调里不依赖 self 存活
        let veil = exitVeil
        exitVeil = nil
        let scene = view.window?.windowScene
        let presenter = presentingViewController
        let rotateBack = {
            scene?.requestGeometryUpdate(
                .iOS(interfaceOrientations: .portrait)
            ) { error in
                NSLog("[EntryIntro] requestGeometryUpdate portrait failed: \(error.localizedDescription)")
            }
        }

        guard animated else {
            // 播放失败：立即放行，不等转场
            rotateBack()
            teardownPlayer()
            veil?.removeFromSuperview()
            presenter?.dismiss(animated: false)
            return
        }

        // 阶段一：入场层淡出到黑幕（0.3s），此时不请求转方向，
        // 画面（含关闭按钮）整体隐入黑场，用户看不到任何旋转。
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
            self.view.alpha = 0
        }, completion: { [weak self] _ in
            // 阶段二：黑幕遮蔽下拆播放器、请求转回竖屏、移除入场 VC；
            // 旋转动画在黑幕下走完后，黑幕再淡出露出竖屏主页墙。
            self?.teardownPlayer()
            rotateBack()
            if let presenter {
                presenter.dismiss(animated: false) {
                    Self.revealHome(veil: veil)
                }
            } else {
                Self.revealHome(veil: veil)
            }
        })
    }

    /// 黑幕淡出露出主页墙：先留 0.5s 让系统旋转在黑幕下走完，再 0.35s 淡出；
    /// 另设 2.5s 兜底强制移除，绝不把用户挡在黑屏后。
    private static func revealHome(veil: UIView?) {
        guard let veil else { return }
        UIView.animate(withDuration: 0.35, delay: 0.5, options: [.curveEaseOut], animations: {
            veil.alpha = 0
        }, completion: { _ in
            veil.removeFromSuperview()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            veil.removeFromSuperview()
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
