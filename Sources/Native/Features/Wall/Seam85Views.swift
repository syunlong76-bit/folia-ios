import Combine
import UIKit

/// (85) 第 1 条：世界缝共享等级（网页 bravaisSeamLevel 同
/// 式：全局一个等级、跨面沿用——主页折叠后进歌单，缝仍是
/// 折叠的）。手机档只有 spine（64 书脊）/ hidden 两级；
/// 歌单的展开档（300 完整条）是面内状态、不入本存储。
enum SeamState85 {
    static var levelHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "folia.seam85.hidden") }
        set { UserDefaults.standard.set(newValue, forKey: "folia.seam85.hidden") }
    }

    /// (89)B b-seam-narrow：首页窄缝 120 档开关（网页
    /// BRAVAIS_SEAM_HOME_WIDTH=120）。true 时主页缝开口
    /// 宽走 120 宽档排版，false 回书脊 64；点缝上「书库」
    /// 标题切换（见 HomeSeam85View.onToggleWide89）。
    static var narrow120: Bool {
        get { UserDefaults.standard.bool(forKey: "folia.seam89.narrow120") }
        set { UserDefaults.standard.set(newValue, forKey: "folia.seam89.narrow120") }
    }

    /// (94) 94-4：二维码展开态/平台——母版共享状态（主页/
    /// 歌单两缝共用一份、旋转重排不丢；进程内暂存不落盘，
    /// 缝重建后按此恢复展开态并续跑取码流）。
    static var qrOpen94 = false
    static var qrProvider94 = "qq"

    /// 网页 contentOpacityFor 同式：开口窄于排版宽时内容
    /// 随之淡出（开到 35% 以下不可见）。
    static func contentOpacity(rendered: CGFloat, content: CGFloat) -> CGFloat {
        max(0, min(1, (rendered / max(content, 1) - 0.35) / 0.65))
    }
}

/// 竖排文字（字间换行，与 (84) 侧栏/网页 writing-mode 同
/// 视觉语言）。
enum Seam85Text {
    static func vertical(_ text: String) -> String {
        text.map { String($0) }.joined(separator: "\n")
    }
}

/// (86) 第 1/2 条：缝底（两缝共用）。
/// port90（Miller 2026-11-26 20:19/20:27 定）：油画背景图整组退役，
/// 改系统毛玻璃——UIVisualEffectView(systemUltraThinMaterialDark，
/// 与控制台卡同材质）＋轻 tint 黑 0.18 保竖排小字可读；透出墙面。
/// 0 0 18px 黑投影保留。本层不接手势（缝命中纪律不变：只认控件本体）。
final class SeamBackdrop86: UIView {

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let tintView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 9
        layer.shadowOffset = .zero
        isUserInteractionEnabled = false
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)
        tintView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        tintView.isUserInteractionEnabled = false
        addSubview(tintView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        tintView.frame = bounds
    }
}

/// (86) 第 2 条：缝上长按 0.55s 切主题——与点播台长按
/// 同一通路（写 MiniPlayerTheme.stored.next＋发同一通
/// 知，主题单源不分叉；特效总开关关时停用、同台口
/// 径）。识别器挂缝本体：触摸落在缝内任一控件上时祖先
/// 识别器同收，认领即 cancelsTouchesInView、控件不误
/// 触；缝空域穿透纪律不变（空域触摸归墙、长按不达）。
enum SeamThemeCycle86 {
    static func cycle() {
        guard MiniPlayerTheme.effectsEnabled else { return }
        MiniPlayerTheme.stored = MiniPlayerTheme.stored.next
        NotificationCenter.default.post(
            name: .foliaMiniPlayerThemeChanged, object: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Breadcrumbs.log("seam86 theme=\(MiniPlayerTheme.stored.rawValue)")
    }
}

/// (93) C1/C2/C3 共享字形工厂：样片定版细线字形本地描画
/// （24 画布、统一线宽 1.7、圆头端点/圆角连接、光学尺寸
/// 约 16px；不走 SF Symbols、不改 Deck82）。路径逐字形按
/// 样片 SVG 换算（搜索/齿轮/列表/更多/双音符/爱心/云/书
/// 本/服务器/展开角）；齿轮为标准齿轮形（8 齿＋环身＋中
/// 心孔，填充剪影＋孔洞挖空）；排版三段字形（砖墙格/列
/// 表/专辑）与样片 .layoutseg/.ab 同源：字形 15–17.5px、
/// 砖墙格光学再 ×0.86（绘制时绕中心缩放）。
enum SeamGlyph93 {

    enum Kind {
        case search, gear, list, more, consoleNotes
        case heart, cloud, book, server, expandCorners
        case layoutGrid, layoutList, layoutAlbum
    }

    static func image(_ kind: Kind, pointSize: CGFloat = 16) -> UIImage? {
        let scale = pointSize / 24
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            UIColor.white.setStroke()
            UIColor.white.setFill()
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }
            func stroke(_ path: UIBezierPath, w: CGFloat = 1.7) {
                path.lineWidth = w * scale
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                      w: CGFloat = 1.7) {
                let path = UIBezierPath()
                path.move(to: p(x1, y1))
                path.addLine(to: p(x2, y2))
                stroke(path, w: w)
            }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
                UIBezierPath(ovalIn: CGRect(
                    x: (x - r) * scale, y: (y - r) * scale,
                    width: 2 * r * scale, height: 2 * r * scale)).fill()
            }
            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                       _ r: CGFloat) -> UIBezierPath {
                UIBezierPath(roundedRect: CGRect(
                    x: x * scale, y: y * scale,
                    width: w * scale, height: h * scale),
                    cornerRadius: r * scale)
            }
            switch kind {
            case .search:
                stroke(UIBezierPath(ovalIn: CGRect(
                    x: 4.6 * scale, y: 4.6 * scale,
                    width: 12.8 * scale, height: 12.8 * scale)))
                line(15.7, 15.7, 20.1, 20.1)
            case .gear:
                // (93) 标准齿轮：8 齿（圆角齿片绕心 45° 步进）
                // ＋环身圆盘填充，中心孔以 clear 挖空成形。
                for i in 0..<8 {
                    let tooth = UIBezierPath(roundedRect: CGRect(
                        x: -1.3 * scale, y: -9.7 * scale,
                        width: 2.6 * scale, height: 3.8 * scale),
                        cornerRadius: 0.9 * scale)
                    cg.saveGState()
                    cg.translateBy(x: 12 * scale, y: 12 * scale)
                    cg.rotate(by: CGFloat(i) * .pi / 4)
                    tooth.fill()
                    cg.restoreGState()
                }
                UIBezierPath(ovalIn: CGRect(
                    x: 5 * scale, y: 5 * scale,
                    width: 14 * scale, height: 14 * scale)).fill()
                cg.saveGState()
                cg.setBlendMode(.clear)
                UIBezierPath(ovalIn: CGRect(
                    x: 8.9 * scale, y: 8.9 * scale,
                    width: 6.2 * scale, height: 6.2 * scale)).fill()
                cg.restoreGState()
            case .list:
                line(8.7, 6.4, 19.4, 6.4)
                line(8.7, 12, 19.4, 12)
                line(8.7, 17.6, 19.4, 17.6)
                dot(4.7, 6.4, 1.3)
                dot(4.7, 12, 1.3)
                dot(4.7, 17.6, 1.3)
            case .more:
                dot(5, 12, 1.5)
                dot(12, 12, 1.5)
                dot(19, 12, 1.5)
            case .consoleNotes:
                // 样片双音符（上下对称）：两椭圆音头＋音杆＋弧梁。
                UIBezierPath(ovalIn: CGRect(
                    x: 12.65 * scale, y: 7.15 * scale,
                    width: 4.7 * scale, height: 3.7 * scale)).fill()
                UIBezierPath(ovalIn: CGRect(
                    x: 6.65 * scale, y: 13.15 * scale,
                    width: 4.7 * scale, height: 3.7 * scale)).fill()
                let stem1 = UIBezierPath()
                stem1.move(to: p(17.3, 8.7))
                stem1.addLine(to: p(17.3, 3.8))
                stem1.addCurve(to: p(21, 6.7),
                               controlPoint1: p(19.1, 4.1),
                               controlPoint2: p(20.3, 5.2))
                stroke(stem1, w: 1.6)
                let stem2 = UIBezierPath()
                stem2.move(to: p(6.7, 15.3))
                stem2.addLine(to: p(6.7, 20.2))
                stem2.addCurve(to: p(3, 17.3),
                               controlPoint1: p(4.9, 19.9),
                               controlPoint2: p(3.7, 18.8))
                stroke(stem2, w: 1.6)
            case .heart:
                let path = UIBezierPath()
                path.move(to: p(12, 20.3))
                path.addCurve(to: p(3, 9.9),
                              controlPoint1: p(6.4, 16.9),
                              controlPoint2: p(3, 13.6))
                path.addCurve(to: p(7.7, 5),
                              controlPoint1: p(3, 7.2),
                              controlPoint2: p(5.1, 5))
                path.addCurve(to: p(12, 7.4),
                              controlPoint1: p(9.4, 5),
                              controlPoint2: p(11, 5.9))
                path.addCurve(to: p(16.3, 5),
                              controlPoint1: p(13, 5.9),
                              controlPoint2: p(14.6, 5))
                path.addCurve(to: p(21, 9.9),
                              controlPoint1: p(18.9, 5),
                              controlPoint2: p(21, 7.2))
                path.addCurve(to: p(12, 20.3),
                              controlPoint1: p(21, 13.6),
                              controlPoint2: p(17.6, 16.9))
                path.close()
                stroke(path)
            case .cloud:
                let path = UIBezierPath()
                path.move(to: p(6.6, 18.4))
                path.addLine(to: p(17.3, 18.4))
                path.addCurve(to: p(18.1, 10.8),
                              controlPoint1: p(20.9, 17.8),
                              controlPoint2: p(21.1, 12.6))
                path.addCurve(to: p(7.3, 11.85),
                              controlPoint1: p(16.8, 6.4),
                              controlPoint2: p(9.6, 5.7))
                path.addCurve(to: p(6.6, 18.4),
                              controlPoint1: p(4.7, 12.7),
                              controlPoint2: p(4.9, 17.3))
                path.close()
                stroke(path)
            case .book:
                let path = UIBezierPath()
                path.move(to: p(12, 6.4))
                path.addCurve(to: p(4.6, 4.5),
                              controlPoint1: p(10.3, 4.9),
                              controlPoint2: p(7.9, 4.3))
                path.addLine(to: p(4.6, 17.7))
                path.addCurve(to: p(12, 19.6),
                              controlPoint1: p(7.9, 17.5),
                              controlPoint2: p(10.3, 18.1))
                path.addCurve(to: p(19.4, 17.7),
                              controlPoint1: p(13.7, 18.1),
                              controlPoint2: p(16.1, 17.5))
                path.addLine(to: p(19.4, 4.5))
                path.addCurve(to: p(12, 6.4),
                              controlPoint1: p(16.1, 4.3),
                              controlPoint2: p(13.7, 4.9))
                path.close()
                stroke(path)
                line(12, 6.4, 12, 19.6)
            case .server:
                stroke(rrect(4, 4.2, 16, 6.3, 1.8))
                stroke(rrect(4, 13.5, 16, 6.3, 1.8))
                dot(7.6, 7.35, 1.05)
                dot(7.6, 16.65, 1.05)
            case .expandCorners:
                for (pts) in [[(9.4, 4.8), (4.8, 4.8), (4.8, 9.4)],
                              [(14.6, 4.8), (19.2, 4.8), (19.2, 9.4)],
                              [(9.4, 19.2), (4.8, 19.2), (4.8, 14.6)],
                              [(14.6, 19.2), (19.2, 19.2), (19.2, 14.6)]]
                    as [[(CGFloat, CGFloat)]] {
                    let path = UIBezierPath()
                    path.move(to: p(pts[0].0, pts[0].1))
                    path.addLine(to: p(pts[1].0, pts[1].1))
                    path.addLine(to: p(pts[2].0, pts[2].1))
                    stroke(path)
                }
            case .layoutGrid:
                // (93) 砖墙格：四实心圆角方，光学 ×0.86 绕心缩。
                cg.saveGState()
                cg.translateBy(x: 12 * scale, y: 12 * scale)
                cg.scaleBy(x: 0.86, y: 0.86)
                cg.translateBy(x: -12 * scale, y: -12 * scale)
                rrect(4, 4, 7.2, 7.2, 1.8).fill()
                rrect(12.8, 4, 7.2, 7.2, 1.8).fill()
                rrect(4, 12.8, 7.2, 7.2, 1.8).fill()
                rrect(12.8, 12.8, 7.2, 7.2, 1.8).fill()
                cg.restoreGState()
            case .layoutList:
                rrect(4, 5, 4.6, 4.6, 1.2).fill()
                rrect(10.6, 6.15, 9.4, 2.3, 1.15).fill()
                rrect(4, 14.4, 4.6, 4.6, 1.2).fill()
                rrect(10.6, 15.55, 9.4, 2.3, 1.15).fill()
            case .layoutAlbum:
                stroke(rrect(4.2, 4.2, 15.6, 15.6, 3.4), w: 1.9)
                stroke(UIBezierPath(ovalIn: CGRect(
                    x: 8.9 * scale, y: 8.9 * scale,
                    width: 6.2 * scale, height: 6.2 * scale)), w: 1.9)
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// (93) C3 排版名（面包屑 p93 layout sw= 插值用）。
    static func layoutName93(_ mode: Int) -> String {
        ["wall", "magazine", "shelf"][max(0, min(2, mode))]
    }
}

