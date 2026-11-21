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
    private static var cachedFirstFrame: UIImage?
    private static var cachedColor: UIColor?

    /// 强制解码：把图绘进 scale=1 位图上下文完成解压缩，
    /// 之后绘制零等待（默认按设备 scale 解码会放大数倍）。
    private static func decoded(_ raw: UIImage) -> UIImage {
        let size = raw.size
        guard size.width > 0, size.height > 0 else { return raw }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 预解码后的海报图（1280×720，母带 2.0s 帧）：首次调用
    /// 同步解码并缓存，之后命中缓存。资源缺失返回 nil（调
    /// 用方以主色兜底）。
    static func image() -> UIImage? {
        if let cachedImage { return cachedImage }
        guard let path = Bundle.main.path(forResource: "entry-poster",
                                          ofType: "jpg",
                                          inDirectory: "EntryVideo"),
              let raw = UIImage(contentsOfFile: path) else { return nil }
        let decodedImage = decoded(raw)
        cachedImage = decodedImage
        return decodedImage
    }

    /// 视频首帧图（3.7 (54) 工作流 O）：entry-firstframe.jpg
    /// 是 faststart 产物 time=0 首帧的提取帧。离线逐像素比
    /// 对实锤：现有海报 entry-poster.jpg 是母带 2.0s 帧（与
    /// 2.0s 提取帧 64×36 缩图 RMSE 0.47、平均色逐位相同），
    /// 与首帧不是同一图（RMSE 80.1）——VC 内垫底用海报时，
    /// 首帧交接瞬间画面内容跳一帧，是「卡帧」观感的来源之
    /// 一。VC 内垫底改用本图，与视频第一帧像素级同图、交
    /// 接无跳变；window 层 veil 与 LaunchScreen 仍用海报
    /// （不在本条范围）。资源缺失返回 nil，调用方回退海报。
    static func firstFrameImage() -> UIImage? {
        if let cachedFirstFrame { return cachedFirstFrame }
        guard let path = Bundle.main.path(forResource: "entry-firstframe",
                                          ofType: "jpg",
                                          inDirectory: "EntryVideo"),
              let raw = UIImage(contentsOfFile: path) else { return nil }
        let decodedImage = decoded(raw)
        cachedFirstFrame = decodedImage
        return decodedImage
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
/// - 卡帧修复（3.7 (54) 工作流 O，Miller 01:26 录屏点名
///   「点进去视频要立刻播放、不许有卡帧」）：(53) 后黑帧已
///   除，但播放器在呈现后才装配/加载，海报静帧停留被感知
///   为卡帧。三管齐下：①视频资源换 faststart 版（moov 前
///   置，流拷贝重排、与母带逐流 framemd5 一致，见
///   EntryPlayerPreheat 与 project.yml 注释）；②播放器预
///   热——SceneDelegate 建窗阶段先建好 player/item 异步加
///   载至可播并 preroll，VC 呈现时接管同一实例直接 play；
///   退场后 player 泊回预热仓 seek 回零，第二次进墙即时再
///   播（「每次进墙都播」语义不变）；预热失败/未就绪静默
///   回退 VC 现装配路径；③VC 内垫底图换视频首帧同图
///   （EntryPosterArt.firstFrameImage），交接像素级无跳
///   变。新增面包屑 entry playback firstframe（rate>0 且
///   首帧已可显示的首个时刻），与 entry poster presented
///   / entry video readyForDisplay 同为 Breadcrumbs 写行时
///   的 ISO8601 时钟、三点间隔可直接对账。
/// - 丝滑化（3.7 (57) 工作流 A，Miller (55) 录屏逐帧实测）：
///   录屏 t=1.933s 单帧（YAVG 48.2、邻帧 91.8/91.2）经抽帧
///   复核不是「同画面变暗」，是播放器内容以横屏帧条出现在
///   画面上部、下部约 55% 纯黑的几何瞬变帧；faststart 母带
///   同时段亮度连续（0–3s 最低 97.4）、无此帧。已证实的结
///   构缺口：(53) 交接在首帧确认即把 veil 与 VC 内海报层双
///   双摘除，播放器层 isOpaque=false＋clear 背景，此后整段
///   播放期层下无任何不透明垫底——几何/合成任一帧间隙都直
///   接露黑/露墙。修法三件：①横屏几何请求提前到 present
///   之前发出（veil 已同步垫窗、旋转在油画遮盖下先行），
///   播放期不再叠几何变更，present 完成后的原请求保留作双
///   保险；②海报层交接后不摘除，降为整段播放期的垫底（位
///   于播放器层之下、帧恒满 view.bounds），叠化/循环溶出
///   时与视频层同段淡出、不作中间层独占；③首帧确认后播
///   放器层翻为 isOpaque＋海报主色背景，单帧内容冲刷只露
///   油画色。退场侧：(23) 的串行时序（淡出→dismiss→才发
///   竖屏请求→系统旋转）使墙以横屏布局静止示人约 0.8s 后
///   猛地正过来（录屏 9.17–9.97s 亮度恒 75.1、转正仅约
///   0.13s），违反「淡出遮住旋转」定版——改：退场开始即
///   动态解锁本 VC 方向（exitOrientationUnlocked＋
///   setNeedsUpdateOfSupportedInterfaceOrientations，iOS
///   17 目标可用）并同刻发竖屏请求，旋转与整面淡出并行、
///   在油画覆盖下完成；dismiss 完成后的原请求保留作兜底，
///   PortraitRestore 加在飞守卫防双请求打断旋转动画；需
///   旋转时跳过墙面 1.02 落位变换（防变换与旋转冲突）。
///   新增面包屑：entry rotate landscape request /
///   entry rotate transition begin / entry rotate landed /
///   entry rotate unlock / entry rotate portrait request /
///   entry rotate portrait landed / entry poster handoff /
///   entry poster removed，与录屏时间轴逐点对账。
/// - 开场黑场淡入（3.7 (59) 工作流二，Miller (58) 真机点名
///   后按其原话定版：「点进去你可以黑，但是黑一下之后画
///   面慢慢淡入进来，这样显得丝滑」）：(58) 前的开场是海
///   画先行——window 层 veil 是海报图、VC 内垫首帧图，点开
///   先闪一帧油画画面再进视频，且旋转落地瞬间（录屏
///   1.63–1.77s）有约 130ms 停顿＋一记跳变。改：点开后第
///   一帧就是纯黑（window 垫与 VC 底同为黑、海报层与视频
///   层 alpha 皆 0），几何请求维持 (58) 单发＋看门狗、旋
///   转全程在黑场之下完成；横屏真实落地（landed 凭据，
///   起播门的 timeout-300ms 兜底只放播放、不放淡入——
///   (58) 日志实锤其先播竖屏约 0.19s 即录屏一顿）且首帧
///   已可显示后，视频层以 1.0s curveEaseOut（iOS 系统缓
///   动、非线性匀速）从黑场淡入，期间视频已在播（起播门
///   放行时即从第 0 帧 play、边播边淡入），淡入中无亮度
///   跳变。海报垫底随之改制：开场不再抢第一帧，仅
///   在淡入完成时恢复为播放期垫底（(57) 防线不变）；退场
///   沿用 (58)（等墙的 portrait landed、0.6s 上限、淡出盖
///   住），开/退场视觉语言一致（都经黑/淡过渡）。新增面
///   包屑 entry fadein begin / entry fadein done dur=1.0；
///   母带每 5 帧垫一帧是源文件自带（25fps 凑 30fps，主聊
///   天实测 60/299），播放器侧无解、不在本包范围。

/// 入场播放器预热仓（3.7 (54) 工作流 O）：所有权与生命
/// 周期——本枚举静态持有预热的 AVPlayer/AVPlayerItem；
/// SceneDelegate 建窗时 warmUp() 建仓（全程异步加载，不
/// 阻塞建窗；资源缺失/加载失败静默弃仓，VC 回退现装配）；
/// EntryIntroViewController 起播时 take() 接管同一实例
/// （所有权移交 VC，仓清空）；VC teardown 时 park() 泊
/// 回（pause + seek 回零 + 复位静音），仓重新持有待下次
/// take。仓内 item 只有 .readyToPlay 才可被 take，未就
/// 绪一律回退现装配路径，不许等它。
enum EntryPlayerPreheat {

    private static var player: AVPlayer?
    private static var item: AVPlayerItem?
    private static var statusObservation: NSKeyValueObservation?
    private static var isReady = false
    /// VC 已接管在用：warmUp 不重复建仓、take 不二次移交。
    private static var inUse = false

    /// 建仓预热（SceneDelegate 建窗阶段调用，主线程）：建
    /// player/item 后即返回，加载走 AVFoundation 异步通
    /// 道；preferredForwardBufferDuration=2——10s 本地短片
    /// 预缓冲 2s 足够起播即满帧，后段在本机文件读取下瞬
    /// 时补齐；automaticallyWaitsToMinimizeStalling=false
    /// ——素材是 Bundle 本地文件、无网络卡顿源，等待最小
    /// 化卡顿的逻辑只会平添起播延迟，与「立刻播放」目标
    /// 相悖。readyToPlay 后 preroll 把首段解码也预做完。
    static func warmUp() {
        guard player == nil, !inUse else { return }
        guard let url = EntryIntroPresenter.videoURL else {
            NSLog("[EntryIntro] preheat skipped: entry video missing from bundle")
            return
        }
        let asset = AVURLAsset(url: url)
        let newItem = AVPlayerItem(asset: asset)
        newItem.preferredForwardBufferDuration = 2
        let newPlayer = AVPlayer(playerItem: newItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = .pause
        item = newItem
        player = newPlayer
        isReady = false
        Breadcrumbs.log("entry preheat begin")
        statusObservation = newItem.observe(\.status, options: [.new]) { observedItem, _ in
            DispatchQueue.main.async {
                switch observedItem.status {
                case .readyToPlay:
                    isReady = true
                    newPlayer.preroll(atRate: 1) { _ in }
                    Breadcrumbs.log("entry preheat ready")
                case .failed:
                    NSLog("[EntryIntro] preheat item failed: \(observedItem.error?.localizedDescription ?? "?")")
                    Breadcrumbs.log("entry preheat failed")
                    discard()
                default:
                    break
                }
            }
        }
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}
    }

    /// VC 接管预热实例：仅仓内 item 已 .readyToPlay 时移
    /// 交（所有权归 VC、仓清空并置 inUse）；未就绪/失败/
    /// 空仓返回 nil，VC 走现装配路径，不等预热。
    static func take() -> (player: AVPlayer, item: AVPlayerItem)? {
        guard let player, let item, isReady,
              item.status == .readyToPlay else { return nil }
        statusObservation?.invalidate()
        statusObservation = nil
        self.player = nil
        self.item = nil
        isReady = false
        inUse = true
        return (player, item)
    }

    /// VC 退场泊回：pause + seek 回零 + 复位静音，仓重新
    /// 持有；下次进墙 take 时 seek 已归零、可即时再播。
    /// item 状态以泊回时实查为准（播过的 item 仍
    /// .readyToPlay），不达标则弃仓、下次 warmUp 重建。
    static func park(player parkedPlayer: AVPlayer, item parkedItem: AVPlayerItem) {
        inUse = false
        parkedPlayer.pause()
        parkedPlayer.isMuted = false
        guard parkedItem.status == .readyToPlay else {
            Breadcrumbs.log("entry preheat discard reason=item-not-ready")
            return
        }
        player = parkedPlayer
        item = parkedItem
        isReady = true
        parkedPlayer.seek(to: .zero)
        Breadcrumbs.log("entry preheat parked")
    }

    /// 预热失败弃仓：清持有待下次 warmUp 重建；VC 侧从未
    /// 依赖仓，弃仓对呈现零影响。
    private static func discard() {
        statusObservation?.invalidate()
        statusObservation = nil
        player = nil
        item = nil
        isReady = false
    }
}

enum EntryIntroPresenter {

    /// 入场视频资源（3.7 (54) 工作流 O 起为 faststart 版：
    /// moov 前置的流拷贝重排产物，与母带逐流 framemd5 一
    /// 致；原 entry-v5.mp4 保留在同目录、不再被加载）。
    /// Presenter 的缺失守卫与预热仓共用同一出处。
    static var videoURL: URL? {
        Bundle.main.url(forResource: "entry-v5-faststart",
                        withExtension: "mp4",
                        subdirectory: "EntryVideo")
    }

    private static var isPresenting = false
    private static var suppressNextPresent = false
    private static weak var current: EntryIntroViewController?

    /// 几何请求单发看门狗（3.7 (58) 定稿②）：(57) 的双发请求
    /// （present 前＋present 后）在日志里与系统纠正轮叠成开场
    /// 1.4s 两轮旋转。(58) 收敛为单一发点（present 前）＋看门
    /// 狗：第一发后 200ms 未见任何 rotate transition begin，
    /// 才补发一次（封顶一次，src=watchdog-retry）；补后仍无
    /// 则不再发——由 VC 的起播门 300ms 超时放行 play 收口，
    /// 不许看门狗自己变成第二套双保险。
    private static var rotateTransitionBegan = false
    private static var rotateWatchdog: DispatchWorkItem?

    /// VC 的 viewWillTransition 起跑时调：本次呈现已见旋转
    /// 过渡开始，看门狗作废。
    static func noteRotateTransitionBegan() {
        rotateTransitionBegan = true
        rotateWatchdog?.cancel()
        rotateWatchdog = nil
    }

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
        rotateWatchdog?.cancel()
        rotateWatchdog = nil
        rotateTransitionBegan = false
    }

    /// 由主页墙进入页触发：在 presenter 之上呈现入场视频。
    /// 每次真进墙都受理；正在呈现中、资源缺失、窗口未就绪
    /// 不受理。dataState 是呈现方的数据状态闭包，受理时快照
    /// 保存、本轮循环判定只读它（按呈现隔离）。
    @discardableResult
    static func present(from presenter: UIViewController,
                        dataState: @escaping () -> EntryIntroDataState) -> Bool {
        guard !isPresenting else { return false }
        guard let url = videoURL else {
            // 资源缺失：静默放行，绝不因入场面挡住主页墙
            NSLog("[EntryIntro] entry-v5-faststart.mp4 missing from bundle, skip")
            return false
        }
        guard let window = presenter.view.window else { return false }
        isPresenting = true
        activeDataStateProvider = dataState
        rotateTransitionBegan = false
        rotateWatchdog?.cancel()
        rotateWatchdog = nil
        // 叠化门控武装前置（3.7 (23)）：present 前先强制目标墙
        // 完成布局——直溶要求视频层之下就是已布局、首帧将就
        // 绪的主页墙，不许溶到一张还没排版的墙上。
        presenter.view.layoutIfNeeded()
        // 黑场垫同步就位（3.7 (53) 工作流 I 立同步垫制、
        // (59) 工作流二改黑）：present 受理即在同步段把垫层
        // 放进 window 并落 entry.poster.presented（面包屑名
        // 沿用、日志口径连续），VC 的呈现仍走原异步回合，
        // 时序语义不变。(53)/(57) 时代 veil 是海报图——点开
        // 先闪一帧油画再进视频，正是 (59) 点名要除的闪屏；
        // 按 Miller 原话规格改纯黑垫：黑场即入场第一帧，VC
        // 呈现后由其自身黑底接管（见 VC viewDidLoad），旋
        // 转在黑下完成、视频就绪后 1.0s 淡入（见 VC
        // beginOpeningFadeIfReady，彼时撤垫）。不拦截触摸：
        // 哪怕残留也不会挡住墙交互（退场另有兜底移除）。
        let veil = UIView(frame: window.bounds)
        veil.backgroundColor = .black
        veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        veil.isUserInteractionEnabled = false
        window.addSubview(veil)
        Breadcrumbs.log("entry poster presented src=veil")

        // 推迟一帧再呈现，确保 presenter 已进窗口层级
        DispatchQueue.main.async {
            // 横屏几何请求（3.7 (57) 工作流 A 提前到 present
            // 之前发、(58) 定稿②收敛为单一发点）：(57) 在
            // present 前后各发一发（双保险），日志实证与系统
            // 纠正轮叠成开场两轮旋转、首帧落在翻转中间。(58)
            // 只发这一发：此刻顶层是全向掩码的主页墙、请求可
            // 被受理，且 window 已同步垫好 veil（(59) 起为不
            // 透明黑场），旋转全程在黑场遮盖下进行。发送后武装
            // 200ms 看门狗：未见任何 rotate transition begin
            // 才补发一次（封顶，src=watchdog-retry）；补后仍
            // 无则不再发，由 VC 起播门超时放行收口。落地时刻
            // 由 VC 的 viewWillTransition 完成回调落 entry
            // rotate landed，与录屏时间轴对账。
            Breadcrumbs.log("entry rotate landscape request src=pre-present")
            window.windowScene?.requestGeometryUpdate(
                .iOS(interfaceOrientations: .landscapeRight)
            ) { error in
                NSLog("[EntryIntro] requestGeometryUpdate landscape (pre-present) failed: \(error.localizedDescription)")
            }
            let watchdog = DispatchWorkItem {
                guard isPresenting, !rotateTransitionBegan else { return }
                guard window.windowScene?.interfaceOrientation != .landscapeRight
                else { return }
                Breadcrumbs.log("entry rotate landscape request src=watchdog-retry")
                window.windowScene?.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .landscapeRight)
                ) { error in
                    NSLog("[EntryIntro] requestGeometryUpdate landscape (watchdog-retry) failed: \(error.localizedDescription)")
                }
            }
            rotateWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: watchdog)
            let vc = EntryIntroViewController(url: url)
            vc.exitVeil = veil
            // overFullScreen（3.7 (23) 直溶前提）：呈现方（主页
            // 墙）的 view 在入场全程留在窗口层级里，视频层溶
            // 出时其下直接是墙；fullScreen 会在呈现完成后把墙
            // view 移出层级，直溶无对象可溶。
            vc.modalPresentationStyle = .overFullScreen
            current = vc
            presenter.present(vc, animated: false) {
                // 墙首帧提交确认（3.7 (23)）：一笔空事务的完成
                // 回调在墙首帧提交到渲染服务后触发——落面包屑
                // 并武装叠化门控（门控未武装不起叠化，防溶到
                // 未就绪的墙）。（(58)：原在此处的第二发几何请
                // 求已删，见上方单发点注释。）
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
    /// 本次播放用的是预热实例（3.7 (54) 工作流 O）：退场
    /// teardown 时泊回预热仓复用，不直接弃置。
    private var usesPreheatedPlayer = false
    /// 首帧真播时刻已落面包屑（3.7 (54) 工作流 O）：entry
    /// playback firstframe 每呈现只落一次。
    private var firstFrameLogged = false
    private var timeControlObservation: NSKeyValueObservation?
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
    /// 首帧已可显示（3.7 (59) 工作流二）：readyForDisplay
    /// 确认后置位，是开场淡入的双条件之一（另一为起播门放
    /// 行）；只置一次，退场后迟到回调由 isDismissing 封口。
    private var videoReady = false
    /// 开场淡入已起跑/已完成（3.7 (59) 工作流二）：起跑后
    /// 不许重入；完成时海报垫底恢复、view 底色回透明。
    private var openingFadeBegan = false
    private var openingFadeDone = false
    /// 淡入的横屏落地凭据（3.7 (59) 硬要求，(58) 桥日志定
    /// 案）：与起播门分开记账——(58) 实测起播门被
    /// timeout-300ms 兜底放行（35.051）、firstframe 落在竖
    /// 屏几何（35.053），横屏 landed 迟至 35.245，视频在竖
    /// 屏下先播约 0.19s 再转横，即录屏「切横屏卡一顿」。
    /// 故：超时兜底只许放行播放（保时间轴/音频），不许放
    /// 行淡入；本凭据只在真实横屏落地（landed）或开场即横
    /// 屏（already-landscape）时置位，淡入凭它起跑、日志
    /// 注明 gate=<来源>。
    private var fadeGateSource: String?
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

    /// VC 内海报层（3.7 (53) 工作流 I 立、(59) 改制）：垫
    /// 在播放器层之下；(59) 前是开场占位（首帧确认前恒显
    /// 油画、确认后交接），(59) 起开场让位黑场淡入，本层初
    /// 始 alpha=0、仅在淡入完成时恢复为播放期垫底。
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

    /// 退场方向解锁（3.7 (57) 工作流 A）：播放期恒横屏专属
    /// （与原写死 .landscape 一致）；退场开始置位后改全向
    /// （与 Info.plist 应用掩码同集），配合
    /// setNeedsUpdateOfSupportedInterfaceOrientations 让竖屏
    /// 请求在 VC 仍压顶时即可被受理、旋转与淡出并行（见
    /// dismissIntro）。置位只发生在 isDismissing 已封口的退
    /// 场路径上，无回滚场景。
    private var exitOrientationUnlocked = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        exitOrientationUnlocked
            ? [.portrait, .landscapeLeft, .landscapeRight]
            : .landscape
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }

    /// 几何变更对账（3.7 (57) 工作流 A）：本 VC 在场期间的
    /// 每次界面旋转（进场转横屏、退场解锁后转竖屏）都经此
    /// 回调——起跑落 entry rotate transition begin（带目标
    /// 尺寸），协调器完成落 entry rotate landed（带落地后
    /// 场景实际方向）。与 entry rotate landscape request /
    /// entry rotate portrait request 的发出时刻三点对账，
    /// 即可判定旋转落在起播前、播放中还是退场段（(55) 录
    /// 屏暗闪帧定级所缺的正是这组时刻）。
    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // (58)：通知 Presenter 已见旋转过渡开始（单发看门狗
        // 作废）；落地后由下方完成回调放行起播门。
        EntryIntroPresenter.noteRotateTransitionBegan()
        Breadcrumbs.log("entry rotate transition begin size=\(Int(size.width))x\(Int(size.height))")
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            // 横屏落地放行起播门（3.7 (58) 定稿②）：首帧不再
            // 落在翻转中间；竖屏落地（退场轮）不放行。
            if self.view.window?.windowScene?.interfaceOrientation.isLandscape == true {
                // 淡入 landed 凭据（(59) 硬要求）：起播门若已
                // 被 timeout-300ms 兜底放行，releasePlaybackGate
                // 会直接返回——凭据与淡入合流须在此独立补记，
                // 迟到的横屏落地照样能起跑淡入（黑场等它）。
                if self.fadeGateSource == nil { self.fadeGateSource = "landed" }
                self.releasePlaybackGate(reason: "landed")
                self.beginOpeningFadeIfReady()
            }
            let orientation = self.view.window?.windowScene?.interfaceOrientation
            let name: String
            switch orientation {
            case .portrait: name = "portrait"
            case .portraitUpsideDown: name = "portraitUpsideDown"
            case .landscapeLeft: name = "landscapeLeft"
            case .landscapeRight: name = "landscapeRight"
            default: name = "unknown"
            }
            Breadcrumbs.log("entry rotate landed orient=\(name)")
        }
    }

    /// 退场方向解锁（3.7 (57) 工作流 A，dismissIntro 调用）：
    /// 置旗标后通知系统重估本 VC 的方向掩码（iOS 16+ API，
    /// 本工程目标 iOS 17 可用）。幂等：重复调用无操作。
    private func unlockOrientationsForExit() {
        guard !exitOrientationUnlocked else { return }
        exitOrientationUnlocked = true
        setNeedsUpdateOfSupportedInterfaceOrientations()
        Breadcrumbs.log("entry rotate unlock")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 黑底开场（3.7 (59) 工作流二）：viewDidLoad 同步即
        // 黑——黑场就是入场第一帧，其下 window 黑垫（
        // Presenter）与本底同色无缝；旋转在黑下完成，视频
        // 就绪后淡入（beginOpeningFadeIfReady）。淡入完成时
        // 本底改回 .clear，复原 (23) 直溶退场前提（视频层
        // 溶出/整面淡出时其下直接是主页墙，overFullScreen
        // 保墙在层级内）。closeButton 等子视图不受影响。
        view.backgroundColor = .black
        // 海报层（3.7 (53) 工作流 I 立、(59) 改制）：仍垫在
        // 播放器层之下、图仍用视频首帧同图（(54) 工作流
        // O），但开场不再抢第一帧——初始 alpha=0，只在开场
        // 淡入完成时恢复 alpha=1 降为播放期垫底（(57) 防
        // 线：播放器层间隙帧露油画不露黑，口径不变）。
        posterView.image = EntryPosterArt.firstFrameImage() ?? EntryPosterArt.image()
        // (61) 第 2 条：底色改纯黑（原 dominantColor 橄榄绿
        // #6A7342 在图缺位/未铺满时即平绿画布）——垫底只认海
        // 报图本体，图外一律黑，与 (59) 黑场第一帧同口径。
        posterView.backgroundColor = .black
        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.frame = view.bounds
        posterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        posterView.alpha = 0
        view.addSubview(posterView)
        playerView.playerLayer.videoGravity = .resizeAspectFill
        playerView.playerLayer.backgroundColor = UIColor.clear.cgColor
        playerView.playerLayer.isOpaque = false
        playerView.backgroundColor = .clear
        playerView.isOpaque = false
        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 视频层初始 alpha=0：自黑场淡入（1.0s，见
        // beginOpeningFadeIfReady），起播门放行前恒黑。
        playerView.alpha = 0
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
        // (58) 掉帧探针自呈现起跑、teardown 时汇总落日志。
        startFrameProbe()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        posterView.frame = view.bounds
        playerView.frame = view.bounds
    }

    // MARK: - 播放

    private func startPlayback() {
        Breadcrumbs.log("entry show")
        // 播放器来源（3.7 (54) 工作流 O）：优先接管预热仓
        // 已加载至可播的同一实例、呈现即 play；预热未就绪/
        // 失败时回退现装配（原路径一字未改）。接管时 item
        // 已 seek 归零（建仓起点/泊回时归零），起播点恒为 0。
        let item: AVPlayerItem
        let player: AVPlayer
        if let preheated = EntryPlayerPreheat.take() {
            item = preheated.item
            player = preheated.player
            usesPreheatedPlayer = true
            Breadcrumbs.log("entry preheat reused")
        } else {
            item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
        }
        player.actionAtItemEnd = .pause
        // 本地短片不起播等待（口径与预热仓一致，见 warmUp）。
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        playerView.playerLayer.player = player

        // 首帧真播时刻（3.7 (54) 工作流 O）：timeControlStatus
        // 转 .playing 的 KVO 为主触发，noteFirstFrameIfNeeded
        // 另要求 rate>0 且首帧已可显示，三者齐备才落 entry
        // playback firstframe；周期观察者同口径兜底（见下）。
        timeControlObservation = player.observe(
            \.timeControlStatus, options: [.new]
        ) { [weak self] observedPlayer, _ in
            guard observedPlayer.timeControlStatus == .playing else { return }
            DispatchQueue.main.async { self?.noteFirstFrameIfNeeded() }
        }

        // 首帧渲染确认（3.7 (53) 工作流 I）：AVPlayerLayer
        // .isReadyForDisplay 是「首帧已可显示」的权威信号——
        // 原 veil 撤除挂在周期观察者的 timeControlStatus ==
        // .playing 轮询上，playing 可早于帧真绘出、且轮询有
        // ≤0.1s 迟滞。改 KVO 直达：置真即落 entry.video.
        // readyForDisplay 并尝试起跑开场淡入（(59)：与起播
        // 门放行双条件合流，见 beginOpeningFadeIfReady）；
        // 周期观察者保留同信号兜底（防 KVO 漏拍）。
        readyForDisplayObservation = playerView.playerLayer.observe(
            \.isReadyForDisplay, options: [.new]
        ) { [weak self] layer, _ in
            if layer.isReadyForDisplay {
                DispatchQueue.main.async { self?.handleVideoReadyForDisplay() }
            } else {
                // (61) 第 2 条判别面包屑：readyForDisplay 跌落
                // （解码迟滞/帧缺位）逐次落 entry gap 行，与循
                // 环 seek 的 gap 行同窗对账绿窗来源。
                DispatchQueue.main.async { self?.noteEntryGapStallIfNeeded() }
            }
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
            // 预热复用实例的静音态显式复位（泊回已复位，此为
            // 起播侧双保险）：本入场未因引擎静音就不许哑播。
            player.isMuted = false
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
            // (58) 掉帧量测：本观察者是嫌疑#1，逐 tick 耗时经
            // EntryCallbackTimings 登记最大值，teardown 汇总
            // 进 entry framedrops summary 的 top3 caller。
            EntryCallbackTimings.measure("entry.timeObserver") {
                if !self.videoReady, self.playerView.playerLayer.isReadyForDisplay {
                    self.handleVideoReadyForDisplay()
                }
                self.noteFirstFrameIfNeeded()
                self.checkDissolveGate()
                self.checkLoopDataReadyExit()
            }
        }

        armPlaybackGate()
    }

    // MARK: - 起播门与掉帧量测（3.7 (58) 定稿②）

    /// 起播门：play 推迟到横屏旋转 landed 之后——(57) 日志
    /// 实证 firstframe 落在翻转中间、播放期叠几何变更正是
    /// 周期掉帧的竞速候选。放行三路：已横屏（already-
    /// landscape）／旋转落地（landed，viewWillTransition 完
    /// 成回调）／300ms 超时（timeout-300ms，请求被系统吞掉
    /// 时不许挂死海报）。放行点落 entry playback gate
    /// released，验收按「firstframe 晚于放行点」判读。
    /// (59) 分工：本门只管播放；开场淡入另认 fadeGateSource
    /// 凭据（只认 landed/already-landscape），超时放行不
    /// 起跑淡入——黑场宁可多等落地，不许竖屏先亮画面。
    private var playbackGateReleased = false
    private var playbackGateWorkItem: DispatchWorkItem?

    private func armPlaybackGate() {
        guard !playbackGateReleased else { return }
        if view.window?.windowScene?.interfaceOrientation.isLandscape == true {
            // 开场即横屏：无旋转可等，淡入凭据同刻成立
            // （(59)：与 landed 同级，区别只在日志来源名）。
            fadeGateSource = "already-landscape"
            releasePlaybackGate(reason: "already-landscape")
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.releasePlaybackGate(reason: "timeout-300ms")
        }
        playbackGateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func releasePlaybackGate(reason: String) {
        guard !playbackGateReleased, !isDismissing else { return }
        playbackGateReleased = true
        playbackGateWorkItem?.cancel()
        playbackGateWorkItem = nil
        Breadcrumbs.log("entry playback gate released reason=\(reason)")
        scheduleWatchdog()
        player?.play()
        // 开场淡入合流（(59)）：本方法只管播放放行；淡入另
        // 认 fadeGateSource 凭据——timeout-300ms 兜底走到这
        // 里时凭据未立、本调用为空转，淡入等迟到的 landed
        // 回调补记凭据后合流（黑场等它，不抢跑）。
        beginOpeningFadeIfReady()
    }

    /// 掉帧量测探针：CADisplayLink 逐帧记间隔。>50ms 的逐次
    /// 落 entry framedrops gap（t=相对首 tick 秒数，与录屏逐
    /// 帧对位定责）；逐秒落 entry framedrops sec（帧数/最大
    /// 间隔/>50ms 次数）；teardown 落 summary（总 gap 数＋
    /// 最大间隔＋嫌疑回调耗时 top3）。Pro 判据：落地后重复
    /// 帧 ≤2/秒、退场期 ≤3/秒——录屏与本探针逐秒对位复核。
    private var frameLink: CADisplayLink?
    private var frameLinkStart: CFTimeInterval = 0
    private var frameLinkLast: CFTimeInterval = 0
    private var frameSecondIndex = -1
    private var frameSecondCount = 0
    private var frameSecondMaxMs: Double = 0
    private var frameSecondGaps = 0
    private var frameGapTotal = 0
    private var frameGapMaxMs: Double = 0

    private func startFrameProbe() {
        guard frameLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frameProbeTick(_:)))
        link.add(to: .main, forMode: .common)
        frameLink = link
    }

    @objc private func frameProbeTick(_ link: CADisplayLink) {
        let now = link.timestamp
        if frameLinkStart == 0 {
            frameLinkStart = now
            frameLinkLast = now
            frameSecondIndex = 0
            return
        }
        let intervalMs = (now - frameLinkLast) * 1000
        frameLinkLast = now
        let second = Int(now - frameLinkStart)
        if second != frameSecondIndex {
            if frameSecondIndex >= 0 { logFrameSecond() }
            frameSecondIndex = second
            frameSecondCount = 0
            frameSecondMaxMs = 0
            frameSecondGaps = 0
        }
        frameSecondCount += 1
        if intervalMs > frameSecondMaxMs { frameSecondMaxMs = intervalMs }
        if intervalMs > 50 {
            frameSecondGaps += 1
            frameGapTotal += 1
            if intervalMs > frameGapMaxMs { frameGapMaxMs = intervalMs }
            Breadcrumbs.log("entry framedrops gap t=\(String(format: "%.2f", now - frameLinkStart))s interval=\(String(format: "%.1f", intervalMs))ms")
        }
    }

    private func logFrameSecond() {
        Breadcrumbs.log("entry framedrops sec=\(frameSecondIndex) frames=\(frameSecondCount) maxGap=\(String(format: "%.1f", frameSecondMaxMs))ms gaps50=\(frameSecondGaps)")
    }

    private func stopFrameProbe() {
        guard let link = frameLink else { return }
        frameLink = nil
        link.invalidate()
        if frameSecondIndex >= 0 { logFrameSecond() }
        Breadcrumbs.log("entry framedrops summary gaps50=\(frameGapTotal) maxGap=\(String(format: "%.1f", frameGapMaxMs))ms topcallers \(EntryCallbackTimings.top3Description())")
        EntryCallbackTimings.reset()
    }

    /// 首帧真播时刻（3.7 (54) 工作流 O）：rate>0（真在播、
    /// 非暂停持帧）且播放器层首帧已可显示的首个时刻，落
    /// entry playback firstframe——与 entry poster presented
    /// / entry video readyForDisplay 同走 Breadcrumbs 写行
    /// ISO8601 时钟，三点间隔可直接对账。KVO（timeControl
    /// Status）与周期观察者共用入口，每呈现只落一次；退场
    /// 后迟到触发由 isDismissing 封口。
    private func noteFirstFrameIfNeeded() {
        guard !firstFrameLogged, !isDismissing, let player,
              player.rate > 0,
              player.timeControlStatus == .playing,
              playerView.playerLayer.isReadyForDisplay else { return }
        firstFrameLogged = true
        Breadcrumbs.log("entry playback firstframe rate=\(String(format: "%.2f", player.rate))")
    }

    /// 首帧已可显示（3.7 (53) 工作流 I）：readyForDisplay 的
    /// KVO 与周期观察者兜底共用入口，一次性——落
    /// entry.video.readyForDisplay 后尝试起跑开场淡入。退场
    /// 已开始时不再触发（防 dismiss 后迟到回调落孤儿面包
    /// 屑/淡出）。
    private func handleVideoReadyForDisplay() {
        guard !videoReady, !isDismissing else { return }
        videoReady = true
        Breadcrumbs.log("entry video readyForDisplay")
        beginOpeningFadeIfReady()
    }

    /// 帧缺位判别面包屑（3.7 (61) 第 2 条）：readyForDisplay
    /// 曾置真后跌回 false = 播放中途帧缺位（解码迟滞/预热仓
    /// 接管竞态），逐次跌落落一行 entry gap reason=stall；
    /// 从未置真过（起播前）的 false 不算 gap、不落。videoReady
    /// 锁存不复位（淡入门控口径不动），本方法只记日志。
    private func noteEntryGapStallIfNeeded() {
        guard videoReady, !isDismissing else { return }
        Breadcrumbs.log("entry gap reason=stall ready=0")
    }

    /// 开场淡入（3.7 (59) 工作流二，Miller 原话规格「点进
    /// 去你可以黑，黑一下之后画面慢慢淡入进来」）：双条件
    /// 齐备才起跑——横屏落地凭据已成立（fadeGateSource，
    /// 只认 landed/already-landscape；起播门的
    /// timeout-300ms 兜底放行不算数——它只放播放，(58) 日
    /// 志实锤超时放行后视频在竖屏几何先播约 0.19s 即录屏
    /// 的切横屏一顿）且首帧已可显示（videoReady）。两侧到
    /// 达顺序不定，handleVideoReadyForDisplay、起播门放行
    /// 与 viewWillTransition 的 landed 回调各调一次本方法
    /// 合流。
    /// 起跑段（同步）：撤 window 黑垫（entry veil cleared
    /// 沿用既有面包屑名——VC 黑底已接管整屏，垫无须再留）
    /// ＋播放器层翻不透明＋纯黑背景（(61) 第 2 条改口径：
    /// 原 (57) 海报主色 dominantColor #6A7342 在循环 seek/
    /// 帧缺位时露出成平绿画布，改纯黑、垫底只认海报图本
    /// 体）；落 entry fadein begin 并注明 gate=<凭据来源>。
    /// 动画段：视频层 alpha 0→1、时长 1.0s、curveEaseOut
    /// （iOS 系统缓动，禁线性匀速）；期间视频已在播——起
    /// 播门放行时已从第 0 帧 play、边播边淡入，淡入只改
    /// alpha 不碰播放时钟，中途无亮度跳变。
    /// 完成段（finished 且未退场）：海报层恢复 alpha=1 降
    /// 为播放期垫底（(57) 口径：恒满 bounds、位于播放器
    /// 层之下，正常播放被视频帧完全盖住，间隙帧露油画；
    /// 退场叠化/溶出时与视频层同段淡出、不作中间层独
    /// 占），view 底色回 .clear 复原 (23) 直溶前提；落
    /// entry poster handoff backing=kept 与 entry fadein
    /// done dur=1.0。被退场打断（finished=false 或
    /// isDismissing）不落 done，收尾归 teardown。
    private func beginOpeningFadeIfReady() {
        guard let gate = fadeGateSource, videoReady,
              !openingFadeBegan, !isDismissing else { return }
        openingFadeBegan = true
        exitVeil?.removeFromSuperview()
        exitVeil = nil
        Breadcrumbs.log("entry veil cleared")
        playerView.playerLayer.isOpaque = true
        // (61) 第 2 条：纯黑（不再 dominantColor）；isOpaque=true
        // 与纯黑不透明底自洽，帧缺位时露黑不露绿。
        playerView.playerLayer.backgroundColor = UIColor.black.cgColor
        playerView.isOpaque = true
        Breadcrumbs.log("entry fadein begin dur=1.0 gate=\(gate)")
        UIView.animate(withDuration: 1.0, delay: 0,
                       options: [.curveEaseOut], animations: {
            self.playerView.alpha = 1
        }, completion: { [weak self] finished in
            guard let self, finished, !self.isDismissing else { return }
            self.openingFadeDone = true
            self.posterView.alpha = 1
            self.view.backgroundColor = .clear
            Breadcrumbs.log("entry poster handoff backing=kept")
            Breadcrumbs.log("entry fadein done dur=1.0")
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
    /// 溶出对象 = 视频层＋其下海报垫底（(57) 起垫底整段在
    /// 场）：两者同段同曲线淡出，溶完画面就是墙本身，垫底
    /// 不作中间层独占；旋转回正自 (57) 起在 dismissIntro 开
    /// 始即与淡出并行发出（PortraitRestore 在飞守卫兜底）。
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
            self.posterView.alpha = 0
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
            self.posterView.alpha = 0
        }, completion: { [weak self] _ in
            guard let self else { return }
            if EntryIntroPresenter.currentDataState == .ready {
                self.dismissIntro(reason: "data-ready", animated: true)
            } else {
                self.loopExitBegan = false
                self.dissolveBegan = false
                self.playerView.layer.removeAllAnimations()
                self.playerView.alpha = 1
                self.posterView.layer.removeAllAnimations()
                self.posterView.alpha = 1
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
            // 先恢复视频层不透明再循环，不许透着墙重播。海报
            // 垫底（(57) 起与视频层同段淡出）同步恢复，续播期
            // 间继续作垫底在场。
            if dissolveBegan {
                dissolveBegan = false
                playerView.layer.removeAllAnimations()
                playerView.alpha = 1
                posterView.layer.removeAllAnimations()
                posterView.alpha = 1
            }
            loopCount += 1
            Breadcrumbs.log("entry loop round=\(loopCount)")
            scheduleWatchdog()
            // (61) 第 2 条判别面包屑：每轮循环 seek 回零各落一
            // 行 entry gap reason=seek——seek 窗口即帧缺位窗，
            // 与绿窗时刻同窗出现即坐实 playerLayer 底色来源。
            Breadcrumbs.log("entry gap reason=seek ready=0")
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
        // 黑场垫若还在（淡入未起跑就退场，如播放失败）：直
        // 接撤除——它只是开场占位，不参与退场衔接。迟到的
        // readyForDisplay/淡入合流由 isDismissing 在
        // handleVideoReadyForDisplay 与
        // beginOpeningFadeIfReady 的 guard 处封口（(59) 起
        // 代替原 veilCleared 旗标），不落孤儿面包屑。
        exitVeil?.removeFromSuperview()
        exitVeil = nil
        // 本次退场引发的墙露面不重播入场（同一次进墙事件）。
        EntryIntroPresenter.suppressNext()

        // 退场收尾（两路共用）：拆播放器 → 提交 dismiss → 落
        // done 面包屑 → 方向恢复兜底（(57)：主发点已提前到
        // 下方 animated 路径的淡出开始；此处 dismiss 完成后
        // 的调用保留作兜底——旋转已落地时为无操作、旋转在
        // 飞时被 PortraitRestore 在飞守卫挡下、旋转未起时按
        // (23) 原路补发；墙 viewDidAppear 另有同路兜底）→
        // 墙帧提交确认。
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
            // 播放失败：立即放行，不等转场（方向恢复走
            // finishDismiss 的兜底原路，(23) 时机不变）。
            teardownPlayer()
            finishDismiss()
            return
        }

        // 退场旋转并行（3.7 (57) 工作流 A）：(23) 的串行时序
        // （淡出→dismiss→才发竖屏请求→系统旋转）使墙以横屏
        // 布局静止示人约 0.8s 后猛地正过来（(55) 录屏实测），
        // 违反定版「退出转回竖屏须淡出遮住、不许露硬转」。
        // (23) 当年把请求压到 dismiss 后，是因为本 VC 写死横
        // 屏专属、压顶时请求必被拒——(57) 先动态解锁本 VC
        // 方向（unlockOrientationsForExit），请求即可在淡出
        // 开始同刻发出：系统旋转动画（约 0.4s）与整面淡出
        // （0.15–0.4s）＋dismiss 并行重叠，旋转全程有油画
        // （视频/海报垫底同属本 VC、随整面淡出）覆盖，墙被
        // 揭开时已竖屏或正在平滑旋转中，不再横倒静止示人。
        let sceneIsLandscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
        if let presenter {
            unlockOrientationsForExit()
            PortraitRestore.requestIfLandscape(from: presenter, source: "dismiss-start")
        }

        // 退场衔接（3.7 (23) 直溶版）：整面淡出直接落到主页墙
        // （VC 透明背景 + overFullScreen，墙全程在层级内），
        // 墙面弹簧落位同段并行（自 (21) 沿用：1.02 蓄势 →
        // 弹簧回 1.00）；总时长 ≤0.6s 不变。尾段叠化已起跑
        // 时视频层已溶尽，本段只清关闭按钮与整面残余，时长
        // 压到 0.15（合并去重，不重新引入任何中间层独占）。
        // (57) 补：需要旋转回正时跳过墙面落位——1.02 变换挂
        // 在正在旋转的墙 view 上与系统旋转变换同帧竞争，是
        // 「猛地正过来」的嫌疑共犯；旋转本身即落位动势。
        let fast = reason == "closed"
        let fadeDuration = fast ? 0.3 : (dissolveBegan ? 0.15 : 0.4)
        Breadcrumbs.log("entry video alpha fade dur=\(String(format: "%.2f", fadeDuration)) dissolve=\(dissolveBegan)")
        if fast {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: {
                self.closeButton.alpha = 0
            })
        }
        if sceneIsLandscape {
            Breadcrumbs.log("entry wall settle skipped reason=rotation-parallel")
        } else {
            Self.beginWallSettle(wallView: presenter?.view, fast: fast)
        }

        // 退场提交等竖屏落地（3.7 (58) 定稿②）：(57) 淡出
        // （0.15–0.4s）短于旋转耗时，提交时墙可能还在转——
        // 露出旋转中的墙正是 (55) 录屏横倒冻结/黑角帧的竞速
        // 源。(58)：横屏退场时淡出延长到 0.6s 覆盖全程，
        // 提交（teardown＋dismiss）等 PortraitRestore 的
        // landed 通知（entry rotate portrait landed）先到则
        // 收短淡出立即提交；0.6s 超时兜底提交，不许挂死。
        // 验收按日志时序判读：landed 必须早于 dismiss done。
        // 竖屏退场无旋转、照旧淡出完即提交。
        var proceedFired = false
        let proceed = {
            guard !proceedFired else { return }
            proceedFired = true
            self.teardownPlayer()
            finishDismiss()
        }
        if sceneIsLandscape {
            UIView.animate(withDuration: 0.6, delay: 0, options: [.curveEaseOut], animations: {
                self.view.alpha = 0
            }, completion: { _ in proceed() })
            PortraitRestore.whenPortraitLanded(from: self) {
                guard !proceedFired else { return }
                self.view.layer.removeAllAnimations()
                UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut], animations: {
                    self.view.alpha = 0
                }, completion: { _ in proceed() })
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proceed() }
        } else {
            UIView.animate(withDuration: fadeDuration, delay: 0, options: [.curveEaseOut], animations: {
                self.view.alpha = 0
            }, completion: { _ in proceed() })
        }
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
        // (58) 掉帧探针收口（汇总落日志后摘链）＋起播门残留
        // 放行任务取消（退场后迟到的超时放行不许再 play）。
        stopFrameProbe()
        playbackGateWorkItem?.cancel()
        playbackGateWorkItem = nil
        // 海报垫底摘除时刻（3.7 (57) 工作流 A）：(57) 起垫底
        // 整段播放期在场，其摘除点即 teardown（退场两路共用
        // 的唯一拆解点，每呈现恰一次）——与 entry poster
        // handoff 成对落痕，垫底在场区间可与录屏对账。
        Breadcrumbs.log("entry poster removed")
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
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
        // 预热实例泊回（3.7 (54) 工作流 O）：VC 侧观察者已
        // 全部摘除后才泊回，仓内实例无任何 VC 残留订阅；
        // park 内部 seek 回零，下次进墙接管即从头即时再播。
        // 现装配实例照旧弃置（player=nil 后 ARC 释放）。
        if usesPreheatedPlayer, let outgoingPlayer = player,
           let outgoingItem = outgoingPlayer.currentItem {
            EntryPlayerPreheat.park(player: outgoingPlayer, item: outgoingItem)
            usesPreheatedPlayer = false
        }
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
///   调用点 (23) 时两处——入场 dismiss 完成（EntryIntro）
///   与墙 viewDidAppear 兜底（HomeWall），双触发以 0.3s 去
///   重窗合并为一次；(57) 起主发点提前为入场退场开始
///   （dismiss-start，VC 已动态解锁方向、请求可被受理，
///   旋转与淡出并行），原两处降为兜底，并加在飞守卫防重
///   复请求打断旋转动画。
/// - 发后 0.2s（转场动画量级）校验实际方向：仍横屏重试一
///   次；最终结果落面包屑，失败时带顶层 VC 的 supported
///   mask 与 error，不再只 NSLog 无从对账。
enum PortraitRestore {

