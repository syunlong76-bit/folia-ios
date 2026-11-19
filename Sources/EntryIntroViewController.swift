import AVFoundation
import UIKit

/// 入场视频数据状态（3.7 (20)）：主页墙的歌单数据加载机对入场
/// 循环的答复——播完一轮时据此决定退场还是再播一轮掩盖。
enum EntryIntroDataState {
    case loading, ready, failed
}

/// 入场视频：v5 全油画入场动画（Miller 2026-11-19 定版）。
///
/// 口径（2026-11-19 12:04/12:07 定；13:04 挪位修正，3.7 (17) 落地；
/// 16:12 触发口径纠正，3.7 (20) 落地）：
/// - 槽位归主页墙进入页：由 HomeWallViewController 在每次进入时
///   触发，以本文件整套横屏 modal 机制呈现；冷启动进 App 的路径
///   就是进墙，效果上冷启仍先见视频，但所有权归墙进入页。
/// - **每次进墙都播**（16:12 Miller 点明原设定，我方 (17)/(18)
///   曾窄化成「每进程只播一次」，已撤销）：动画的用途就是掩盖
///   拉取数据慢——退出重进墙时数据重拉的几秒只剩黑屏即是反例。
///   唯一抑制是入场自身退场引发的那次墙露面（同一次进墙事件的
///   下半程，Presenter 的一次性抑制标志消费），防自激重播。
/// - 循环掩盖（3.7 (20)）：每轮自然播完时查墙数据状态——已就绪
///   才退场；仍在加载则 seek 回零再播一轮；已明确失败（最终失败
///   /未登录落定）则退场落到墙的失败态，不无限循环。关闭按钮
///   任何时候可退场。数据先就绪不许掐断当前播次（(18) 定版）。
/// - 呈现时把界面转到横屏（preferredInterfaceOrientationForPresentation +
///   windowScene.requestGeometryUpdate），单层 AVPlayerLayer
///   resizeAspectFill 铺满全屏（16:9 素材在 19.5:9 上下少量裁切，定版接受）。
/// - 关闭按钮（12:07 追加）：横屏安全区右上角，系统观感（半透明黑圆底 +
///   白色 ×，34pt），入场开始即显示可点；点它立即结束入场进墙——
///   墙数据未就绪时墙自呈既有加载态，不黑屏、不堵在入场面。
/// - 画面点按不再跳过（12:07 定）：只认关闭按钮与自动退出，避免误触。
/// - 海报垫底 + 退场衔接（3.7 (20)，Miller 16:14 追加「衔接好」）：
///   入场 VC 之下、墙之上垫一层油画海报帧（母带 2.0s 帧，
///   Resources/EntryVideo/entry-poster.jpg）。退场 choreography：
///   视频层 0.4s 淡出露出海报 → 横→竖旋转在海报遮蔽下完成 →
///   海报与真实墙面交叉淡入（0.35s）+ 墙面 1.02→1.00 弹簧落位；
///   点关闭走同一套、节奏略快且关闭按钮先行淡出（0.15s）。
///   曲线用 iOS 系统减速/弹簧，禁线性硬切。消失后彻底释放 player。
///   保留的安全出口（视频自身问题，非加载）：播放失败立即放行、
///   看门狗（每轮时长 + 2.5s）兜底。
/// - 音频（3.7 (20) 定案修正）：播放期类别用 .playback 与全局
///   统一——(16) 曾刻意定 .ambient（遵静音拨片），是全 App 唯一
///   遵拨片的发声面，拨片静音时画面照播、声音全哑（audit-3720
///   定案，(19) 真机无声即此）。退出时类别本就是 .playback，
///   teardown 只停活通知他人，口径与启动一致。
enum EntryIntroPresenter {

    private static var isPresenting = false
    private static var suppressNextPresent = false
    private static weak var current: EntryIntroViewController?