/// 缝宿主侧边竖标签（网页 BRAVAIS_EDGE_TAB）：缝折叠或被
/// 平移挤出视口时出现在屏幕侧边，点它在当前视口重新裂开。
final class SeamEdgeTab85View: UIView {

    var onTap: (() -> Void)?

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.42)
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        label.text = Seam85Text.vertical("书库")
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    @objc private func tapped() { onTap?() }
}

/// (94) 94-4：缝排版单一母版——主页缝与歌单页缝共用同一
/// 个 SeamMaster 核心组件，自上而下构成定版（与样片
/// ge-dan-qiang-pai-ban-zhong-she-ji-yang-pian 定版一致）：
/// 缝顶圆形头像（34pt，点头像缝中区原地切登录二维码，
/// QQ/酷狗页签可切、无浮层无遮罩、再点头像切回）→ 页签
/// 行 → 四入口图标行（我喜欢的音乐/云盘/日记本/Navidrome）
/// → 排版胶囊（横排三段，与歌单页同一组件、同一共享状态
/// foliaPlaylistLayout91）→ 缝底图标排 → 缝底播放区（上一
/// 首/暂停白圆钮 38/下一首）。页面差异只剩数据（页签内容/
/// 计数/头部语义）与回调转发，由 HomeSeam85View /
/// PlaylistSeam85View 两个适配类承担；构成、布局、状态
/// （页签选中/胶囊模式/播放态/二维码展开态）只有这一份
/// 实现，不许再各写一套缝。
final class SeamMaster: UIView {

    enum Entry { case liked, cloud, diary, navidrome }
    enum Tool { case search, settings, queue, more, console, append, expand }
    enum Header { case homeTitle(String), playlist }

    struct ToolItem {
        let tool: Tool
        let glyph: SeamGlyph93.Kind
        let label: String
    }

    // MARK: 语义回调（适配类转发到宿主既有闭包）

    var onFold: (() -> Void)?
    var onBack: (() -> Void)?
    var onHeaderTitleTap: (() -> Void)?
    var onTabSelected: ((Int) -> Void)?
    var onEntry: ((Entry) -> Void)?
    var onLayoutMode: ((Int) -> Void)?
    var onTool: ((Tool) -> Void)?
    /// 歌单页专用：缝底播放区中央钮在未播放时接歌单全量
    /// 播放（宿主 onPlayAll）；主页不设、走全局播放切换。
    var onPlayAll: (() -> Void)?

    var header: Header = .playlist {
        didSet { applyHeader() }
    }

    /// 内容纵向内边距（宿主按工具条/点播台占位设定，转发
    /// 自适配类既有 contentTopInset/contentBottomInset）。
    var contentTopInset: CGFloat = 108 { didSet { setNeedsLayout() } }
    var contentBottomInset: CGFloat = 132 { didSet { setNeedsLayout() } }
    /// 内容淡出（宿主按渲染开口逐帧喂，见 SeamState85）。
    var contentOpacity: CGFloat = 1 {
        didSet { contentView.alpha = contentOpacity }
    }
    /// 主页 120 宽档标记（宿主 displayWide89 转发；只影响
    /// 入口/工具排的行列折法，构成不变）。
    var displayWide: Bool = false { didSet { setNeedsLayout() } }
    /// 歌单展开档标记（展开工具钮选中态）。
    var isExpanded94: Bool = false { didSet { refreshTools() } }

    // MARK: 视图

    private let host94: String
    private let backdrop86 = SeamBackdrop86()
    private let contentView = UIView()

    private let avatarButton = UIButton(type: .custom)
    private let avatarImageView = UIImageView()
    private let avatarFallbackLabel = UILabel()
    private let avatarPlaceholderIcon = UIImageView()

    private let mainScroll = UIScrollView()
    private let mainContent = UIView()
    private let headerTitleButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let foldButton = UIButton(type: .system)
    private var tabButtons: [UIButton] = []
    private let tabNoteLabel = UILabel()
    private var entryButtons: [UIButton] = []
    private let capsuleView = UIView()
    private var capsuleButtons: [UIButton] = []

    private let qrPanel = UIView()
    private let qrTitleLabel = UILabel()
    private let qrCloseButton = UIButton(type: .system)
    private var qrTabButtons: [UIButton] = []
    private let qrImageView = UIImageView()
    private let qrStatusLabel = UILabel()
    private let qrSpinner = UIActivityIndicatorView(style: .medium)

    private var toolButtons: [UIButton] = []
    private let prevButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    // MARK: 状态

    private var tabTitles: [String] = []
    private var tabNote: String?
    private(set) var selectedTabIndex: Int = 0
    private(set) var layoutMode: Int =
        UserDefaults.standard.integer(forKey: "foliaPlaylistLayout91")
    private var toolItems: [ToolItem] = []

    /// 主区内容高于视口时（横屏矮高）主区纵向可滚、命中
    /// 放行滚动视图本体；常态内容不滚动、缝背景穿透纪律
    /// 不变（适配类 hitTest 据此判定）。
    private(set) var wantsScrollHit94 = false

    private var avatarKey: String?
    private var avatarHasName = false
    private static var enrichAttempted94 = Set<String>()

    private var isPlaying94 = PlaybackEngine.shared.isPlaying
    private var playingCancellable: AnyCancellable?

    private let qqClient94 = QQLoginClient()
    private let kugouClient94 = KugouLoginClient()
    private let coordinator94 = PollingCoordinator.shared
    private var qrFlowActive = false

    // (95) 10：二维码图后台预生成缓存（按 payload 失效）
    // 与切换动画帧间隔自证探针。
    private var qrCachedImage95: UIImage?
    private var qrCachedKey95: String?

    // (98) 第 5 条：二维码加速——channels 会话缓存（App 生命周期
    // 内复用）、key 预取缓存（TTL 120s，unikey 180s 留 60s 余
    // 量）、双槽码缓存（按 provider 存 key＋图 payload＋生成时
    // 刻，切回未过前端有效窗直接复用图并以原 key 续轮询）。
    static var qrChannels98: [String]?
    static var qrKeyCache98: [String: (key: String, channel: String, at: Date)] = [:]
    static var qrSlot98: [String: (key: String, base64: String?, content: String?, at: Date, pre: Bool)] = [:]
    private var qrT098: Date?
    private var qrTotalLogged98 = false
    private var qrCacheHit98 = false
    private var qrReuseKey98: String?

    // (99) 第 6 条：预生成整码＋静默续期——在册平台（默认家
    // 缝构建时入册、另一家首次切到后入册）、同平台在途守卫
    // （同时只许一个生成）、最近登录上下文时刻（开缝/切签/
    // 取码流启动时刷新；超 30 分钟无上下文停续期）、续期定
    // 时器（15s tick、主 RunLoop；宿主弱引用，宿主没了自停）。
    // 预生成码只存进程内静态缓存、不落盘、不外发。
    static var qrPreInFlight99: Set<String> = []
    static var qrEnrolled99: Set<String> = []
    static var qrPreAttempt99: [String: Date] = [:]
    static var qrLastCtx99: Date?
    static var qrRenewTimer99: Timer?
    static weak var qrRenewHost99: SeamMaster?
    private var qrPreHit99 = false

    /// 前端可用窗（与 startQRFlow 双槽判定同值：QQ 160s／
    /// 酷狗 285s，各已留 15s 余量于服务端 TTL）。
    private static func qrWindow99(_ prov: String) -> TimeInterval {
        prov == "qq" ? 160 : 285
    }

    private func qrSeg98(_ prov: String, _ stage: String, _ t0: Date) {
        Breadcrumbs.log("p98 qr seg prov=\(prov) stage=\(stage) ms=\(Int(Date().timeIntervalSince(t0) * 1000)) node=\(ProviderLoginTransport.lastNodeIndex98)")
    }

    private func qrTotal98(_ prov: String) {
        guard !qrTotalLogged98, let t0 = qrT098 else { return }
        qrTotalLogged98 = true
        Breadcrumbs.log("p98 qr total prov=\(prov) ms=\(Int(Date().timeIntervalSince(t0) * 1000)) cache=\(qrCacheHit98 ? 1 : 0) pre=\(qrPreHit99 ? 1 : 0)")
    }

    /// (99) 第 6 条：缝构建时（现有最早触发点，沿 (98)
    /// prefetchQRKeys98 的 init 调用）把默认平台从「预取
    /// key」升级为「预生成整码」——key＋create 全链路走完、
    /// 整码入双槽，用户点头像时直接命中（见 startQRFlow 的
    /// pre=1 口径）。另一家仍只预热 key，首次被切到后由
    /// startQRFlow 入册、同样纳入预生成＋续期。两家都已登
    /// 录时无码可备、跳过。失败静默：不落痕于 UI、按需链
    /// 路（startQRFlow 整链重跑）原样兜底。
    private func prefetchQRKeys98() {
        if let target = defaultQRProvider99() {
            pregenerateQR99(target, renewal: false)
        }
        Task { [weak self] in
            guard let self else { return }
            if Self.qrKeyCache98["qq"] == nil {
                var channel = "qq"
                if let chs = Self.qrChannels98, !chs.contains(channel) {
                    channel = chs.first ?? channel
                }
                if let key = try? await self.qqClient94.fetchKey(channel: channel) {
                    Self.qrKeyCache98["qq"] = (key, channel, Date())
                }
            }
            if Self.qrKeyCache98["kugou"] == nil,
               let key = try? await self.kugouClient94.fetchKey() {
                Self.qrKeyCache98["kugou"] = (key, "", Date())
            }
        }
    }