    private static var lastRequestAt: CFTimeInterval = 0
    /// 旋转在飞守卫（3.7 (57) 工作流 A）：一次竖屏请求已发
    /// 出、落地校验未落定期间为真。此间任何来源的重复请求
    /// （dismiss 完成兜底、墙 viewDidAppear 兜底）一律挡下
    /// 并落痕——旋转动画中途再发几何请求会打断插值、把平
    /// 滑旋转打成跳变，正是 (55) 录屏「猛地正过来」的嫌疑
    /// 机制之一。落地（校验见竖屏）或最终失败时清零。
    private static var requestInFlight = false

    /// 竖屏落地一次性等待者（3.7 (58) 定稿②）：退场提交需要
    /// 等墙转回竖屏落地才露墙（否则露正在转的墙面＝(55) 录屏
    /// 的横倒冻结/黑角帧）。attempt 的任一终局（确认落地/
    /// 两轮放弃/请求报错）都触发全部等待者——等待方自带
    /// 0.6s 超时兜底，失败也触发、不许双等挂死。
    private static var portraitLandedWaiters: [() -> Void] = []

    /// 登记一次竖屏落地等待；调用时界面已竖屏则下一轮
    /// runloop 即回调（不等请求轮次）。
    static func whenPortraitLanded(from vc: UIViewController,
                                   _ waiter: @escaping () -> Void) {
        guard let scene = vc.view.window?.windowScene,
              scene.interfaceOrientation.isLandscape else {
            DispatchQueue.main.async(execute: waiter)
            return
        }
        portraitLandedWaiters.append(waiter)
    }