    /// 主页墙数据状态提供者（HomeWall 在 viewDidLoad 登记，
    /// 弱引用自持）。未登记者按 failed 答复：宁可退场进墙，
    /// 不许入场无限循环。
    static var dataStateProvider: (() -> EntryIntroDataState)?
    static var currentDataState: EntryIntroDataState {
        dataStateProvider?() ?? .failed
    }

    /// 入场退场会引发主页墙紧接着的一次 viewDidAppear（同一次
    /// 进墙事件的下半程）：VC 退场前调本方法置标志，墙在
    /// viewDidAppear 里消费一次、跳过重播。
    static func suppressNext() {
        suppressNextPresent = true
    }

    static func consumeSuppression() -> Bool {
        guard suppressNextPresent else { return false }
        suppressNextPresent = false
        return true
    }

    /// VC 退场落定后回调：清呈现中标志，允许下一次进墙再播。
    static func introDidFinish() {
        isPresenting = false
        current = nil
    }

    /// 由主页墙进入页触发：在 presenter 之上呈现入场视频。
    /// 每次进墙都受理；正在呈现中、资源缺失、窗口未就绪不受理。
    @discardableResult
    static func present(from presenter: UIViewController) -> Bool {
        guard !isPresenting else { return false }
        guard let url = Bundle.main.url(forResource: "entry-v5",
                                        withExtension: "mp4",
                                        subdirectory: "EntryVideo") else {
            // 资源缺失：静默放行，绝不因入场面挡住主页墙
            NSLog("[EntryIntro] entry-v5.mp4 missing from bundle, skip")
            return false
        }
        guard let window = presenter.view.window else { return false }
        isPresenting = true
        // 推迟一帧再呈现，确保 presenter 已进窗口层级
        DispatchQueue.main.async {
            // 海报垫：垫在入场 VC 之下、主页墙之上。播放期它被
            // 视频层盖住；退场时视频先淡到它身上，转回竖屏在
            // 海报下完成，随后海报与墙面交叉淡入。不拦截触摸：
            // 哪怕残留也不会挡住墙交互（另有兜底移除）。
            let veil = UIImageView(frame: window.bounds)
            if let posterPath = Bundle.main.path(forResource: "entry-poster",
                                                 ofType: "jpg",
                                                 inDirectory: "EntryVideo"),
               let poster = UIImage(contentsOfFile: posterPath) {
                veil.image = poster
            } else {
                veil.backgroundColor = .black
                NSLog("[EntryIntro] entry-poster.jpg missing, veil falls back to black")
            }
            veil.contentMode = .scaleAspectFill
            veil.clipsToBounds = true
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
    /// 已循环播次计数（面包屑对账用，首轮为 0）。
    private var loopCount = 0

    private let playerView = PlayerLayerView()
    private let closeButton = UIButton(type: .custom)

    /// 退出海报垫（由 Presenter 垫在 window 里、入场 VC 之下），退场序列用
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

        // 音频：.playback 与全局统一（3.7 (20) 定案）——不遵静音
        // 拨片，与 AppDelegate 启动口径、PlaybackEngine 一致。
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            NSLog("[EntryIntro] AVAudioSession playback failed: \(error.localizedDescription)")
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            NSLog("[EntryIntro] player item failed: \(item.error?.localizedDescription ?? "?")")
            DispatchQueue.main.async { self?.dismissIntro(reason: "failed", animated: false) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.handlePlaybackEnded() }
        failObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.dismissIntro(reason: "failed", animated: false) }

        scheduleWatchdog()
        player.play()
    }

    /// 看门狗：单轮时长 + 2.5s 兜底放行（时长未知时按 12.5s）；
    /// 每轮循环重排，防某一轮播完通知丢失时挂死在入场面。
    private func scheduleWatchdog() {
        watchdog?.cancel()
        let duration = player?.currentItem?.duration.seconds ?? 0
        let limit = (duration.isFinite && duration > 0) ? duration + 2.5 : 12.5
        let work = DispatchWorkItem { [weak self] in
            self?.dismissIntro(reason: "watchdog", animated: true)
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: work)
    }