    /// 默认平台（openQR94 同判据：第一家未登录的，QQ 先、
    /// 酷狗后）；都已登录返回 nil。
    private func defaultQRProvider99() -> String? {
        if ProviderSessionStatusQuery.status(for: .qq).isLoggedIn == false {
            return "qq"
        }
        if ProviderSessionStatusQuery.status(for: .kugou).isLoggedIn == false {
            return "kugou"
        }
        return nil
    }

    /// 预生成/续期共用入口（主线程调用约定：静态守卫与登
    /// 记只在此改）。同平台在途直接让路；槽内码尚鲜（距可
    /// 用窗上限 ≥30s）不重生成。续期失败不清空旧槽——旧码
    /// 到期后由按需链路整链重跑兜底。
    private func pregenerateQR99(_ prov: String, renewal: Bool) {
        guard !Self.qrPreInFlight99.contains(prov) else { return }
        if renewal, let last = Self.qrPreAttempt99[prov],
           Date().timeIntervalSince(last) < 60 { return }
        if let slot = Self.qrSlot98[prov],
           Date().timeIntervalSince(slot.at) < Self.qrWindow99(prov) - 30 {
            if !renewal {
                Breadcrumbs.log("p99 qr pre prov=\(prov) hit=1 ms=0")
            }
            return
        }
        Self.qrPreInFlight99.insert(prov)
        Self.qrPreAttempt99[prov] = Date()
        Self.qrEnrolled99.insert(prov)
        Self.qrLastCtx99 = Date()
        Self.startQRRenewTimer99(host: self)
        let oldAge = Self.qrSlot98[prov]
            .map { Int(Date().timeIntervalSince($0.at)) } ?? 0
        let t0 = Date()
        Task { [weak self] in
            var stored = false
            if let self {
                stored = await self.generateQRCode99(prov)
            }
            await MainActor.run {
                Self.qrPreInFlight99.remove(prov)
                guard stored else { return }
                if renewal {
                    Breadcrumbs.log("p99 qr ren prov=\(prov) age=\(oldAge)")
                } else {
                    Breadcrumbs.log("p99 qr pre prov=\(prov) hit=0 ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
                }
            }
        }
    }

    /// key＋create 全链路（与取码流同段同缓存口径：key 优
    /// 先吃 120s 预取缓存）；成功把整码写双槽并标 pre。
    /// 任一步失败返回 false、什么都不写。
    private func generateQRCode99(_ prov: String) async -> Bool {
        if prov == "qq" {
            var channel = "qq"
            if let chs = Self.qrChannels98, !chs.contains(channel) {
                channel = chs.first ?? channel
            }
            var key = ""
            if let kc = Self.qrKeyCache98["qq"], kc.channel == channel,
               Date().timeIntervalSince(kc.at) < 120 {
                key = kc.key
            } else {
                guard let fetched = try? await qqClient94.fetchKey(channel: channel)
                else { return false }
                key = fetched
                Self.qrKeyCache98["qq"] = (key, channel, Date())
            }
            guard let qr = try? await qqClient94.createQR(key: key),
                  let img = qr.qrimgBase64, !img.isEmpty else { return false }
            Self.qrSlot98["qq"] = (qr.key, qr.qrimgBase64, nil, Date(), true)
            return true
        }
        var key = ""
        if let kc = Self.qrKeyCache98["kugou"],
           Date().timeIntervalSince(kc.at) < 120 {
            key = kc.key
        } else {
            guard let fetched = try? await kugouClient94.fetchKey()
            else { return false }
            key = fetched
            Self.qrKeyCache98["kugou"] = (key, "", Date())
        }
        guard let qr = try? await kugouClient94.createQR(key: key),
              (qr.qrimgBase64?.isEmpty == false) || (qr.qrContent?.isEmpty == false)
        else { return false }
        Self.qrSlot98["kugou"] = (qr.key, qr.qrimgBase64, qr.qrContent, Date(), true)
        return true
    }

    // MARK: (99) 静默续期调度

    private static func startQRRenewTimer99(host: SeamMaster) {
        qrRenewHost99 = host
        guard qrRenewTimer99 == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { _ in
            guard let host = qrRenewHost99 else {
                qrRenewTimer99?.invalidate()
                qrRenewTimer99 = nil
                return
            }
            host.qrRenewTick99()
        }
        RunLoop.main.add(timer, forMode: .common)
        qrRenewTimer99 = timer
    }

    /// 续期 tick（15s）：停跑条件——无在册平台、距最近登
    /// 录上下文超 30 分钟（定时器自销，下次入册/开缝再
    /// 起）。单 tick 内：App 非活跃跳过（不补跑）；面板正
    /// 开着的平台由取码流自管过期刷新、不抢；已登录的平
    /// 台退册清槽；在册平台槽龄进入可用窗末 30s（留 ≥30s
    /// 余量）才静默重生成，槽缺失（曾失败）亦补生成（受
    /// pregenerateQR99 的 60s 尝试间隔约束）。
    private func qrRenewTick99() {
        if Self.qrEnrolled99.isEmpty {
            Self.qrRenewTimer99?.invalidate()
            Self.qrRenewTimer99 = nil
            return
        }
        guard let ctx = Self.qrLastCtx99,
              Date().timeIntervalSince(ctx) < 30 * 60 else {
            Self.qrRenewTimer99?.invalidate()
            Self.qrRenewTimer99 = nil
            return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        for prov in Array(Self.qrEnrolled99) {
            if SeamState85.qrOpen94, SeamState85.qrProvider94 == prov { continue }
            let provider: NativeSessionStore.Provider = prov == "kugou" ? .kugou : .qq
            if ProviderSessionStatusQuery.status(for: provider).isLoggedIn {
                Self.qrEnrolled99.remove(prov)
                Self.qrSlot98[prov] = nil
                continue
            }
            guard let slot = Self.qrSlot98[prov] else {
                pregenerateQR99(prov, renewal: true)
                continue
            }
            if Date().timeIntervalSince(slot.at) >= Self.qrWindow99(prov) - 30 {
                pregenerateQR99(prov, renewal: true)
            }
        }
    }
    private var qrAnimLink95: CADisplayLink?
    private var qrAnimLast95: CFTimeInterval = 0
    private var qrAnimMaxGap95: Double = 0
    private var qrAnimFrames95: Int = 0

    init(host: String) {
        host94 = host
        super.init(frame: .zero)
        build()
        // (94) 94-4 自证：每页缝构建落一行（avatar/qr 为母
        // 版槽位在岗标记：头像位与二维码切换区均已装配）。
        Breadcrumbs.log("p94 seam host=\(host) avatar=1 qr=1 ver=master")
        prefetchQRKeys98()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        playingCancellable?.cancel()
        qrAnimLink95?.invalidate()
        if qrFlowActive { coordinator94.cancelActive(reason: "seam94-deinit") }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        refreshAccount94()
        applyQRVisibility()
        if SeamState85.qrOpen94 && !qrFlowActive { startQRFlow() }
    }

    // MARK: 装配

    private func build() {
        backgroundColor = .clear
        addSubview(backdrop86)
        contentView.isUserInteractionEnabled = true
        addSubview(contentView)

        // 缝顶圆形头像（34pt，样片 32–36 档）：图层圆裁、
        // 白 0.35 描边环；无图时昵称首字/人形占位（与侧栏
        // WorkbenchAvatarView 同口径）。
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        avatarImageView.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarImageView)
        avatarFallbackLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarFallbackLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        avatarFallbackLabel.textAlignment = .center
        avatarFallbackLabel.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarFallbackLabel)
        avatarPlaceholderIcon.image = UIImage(
            systemName: "person.crop.circle.fill")
        avatarPlaceholderIcon.tintColor = UIColor.white.withAlphaComponent(0.45)
        avatarPlaceholderIcon.contentMode = .scaleAspectFit
        avatarPlaceholderIcon.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarPlaceholderIcon)
        avatarButton.layer.cornerRadius = 17
        avatarButton.layer.borderWidth = 1
        avatarButton.layer.borderColor =
            UIColor.white.withAlphaComponent(0.35).cgColor
        avatarButton.clipsToBounds = true
        avatarButton.accessibilityLabel = "账户头像，点击切换登录二维码"
        avatarButton.addTarget(self, action: #selector(avatarTapped),
                               for: .touchUpInside)
        contentView.addSubview(avatarButton)

        // 主区（页签/入口/胶囊）：常态整幅呈现；横屏矮高时
        // 内容纵滚（见 layoutSubviews 的 wantsScrollHit94）。
        mainScroll.showsVerticalScrollIndicator = false
        mainScroll.showsHorizontalScrollIndicator = false
        mainScroll.addSubview(mainContent)
        contentView.addSubview(mainScroll)

