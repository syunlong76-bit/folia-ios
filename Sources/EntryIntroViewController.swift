import AVFoundation
import Combine
import QuartzCore
import UIKit

/// 入场视频数据状态（3.7 (20)）：主页墙的歌单数据加载机对入场
/// 循环的答复——播完一轮时据此决定退场还是再播一轮掩盖。
enum EntryIntroDataState {
    case loading, ready, failed
}

/// 入场海报资源（3.7 (53) 工作流 I）：entry-poster.jpg 的预解码
/// 缓存与平均主色。原 veil 在 present 的异步回合里用
/// UIImage(contentsOfFile:) 惰性加载（首绘才解码），且垫在
/// window 层、位于呈现出的入场 VC 之下——VC 内 AVPlayerLayer
/// 未出帧时是不透明黑，海报实际从未盖住黑窗（见下方 (53)
/// 定级）。本枚举把解码提前完成并缓存，SceneDelegate 的窗口
/// 底色与 VC 内海报层共用同一份图/色。仅主线程调用（窗口建
/// 立、present、viewDidLoad 皆主线程），静态缓存不加锁。
enum EntryPosterArt {

    private static var cachedImage: UIImage?
    private static var cachedColor: UIColor?

    /// 预解码后的海报图（1280×720，母带 2.0s 帧）：首次调用
    /// 同步解码并绘进位图上下文强制完成解压缩，之后命中缓
    /// 存、绘制零等待。资源缺失返回 nil（调用方以主色兜底）。
    static func image() -> UIImage? {
        if let cachedImage { return cachedImage }
        guard let path = Bundle.main.path(forResource: "entry-poster",
                                          ofType: "jpg",
                                          inDirectory: "EntryVideo"),
              let raw = UIImage(contentsOfFile: path) else { return nil }
        let size = raw.size
        guard size.width > 0, size.height > 0 else {
            cachedImage = raw
            return raw
        }
        // scale=1 按像素原尺寸解码（默认按设备 scale 会放大数倍）。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let decoded = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: size))
        }
        cachedImage = decoded
        return decoded
    }

    /// 海报平均主色：把解码图绘进 1×1 上下文取平均（图已解
    /// 码、一次性开销可忽略）。取色失败回退实测平均色
    /// #6A7342（橄榄绿，离线对 entry-poster.jpg 全图平均所
    /// 得）。窗口底色/海报层底色共用，保证任何一层露出时都
    /// 是油画色域而非黑。
    static var dominantColor: UIColor {
        if let cachedColor { return cachedColor }
        let fallback = UIColor(red: 106.0 / 255, green: 115.0 / 255,
                               blue: 66.0 / 255, alpha: 1)
        guard let cgImage = image()?.cgImage else {
            cachedColor = fallback
            return fallback
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(
            data: &pixel, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = UIColor(red: CGFloat(pixel[0]) / 255,
                            green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        cachedColor = color
        return color
    }
}

/// 入场视频：v5 全油画入场动画（Miller 2026-11-19 定版）。
///
/// 口径（2026-11-19 12:04/12:07 定；13:04 挪位修正，3.7 (17) 落地；
/// 16:12 触发口径纠正，3.7 (20) 落地；3.7 (21) 触发点修正）：
/// - 槽位归主页墙进入页：由 HomeWallViewController 在真进墙时
///   触发，以本文件整套横屏 modal 机制呈现；冷启动进 App 的路径
///   就是进墙，效果上冷启仍先见视频，但所有权归墙进入页。
/// - **每次进墙都播**（16:12 Miller 点明原设定，我方 (17)/(18)
///   曾窄化成「每进程只播一次」，已撤销）：动画的用途就是掩盖
///   拉取数据慢——退出重进墙时数据重拉的几秒只剩黑屏即是反例。
///   (20) 把触发挂在 viewDidAppear 每次露面，进歌单退回也重播
///   （Miller：「镶嵌错了」）；(21) 改实例级一次性（audit-3721
///   A2）：HomeWall 实例首露面才触发，同实例子页返回不播——
///   判别依赖「顶层进墙恒新建实例」的当前拓扑。入场自身退场
///   引发的那次墙露面由 Presenter 的一次性抑制标志消费，防
///   自激重播。
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
/// - 尾段叠化（3.7 (22) 立、(23) 直溶重做，DS R49 Q4/Q5）：
///   (22) 的门控只在尾 1.0s 内采样、无迟到兜底，且溶出对象
///   是海报垫（视频→海报→墙两段式）——真机帧差分实证叠化
///   根本没运行（audit-3723 §2a）。(23) 改直溶：入场 VC 改
///   overFullScreen + 透明背景，海报垫只作起播前占位（起播
///   即撤），自然播完路径下视频层 alpha 在最后 1.0s 直接溶
///   到其下的主页墙；门控武装前置条件 = present 前已强制目
///   标墙 layoutIfNeeded 且首帧已提交；就绪检查从剩余
///   ≤1.5s 起每 tick 查，就绪迟到以剩余时长（下限 0.3s）补
///   溶；播完墙未就绪仍循环重播、不进叠化。点关闭保持快速
///   退场、不走叠化。退场全程面包屑（dismiss begin/commit/
///   done、wall firstframe、video alpha）供猎 (22) 遗留的约
///   0.7–1s 黑场。
/// - 方向恢复（3.7 (23)，DS R49 Q6）：(22) 前回竖屏请求只在
///   退场开始发一次、彼时横屏专属入场 VC 仍压顶，退场后零
///   重试——真机横屏卡死约 5s 等设备转动才回正（audit-3723
///   §2b）。改：请求移到 dismiss 完成后发（PortraitRestore），
///   墙 viewDidAppear 再兜底发一次（双触发幂等、0.3s 内去
///   重）；动画结束 0.2s 后校验实际方向、仍横屏重试一次；
///   失败落面包屑（mask/topVC/error），不再只 NSLog。
/// - 双声纪律（3.7 (23)，Miller 19:11 定版 + DS R49 Q7）：
///   进墙时歌曲正在播放 → 入场 player 静音照播、歌曲继续，
///   且入场不调用 AVAudioSession setActive（会话归引擎）；
///   未播放 → 入场照常 setCategory/setActive 放定版音乐。
///   入场期间引擎被远程/锁屏起播 → 立即静音入场（幂等）；
///   teardown 的 setActive(false) 只在本入场激活过会话且引
///   擎未播放时执行。入场永不写 Now Playing（归引擎）。
/// - 海报垫底 + 退场衔接（3.7 (20) 立项、(21) 并行化修正；
///   (23) 起海报垫降为起播前占位、起播即撤，退场衔接改由
///   直溶 + 整面淡出 + 墙面弹簧落位承担，下文 (20)/(21) 编
///   排仅作沿革）：
///   入场 VC 之下、墙之上垫一层油画海报帧（母带 2.0s 帧，
///   Resources/EntryVideo/entry-poster.jpg）。(20) 的退场是全
///   串行分段 + revealHome 固定 delay 0.45s，海报全不透明静止
///   独占约 0.45s（Miller：「停留一下，很突兀」，audit-3721
///   A3）；(21) 改全程并行重叠：退场开始即发旋转请求（在视频
///   +海报双层遮盖下转完）、视频淡出段内海报交叉淡出与墙面
///   1.02→1.00 弹簧落位错峰同跑——海报只作中间层、永不独占
///   画面，固定 delay 归零，总时长 ≤0.6s；点关闭同套并行
///   （按钮淡出并入主段，不再串行前置）。曲线用 iOS 系统
///   减速/弹簧，禁线性硬切。消失后彻底释放 player。
///   保留的安全出口（视频自身问题，非加载）：播放失败立即放行、
///   看门狗（每轮时长 + 2.5s）兜底。
/// - 音频（3.7 (20) 定案修正）：播放期类别用 .playback 与全局
///   统一——(16) 曾刻意定 .ambient（遵静音拨片），是全 App 唯一
///   遵拨片的发声面，拨片静音时画面照播、声音全哑（audit-3720
///   定案，(19) 真机无声即此）。退出时类别本就是 .playback，
///   teardown 只停活通知他人，口径与启动一致。（(23) 起会话
///   的激活/停活按上方双声纪律收紧：引擎在播时入场不激活、
///   teardown 条件停活；类别口径不变。）
/// - 一帧黑屏修复（3.7 (53) 工作流 I，Miller 令「第一帧就
///   是油画、零黑帧」）：(52) 日志 entry show→视频首帧约
///   46ms 全黑，逐层实查定级：①主因＝海报层序失效——veil
///   垫在 window 层、位于呈现出的入场 VC 之下，而 VC 内
///   AVPlayerLayer 未出帧时是不透明黑，海报从未盖住黑窗；
///   ②次因＝veil 在 present 异步回合才创建且海报图惰性解
///   码，墙露面→veil 绘出之间漏黑；③窗口底色纯黑在
///   LaunchScreen→veil 之间兜底露黑。修法：海报预解码
///   （EntryPosterArt）后 present 同步段即垫 veil 并落
///   entry.poster.presented；VC 内播放器层之下再垫同图海
///   报层、播放器层背景改透明；交接改以 AVPlayerLayer
///   .isReadyForDisplay 为准（KVO＋周期兜底），置真落
///   entry.video.readyForDisplay 后 veil 即撤（entry.veil
///   .cleared 保留）、海报层淡出；窗口底色改海报平均主
///   色。入场语义（横屏/关闭键/只认关闭与自然播完/未就绪
///   循环/就绪不提前退场/退场淡出回竖屏）一概未动。
enum EntryIntroPresenter {

    private static var isPresenting = false
    private static var suppressNextPresent = false
    private static weak var current: EntryIntroViewController?

    /// 本次呈现的数据状态快照（3.7 (21)）：present 时由呈现方
    /// （HomeWall）把自家状态闭包交进来、按呈现隔离读取——
    /// (20) 用全局静态登记，后建实例覆盖先建实例，并行加载时
    /// 入场会读到别家的状态（真机 entries 已 ok 却以
    /// data-failed 退场）。无快照时按 failed 答复：宁可退场
    /// 进墙，不许入场无限循环。退场落定后清空。
    private static var activeDataStateProvider: (() -> EntryIntroDataState)?
    static var currentDataState: EntryIntroDataState {
        activeDataStateProvider?() ?? .failed
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

    /// VC 退场落定后回调：清呈现中标志与数据状态快照，允许
    /// 下一次进墙再播。
    static func introDidFinish() {
        isPresenting = false
        current = nil
        activeDataStateProvider = nil
    }

    /// 由主页墙进入页触发：在 presenter 之上呈现入场视频。
    /// 每次真进墙都受理；正在呈现中、资源缺失、窗口未就绪
    /// 不受理。dataState 是呈现方的数据状态闭包，受理时快照
    /// 保存、本轮循环判定只读它（按呈现隔离）。
    @discardableResult
    static func present(from presenter: UIViewController,
                        dataState: @escaping () -> EntryIntroDataState) -> Bool {
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
        activeDataStateProvider = dataState
        // 叠化门控武装前置（3.7 (23)）：present 前先强制目标墙
        // 完成布局——直溶要求视频层之下就是已布局、首帧将就
        // 绪的主页墙，不许溶到一张还没排版的墙上。
        presenter.view.layoutIfNeeded()
        // 海报垫同步就位（3.7 (53) 工作流 I）：原实现把 veil
        // 的创建放进下面 present 的异步回合，且图走
        // UIImage(contentsOfFile:) 惰性解码——墙露面到 veil
        // 真正绘出之间隔着一回合 + 首绘解码，黑墙从这条缝漏
        // 出。改：present 受理即在同步段把预解码海报
        // （EntryPosterArt）垫进 window 并落 entry.poster.
        // presented；VC 的呈现仍走原异步回合，时序语义不变。
        // veil 仍是起播前占位（垫在入场 VC 之下、主页墙之
        // 上），VC 首帧确认后即撤除（见 clearEntryPoster），
        // 退场直溶不经它。不拦截触摸：哪怕残留也不会挡住墙
        // 交互（退场另有兜底移除）。
        let veil = UIImageView(frame: window.bounds)
        veil.backgroundColor = EntryPosterArt.dominantColor
        if let poster = EntryPosterArt.image() {
            veil.image = poster
        } else {
            NSLog("[EntryIntro] entry-poster.jpg missing, veil falls back to poster color")
        }
        veil.contentMode = .scaleAspectFill
        veil.clipsToBounds = true
        veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        veil.isUserInteractionEnabled = false
        window.addSubview(veil)
        Breadcrumbs.log("entry poster presented src=veil")

        // 推迟一帧再呈现，确保 presenter 已进窗口层级
        DispatchQueue.main.async {
            let vc = EntryIntroViewController(url: url)
            vc.exitVeil = veil
            // overFullScreen（3.7 (23) 直溶前提）：呈现方（主页
            // 墙）的 view 在入场全程留在窗口层级里，视频层溶
            // 出时其下直接是墙；fullScreen 会在呈现完成后把墙
            // view 移出层级，直溶无对象可溶。
            vc.modalPresentationStyle = .overFullScreen
            current = vc
            presenter.present(vc, animated: false) {
                // 呈现后再补一次几何请求，双保险把界面转到横屏
                window.windowScene?.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .landscapeRight)
                ) { error in
                    NSLog("[EntryIntro] requestGeometryUpdate landscape failed: \(error.localizedDescription)")
                }
                // 墙首帧提交确认（3.7 (23)）：一笔空事务的完成
                // 回调在墙首帧提交到渲染服务后触发——落面包屑
                // 并武装叠化门控（门控未武装不起叠化，防溶到
                // 未就绪的墙）。
                CATransaction.begin()
                CATransaction.setCompletionBlock {
                    Breadcrumbs.log("entry wall firstframe")
                    vc.armDissolveGate()
                }
                CATransaction.commit()
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
    /// 首帧可显示观察（3.7 (53) 工作流 I）：AVPlayerLayer
    /// .isReadyForDisplay 的 KVO，海报交接的权威触发。
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var watchdog: DispatchWorkItem?
    private var isDismissing = false
    /// 已循环播次计数（面包屑对账用，首轮为 0）。
    private var loopCount = 0
    /// 尾段叠化已起跑（3.7 (22) 立、(23) 直溶）：自然播完路
    /// 径最后 1.0s 的预退场状态；起跑后 dismissIntro 的整面
    /// 淡出段按已叠化合并去重。循环重播前必须复位并恢复画
    /// 面不透明。
    private var dissolveBegan = false
    /// 叠化门控武装（3.7 (23)）：present 完成且目标墙首帧已
    /// 提交后由 Presenter 调用 armDissolveGate 置位；未武装
    /// 时 checkDissolveGate 不起叠化。
    private var dissolveArmed = false
    /// 海报已交接（3.7 (23) 立、(53) 改触发）：首帧渲染确认
    /// （readyForDisplay）后 veil＋VC 内海报层一并交接，只
    /// 执行一次；退场先行时由 dismissIntro 置位封口。
    private var veilCleared = false
    /// 本入场激活过音频会话（3.7 (23) 双声纪律）：引擎播放
    /// 中进墙时入场不碰会话（归引擎），此旗标为假；teardown
    /// 只在旗标为真且引擎未播放时才 setActive(false)。
    private var sessionActivatedByEntry = false
    /// 入场已被静音（引擎在播）：起播判定与在播期间订阅共用，
    /// 幂等——静音后不再回头取消（规格只要求避让）。
    private var mutedForEngine = false
    /// 引擎播放态订阅（3.7 (23)）：入场期间引擎被远程/锁屏
    /// 起播时立即静音入场；teardown 取消。
    private var enginePlaySubscription: AnyCancellable?
    /// 叠化门控的周期观察者（0.1s）：查剩余时长与数据状态。
    private var timeObserver: Any?

    /// 叠化门控武装（Presenter 在墙首帧提交后调用）。
    func armDissolveGate() {
        dissolveArmed = true
    }

    /// VC 内海报层（3.7 (53) 工作流 I）：垫在播放器层之下，
    /// 首帧渲染确认前恒显油画海报，确认后淡出移除。
    private let posterView = UIImageView()
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
        // 透明背景（3.7 (23) 直溶）：视频层溶出/整面淡出时其
        // 下直接是主页墙（overFullScreen 保墙在层级内）；起播
        // 前的空窗由海报垫（window 层、VC 之下）盖住，不靠黑
        // 底。closeButton 等子视图不受影响。
        view.backgroundColor = .clear
        // 海报层（3.7 (53) 工作流 I）：VC 内、播放器层之下的
        // 油画海报——原设计只有 window 层 veil 一张海报，而
        // AVPlayerLayer 未出帧时呈不透明黑、又位于 veil 之
        // 上，海报从未盖住黑窗（(52) 日志 entry show→首帧约
        // 46ms 全黑即此）。海报改垫进 VC 本层：viewDidLoad
        // 同步就位（图已由 Presenter 预解码），播放器层背景
        // 改透明，首帧渲染确认（readyForDisplay）前画面恒为
        // 海报，确认后淡出交接（见 clearEntryPoster）。
        posterView.image = EntryPosterArt.image()
        posterView.backgroundColor = EntryPosterArt.dominantColor
        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.frame = view.bounds
        posterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(posterView)
        playerView.playerLayer.videoGravity = .resizeAspectFill
        playerView.playerLayer.backgroundColor = UIColor.clear.cgColor
        playerView.playerLayer.isOpaque = false
        playerView.backgroundColor = .clear
        playerView.isOpaque = false
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
        posterView.frame = view.bounds
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

        // 首帧渲染确认（3.7 (53) 工作流 I）：AVPlayerLayer
        // .isReadyForDisplay 是「首帧已可显示」的权威信号——
        // 原 veil 撤除挂在周期观察者的 timeControlStatus ==
        // .playing 轮询上，playing 可早于帧真绘出、且轮询有
        // ≤0.1s 迟滞。改 KVO 直达：置真即落 entry.video.
        // readyForDisplay 并交接海报（clearEntryPoster）；周
        // 期观察者保留同信号兜底（防 KVO 漏拍）。
        readyForDisplayObservation = playerView.playerLayer.observe(
            \.isReadyForDisplay, options: [.new]
        ) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.handleVideoReadyForDisplay() }
        }
        if playerView.playerLayer.isReadyForDisplay {
            handleVideoReadyForDisplay()
        }

        // 音频（3.7 (23) 双声纪律，Miller 19:11 定版 + DS
        // R49 Q7）：引擎正在放歌 → 入场静音照播、歌曲继续，
        // 且入场不调用 setCategory/setActive（会话归引擎，
        // 不抢不改）；未放歌 → 入场照常激活会话放定版音乐
        // （.playback 与全局统一、(20) 定案不遵静音拨片）。
        // 入场期间订阅引擎播放态：被远程/锁屏起播时立即静
        // 音入场（幂等，见 muteForEnginePlayback）。
        let engine = PlaybackEngine.shared
        if engine.isPlaying {
            player.isMuted = true
            mutedForEngine = true
            Breadcrumbs.log("entry audio muted reason=engine-playing-at-entry")
        } else {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                sessionActivatedByEntry = true
            } catch {
                NSLog("[EntryIntro] AVAudioSession playback failed: \(error.localizedDescription)")
            }
        }
        enginePlaySubscription = engine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard playing else { return }
                self?.muteForEnginePlayback()
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

        // 尾段叠化门控（3.7 (22) 立、(23) 直溶）：0.1s 周期查
        // 剩余时长与数据状态（见 checkDissolveGate）；同一观
        // 察者兼首帧确认兜底——readyForDisplay 的 KVO 若漏
        // 拍，tick 见其已置真即补交接海报（(53) 前是按
        // timeControlStatus == .playing 撤垫，早于帧绘出）。
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !self.veilCleared, self.playerView.playerLayer.isReadyForDisplay {
                self.handleVideoReadyForDisplay()
            }
            self.checkDissolveGate()
            self.checkLoopDataReadyExit()
        }

        scheduleWatchdog()
        player.play()
    }

    /// 首帧已可显示（3.7 (53) 工作流 I）：readyForDisplay 的
    /// KVO 与周期观察者兜底共用入口，一次性——落
    /// entry.video.readyForDisplay 后交接海报。退场已开始时
    /// 不再触发（防 dismiss 后迟到回调落孤儿面包屑/淡出）。
    private func handleVideoReadyForDisplay() {
        guard !veilCleared, !isDismissing else { return }
        Breadcrumbs.log("entry video readyForDisplay")
        clearEntryPoster()
    }

    /// 海报交接（3.7 (53) 工作流 I）：首帧渲染确认后执行一
    /// 次——window 层 veil 即撤（entry.veil.cleared 沿用既有
    /// 面包屑名），VC 内海报层 0.25s 淡出后移除：此刻播放
    /// 器层已绘出真帧，淡出只是海报→视频的同内容交接（海
    /// 报本就是母带帧），不存在黑窗。曲线 easeOut 与退场段
    /// 同族。
    private func clearEntryPoster() {
        guard !veilCleared else { return }
        veilCleared = true
        exitVeil?.removeFromSuperview()
        exitVeil = nil
        Breadcrumbs.log("entry veil cleared")
        UIView.animate(withDuration: 0.25, delay: 0,
                       options: [.curveEaseOut], animations: {
            self.posterView.alpha = 0
        }, completion: { [weak self] _ in
            self?.posterView.removeFromSuperview()
        })
    }

    /// 引擎在播时静音入场（3.7 (23)，幂等）：起播判定与在播
    /// 订阅共用；只静音入场自己的 player，会话与引擎播放一
    /// 概不碰。已静音/已退场/无 player 时无操作。
    private func muteForEnginePlayback() {
        guard !mutedForEngine, !isDismissing, let player else { return }
        mutedForEngine = true
        player.isMuted = true
        Breadcrumbs.log("entry audio muted reason=engine-started-during-entry")
    }

    /// 尾段叠化门控（3.7 (23) 直溶重做，DS R49 Q4/Q5）：
    /// 前提全齐才起跑——门控已武装（墙首帧就绪）、自然播完
    /// 路径、主页墙数据 .ready。就绪检查从剩余 ≤1.5s 起每
    /// tick 查：剩余 >1.0 时只候命（不提前溶）；进入 ≤1.0s
    /// 且已就绪即起溶，时长 = 剩余时长夹 [0.3, 1.0]——就绪
    /// 在叠化窗内迟到（剩余已不足 1.0）以剩余时长补溶、下
    /// 限 0.3s 防一闪而过。.loading 不起（播完按既有口径循
    /// 环掩盖，下一轮再判）；.failed 不起（退场落墙失败态）。
    /// 溶出对象 = 视频层本身：VC 背景透明、其下即主页墙
    /// （海报垫起播时已撤），溶完画面就是墙本身；旋转回正
    /// 在 dismiss 完成后由 PortraitRestore 处理。
    private func checkDissolveGate() {
        guard dissolveArmed, !isDismissing, !dissolveBegan, let player,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 1.5 else { return }
        let remaining = duration - player.currentTime().seconds
        guard remaining > 0.05, remaining <= 1.5 else { return }
        guard EntryIntroPresenter.currentDataState == .ready else { return }
        guard remaining <= 1.0 else { return }
        dissolveBegan = true
        let dissolveDuration = min(max(remaining, 0.3), 1.0)
        Breadcrumbs.log("entry dissolve begin dur=\(String(format: "%.2f", dissolveDuration)) remaining=\(String(format: "%.2f", remaining))")
        UIView.animate(withDuration: dissolveDuration, delay: 0,
                       options: [.curveEaseInOut], animations: {
            self.playerView.alpha = 0
        })
    }

    /// 循环软化已起跑（3.7 (40)）：见 checkLoopDataReadyExit。
    private var loopExitBegan = false

    /// 循环软化（3.7 (40)，Miller 16:32 拍板）：第一轮
    /// （loopCount == 0）逻辑一字不动——播满、数据就绪也不
    /// 提前退（唯一出口是尾段叠化窗，见 checkDissolveGate）。
    /// 一旦已进入循环（round ≥ 1，是数据迟到才被迫续播掩
    /// 盖），数据就绪即在当前播放点溶出退场，不再把这一轮
    /// 陪播满：溶出与尾段叠化同手法（视频层 alpha → 0、
    /// 0.6s easeInOut），随后走标准 dismissIntro；溶出期间
    /// 数据状态若翻回未就绪（极端竞态），恢复画面并复位旗
    /// 标、按原循环口径继续，不误退场。
    private func checkLoopDataReadyExit() {
        guard loopCount >= 1, !isDismissing, !dissolveBegan, !loopExitBegan
        else { return }
        guard EntryIntroPresenter.currentDataState == .ready else { return }
        loopExitBegan = true
        dissolveBegan = true
        Breadcrumbs.log("entry loop exit reason=data-ready")
        UIView.animate(withDuration: 0.6, delay: 0,
                       options: [.curveEaseInOut], animations: {
            self.playerView.alpha = 0
        }, completion: { [weak self] _ in
            guard let self else { return }
            if EntryIntroPresenter.currentDataState == .ready {
                self.dismissIntro(reason: "data-ready", animated: true)
            } else {
                self.loopExitBegan = false
                self.dissolveBegan = false
                self.playerView.layer.removeAllAnimations()
                self.playerView.alpha = 1
            }
        })
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
            // 叠化已起跑但状态翻回加载（门控后数据状态变化）：
            // 先恢复视频层不透明再循环，不许透着墙重播。
            if dissolveBegan {
                dissolveBegan = false
                playerView.layer.removeAllAnimations()
                playerView.alpha = 1
            }
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
        Breadcrumbs.log("entry dismiss begin reason=\(reason)")
        watchdog?.cancel()
        watchdog = nil
        view.isUserInteractionEnabled = false

        // 先把退出要用的对象都摘出来，动画回调里不依赖 self 存活
        let presenter = presentingViewController
        // 海报垫若还在（起播未确认就退场，如播放失败）：直接
        // 撤除——(23) 起它只是起播前占位，不参与退场衔接。
        // (53) 补：置 veilCleared 封住 readyForDisplay 迟到交
        // 接，防退场后海报淡出/面包屑孤儿触发。
        veilCleared = true
        exitVeil?.removeFromSuperview()
        exitVeil = nil
        // 本次退场引发的墙露面不重播入场（同一次进墙事件）。
        EntryIntroPresenter.suppressNext()

        // 退场收尾（两路共用）：拆播放器 → 提交 dismiss → 落
        // done 面包屑 → 方向恢复（(23)：请求移到 dismiss 完
        // 成后发，彼时横屏专属的本 VC 已离顶层，请求可被受
        // 理；墙 viewDidAppear 另有兜底同路）→ 墙帧提交确认。
        let finishDismiss = {
            Breadcrumbs.log("entry transition commit reason=\(reason)")
            if let presenter {
                presenter.dismiss(animated: false) {
                    Breadcrumbs.log("entry dismiss done reason=\(reason)")
                    EntryIntroPresenter.introDidFinish()
                    PortraitRestore.requestIfLandscape(from: presenter, source: "dismiss-done")
                    CATransaction.begin()
                    CATransaction.setCompletionBlock {
                        Breadcrumbs.log("entry wall frame presented")
                    }
                    CATransaction.commit()
                }
            } else {
                Breadcrumbs.log("entry dismiss done reason=\(reason)")
                EntryIntroPresenter.introDidFinish()
            }
        }

        guard animated else {
            // 播放失败：立即放行，不等转场
            teardownPlayer()
            finishDismiss()
            return
        }

        // 退场衔接（3.7 (23) 直溶版）：整面淡出直接落到主页墙
        // （VC 透明背景 + overFullScreen，墙全程在层级内），
        // 墙面弹簧落位同段并行（自 (21) 沿用：1.02 蓄势 →
        // 弹簧回 1.00）；总时长 ≤0.6s 不变。尾段叠化已起跑
        // 时视频层已溶尽，本段只清关闭按钮与整面残余，时长
        // 压到 0.15（合并去重，不重新引入任何中间层独占）。
        // 旋转回正不在本段发请求——见 finishDismiss 的 (23)
        // 时机修正。
        let fast = reason == "closed"
        let fadeDuration = fast ? 0.3 : (dissolveBegan ? 0.15 : 0.4)
        Breadcrumbs.log("entry video alpha fade dur=\(String(format: "%.2f", fadeDuration)) dissolve=\(dissolveBegan)")
        if fast {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: {
                self.closeButton.alpha = 0
            })
        }
        Self.beginWallSettle(wallView: presenter?.view, fast: fast)
        UIView.animate(withDuration: fadeDuration, delay: 0, options: [.curveEaseOut], animations: {
            self.view.alpha = 0
        }, completion: { [weak self] _ in
            self?.teardownPlayer()
            finishDismiss()
        })
    }

    /// 墙面落位（3.7 (21) 沿用、(23) 去海报段）：退场开始即调
    /// 用——墙面先置 1.02 蓄势，整面淡出段内弹簧落位回
    /// 1.00，给「溶回主页」一个落点感；无海报中介层。
    private static func beginWallSettle(wallView: UIView?, fast: Bool) {
        guard let wallView else { return }
        wallView.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        UIView.animate(withDuration: fast ? 0.4 : 0.45, delay: fast ? 0.1 : 0.15,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction], animations: {
            wallView.transform = .identity
        })
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = nil
        failObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        enginePlaySubscription?.cancel()
        enginePlaySubscription = nil
        playerView.playerLayer.player = nil
        player = nil

        // 音频会话收尾（3.7 (23) 双声纪律）：只在本入场亲手
        // 激活过会话、且引擎当前未播放时才停活通知他人——
        // 引擎在播时会话归引擎，入场停活会误伤正在放的歌
        // （(22) 前无条件停活的隐患，audit-3723 §2c 附带项）。
        // 类别在播放期已定为 .playback，不改写。
        guard sessionActivatedByEntry, !PlaybackEngine.shared.isPlaying else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            NSLog("[EntryIntro] AVAudioSession deactivate failed: \(error.localizedDescription)")
        }
    }
}