    /// 一轮自然播完（3.7 (20) 循环掩盖）：查墙数据状态——
    /// 就绪才退场；仍在加载则回零再播一轮（掩盖拉数据）；
    /// 已明确失败则退场落到墙的失败态，不无限循环。
    private func handlePlaybackEnded() {
        guard !isDismissing else { return }
        switch EntryIntroPresenter.currentDataState {
        case .ready:
            dismissIntro(reason: "finished", animated: true)
        case .failed:
            dismissIntro(reason: "data-failed", animated: true)
        case .loading:
            loopCount += 1
            Breadcrumbs.log("entry loop round=\(loopCount)")
            scheduleWatchdog()
            player?.seek(to: .zero) { [weak self] _ in
                guard let self, !self.isDismissing else { return }
                self.player?.play()
            }
        }
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
        // 本次退场引发的墙露面不重播入场（同一次进墙事件）。
        EntryIntroPresenter.suppressNext()

        guard animated else {
            // 播放失败：立即放行，不等转场
            rotateBack()
            teardownPlayer()
            veil?.removeFromSuperview()
            if let presenter {
                presenter.dismiss(animated: false) {
                    EntryIntroPresenter.introDidFinish()
                }
            } else {
                EntryIntroPresenter.introDidFinish()
            }
            return
        }

        // 退场衔接（3.7 (20)）：点关闭节奏略快且关闭按钮先行
        // 淡出；自然播完/看门狗走标准节奏，按钮随视频层一起淡。
        let fast = reason == "closed"
        let fadeDuration = fast ? 0.3 : 0.4
        let beginExit = { [weak self] in
            guard let self else { return }
            // 阶段一：视频层淡出到海报垫（0.4s），此时不请求转
            // 方向，画面整体隐入油画帧，用户看不到任何旋转。
            UIView.animate(withDuration: fadeDuration, delay: 0, options: [.curveEaseOut], animations: {
                self.view.alpha = 0
            }, completion: { [weak self] _ in
                // 阶段二：海报遮蔽下拆播放器、请求转回竖屏、移除
                // 入场 VC；旋转在海报下走完后，海报与墙面交叉
                // 淡入 + 墙面弹簧落位（revealHome）。
                self?.teardownPlayer()
                rotateBack()
                if let presenter {
                    presenter.dismiss(animated: false) {
                        EntryIntroPresenter.introDidFinish()
                        Self.revealHome(veil: veil, wallView: presenter.view, fast: fast)
                    }
                } else {
                    Self.revealHome(veil: veil, wallView: nil, fast: fast)
                }
            })
        }
        if fast {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: {
                self.closeButton.alpha = 0
            }, completion: { _ in beginExit() })
        } else {
            beginExit()
        }
    }

    /// 海报与真实墙面交叉淡入：先留一拍让系统旋转在海报下走完，
    /// 海报 0.35s 淡出的同时墙面以 1.02→1.00 弹簧落位收尾；
    /// 另设 2.5s 兜底强制移除，绝不把用户挡在海报后。
    private static func revealHome(veil: UIView?, wallView: UIView?, fast: Bool) {
        guard let veil else { return }
        wallView?.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        let delay = fast ? 0.35 : 0.45
        UIView.animate(withDuration: 0.35, delay: delay, options: [.curveEaseOut], animations: {
            veil.alpha = 0
        }, completion: { _ in
            veil.removeFromSuperview()
        })
        UIView.animate(withDuration: 0.45, delay: delay,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction], animations: {
            wallView?.transform = .identity
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

        // 音频会话收尾：停活并通知他人。类别在播放期已定为
        // .playback、与 AppDelegate 启动口径相同，不再改写。
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            NSLog("[EntryIntro] AVAudioSession deactivate failed: \(error.localizedDescription)")
        }
    }
}