        // 头部语义行：主页＝「书库」标题（点按翻 64/120 档，
        // 沿既有 onToggleWide89）＋折叠钮；歌单页＝返回＋折叠。
        headerTitleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .heavy)
        headerTitleButton.setTitleColor(
            UIColor.white.withAlphaComponent(0.85), for: .normal)
        headerTitleButton.contentHorizontalAlignment = .left
        headerTitleButton.addTarget(self, action: #selector(headerTitleTapped),
                                    for: .touchUpInside)
        mainContent.addSubview(headerTitleButton)
        backButton.setImage(UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13, weight: .semibold)), for: .normal)
        backButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        backButton.accessibilityLabel = "返回"
        backButton.addTarget(self, action: #selector(backTapped),
                             for: .touchUpInside)
        mainContent.addSubview(backButton)
        foldButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 12, weight: .semibold)), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.55)
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped),
                             for: .touchUpInside)
        mainContent.addSubview(foldButton)

        // 页签行附注（歌单计数走此位，见 PlaylistSeam85View）。
        tabNoteLabel.font = .systemFont(ofSize: 11)
        tabNoteLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        tabNoteLabel.textAlignment = .center
        mainContent.addSubview(tabNoteLabel)

        // 四入口图标行（(93) C2 字形工厂复用：爱心/云/书本/
        // 服务器，SeamGlyph93、1.7 线宽、16px 光学尺寸）。
        for (index, glyph, label) in [
            (0, SeamGlyph93.Kind.heart, "我喜欢的音乐"),
            (1, SeamGlyph93.Kind.cloud, "云盘"),
            (2, SeamGlyph93.Kind.book, "日记本"),
            (3, SeamGlyph93.Kind.server, "Navidrome"),
        ] as [(Int, SeamGlyph93.Kind, String)] {
            let button = UIButton(type: .system)
            button.setImage(SeamGlyph93.image(glyph), for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.62)
            button.accessibilityLabel = label
            button.tag = index
            button.addTarget(self, action: #selector(entryTapped(_:)),
                             for: .touchUpInside)
            mainContent.addSubview(button)
            entryButtons.append(button)
        }

        // 排版胶囊（横排三段，主页/歌单页同一组件同一状态；
        // 字形与选中语言沿 (93) C3：白 pill＋深字形）。
        capsuleView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        capsuleView.layer.borderWidth = 0.5
        capsuleView.layer.borderColor =
            UIColor.white.withAlphaComponent(0.16).cgColor
        capsuleView.layer.cornerRadius = 18
        mainContent.addSubview(capsuleView)
        let capsuleGlyphs: [SeamGlyph93.Kind] = [.layoutGrid, .layoutList, .layoutAlbum]
        let capsuleNames = ["现行版式", "杂志式", "唱片架式"]
        for (index, glyph) in capsuleGlyphs.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(SeamGlyph93.image(glyph, pointSize: 16), for: .normal)
            // (95) 6b：写死 cornerRadius=15 废除——窄档钮宽
            // ≈17pt 时半径大于宽/2 被 CALayer 渲染成尖叶形；
            // 改在 layoutMainContent 按实际帧钳制为全圆角。
            button.tag = index
            button.accessibilityLabel = capsuleNames[index]
            button.addTarget(self, action: #selector(capsuleTapped(_:)),
                             for: .touchUpInside)
            capsuleView.addSubview(button)
            capsuleButtons.append(button)
        }
        refreshCapsule()

        buildQRPanel()
        buildFooter()

        // 播放态单一事实源：PlaybackEngine.$isPlaying（与两
        // 宿主点播台同一订阅口径），只刷中央钮字形。
        playingCancellable = PlaybackEngine.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.isPlaying94 = playing
                self?.refreshTransport()
            }
        refreshTransport()
        applyHeader()
        applyQRVisibility()
    }

    private func buildQRPanel() {
        // 缝中区原地切换的登录二维码区（样片 .seam-qr）：替
        // 换主区呈现、无浮层无遮罩；点头像或关闭钮切回。
        qrPanel.backgroundColor = UIColor.white.withAlphaComponent(0.045)
        qrPanel.layer.borderWidth = 0.5
        qrPanel.layer.borderColor =
            UIColor.white.withAlphaComponent(0.16).cgColor
        qrPanel.layer.cornerRadius = 16
        qrPanel.isHidden = true
        contentView.addSubview(qrPanel)
        qrTitleLabel.text = "扫码登录"
        qrTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        qrTitleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        qrPanel.addSubview(qrTitleLabel)
        qrCloseButton.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 10, weight: .semibold)), for: .normal)
        qrCloseButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        qrCloseButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        qrCloseButton.layer.cornerRadius = 13
        qrCloseButton.accessibilityLabel = "关闭二维码"
        qrCloseButton.addTarget(self, action: #selector(qrCloseTapped),
                                for: .touchUpInside)
        qrPanel.addSubview(qrCloseButton)
        for (index, title) in ["QQ 音乐", "酷狗音乐"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
            button.layer.cornerRadius = 9
            button.tag = index
            button.accessibilityLabel = title
            button.addTarget(self, action: #selector(qrTabTapped(_:)),
                             for: .touchUpInside)
            qrPanel.addSubview(button)
            qrTabButtons.append(button)
        }
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 10
        qrImageView.clipsToBounds = true
        qrImageView.contentMode = .scaleAspectFit
        qrPanel.addSubview(qrImageView)
        qrStatusLabel.font = .systemFont(ofSize: 11)
        qrStatusLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        qrStatusLabel.textAlignment = .center
        qrStatusLabel.numberOfLines = 2
        qrPanel.addSubview(qrStatusLabel)
        qrSpinner.color = .white
        qrSpinner.hidesWhenStopped = true
        qrPanel.addSubview(qrSpinner)
        refreshQRTabs()
    }

    private func buildFooter() {
        // 缝底播放区：上一首/暂停白圆钮/下一首——中央钮径
        // 38 与点播台中央钮同值，字形走 DeckGlyph82 同一工
        // 厂（prev/next 19、play/pause 20），三钮热区 ≥38。
        prevButton.setImage(DeckGlyph82.image(.prev, pointSize: 19), for: .normal)
        prevButton.tintColor = .white
        prevButton.accessibilityLabel = "上一首"
        prevButton.addTarget(self, action: #selector(prevTapped),
                             for: .touchUpInside)
        contentView.addSubview(prevButton)
        playButton.backgroundColor = .white
        playButton.layer.cornerRadius = 19
        playButton.tintColor = UIColor(red: 22.0 / 255, green: 22.0 / 255,
                                       blue: 27.0 / 255, alpha: 1)
        playButton.accessibilityLabel = "播放"
        playButton.addTarget(self, action: #selector(playTapped),
                             for: .touchUpInside)
        contentView.addSubview(playButton)
        nextButton.setImage(DeckGlyph82.image(.next, pointSize: 19), for: .normal)
        nextButton.tintColor = .white
        nextButton.accessibilityLabel = "下一首"
        nextButton.addTarget(self, action: #selector(nextTapped),
                             for: .touchUpInside)
        contentView.addSubview(nextButton)
    }

    // MARK: 数据配置（适配类调用）

    func setTabs(titles: [String], selected: Int, note: String?) {
        tabTitles = titles
        tabNote = note
        for button in tabButtons { button.removeFromSuperview() }
        tabButtons = []
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
            // (96) D：缩字号保护——先缩到 0.85（12pt 下限
            // ≈10.2pt）再允许尾截断，不许截到只剩一个点；
            // 0.66 档曾跌破可读下限（≈8pt），见 audit-95
            // §二.2 存疑项。
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.85
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.accessibilityLabel = title
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)),
                             for: .touchUpInside)
            mainContent.addSubview(button)
            tabButtons.append(button)
        }
        tabNoteLabel.text = note
        tabNoteLabel.isHidden = note == nil
        selectedTabIndex = max(0, min(selected, max(0, titles.count - 1)))
        refreshTabs()
        setNeedsLayout()
    }

    func setSelectedTab(_ index: Int) {
        selectedTabIndex = index
        refreshTabs()
    }

    func setTools(_ items: [ToolItem]) {
        toolItems = items
        for button in toolButtons { button.removeFromSuperview() }
        toolButtons = []
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(SeamGlyph93.image(item.glyph), for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.7)
            button.accessibilityLabel = item.label
            button.tag = index
            button.addTarget(self, action: #selector(toolTapped(_:)),
                             for: .touchUpInside)
            contentView.addSubview(button)
            toolButtons.append(button)
        }
        refreshTools()
        setNeedsLayout()
    }

    func setLayoutMode(_ mode: Int, notify: Bool) {
        layoutMode = max(0, min(2, mode))
        refreshCapsule()
        if notify { onLayoutMode?(layoutMode) }
    }

    // MARK: 选中态回刷

    private func applyHeader() {
        switch header {
        case .homeTitle(let title):
            headerTitleButton.setTitle(title, for: .normal)
            headerTitleButton.isHidden = false
            backButton.isHidden = true
        case .playlist:
            headerTitleButton.isHidden = true
            backButton.isHidden = false
        }
    }

    private func refreshTabs() {
        for (index, button) in tabButtons.enumerated() {
            // 缝页签选中语言（(86) 定版）：白 0.9 全圆 pill＋
            // 深色字；未选透明底＋white/62。
            let selected = index == selectedTabIndex
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.setTitleColor(selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.62), for: .normal)
            button.layer.cornerRadius = 14
        }
    }

    private func refreshCapsule() {
        for (index, button) in capsuleButtons.enumerated() {
            let selected = index == layoutMode
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.tintColor = selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.62)
        }
    }

    private func refreshTools() {
        for (index, button) in toolButtons.enumerated() {
            guard index < toolItems.count else { continue }
            let active = toolItems[index].tool == .expand && isExpanded94
            button.backgroundColor = active
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.tintColor = active
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.7)
            button.layer.cornerRadius = 13
        }
    }

    private func refreshTransport() {
        playButton.setImage(
            DeckGlyph82.image(isPlaying94 ? .pause : .play, pointSize: 20),
            for: .normal)
        playButton.accessibilityLabel = isPlaying94 ? "暂停" : "播放"
    }

    // MARK: 头像（(92) 定案同源：侧栏三家头像行同一资料
    // 缓存 ProviderSessionStatusQuery＋同一 WorkbenchCover
    // .loadAvatar 加载链＋同款 enrichProfile 自愈链）

    func refreshAccount94() {
        let statuses = ProviderSessionStatusQuery.allStatuses()
        let loggedIn = statuses.filter(\.isLoggedIn)
        let avatarStatus = loggedIn.first { $0.avatarURL != nil }
            ?? statuses.first { $0.avatarURL != nil }
        let name = loggedIn.first?.displayName ?? statuses.first?.displayName
        avatarHasName = !(name ?? "").isEmpty
        avatarFallbackLabel.text = name.flatMap { $0.first.map(String.init) }
        let key = avatarStatus?.avatarURL?.absoluteString
            ?? "none:\(name ?? "")"
        if key != avatarKey {
            avatarKey = key
            if let status = avatarStatus, let url = status.avatarURL {
                let expected = key
                WorkbenchCover.loadAvatar(url: url, into: avatarImageView,
                    completion: { [weak self] ok in
                        guard let self, self.avatarKey == expected else { return }
                        self.avatarFallbackLabel.isHidden = ok || !self.avatarHasName
                        self.avatarPlaceholderIcon.isHidden = ok || self.avatarHasName
                        Breadcrumbs.log(
                            "p94 seam avatar img=\(ok ? "ok" : "nil") src=\(status.provider.rawValue)")
                    },
                    isCurrent: { [weak self] in self?.avatarKey == expected })
            } else {
                avatarImageView.image = nil
                avatarFallbackLabel.isHidden = !avatarHasName
                avatarPlaceholderIcon.isHidden = avatarHasName
                Breadcrumbs.log("p94 seam avatar img=nil src=none")
            }
        }
        // 自愈链（与 WorkbenchOverlayHostView.enrichProfile92
        // 同源三路）：已登录但资料缺头像/昵称/VIP 的家，每家
        // 每进程补齐一次（母版两实例共享尝试集，不重复打）。
        for status in statuses
        where status.isLoggedIn
            && (status.avatarURL == nil || status.displayName == nil
                || status.vipLevel == nil)
            && !Self.enrichAttempted94.contains(status.provider.rawValue) {
            Self.enrichAttempted94.insert(status.provider.rawValue)
            enrichProfile94(for: status.provider)
        }
    }

    private func enrichProfile94(for provider: NativeSessionStore.Provider) {
        Task { [weak self] in
            switch provider {
            case .netease:
                guard let status = try? await NativeDataClient.shared.fetchLoginStatus(),
                      status.loggedIn else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .netease, accountId: status.userId,
                    displayName: status.nickname, avatarURLString: status.avatarURL)
                NativeSessionStore.shared.saveVIP(
                    provider: .netease, level: status.vipType)
            case .qq:
                let client = QQLoginClient()
                guard let cookie = NativeSessionStore.shared.qqCookieString(),
                      let profile = try? await client.fetchLoginStatus(cookie: cookie)
                else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .qq, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
                if let vip = await client.fetchVIPLevel(cookie: cookie) {
                    NativeSessionStore.shared.saveVIP(provider: .qq, level: vip)
                }
            case .kugou:
                let client = KugouLoginClient()
                guard let cookie = NativeSessionStore.shared.kugouCookieString(),
                      let profile = try? await client.fetchUserDetail(
                        cookie: cookie, userId: Self.kugouUserId94(in: cookie))
                else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .kugou, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
                if let initial = profile.vipLevel {
                    NativeSessionStore.shared.saveVIP(provider: .kugou, level: initial)
                }
                if let vip = await client.fetchVIPLevel(cookie: cookie) {
                    NativeSessionStore.shared.saveVIP(provider: .kugou, level: vip)
                }
            }
            Breadcrumbs.log("p94 seam enrich provider=\(provider.rawValue)")
            await MainActor.run { self?.refreshAccount94() }
        }
    }

    private static func kugouUserId94(in cookie: String) -> String? {
        for entry in cookie.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "userid" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: 二维码（取码/轮询沿 LoginViewController 网页版
    // 登录流：QQLoginClient/KugouLoginClient 三步＋
    // PollingCoordinator 代次纪律＋落存前同款校验与复核；
    // 不新造端点、不新造落存形态）

    private var qrProvider: NativeSessionStore.Provider {
        SeamState85.qrProvider94 == "kugou" ? .kugou : .qq
    }

    private func applyQRVisibility() {
        let open = SeamState85.qrOpen94
        if open { refreshQRTabs() }
        let incoming: UIView = open ? qrPanel : mainScroll
        let outgoing: UIView = open ? mainScroll : qrPanel
        // 未入窗（装配期）或已在终态：直接落终态，不播动画。
        guard window != nil,
              incoming.isHidden || incoming.alpha < 1 else {
            incoming.isHidden = false
            incoming.alpha = 1
            incoming.transform = .identity
            outgoing.isHidden = true
            outgoing.alpha = 1
            outgoing.transform = .identity
            return
        }
        // (95) 10：iOS 系统弹簧交叉淡化＋入场区轻位移
        // （4pt→0）；动画完成才置 outgoing 的 isHidden 终
        // 态，期间 .allowUserInteraction 不阻塞点按。
        startQRAnimProbe95()
        incoming.isHidden = false
        incoming.alpha = 0
        incoming.transform = CGAffineTransform(translationX: 0, y: 4)
        outgoing.isHidden = false
        outgoing.alpha = 1
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction,
                                 .beginFromCurrentState]) {
            incoming.alpha = 1
            incoming.transform = .identity
            outgoing.alpha = 0
        } completion: { [weak self] _ in
            outgoing.isHidden = true
            outgoing.alpha = 1
            outgoing.transform = .identity
            incoming.alpha = 1
            incoming.transform = .identity
            self?.stopQRAnimProbe95()
        }
    }

    // (95) 10：帧间隔自证——CADisplayLink 记最大帧间隔，
    // 动画结束落一行 p95 seam qr anim。
    private func startQRAnimProbe95() {
        qrAnimLink95?.invalidate()
        qrAnimLast95 = 0
        qrAnimMaxGap95 = 0
        qrAnimFrames95 = 0
        let link = CADisplayLink(target: self,
                                 selector: #selector(qrAnimTick95(_:)))
        link.add(to: .main, forMode: .common)
        qrAnimLink95 = link
    }

    @objc private func qrAnimTick95(_ link: CADisplayLink) {
        if qrAnimLast95 > 0 {
            let gap = (link.timestamp - qrAnimLast95) * 1000
            if gap > qrAnimMaxGap95 { qrAnimMaxGap95 = gap }
        }
        qrAnimLast95 = link.timestamp
        qrAnimFrames95 += 1
    }

    private func stopQRAnimProbe95() {
        qrAnimLink95?.invalidate()
        qrAnimLink95 = nil
        let maxgap = Int(qrAnimMaxGap95.rounded())
        Breadcrumbs.log("p95 seam qr anim maxgap=\(maxgap) frames=\(qrAnimFrames95)")
    }

    private func refreshQRTabs() {
        for (index, button) in qrTabButtons.enumerated() {
            let selected = (index == 0) == (qrProvider == .qq)
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.setTitleColor(selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.6), for: .normal)
        }
        qrStatusLabel.text = qrProvider == .qq
            ? "请使用 QQ 音乐 App 扫一扫登录" : "请使用酷狗音乐 App 扫一扫登录"
    }

    private func openQR94() {
        // 缺省平台：第一家未登录的（QQ 先、酷狗后）；都已登
        // 录时沿当前共享选择。
        if ProviderSessionStatusQuery.status(for: .qq).isLoggedIn == false {
            SeamState85.qrProvider94 = "qq"
        } else if ProviderSessionStatusQuery.status(for: .kugou).isLoggedIn == false {
            SeamState85.qrProvider94 = "kugou"
        }
        SeamState85.qrOpen94 = true
        applyQRVisibility()
        Breadcrumbs.log("p94 seam qr=open provider=\(qrProvider.rawValue)")
        startQRFlow()
    }

    private func closeQR94() {
        SeamState85.qrOpen94 = false
        if qrFlowActive {
            qrFlowActive = false
            coordinator94.cancelActive(reason: "seam94-qr-close")
        }
        qrSpinner.stopAnimating()
        applyQRVisibility()
    }

    private func startQRFlow() {
        let provider = qrProvider
        let gen = coordinator94.begin(provider: provider)
        qrFlowActive = true
        // (98) 第 5 条：计时起点＋双槽判定——本台槽未过前端有
        // 效窗（QQ 160s／酷狗 285s，各留 15s 余量）则复用其
        // key 续轮询；过期才清槽整链重跑。(95) 的 payload 解
        // 码缓存只在整链重跑时失效。
        qrT098 = Date()
        qrTotalLogged98 = false
        qrCacheHit98 = false
        qrReuseKey98 = nil
        qrPreHit99 = false
        // (99) 第 6 条：取码流启动即登录上下文——刷新续期
        // 上下文时刻并把本台入册（另一家首次切到即在此入
        // 册，此后与默认家同享预生成＋静默续期）。
        Self.qrLastCtx99 = Date()
        Self.qrEnrolled99.insert(provider.rawValue)
        Self.startQRRenewTimer99(host: self)
        if let slot = Self.qrSlot98[provider.rawValue],
           Date().timeIntervalSince(slot.at) < (provider == .qq ? 160 : 285) {
            qrReuseKey98 = slot.key
            qrCacheHit98 = true
            qrPreHit99 = slot.pre
            if slot.pre {
                Breadcrumbs.log("p99 qr pre prov=\(provider.rawValue) hit=1 ms=0")
            }
        } else {
            Self.qrSlot98[provider.rawValue] = nil
            qrCachedKey95 = nil
            qrCachedImage95 = nil
        }
        qrImageView.image = nil
        qrStatusLabel.text = "正在生成二维码…"
        qrSpinner.startAnimating()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runQRFlow(provider: provider, gen: gen)
        }
        coordinator94.attach(task, generation: gen)
    }

    private enum QRFlowOutcome { case done, refresh, fatal }

    private func runQRFlow(provider: NativeSessionStore.Provider, gen: Int) async {
        // QQ 后端 TTL 180 秒、前端 175 秒收手；酷狗 5 分钟
        // （LoginViewController 同口径）。
        let deadline = Date().addingTimeInterval(provider == .qq ? 175 : 5 * 60)
        while !Task.isCancelled, coordinator94.isCurrent(gen), Date() < deadline {
            let outcome = provider == .qq
                ? await runOneQQQRCode(gen: gen, deadline: deadline)
                : await runOneKugouQRCode(gen: gen, deadline: deadline)
            if outcome == .done || outcome == .fatal || Task.isCancelled {
                // 收尾摘除协调器登记（成功路径已在
                // qrLoginSucceeded 内 finish，此处幂等补位）；
                // 被新一代次取消时 isCurrent 为假、不动他人。
                await MainActor.run {
                    if self.coordinator94.isCurrent(gen) {
                        self.qrFlowActive = false
                        self.coordinator94.finish(generation: gen)
                        if outcome == .fatal {
                            self.qrSpinner.stopAnimating()
                        } else if Date() >= deadline {
                            self.qrStatusLabel.text = "二维码已过期，点头像重试"
                            self.qrSpinner.stopAnimating()
                        }
                    }
                }
                return
            }
        }
        if !coordinator94.isCurrent(gen) { return }
        await MainActor.run {
            if self.qrFlowActive {
                self.qrFlowActive = false
                self.coordinator94.finish(generation: gen)
                self.qrStatusLabel.text = "二维码已过期，点头像重试"
                self.qrSpinner.stopAnimating()
            }
        }
    }

    private func runOneQQQRCode(gen: Int, deadline: Date) async -> QRFlowOutcome {
        let qr: QQLoginClient.QRCode
        if let reuse = qrReuseKey98, let slot = Self.qrSlot98["qq"] {
            // (98) 第 5 条：双槽复用——跳过取码段直入轮询。
            qrReuseKey98 = nil
            qr = QQLoginClient.QRCode(key: reuse, qrimgBase64: slot.base64)
        } else {
          do {
            // (98) 第 5 条：channels 改会话缓存——缺省直接以
            // "qq" 发 key（静态回落集同口径），缓存缺席时后台
            // 补探测、不再每开必付串行探测跳；fetchKey 失败才
            // 回头探测 channels 换通道重试一次。
            var channel = "qq"
            if let chs = Self.qrChannels98, !chs.contains(channel) {
                channel = chs.first ?? channel
            }
            if Self.qrChannels98 == nil {
                Task { [weak self] in
                    guard let self else { return }
                    if let chs = await self.qqClient94.fetchChannels() {
                        Self.qrChannels98 = chs
                    }
                }
            }
            var key = ""
            if let kc = Self.qrKeyCache98["qq"], kc.channel == channel,
               Date().timeIntervalSince(kc.at) < 120 {
                key = kc.key
                qrCacheHit98 = true
                Breadcrumbs.log("p98 qr seg prov=qq stage=key ms=0 node=-1")
            } else {
                let kt0 = Date()
                do {
                    key = try await qqClient94.fetchKey(channel: channel)
                } catch {
                    let ct0 = Date()
                    guard let chs = await qqClient94.fetchChannels() else { throw error }
                    Self.qrChannels98 = chs
                    qrSeg98("qq", "ch", ct0)
                    let alt = chs.contains("qq") ? "qq" : (chs.first ?? channel)
                    guard alt != channel else { throw error }
                    channel = alt
                    key = try await qqClient94.fetchKey(channel: channel)
                }
                qrSeg98("qq", "key", kt0)
                Self.qrKeyCache98["qq"] = (key, channel, Date())
            }
            let ct0 = Date()
            qr = try await qqClient94.createQR(key: key)
            qrSeg98("qq", "create", ct0)
            Self.qrSlot98["qq"] = (qr.key, qr.qrimgBase64, nil, Date(), false)
          } catch {
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败，请检查网络后重试"
                self.qrSpinner.stopAnimating()
            }
            return .fatal
        }
        }
        if Task.isCancelled || !coordinator94.isCurrent(gen) { return .done }
        guard let image = qr.qrimgBase64, !image.isEmpty else {
            Breadcrumbs.log("login.qq.fail reason=no-qrimg")
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败（后端未回图），请重试"
                self.qrSpinner.stopAnimating()
            }
            return .fatal
        }
        await MainActor.run {
            self.showQRImage(base64: image, content: nil)
            self.qrTotal98("qq")
            self.qrStatusLabel.text = "请用 QQ 扫码"
            self.qrSpinner.stopAnimating()
        }
        while !Task.isCancelled, coordinator94.isCurrent(gen), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || !coordinator94.isCurrent(gen) { return .done }
            let result: QQLoginClient.CheckResult
            do {
                result = try await qqClient94.check(key: qr.key)
            } catch {
                continue // 单次轮询失败不终止（LoginViewController 同口径）。
            }
            switch result {
            case .waiting, .unknown:
                break
            case .scanned:
                await MainActor.run { self.qrStatusLabel.text = "已扫码，请在手机上确认登录" }
            case .expired:
                Breadcrumbs.log("login.qq.expired")
                await MainActor.run { self.qrStatusLabel.text = "二维码已过期，正在刷新…" }
                return .refresh
            case .failed:
                Breadcrumbs.log("login.qq.fail reason=upstream-rejected")
                await MainActor.run {
                    self.qrStatusLabel.text = "登录被上游拒绝，请稍后重试"
                    self.qrSpinner.stopAnimating()
                }
                return .fatal
            case .authorized(let cookie):
                guard coordinator94.isCurrent(gen) else { return .done }
                return await handleQQAuthorized94(cookie, gen: gen)
            }
        }
        return .done
    }

    private func handleQQAuthorized94(_ cookie: String, gen: Int) async -> QRFlowOutcome {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NativeSessionStore.isValidQQCookie(value) else {
            Breadcrumbs.log("login.qq.fail reason=invalid-cookie len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "登录回包异常（会话校验未过），请重试"
            }
            return .fatal
        }
        let expires = Date().addingTimeInterval(3 * 24 * 3600)
        guard NativeSessionStore.shared.saveQQSession(
            cookie: value, accountId: nil, displayName: nil,
            loginType: 2, expiresAt: expires) else {
            Breadcrumbs.log("login.qq.fail reason=keychain-write len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "会话保存失败，请重试"
            }
            return .fatal
        }
        Breadcrumbs.log("login.qq.success len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
        // login_status 复核（LoginViewController 同判据）：后
        // 端不认只清 QQ 本家；网络失败按 transient 保留会话。
        do {
            if let profile = try await qqClient94.fetchLoginStatus(cookie: value) {
                NativeSessionStore.shared.saveProfile(
                    provider: .qq, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
                _ = NativeSessionStore.shared.saveQQSession(
                    cookie: value, accountId: profile.accountId,
                    displayName: profile.nickname, loginType: 2, expiresAt: expires)
            } else {
                let verdict = NativeSessionStore.classifyAuthFailure(
                    provider: .qq, httpStatus: 200, businessCode: nil,
                    errorCode: nil, hasProfile: false)
                if verdict == .sessionInvalid {
                    Breadcrumbs.log("login.qq.fail reason=status-unrecognized")
                    NativeSessionStore.shared.clear(provider: .qq, reason: "status-unrecognized")
                    await MainActor.run {
                        self.qrStatusLabel.text = "后端未确认登录，请重试"
                        self.qrSpinner.stopAnimating()
                    }
                    return .fatal
                }
            }
        } catch {
            Breadcrumbs.log("login.qq.status-check result=transient")
        }
        await MainActor.run { self.qrLoginSucceeded(provider: .qq, gen: gen) }
        return .done
    }

    private func runOneKugouQRCode(gen: Int, deadline: Date) async -> QRFlowOutcome {
        let qr: KugouLoginClient.QRCode
        if let reuse = qrReuseKey98, let slot = Self.qrSlot98["kugou"] {
            qrReuseKey98 = nil
            qr = KugouLoginClient.QRCode(key: reuse, qrimgBase64: slot.base64,
                                         qrContent: slot.content)
        } else {
          do {
            var key = ""
            if let kc = Self.qrKeyCache98["kugou"],
               Date().timeIntervalSince(kc.at) < 120 {
                key = kc.key
                qrCacheHit98 = true
                Breadcrumbs.log("p98 qr seg prov=kugou stage=key ms=0 node=-1")
            } else {
                let kt0 = Date()
                key = try await kugouClient94.fetchKey()
                qrSeg98("kugou", "key", kt0)
                Self.qrKeyCache98["kugou"] = (key, "", Date())
            }
            let ct0 = Date()
            qr = try await kugouClient94.createQR(key: key)
            qrSeg98("kugou", "create", ct0)
            Self.qrSlot98["kugou"] = (qr.key, qr.qrimgBase64, qr.qrContent, Date(), false)
          } catch {
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败，请检查网络后重试"
                self.qrSpinner.stopAnimating()
            }
            return .fatal
        }
        }
        if Task.isCancelled || !coordinator94.isCurrent(gen) { return .done }
        await MainActor.run {
            self.showQRImage(base64: qr.qrimgBase64, content: qr.qrContent)
            self.qrTotal98("kugou")
            self.qrStatusLabel.text = "请用酷狗音乐 App 扫码"
            self.qrSpinner.stopAnimating()
        }
        while !Task.isCancelled, coordinator94.isCurrent(gen), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || !coordinator94.isCurrent(gen) { return .done }
            let result: KugouLoginClient.CheckResult
            do {
                result = try await kugouClient94.check(key: qr.key)
            } catch {
                continue
            }
            switch result {
            case .waiting, .unknown:
                break
            case .scanned:
                await MainActor.run { self.qrStatusLabel.text = "已扫码，请在手机上确认登录" }
            case .expired:
                Breadcrumbs.log("login.kugou.expired")
                await MainActor.run { self.qrStatusLabel.text = "二维码已过期，正在刷新…" }
                return .refresh
            case .failed:
                Breadcrumbs.log("login.kugou.fail reason=check-failed")
                await MainActor.run {
                    self.qrStatusLabel.text = "登录失败，请重试"
                    self.qrSpinner.stopAnimating()
                }
                return .fatal
            case .authorized(let cookie, let userId):
                guard coordinator94.isCurrent(gen) else { return .done }
                return await handleKugouAuthorized94(cookie, userId: userId, gen: gen)
            }
        }
        return .done
    }

    private func handleKugouAuthorized94(_ cookie: String, userId: String,
                                          gen: Int) async -> QRFlowOutcome {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NativeSessionStore.shared.saveKugouCookie(value) else {
            Breadcrumbs.log("login.kugou.fail reason=invalid-or-write len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "登录回包异常（会话校验未过），请重试"
            }
            return .fatal
        }
        Breadcrumbs.log("login.kugou.success len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
        // 新会话先显式清旧资料再只存 accountId（LoginView-
        // Controller 同口径，防串号），detail 复核补资料。
        NativeSessionStore.shared.saveProfile(
            provider: .kugou, accountId: nil, displayName: nil, avatarURLString: nil)
        NativeSessionStore.shared.saveProfile(
            provider: .kugou, accountId: userId, displayName: nil, avatarURLString: nil)
        do {
            let profile = try await kugouClient94.fetchUserDetail(
                cookie: value, userId: userId)
            NativeSessionStore.shared.saveProfile(
                provider: .kugou, accountId: profile.accountId ?? userId,
                displayName: profile.nickname,
                avatarURLString: profile.avatarURLString)
        } catch ProviderLoginTransport.TransportError.http(let status) {
            let verdict = NativeSessionStore.classifyAuthFailure(
                provider: .kugou, httpStatus: status, businessCode: nil,
                errorCode: nil, hasProfile: nil)
            if verdict == .sessionInvalid {
                Breadcrumbs.log("login.kugou.fail reason=status-rejected status=\(status)")
                NativeSessionStore.shared.clear(provider: .kugou, reason: "status-rejected")
                await MainActor.run {
                    self.qrStatusLabel.text = "后端未确认登录，请重试"
                    self.qrSpinner.stopAnimating()
                }
                return .fatal
            }
            Breadcrumbs.log("login.kugou.status-check result=transient status=\(status)")
        } catch {
            Breadcrumbs.log("login.kugou.status-check result=transient")
        }
        await MainActor.run { self.qrLoginSucceeded(provider: .kugou, gen: gen) }
        return .done
    }

    private func qrLoginSucceeded(provider: NativeSessionStore.Provider, gen: Int) {
        qrFlowActive = false
        // (99) 第 6 条：码已被消费且该家已登录——退出预生成
        // 在册并清槽，续期 tick 不再为它重生成。
        Self.qrEnrolled99.remove(provider.rawValue)
        Self.qrSlot98[provider.rawValue] = nil
        coordinator94.finish(generation: gen)
        Breadcrumbs.log("p94 seam qr login=\(provider.rawValue)")
        closeQR94()
        refreshAccount94()
    }

    /// 二维码图（LoginViewController 同式：base64 优先，缺
    /// 图用内容串本地生成；白瓷砖垫边统一在此）。
    /// (95) 10：解码＋tile 合成＋CIContext 出图全移后台队
    /// 列预生成、结果按 payload 缓存到实例属性；主线程只
    /// 赋值 imageView.image，不再卡切换关键路径。
    private func showQRImage(base64: String?, content: String?) {
        let key95 = (base64 ?? "") + "\u{1}" + (content ?? "")
        if qrCachedKey95 == key95, let cached = qrCachedImage95 {
            qrImageView.image = cached
            return
        }
        qrCachedKey95 = key95
        qrCachedImage95 = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var result: UIImage?
            if let raw = base64, !raw.isEmpty {
                let body = raw.contains(",")
                    ? String(raw.split(separator: ",", maxSplits: 1).last ?? "") : raw
                if let data = Data(base64Encoded: body),
                   let image = UIImage(data: data) {
                    result = Self.tileQR94(image)
                }
            }
            if result == nil, let content,
               let image = Self.makeQR94(text: content) {
                result = Self.tileQR94(image)
            }
            guard let result else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.qrCachedKey95 == key95 else { return }
                self.qrCachedImage95 = result
                self.qrImageView.image = result
            }
        }
    }

    private static func tileQR94(_ image: UIImage) -> UIImage {
        let tile: CGFloat = 240, code: CGFloat = 204
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(UIScreen.main.scale, 2)
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: tile, height: tile), format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: tile, height: tile))
            image.draw(in: CGRect(
                x: (tile - code) / 2, y: (tile - code) / 2,
                width: code, height: code))
        }
    }

    private static func makeQR94(text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: 点按

    @objc private func avatarTapped() {
        if SeamState85.qrOpen94 {
            Breadcrumbs.log("p94 seam qr=close src=avatar")
            closeQR94()
        } else {
            openQR94()
        }
    }

    @objc private func qrCloseTapped() {
        Breadcrumbs.log("p94 seam qr=close src=button")
        closeQR94()
    }

    @objc private func qrTabTapped(_ sender: UIButton) {
        let provider: NativeSessionStore.Provider = sender.tag == 0 ? .qq : .kugou
        guard provider != qrProvider || !qrFlowActive else { return }
        SeamState85.qrProvider94 = provider.rawValue
        refreshQRTabs()
        Breadcrumbs.log("p94 seam qr=open provider=\(provider.rawValue)")
        startQRFlow()
    }

    @objc private func headerTitleTapped() { onHeaderTitleTap?() }
    @objc private func backTapped() { onBack?() }
    @objc private func foldTapped() { onFold?() }

    @objc private func tabTapped(_ sender: UIButton) {
        selectedTabIndex = sender.tag
        refreshTabs()
        onTabSelected?(sender.tag)
    }

    @objc private func entryTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0: onEntry?(.liked)
        case 1: onEntry?(.cloud)
        case 2: onEntry?(.diary)
        default: onEntry?(.navidrome)
        }
    }

    @objc private func capsuleTapped(_ sender: UIButton) {
        setLayoutMode(sender.tag, notify: true)
    }

    @objc private func toolTapped(_ sender: UIButton) {
        guard sender.tag < toolItems.count else { return }
        onTool?(toolItems[sender.tag].tool)
    }

    @objc private func prevTapped() {
        Breadcrumbs.log("p94 seam transport=prev host=\(host94)")
        QueueManager.shared.playPrevious()
    }

    @objc private func playTapped() {
        Breadcrumbs.log("p94 seam transport=play host=\(host94)")
        if isPlaying94 {
            PlaybackEngine.shared.pause()
        } else if let onPlayAll {
            onPlayAll()
        } else {
            PlaybackEngine.shared.togglePlayPause()
        }
    }

    @objc private func nextTapped() {
        Breadcrumbs.log("p94 seam transport=next host=\(host94)")
        QueueManager.shared.playNext(manual: true)
    }

    // MARK: 布局（横竖屏同一套相对排版；缝宽由宿主帧给、
    // 两态同值，旋转只重排不丢二维码展开态——展开态在
    // SeamState85 共享存储、布局不回写）

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop86.frame = bounds
        let top = contentTopInset
        let contentH = max(0, bounds.height - contentTopInset - contentBottomInset)
        contentView.frame = CGRect(x: 0, y: top, width: bounds.width, height: contentH)
        let W = bounds.width
        let H = contentH
        // 内容列宽：窄缝用满宽；展开档（300）收列居中，不拉伸。
        // 宿主开合补间会经过极小宽度，列宽下限 44 防负尺寸帧。
        let contentW = W <= 140 ? max(W, 44) : min(W, 220)
        let contentX = max(0, (W - contentW) / 2)

        // 头像 34 居中顶部。
        avatarButton.frame = CGRect(x: (W - 34) / 2, y: 0, width: 34, height: 34)
        avatarImageView.frame = avatarButton.bounds
        avatarImageView.layer.cornerRadius = 17
        avatarFallbackLabel.frame = avatarButton.bounds
        avatarPlaceholderIcon.frame = CGRect(
            x: 6, y: 6, width: 22, height: 22)

        // 缝底两排：工具排（窄缝 2 行/宽档 1 行）＋播放区
        // （窄档纵排 102 / 宽档横排 44）。
        let toolRows = contentW < 100 ? 2 : 1
        let toolsH: CGFloat = toolRows == 2 ? 56 : 30
        // (96) D：窄档（contentW<100，如主页缝 64）播放区
        // 改纵排专属形态——三钮 30×30、间距 6、纵向总高
        // 3*30+2*6=102，居中于 centerX；footerH 相应改
        // toolsH+6+102。宽档保持现行 span95 公式不动。
        let narrowTransport96 = contentW < 100
        let transportH96: CGFloat = narrowTransport96 ? 102 : 44
        let footerH = toolsH + 6 + transportH96
        let footerY = H - footerH
        layoutTools(contentX: contentX, contentW: contentW,
                    y: footerY, height: toolsH, rows: toolRows)
        let transportY = footerY + toolsH + 6
        let centerX = W / 2
        if narrowTransport96 {
            // 纵排几何（64 档复算）：钮 x∈[centerX−15,
            // centerX+15]⊂缝界；y 段 [transportY,
            // transportY+30] / [+36,+66] / [+72,+102]，
            // 间距 6 互不重叠，总高 102＝footerH 余量，
            // 末钮底边恰为内容区底边。
            let bx96 = centerX - 15
            prevButton.frame = CGRect(x: bx96, y: transportY,
                                      width: 30, height: 30)
            playButton.frame = CGRect(x: bx96, y: transportY + 36,
                                      width: 30, height: 30)
            nextButton.frame = CGRect(x: bx96, y: transportY + 72,
                                      width: 30, height: 30)
        } else {
            // (95) 6d：三钮跨度随缝内容宽自适应（旧固定总跨
            // 120 在 64 窄缝双侧各出界 28pt）；play 居中 38 不
            // 变，prev/next 中心 = centerX ∓ (span/2 − 19)，
            // 宽档（contentW≥120）时 span=120 与旧视觉一致。
            let span95 = min(120, contentW - 8)
            let side95 = span95 / 2 - 19
            prevButton.frame = CGRect(x: centerX - side95 - 19, y: transportY + 3,
                                      width: 38, height: 38)
            playButton.frame = CGRect(x: centerX - 19, y: transportY + 3,
                                      width: 38, height: 38)
            nextButton.frame = CGRect(x: centerX + side95 - 19, y: transportY + 3,
                                      width: 38, height: 38)
        }

        // 主区/二维码区共用同一矩形（原地切换）。
        let mainY: CGFloat = 40
        let mainH = max(0, footerY - mainY - 6)
        mainScroll.frame = CGRect(x: contentX, y: mainY,
                                  width: contentW, height: mainH)
        let required = layoutMainContent(contentW: contentW)
        mainContent.frame = CGRect(
            x: 0, y: 0, width: contentW, height: max(required, mainH))
        mainScroll.contentSize = mainContent.frame.size
        wantsScrollHit94 = required > mainH + 1
        mainScroll.panGestureRecognizer.isEnabled = wantsScrollHit94

        qrPanel.frame = CGRect(x: contentX, y: mainY,
                               width: contentW, height: mainH)
        layoutQRPanel(contentW: contentW, height: mainH)
    }

    private func layoutTools(contentX: CGFloat, contentW: CGFloat,
                             y: CGFloat, height: CGFloat, rows: Int) {
        let count = max(1, toolButtons.count)
        if rows == 2 {
            let cols = 3
            let cellW = contentW / CGFloat(cols)
            let cellH = height / 2
            for (index, button) in toolButtons.enumerated() {
                let col = CGFloat(index % cols), row = CGFloat(index / cols)
                button.frame = CGRect(
                    x: contentX + col * cellW + (cellW - 28) / 2,
                    y: y + row * cellH + (cellH - 26) / 2,
                    width: 28, height: 26)
            }
        } else {
            let cellW = contentW / CGFloat(count)
            for (index, button) in toolButtons.enumerated() {
                button.frame = CGRect(
                    x: contentX + cellW * CGFloat(index) + (cellW - 30) / 2,
                    y: y + (height - 30) / 2, width: 30, height: 30)
            }
        }
    }

    /// 主区排版（坐标在 mainContent 内），返回内容总高。
    private func layoutMainContent(contentW: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        // 头部语义行 30。
        switch header {
        case .homeTitle:
            headerTitleButton.frame = CGRect(x: 4, y: y, width: contentW - 44, height: 30)
            foldButton.frame = CGRect(x: contentW - 34, y: y, width: 32, height: 30)
        case .playlist:
            backButton.frame = CGRect(x: 2, y: y, width: 32, height: 30)
            foldButton.frame = CGRect(x: contentW - 34, y: y, width: 32, height: 30)
        }
        y += 34
        // 页签行：逐签横排 pill（文字横排，不再竖拆单字）。
        for button in tabButtons {
            button.frame = CGRect(x: 4, y: y, width: contentW - 8, height: 28)
            y += 31
        }
        if tabNote != nil {
            tabNoteLabel.frame = CGRect(x: 4, y: y - 2, width: contentW - 8, height: 16)
            y += 16
        }
        y += 6
        // 四入口图标行：窄缝 2×2、宽档一行四枚（样片同式）。
        if contentW < 100 {
            for (index, button) in entryButtons.enumerated() {
                let col = CGFloat(index % 2), row = CGFloat(index / 2)
                button.frame = CGRect(
                    x: contentW / 2 - 32 + col * 34, y: y + row * 32,
                    width: 30, height: 30)
            }
            y += 64
        } else {
            let step = contentW / 4
            for (index, button) in entryButtons.enumerated() {
                button.frame = CGRect(
                    x: step * CGFloat(index), y: y, width: step, height: 34)
            }
            y += 34
        }
        y += 10
        // 排版胶囊：横排三段（窄缝 62 宽、宽档 132 宽）。
        let capsuleW: CGFloat = contentW < 100 ? 62 : min(132, contentW - 8)
        capsuleView.frame = CGRect(
            x: (contentW - capsuleW) / 2, y: y, width: capsuleW, height: 36)
        let inner = capsuleW - 6
        let buttonW = (inner - 4) / 3
        for (index, button) in capsuleButtons.enumerated() {
            button.frame = CGRect(
                x: 3 + CGFloat(index) * (buttonW + 2), y: 3,
                width: buttonW, height: 30)
            // (95) 6b：全圆角 pill——半径按实际尺寸钳制，
            // 帧（宽档/窄档）变化时随布局更新。
            button.layer.cornerRadius =
                min(button.frame.width, button.frame.height) / 2
        }
        y += 36
        return y
    }

    private func layoutQRPanel(contentW: CGFloat, height: CGFloat) {
        qrTitleLabel.frame = CGRect(x: 8, y: 6, width: contentW - 44, height: 16)
        qrCloseButton.frame = CGRect(x: contentW - 32, y: 2, width: 26, height: 26)
        var y: CGFloat = 30
        if contentW >= 100 {
            let cellW = (contentW - 19) / 2
            for (index, button) in qrTabButtons.enumerated() {
                button.frame = CGRect(
                    x: 8 + CGFloat(index) * (cellW + 3), y: y,
                    width: cellW, height: 26)
                button.layer.cornerRadius = 13
            }
            y += 32
        } else {
            for (index, button) in qrTabButtons.enumerated() {
                button.frame = CGRect(
                    x: 6, y: y + CGFloat(index) * 27, width: contentW - 12, height: 25)
                button.layer.cornerRadius = 9
            }
            y += 56
        }
        let statusH: CGFloat = 30
        let qrSize = max(40, min(contentW - 12, height - y - statusH - 14))
        qrImageView.frame = CGRect(
            x: (contentW - qrSize) / 2, y: y, width: qrSize, height: qrSize)
        qrSpinner.center = qrImageView.center
        qrStatusLabel.frame = CGRect(
            x: 6, y: y + qrSize + 4, width: contentW - 12, height: statusH)
    }

    /// 命中放行判定（适配类 hitTest 共用）：滚动视图仅在
    /// 内容溢出（横屏矮高）时接本体命中，其余背景穿透。
    func scrollHitView94(_ view: UIView) -> Bool {
        view === mainScroll && wantsScrollHit94
    }
}