/// 方向恢复（3.7 (23)，DS R49 Q6）：入场退场后把界面送回
/// 竖屏。修 (22) 前的卡死机制（audit-3723 §2b）：回竖屏请
/// 求只在退场开始发一次、彼时横屏专属的入场 VC 仍压顶层，
/// 请求落空后全 App 零重试，墙又是全向掩码，系统永不主动
/// 回正，只能等设备物理转动。本类口径：
/// - 只在当前确实横屏时发请求（竖屏时无操作，天然幂等）；
///   调用点两处——入场 dismiss 完成（EntryIntro）与墙
///   viewDidAppear 兜底（HomeWall），双触发以 0.3s 去重窗
///   合并为一次。
/// - 发后 0.2s（转场动画量级）校验实际方向：仍横屏重试一
///   次；最终结果落面包屑，失败时带顶层 VC 的 supported
///   mask 与 error，不再只 NSLog 无从对账。
enum PortraitRestore {

    private static var lastRequestAt: CFTimeInterval = 0

    static func requestIfLandscape(from vc: UIViewController, source: String) {
        guard let scene = vc.view.window?.windowScene else { return }
        guard scene.interfaceOrientation.isLandscape else { return }
        let now = CACurrentMediaTime()
        guard now - lastRequestAt > 0.3 else { return }
        lastRequestAt = now
        attempt(scene: scene, source: source, tryCount: 1)
    }

    private static func attempt(scene: UIWindowScene, source: String, tryCount: Int) {
        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: .portrait)
        ) { error in
            // errorHandler 只在失败时回调，error 为非 Optional。
            Breadcrumbs.log("entry rotate portrait error source=\(source) attempt=\(tryCount) \(failureContext(scene: scene)) error=\(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if scene.interfaceOrientation.isLandscape {
                if tryCount < 2 {
                    PortraitRestore.attempt(scene: scene, source: source, tryCount: tryCount + 1)
                } else {
                    Breadcrumbs.log("entry rotate portrait failed source=\(source) \(failureContext(scene: scene))")
                }
            } else {
                Breadcrumbs.log("entry rotate portrait ok source=\(source) attempt=\(tryCount)")
            }
        }
    }

    /// 失败上下文：顶层 VC 名 + 其 supportedInterfaceOrientations
    /// 原始值（谁在挡竖屏一眼可辨）。
    private static func failureContext(scene: UIWindowScene) -> String {
        var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        let name = top.map { String(describing: type(of: $0)) } ?? "none"
        let mask = top?.supportedInterfaceOrientations.rawValue ?? 0
        return "top=\(name) mask=\(mask)"
    }
}