    private static func firePortraitLandedWaiters() {
        let waiters = portraitLandedWaiters
        portraitLandedWaiters = []
        for waiter in waiters { waiter() }
    }

    static func requestIfLandscape(from vc: UIViewController, source: String) {
        guard let scene = vc.view.window?.windowScene else { return }
        guard scene.interfaceOrientation.isLandscape else { return }
        if requestInFlight {
            Breadcrumbs.log("entry rotate portrait skipped source=\(source) reason=in-flight")
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastRequestAt > 0.3 else { return }
        lastRequestAt = now
        attempt(scene: scene, source: source, tryCount: 1)
    }

    private static func attempt(scene: UIWindowScene, source: String, tryCount: Int) {
        requestInFlight = true
        // 请求发出时刻（3.7 (57) 工作流 A 新增）：与 VC 的
        // entry rotate landed（实际生效）成对，间隔即系统旋
        // 转耗时，可与录屏时间轴逐帧对账。
        Breadcrumbs.log("entry rotate portrait request source=\(source) attempt=\(tryCount)")
        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: .portrait)
        ) { error in
            // errorHandler 只在失败时回调，error 为非 Optional。
            requestInFlight = false
            Breadcrumbs.log("entry rotate portrait error source=\(source) attempt=\(tryCount) \(failureContext(scene: scene)) error=\(error.localizedDescription)")
            firePortraitLandedWaiters()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if scene.interfaceOrientation.isLandscape {
                if tryCount < 2 {
                    PortraitRestore.attempt(scene: scene, source: source, tryCount: tryCount + 1)
                } else {
                    requestInFlight = false
                    Breadcrumbs.log("entry rotate portrait failed source=\(source) \(failureContext(scene: scene))")
                    firePortraitLandedWaiters()
                }
            } else {
                requestInFlight = false
                Breadcrumbs.log("entry rotate portrait ok source=\(source) attempt=\(tryCount)")
                Breadcrumbs.log("entry rotate portrait landed source=\(source) attempt=\(tryCount)")
                firePortraitLandedWaiters()
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