/// (94) 94-4：主页缝适配——只供数据（页签标题/选中态/
/// 宽档）与语义回调转发，构成全在 SeamMaster。
/// 命中纪律同 (84) 侧栏：hitTest 只认控件本体，缝背景一
/// 律穿透——缝随墙走、不是拖动把手（主区滚动溢出时例外
/// 见 SeamMaster.wantsScrollHit94）。
final class HomeSeam85View: UIView {

    var onFold: (() -> Void)?
    var onPlaylists: (() -> Void)?
    var onRadio: (() -> Void)?
    /// (89)B b-seam-tabs：补探索/Navidrome 两页签（网页
    /// resolveHomeTabs 原序），tag 2/5。
    var onExplore: (() -> Void)?
    var onAlbums: (() -> Void)?
    var onLocal: (() -> Void)?
    var onNavidrome: (() -> Void)?
    /// (89)B b-seam-narrow：点「书库」标题切换 64/120 档。
    var onToggleWide89: (() -> Void)?
    var onLiked: (() -> Void)?
    /// (86) 第 1 条：直达入口补云盘列（网页双列同式）。
    var onCloud: (() -> Void)?
    var onSearch: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQueue: (() -> Void)?
    var onMore: (() -> Void)?
    /// (93) C1：缝底工具排控制台入口（宿主接
    /// ConsolePanel82.present，与台面控制台钮同一落点）。
    var onConsole93: (() -> Void)?
    /// (93) C2：四入口图标行日记本（喜欢/云盘/Navidrome
    /// 复用既有 onLiked/onCloud/onNavidrome 闭包不动）。
    var onDiary93: (() -> Void)?

    /// (92) 任务 11：版式切换——写歌单页同一持久化键
    /// foliaPlaylistLayout91（宿主经 onLayoutMode92 落键＋
    /// 落痕，歌单页出现时重读对齐）；母版胶囊即本开关。
    var onLayoutMode92: ((Int) -> Void)?
    var layoutMode92: Int =
        UserDefaults.standard.integer(forKey: "foliaPlaylistLayout91") {
        didSet { master.setLayoutMode(layoutMode92, notify: false) }
    }

    /// 内容纵向内边距（宿主按工具条/点播台占位设定）。
    var contentTopInset: CGFloat {
        get { master.contentTopInset }
        set { master.contentTopInset = newValue }
    }
    var contentBottomInset: CGFloat {
        get { master.contentBottomInset }
        set { master.contentBottomInset = newValue }
    }
    /// 内容淡出（宿主按渲染开口逐帧喂，见 SeamState85）。
    var contentOpacity: CGFloat {
        get { master.contentOpacity }
        set { master.contentOpacity = newValue }
    }

    /// (89)B b-seam-tabs：一级页签标题（网页 resolveHome-
    /// Tabs 原序），tag 与下标同序 0-5。
    private let tabTitles89 = ["歌单", "电台", "探索", "专辑", "本地", "Navidrome"]

    /// (89)B b-seam-tabs：当前选中页签下标（默认 0＝歌单）；
    /// 宿主赋值即转发母版回刷选中态。
    var selectedTabIndex: Int = 0 {
        didSet { master.setSelectedTab(selectedTabIndex) }
    }

    /// (89)B b-seam-narrow：宽档（120）排版开关，转发母版
    /// （只改入口/工具排折法，母版构成不变）。
    var displayWide89: Bool = false {
        didSet { master.displayWide = displayWide89 }
    }

    private let master = SeamMaster(host: "home")

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        backgroundColor = .clear
        master.header = .homeTitle("书库")
        master.setTabs(titles: tabTitles89, selected: selectedTabIndex, note: nil)
        master.setLayoutMode(layoutMode92, notify: false)
        master.setTools([
            SeamMaster.ToolItem(tool: .search, glyph: .search, label: "搜索"),
            SeamMaster.ToolItem(tool: .settings, glyph: .gear, label: "设置"),
            SeamMaster.ToolItem(tool: .queue, glyph: .list, label: "队列"),
            SeamMaster.ToolItem(tool: .more, glyph: .more, label: "更多"),
            SeamMaster.ToolItem(tool: .console, glyph: .consoleNotes, label: "控制台"),
        ])
        master.onHeaderTitleTap = { [weak self] in self?.libraryTapped89() }
        master.onFold = { [weak self] in self?.foldTapped() }
        master.onTabSelected = { [weak self] index in self?.dispatchTab(index) }
        master.onEntry = { [weak self] entry in
            switch entry {
            case .liked: self?.likedTapped()
            case .cloud: self?.cloudTapped()
            case .diary: self?.diaryTapped93()
            case .navidrome: self?.naviIconTapped93()
            }
        }
        master.onLayoutMode = { [weak self] mode in
            self?.layoutMode92 = mode
            self?.onLayoutMode92?(mode)
        }
        master.onTool = { [weak self] tool in
            switch tool {
            case .search: self?.searchTapped()
            case .settings: self?.settingsTapped()
            case .queue: self?.queueTapped()
            case .more: self?.moreTapped()
            case .console: self?.consoleTapped93()
            case .append, .expand: break
            }
        }
        addSubview(master)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        master.frame = bounds
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl || master.scrollHitView94(view) { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 点按（逐项落痕 sidebar85，沿既有口径）

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    private func dispatchTab(_ index: Int) {
        // (89)B b-seam-tabs：tag 与 tabTitles89 同序 0-5
        // （探索 2、Navidrome 5 为既有分发）。
        switch index {
        case 0:
            Breadcrumbs.log("sidebar85 tap dest=playlists")
            onPlaylists?()
        case 1:
            Breadcrumbs.log("sidebar85 tap dest=radio")
            onRadio?()
        case 2:
            Breadcrumbs.log("sidebar85 tap dest=explore")
            onExplore?()
        case 3:
            Breadcrumbs.log("sidebar85 tap dest=albums")
            onAlbums?()
        case 4:
            Breadcrumbs.log("sidebar85 tap dest=local")
            onLocal?()
        default:
            Breadcrumbs.log("sidebar85 tap dest=navidrome")
            onNavidrome?()
        }
    }

    /// (89)B b-seam-narrow：点「书库」标题切换 64/120 档
    /// （翻档与补间重排在宿主侧）。
    @objc private func libraryTapped89() {
        Breadcrumbs.log("sidebar85 tap dest=librarywide")
        onToggleWide89?()
    }

    @objc private func likedTapped() {
        Breadcrumbs.log("sidebar85 tap dest=liked")
        Breadcrumbs.log("p93 seam ent=liked")
        onLiked?()
    }

    @objc private func cloudTapped() {
        Breadcrumbs.log("sidebar85 tap dest=cloud")
        Breadcrumbs.log("p93 seam ent=cloud")
        onCloud?()
    }

    /// (93) C2：日记本入口（宿主接 DiaryBookViewController99，(100) 统一）。
    @objc private func diaryTapped93() {
        Breadcrumbs.log("p93 seam ent=diary")
        onDiary93?()
    }

    /// (93) C2：Navidrome 图标入口（复用既有 onNavidrome
    /// 页签落点，不新造通路）。
    @objc private func naviIconTapped93() {
        Breadcrumbs.log("p93 seam ent=navidrome")
        onNavidrome?()
    }

    /// (93) C1：控制台入口（宿主接 ConsolePanel82）。
    @objc private func consoleTapped93() {
        Breadcrumbs.log("sidebar85 tap dest=console")
        onConsole93?()
    }

    @objc private func searchTapped() {
        Breadcrumbs.log("sidebar85 tap dest=search")
        onSearch?()
    }

    @objc private func settingsTapped() {
        Breadcrumbs.log("sidebar85 tap dest=settings")
        onSettings?()
    }

    @objc private func queueTapped() {
        Breadcrumbs.log("sidebar85 tap dest=queue")
        onQueue?()
    }

    @objc private func moreTapped() {
        Breadcrumbs.log("sidebar85 tap dest=more")
        onMore?()
    }
}

/// (94) 94-4：歌单页缝适配——旧书脊式（竖排标题＋计数＋
/// 竖排胶囊＋大播放三角）整套退役，内部换 SeamMaster 母
/// 版；歌单语义映射：返回/折叠→母版头部语义行、播放全部
/// →缝底播放区中央钮、歌曲计数→页签行附注、歌单名→页签
/// 行横排标题（竖排标题溢出叠印 bug 随书脊退役消解，母
/// 版内无竖排标题）。展开档语义保留：母版工具排展开钮
/// 仍走 onExpandChange、宿主开口宽补间不变。
final class PlaylistSeam85View: UIView {

    var onBack: (() -> Void)?
    var onFold: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onAppendQueue: (() -> Void)?
    var onExpandChange: ((Bool) -> Void)?
    /// (93) C3：排版胶囊（与主页缝共享 SeamGlyph93 工厂与
    /// foliaPlaylistLayout91 单一状态，宿主经此回调写键＋
    /// 切换版式）；母版横排胶囊即本开关。
    var onLayoutMode93: ((Int) -> Void)?
    var layoutMode93: Int =
        UserDefaults.standard.integer(forKey: "foliaPlaylistLayout91") {
        didSet { master.setLayoutMode(layoutMode93, notify: false) }
    }
    /// (93) C1：控制台入口（宿主接 ConsolePanel82，与台面
    /// 控制台钮同一落点）。
    var onConsole93: (() -> Void)?
    /// (94) 94-4 母版补位（新增可选回调，既有签名不变；
    /// 宿主接线见交付报告最小改动清单）：四入口图标行与
    /// 缝底工具排的搜索/设置——母版构成全页一致，这两页
    /// 槽位先立、落点由宿主按主页缝同款接线后生效。
    var onLiked: (() -> Void)?
    var onCloud: (() -> Void)?
    var onDiary93: (() -> Void)?
    var onNavidrome: (() -> Void)?
    var onSearch94: (() -> Void)?
    var onSettings94: (() -> Void)?

    var contentTopInset: CGFloat {
        get { master.contentTopInset }
        set { master.contentTopInset = newValue }
    }
    var contentBottomInset: CGFloat {
        get { master.contentBottomInset }
        set { master.contentBottomInset = newValue }
    }
    var contentOpacity: CGFloat {
        get { master.contentOpacity }
        set { master.contentOpacity = newValue }
    }

    private(set) var expanded = false

    private let master = SeamMaster(host: "wall")

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        backgroundColor = .clear
        master.header = .playlist
        master.setTabs(titles: ["歌单"], selected: 0, note: nil)
        master.setLayoutMode(layoutMode93, notify: false)
        master.setTools([
            SeamMaster.ToolItem(tool: .search, glyph: .search, label: "搜索"),
            SeamMaster.ToolItem(tool: .settings, glyph: .gear, label: "设置"),
            SeamMaster.ToolItem(tool: .append, glyph: .list, label: "加入队列"),
            SeamMaster.ToolItem(tool: .expand, glyph: .expandCorners, label: "展开信息条"),
            SeamMaster.ToolItem(tool: .console, glyph: .consoleNotes, label: "控制台"),
        ])
        master.onBack = { [weak self] in self?.backTapped() }
        master.onFold = { [weak self] in self?.foldTapped() }
        // 页签（歌单名）点按沿旧书脊标题语义：展开/收起。
        master.onTabSelected = { [weak self] _ in self?.expandTapped() }
        master.onEntry = { [weak self] entry in
            switch entry {
            case .liked:
                Breadcrumbs.log("p94 seam ent=liked host=wall")
                self?.onLiked?()
            case .cloud:
                Breadcrumbs.log("p94 seam ent=cloud host=wall")
                self?.onCloud?()
            case .diary:
                Breadcrumbs.log("p94 seam ent=diary host=wall")
                self?.onDiary93?()
            case .navidrome:
                Breadcrumbs.log("p94 seam ent=navidrome host=wall")
                self?.onNavidrome?()
            }
        }
        master.onLayoutMode = { [weak self] mode in
            self?.layoutMode93 = mode
            self?.onLayoutMode93?(mode)
        }
        master.onTool = { [weak self] tool in
            switch tool {
            case .search:
                Breadcrumbs.log("sidebar85 tap dest=search")
                self?.onSearch94?()
            case .settings:
                Breadcrumbs.log("sidebar85 tap dest=settings")
                self?.onSettings94?()
            case .append: self?.appendTapped()
            case .expand: self?.expandTapped()
            case .console: self?.consoleTapped93()
            case .queue, .more: break
            }
        }
        // 播放全部→缝底播放区中央钮（母版 onPlayAll 槽）。
        master.onPlayAll = { [weak self] in self?.playTapped() }
        addSubview(master)
        // port90（Miller 2026-11-26 20:27「都是歪的」）：缝身
        // 摆正、系统毛玻璃——母版 SeamBackdrop86 同口径沿用。
        Breadcrumbs.log("port90 seamtilt=0 glass=1")
    }

    /// 数据回填（标题/计数）：宿主在种子落地与条目变化时调。
    /// 歌单名→页签行横排标题、计数→页签行附注。
    func setPlaylist85(title: String, count: Int) {
        master.setTabs(
            titles: [title.isEmpty ? "歌单" : title],
            selected: 0, note: "\(count) 首")
    }

    func setExpanded85(_ expanded: Bool) {
        self.expanded = expanded
        master.isExpanded94 = expanded
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        master.frame = bounds
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl || master.scrollHitView94(view) { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 点按（逐项落痕 sidebar85，沿既有口径）

    @objc private func backTapped() {
        Breadcrumbs.log("sidebar85 tap dest=back")
        onBack?()
    }

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    @objc private func playTapped() {
        Breadcrumbs.log("sidebar85 tap dest=playall")
        onPlayAll?()
    }

    @objc private func appendTapped() {
        Breadcrumbs.log("sidebar85 tap dest=append")
        onAppendQueue?()
    }

    @objc private func expandTapped() {
        Breadcrumbs.log("sidebar85 tap dest=\(expanded ? "spine" : "expand")")
        onExpandChange?(!expanded)
    }

    /// (93) C1：控制台点按。
    @objc private func consoleTapped93() {
        Breadcrumbs.log("sidebar85 tap dest=console")
        onConsole93?()
    }
}
