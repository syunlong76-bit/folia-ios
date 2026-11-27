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

/// (85) 第 1 条：主页缝内容（书脊档 64，网页 BravaisSeam-
/// Home compact 同构成）：书库行 → 折叠钮 → 竖排页签
/// （歌单/电台/专辑/本地）→ 中段直达入口（我喜欢的音乐）
/// → 底部工具格（搜索/设置／队列/⋯）。
/// port88：账户头像位整件摘除（Miller 2026-11-25 定「头
/// 像全部去掉」，工坊基线同口径）；点头像定位随之退役。
/// 选中态两套（网页 fb3）：一级页签＝填色块；本面无二级
/// 切换（原生分区是独立面、经页签进入），中段直达入口
/// 是普通按钮形态、不冒充页签。
/// 命中纪律同 (84) 侧栏：hitTest 只认按钮本体，缝背景一
/// 律穿透——缝随墙走、不是拖动把手。
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
    /// (93) C1：缝底工具排补控制台入口（样片 lib-tools 第
    /// 五枚），宿主接 ConsolePanel82.present（与台面控制台
    /// 钮同一落点）。
    var onConsole93: (() -> Void)?
    /// (93) C2：四入口图标行补日记本（喜欢/云盘/Navidrome
    /// 复用既有 onLiked/onCloud/onNavidrome 闭包不动）。
    var onDiary93: (() -> Void)?

    /// (92) 任务 11：版式切换（现行/A/B）——Miller 令「页面
    /// 展示 ab 做到主页中间的缝」：开关落缝内原账户空区
    /// （直达双列与工具格之间），写歌单页同一持久化键
    /// foliaPlaylistLayout91（宿主经 onLayoutMode92 落键＋
    /// 落痕，歌单页出现时重读对齐）。
    var onLayoutMode92: ((Int) -> Void)?
    var layoutMode92: Int =
        UserDefaults.standard.integer(forKey: "foliaPlaylistLayout91") {
        didSet { refreshLayoutSwitch92() }
    }
    private let layoutSwitch92 = UIView()
    private var layoutButtons92: [UIButton] = []

    /// 内容纵向内边距（宿主按工具条/点播台占位设定）。
    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    /// 内容淡出（宿主按渲染开口逐帧喂，见 SeamState85）。
    var contentOpacity: CGFloat = 1 {
        didSet { contentView.alpha = contentOpacity }
    }

    /// (89)B b-seam-tabs：一级页签标题（网页 resolveHome-
    /// Tabs 原序），tag 与下标同序 0-5。横/竖两种标题形态
    /// 都由此表生成（竖排走 Seam85Text.vertical）。
    private let tabTitles89 = ["歌单", "电台", "探索", "专辑", "本地", "Navidrome"]

    /// (89)B b-seam-tabs：当前选中页签下标（默认 0＝歌单，
    /// 主页墙本体即歌单集）；宿主点哪个页签选哪个，不再
    /// 恒 0。赋值即刷新选中态。
    var selectedTabIndex: Int = 0 {
        didSet { refreshTabSelection() }
    }

    /// (89)B b-seam-narrow：宽档（120）排版开关。true 时
    /// layoutSubviews 走宽档：内容宽＝bounds.width、页签
    /// 横排整行、直达两整行、工具格底部一排；标题形态随
    /// 档切换（横排原文/竖排逐字）。
    var displayWide89: Bool = false {
        didSet { applyDisplayMode89() }
    }

    private let backdrop86 = SeamBackdrop86()
    private let contentView = UIView()
    private let libraryLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private var tabButtons: [UIButton] = []
    private let likedButton = UIButton(type: .system)
    private let cloudButton = UIButton(type: .system)
    /// (93) C2：四入口图标行新增两枚（日记本/服务器）。
    private let diaryButton93 = UIButton(type: .system)
    private let naviButton93 = UIButton(type: .system)
    private var toolButtons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        // port90：缝底改系统毛玻璃（SeamBackdrop86）；缝背景长按
        // 循环油画随油画退役（点播台长按切主题通路不动）。
        backgroundColor = .clear
        addSubview(backdrop86)
        contentView.isUserInteractionEnabled = true
        addSubview(contentView)

        // 书库标题（网页：extrabold＋字距 0.3em＋white/85）。
        libraryLabel.attributedText = NSAttributedString(
            string: "书库",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .kern: 3.6,
            ])
        libraryLabel.textAlignment = .center
        // (89)B b-seam-narrow：「书库」标题即 64/120 档切换
        // 钮（点按翻档，宿主经 onToggleWide89 走既有补间
        // 重排）。命中纪律随之放行标题本体（见 hitTest）。
        libraryLabel.isUserInteractionEnabled = true
        libraryLabel.addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(libraryTapped89)))
        contentView.addSubview(libraryLabel)

        // 折叠钮（网页：裸 chevron、white/55、无底衬）。
        foldButton.setImage(UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13, weight: .semibold)), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.55)
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped), for: .touchUpInside)
        contentView.addSubview(foldButton)

        // 一级页签（竖排）：歌单默认选中（主页墙当前面即
        // 歌单集，与 (84) 侧栏去向表一致）。字重改网页
        // bold；圆角在布局时按帧高取半成全圆 pill。
        // (89)B b-seam-tabs：4 → 6（补探索 tag2、Navidrome
        // tag5，网页 resolveHomeTabs 原序，见 tabTitles89）。
        for (index, title) in tabTitles89.enumerated() {
            let button = UIButton(type: .system)
            // port90：Navidrome（index 5）窄档横排单行，不走竖拆。
            button.setTitle(index == 5 ? title : Seam85Text.vertical(title),
                            for: .normal)
            button.titleLabel?.numberOfLines = index == 5 ? 1 : 0
            // (89) §5-8：缝页签字号对齐网页 14。
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            button.titleLabel?.textAlignment = .center
            button.accessibilityLabel = title
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            contentView.addSubview(button)
            tabButtons.append(button)
        }
        refreshTabSelection()

        // (93) C2：中段直达改四入口图标行（样片 .lib-icons
        // 定版）：爱心＝我喜欢的音乐、云＝云盘、书本＝日记
        // 本、服务器＝Navidrome，与缝底工具排同一套细线字
        // 形（SeamGlyph93、1.7 线宽、16px）。喜欢/云盘钮本
        // 体与既有 action 不动、只换字形面；排布见
        // layoutSubviews（窄档 2×2、宽档一行四枚）。
        for (button, glyph, title, action) in [
            (likedButton, SeamGlyph93.Kind.heart, "我喜欢的音乐", #selector(likedTapped)),
            (cloudButton, SeamGlyph93.Kind.cloud, "云盘", #selector(cloudTapped)),
            (diaryButton93, SeamGlyph93.Kind.book, "日记本", #selector(diaryTapped93)),
            (naviButton93, SeamGlyph93.Kind.server, "Navidrome", #selector(naviIconTapped93)),
        ] as [(UIButton, SeamGlyph93.Kind, String, Selector)] {
            button.setImage(SeamGlyph93.image(glyph), for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.62)
            button.accessibilityLabel = title
            button.addTarget(self, action: action, for: .touchUpInside)
            contentView.addSubview(button)
        }

        // port88：头像钮已摘除——本缝自上而下为书库行→折
        // 叠钮→页签→直达双列→工具格，无账户位。

        // (93) C1：缝底工具排重画——五枚全走 SeamGlyph93
        // （统一 1.7 线宽/圆头/16px 光学尺寸；设置＝标准齿
        // 轮形，SF gearshape 退役）；既有四钮 action 不动，
        // 第五枚控制台为新增闭包 onConsole93。
        for (glyph, label, action) in [
            (SeamGlyph93.Kind.search, "搜索", #selector(searchTapped)),
            (SeamGlyph93.Kind.gear, "设置", #selector(settingsTapped)),
            (SeamGlyph93.Kind.list, "队列", #selector(queueTapped)),
            (SeamGlyph93.Kind.more, "更多", #selector(moreTapped)),
            (SeamGlyph93.Kind.consoleNotes, "控制台", #selector(consoleTapped93)),
        ] as [(SeamGlyph93.Kind, String, Selector)] {
            let button = UIButton(type: .system)
            button.setImage(SeamGlyph93.image(glyph), for: .normal)
            // (86) 第 1 条：工具格去芯片底（网页裸图标
            // white/70、无底衬无圆角）。
            button.tintColor = UIColor.white.withAlphaComponent(0.7)
            button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside)
            contentView.addSubview(button)
            toolButtons.append(button)
        }
        // (92) 任务 11：版式开关——玻璃胶囊＋三态 A4 字形
        // （现行拼贴/A 杂志/B 唱片架，DeckGlyph82 手绘、三
        // 态轮廓互不混同），选中态走缝页签同语言（白 pill
        // ＋深字形）。帧位在 layoutSubviews 按可用带高自适
        // 应（带高不足 40 时隐藏，见彼处注释）。
        layoutSwitch92.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layoutSwitch92.layer.borderWidth = 0.5
        layoutSwitch92.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        layoutSwitch92.layer.cornerRadius = 18
        contentView.addSubview(layoutSwitch92)
        // (93) C3：胶囊字形换 SeamGlyph93 共享工厂（样片
        // 砖墙格/列表/专辑，16px、砖墙格 ×0.86 在工厂内）。
        let layoutGlyphs93: [SeamGlyph93.Kind] = [.layoutGrid, .layoutList, .layoutAlbum]
        let layoutNames92 = ["现行版式", "杂志式", "唱片架式"]
        for (index, glyph) in layoutGlyphs93.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(SeamGlyph93.image(glyph, pointSize: 16), for: .normal)
            button.layer.cornerRadius = 15
            button.tag = index
            button.accessibilityLabel = layoutNames92[index]
            button.addTarget(self, action: #selector(layoutModeTapped92(_:)),
                             for: .touchUpInside)
            layoutSwitch92.addSubview(button)
            layoutButtons92.append(button)
        }
        refreshLayoutSwitch92()

        // port88 见证：主页缝建成即无头像位（站点存活自证）。
        Breadcrumbs.log("port88 seam=avatarless host=home")
    }

    /// (92) 任务 11：版式开关选中态回刷（缝页签同语言）。
    private func refreshLayoutSwitch92() {
        for (index, button) in layoutButtons92.enumerated() {
            let selected = index == layoutMode92
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.tintColor = selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.62)
        }
    }

    @objc private func layoutModeTapped92(_ sender: UIButton) {
        layoutMode92 = sender.tag
        onLayoutMode92?(sender.tag)
    }

    /// (92) 任务 11：开关帧位——直达区底与工具格顶之间的
    /// 空带居中（窄档横胶囊 58 宽、宽档整行宽）；带高不足
    /// 40（横屏内容高被压扁、与缝内既有元素同级退化）时
    /// 隐藏，版式仍可经宽档/竖屏缝切换、歌单页重读生效。
    /// (93) C1：工具区几何单源（窄档五钮 2 列 3 行须更高
    /// 区、宽档一行五枚走旧 0.08H 区），胶囊带底与工具排
    /// 帧共用此数、不许两处各算。
    private func toolsZone93(H: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let height = displayWide89 ? 0.08 * H : 0.135 * H
        return (H - 0.025 * H - height, height)
    }

    private func layoutLayoutSwitch92(H: CGFloat, cx: CGFloat,
                                      contentW: CGFloat,
                                      shortcutsBottom: CGFloat) {
        let toolsTop = toolsZone93(H: H).top
        let bandTop = shortcutsBottom + 4
        let bandBottom = toolsTop - 4
        guard bandBottom - bandTop >= 40 else {
            layoutSwitch92.isHidden = true
            return
        }
        layoutSwitch92.isHidden = false
        let width: CGFloat = displayWide89 ? contentW - 20 : 62
        let height: CGFloat = 36
        let x: CGFloat = displayWide89 ? 10 : cx - width / 2
        let y = (bandTop + bandBottom) / 2 - height / 2
        layoutSwitch92.frame = CGRect(x: x, y: y, width: width, height: height)
        let inner = width - 6
        let buttonW = (inner - 4) / 3
        for (index, button) in layoutButtons92.enumerated() {
            button.frame = CGRect(
                x: 3 + CGFloat(index) * (buttonW + 2), y: 3,
                width: buttonW, height: height - 6)
        }
    }

    private func refreshTabSelection() {
        for (index, button) in tabButtons.enumerated() {
            // (89)B b-seam-tabs：选中下标改读 selectedTab-
            // Index（宿主同步），不再恒 0。
            let selected = index == selectedTabIndex
            // (86) 第 1 条：网页选中态——白 0.9 全圆 pill＋
            // 深色字；未选透明底＋white/62。（(85) 做反：
            // 白 0.13 方块底＋白字，审计三⑤定案走样。）
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.setTitleColor(selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.62), for: .normal)
        }
    }

    /// (89)B b-seam-narrow：档位形态切换——页签与直达钮
    /// 同时备横/竖两种标题，displayWide89 翻转时换标题、
    /// 对齐与字号，再走 layoutSubviews 的对应排版分支。
    private func applyDisplayMode89() {
        for (index, button) in tabButtons.enumerated() {
            let title = tabTitles89[index]
            // port90：Navidrome 窄档不竖拆单字母——横排单行小字呈现。
            button.setTitle(displayWide89 || index == 5
                ? title : Seam85Text.vertical(title), for: .normal)
            button.titleLabel?.numberOfLines = (index == 5 && !displayWide89) ? 1 : 0
            button.contentHorizontalAlignment = displayWide89 ? .left : .center
            button.contentEdgeInsets = displayWide89
                ? UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0) : .zero
        }
        // (93) C2：喜欢/云盘已图标化，两档同为图标面、无
        // 标题切换（字形/回调不变，仅重排，见 layoutSubviews）。
        libraryLabel.textAlignment = displayWide89 ? .left : .center
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop86.frame = bounds
        // (89)B b-seam-narrow：宽档内容宽＝bounds.width
        // （宿主给 120）；窄档维持 64 居中。
        let contentW: CGFloat = displayWide89 ? bounds.width : 64
        let top = contentTopInset
        let bottom = bounds.height - contentBottomInset
        let contentH = max(0, bottom - top)
        contentView.frame = CGRect(
            x: (bounds.width - contentW) / 2, y: top, width: contentW, height: contentH)
        let cx = contentW / 2
        let H = contentH
        // (86) 第 1 条：全改网页相对比例（BRAVAIS_HOME_
        // SEAM_GEOMETRY／WallParts 渲染同数，基准＝内容
        // 高 H；(85) 的固定 pt 排版整组退役）。
        // (89)B b-seam-narrow：宽档书库标题左对齐、折叠钮靠右。
        libraryLabel.frame = CGRect(
            x: displayWide89 ? 10 : 0, y: 0.028 * H,
            width: displayWide89 ? contentW - 20 : contentW,
            height: max(16, 0.022 * H))
        // (89) §5-7：折叠钮 28 → 36（网页缝图标钮 36×36）。
        foldButton.frame = displayWide89
            ? CGRect(x: contentW - 46, y: 0.066 * H, width: 36, height: 36)
            : CGRect(x: cx - 18, y: 0.066 * H, width: 36, height: 36)
        if displayWide89 {
            // (89)B b-seam-narrow 宽档排版：页签横排整行
            // （行高 36、宽＝内容宽−20、步距 40、起位仍
            // 0.118H；选中态仍白 pill、圆角取半行高）；直
            // 达改两整行横排（0.64H 起、行高 30、步距 34）；
            // 工具格改底部一排 4 图标（区位同窄档）。
            for (index, button) in tabButtons.enumerated() {
                button.frame = CGRect(
                    x: 10, y: 0.118 * H + CGFloat(index) * 40,
                    width: contentW - 20, height: 36)
                button.layer.cornerRadius = 18
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            }
            // (93) C2 宽档：四入口一行四枚等距（样片
            // .lib-icons 同式），行高 34、起位仍 0.64H。
            let entryStep = (contentW - 20) / 4
            for (index, button) in [likedButton, cloudButton,
                                    diaryButton93, naviButton93].enumerated() {
                button.frame = CGRect(
                    x: 10 + entryStep * CGFloat(index), y: 0.64 * H,
                    width: entryStep, height: 34)
            }
            // (93) C1 宽档：工具排一行五枚等距（样片
            // .lib-tools 同式）。
            let zone = toolsZone93(H: H)
            let toolStep = (contentW - 20) / 5
            for (index, button) in toolButtons.enumerated() {
                button.frame = CGRect(
                    x: 10 + toolStep * CGFloat(index),
                    y: zone.top + (zone.height - 28) / 2,
                    width: toolStep, height: 28)
            }
            // (92) 任务 11＋(93) C2：宽档版式开关（入口行底＝0.64H＋34）。
            layoutLayoutSwitch92(H: H, cx: cx, contentW: contentW,
                                 shortcutsBottom: 0.64 * H + 34)
            return
        }
        // port90 页签自适应排版：旧固定步距 0.07H/高 0.062H 下
        // Navidrome 竖拆 9 行必然瀑布压住「本地」。改：页签区
        // [max(0.118H, 折叠钮底+8), 0.615H] 六等分，签在步内
        // 居中、间距均匀、选中胶囊随签居中；普通签宽 30；
        // Navidrome 横排单行（字 9 bold、宽 56 横胶囊）。
        let tabsTop = max(0.118 * H, 0.066 * H + 36 + 8)
        let zoneBottom = 0.615 * H
        let step = max(0, (zoneBottom - tabsTop) / 6)
        let tabH = min(40, max(20, step - 5))
        for (index, button) in tabButtons.enumerated() {
            let y = tabsTop + CGFloat(index) * step + (step - tabH) / 2
            if index == 5 {
                button.frame = CGRect(x: cx - 28, y: y, width: 56, height: tabH)
                button.layer.cornerRadius = tabH / 2
                button.titleLabel?.font = .systemFont(ofSize: 9, weight: .bold)
            } else {
                button.frame = CGRect(x: cx - 15, y: y, width: 30, height: tabH)
                button.layer.cornerRadius = min(30, tabH) / 2
                button.titleLabel?.font = .systemFont(
                    ofSize: tabH >= 36 ? 14 : 12, weight: .bold)
            }
        }
        // (93) C2 窄档：四入口 2×2（缝宽 64 装不下一行四
        // 枚 28 命中格，折两行；列沿与工具格两列同沿
        // cx−30 起、列宽 32），区位仍 0.64H 起、高 62。
        let entryH: CGFloat = 62
        for (index, button) in [likedButton, cloudButton,
                                diaryButton93, naviButton93].enumerated() {
            let col = CGFloat(index % 2), row = CGFloat(index / 2)
            button.frame = CGRect(
                x: cx - 30 + col * 32, y: 0.64 * H + row * 31,
                width: 30, height: 30)
        }
        // (93) C1 窄档：工具格五钮 2 列 3 行（末行控制台
        // 居左列），区高走 toolsZone93、裸图标无底衬。
        let zone = toolsZone93(H: H)
        for (index, button) in toolButtons.enumerated() {
            let col = CGFloat(index % 2), row = CGFloat(index / 2)
            let cellH = zone.height / 3
            button.frame = CGRect(
                x: cx - 30 + col * 32 + 2,
                y: zone.top + row * cellH + (cellH - 26) / 2,
                width: 26, height: 26)
        }
        // (92) 任务 11：窄档版式开关（入口区底＝0.64H＋62）。
        layoutLayoutSwitch92(H: H, cx: cx, contentW: contentW,
                             shortcutsBottom: 0.64 * H + entryH)
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            // (89)B b-seam-narrow：书库标题是 64/120 档切换
            // 钮（手势挂标签本体），与控件同格放行；其余
            // 背景穿透纪律不变。
            if view is UIControl || view === libraryLabel { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // port88：账户回显（setAccount85）随头像摘除整组退役；
    // 账户态展示归设置页账户组与侧栏账户区，本缝不再回填。

    // port90：缝长按切主题已随油画背景退役（handler 删除）。

    // MARK: 点按（逐项落痕 sidebar85）

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    @objc private func tabTapped(_ sender: UIButton) {
        // (89)B b-seam-tabs：tag 与 tabTitles89 同序 0-5
        // （探索 2、Navidrome 5 为本包新增分发）。
        switch sender.tag {
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

    /// (93) C2：日记本入口（宿主接 DiaryViewController90）。
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

/// (85) 第 1 条：歌单页缝（网页 BravaisSeamCollection 同
/// 骨架）：书脊档（64）＝返回 ‹ → 折叠 → 竖排歌单名（点
/// 它展开）→ 竖排计数 → 播放钮 → 展开钮；展开档（300）
/// ＝返回＋横排标题＋计数＋播放全部/加入队列＋收起。
/// 构成与主页缝不同（集合的身份与动作）、骨架同。
final class PlaylistSeam85View: UIView {

    var onBack: (() -> Void)?
    var onFold: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onAppendQueue: (() -> Void)?
    var onExpandChange: ((Bool) -> Void)?
    /// (93) C3：歌单缝同款三段胶囊（与主页缝共享
    /// SeamGlyph93 工厂与 foliaPlaylistLayout91 单一状态，
    /// 宿主经此回调写键＋切换版式）。
    var onLayoutMode93: ((Int) -> Void)?
    var layoutMode93: Int =
        UserDefaults.standard.integer(forKey: "foliaPlaylistLayout91") {
        didSet { refreshLayoutSwitch93() }
    }
    /// (93) C1：展开档补控制台入口（宿主接 ConsolePanel82，
    /// 与台面控制台钮同一落点；书脊档空间不足不装）。
    var onConsole93: (() -> Void)?

    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    var contentOpacity: CGFloat = 1 {
        didSet {
            spineContent.alpha = contentOpacity
            fullContent.alpha = contentOpacity
        }
    }

    private(set) var expanded = false
    // port90（Miller 2026-11-26 20:27「都是歪的」）：(89)B 的 −4°
    // 倾斜容器整件取消、缝身摆正，覆盖 b-seam-tilt 裁定。
    private let backdrop86 = SeamBackdrop86()
    private let spineContent = UIView()
    private let fullContent = UIView()
    private let backButton = UIButton(type: .system)
    private let foldButton = UIButton(type: .system)
    private let titleButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    /// (93) C3：书脊三段胶囊（竖排，样片 .ab 同式）。
    private let layoutSwitch93 = UIView()
    private var layoutButtons93: [UIButton] = []
    /// (93) C1：展开档控制台钮（与播放全部/加入队列同式）。
    private let fullConsoleButton93 = UIButton(type: .system)
    // 展开档
    private let fullBackButton = UIButton(type: .system)
    private let fullTitleLabel = UILabel()
    private let fullMetaLabel = UILabel()
    private let fullPlayButton = UIButton(type: .system)
    private let fullAppendButton = UIButton(type: .system)
    private let fullFoldButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        // port90：缝底改系统毛玻璃（SeamBackdrop86，两缝同口径）；
        // 缝身摆正、三层直挂本体；缝长按切主题随油画退役。
        backgroundColor = .clear
        addSubview(backdrop86)
        addSubview(spineContent)
        addSubview(fullContent)
        fullContent.isHidden = true
        Breadcrumbs.log("port90 seamtilt=0 glass=1")

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = "返回"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        spineContent.addSubview(backButton)
        // port90：折叠钮与返回钮同为 chevron.left 相邻成「双箭头」，
        // 折叠改 xmark（语义＝折叠收起、无障碍标签不变）。
        foldButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped), for: .touchUpInside)
        spineContent.addSubview(foldButton)
        titleButton.titleLabel?.numberOfLines = 0
        titleButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        titleButton.titleLabel?.textAlignment = .center
        titleButton.setTitleColor(.white, for: .normal)
        titleButton.accessibilityLabel = "展开信息条"
        titleButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        spineContent.addSubview(titleButton)
        // port90：计数横排单行（旧竖排在 0.06H 帧高内溢出断行重叠）。
        countLabel.numberOfLines = 1
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        countLabel.textAlignment = .center
        spineContent.addSubview(countLabel)
        // 播放钮去底衬（网页书脊裸钮，同折叠钮口径）。
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.accessibilityLabel = "播放全部"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        spineContent.addSubview(playButton)
        // port88：书脊头像（(86) 第 3 条常驻位）整件摘除，
        // 计数与播放钮之间的 0.70H 段留空。
        // (93) C1：展开钮字形换 SeamGlyph93 四角（1.7 线宽，
        // SF arrow.up.left.and.arrow.down.right 退役）。
        expandButton.setImage(SeamGlyph93.image(.expandCorners), for: .normal)
        expandButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        expandButton.accessibilityLabel = "展开信息条"
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        spineContent.addSubview(expandButton)
        // (93) C3：书脊三段胶囊——玻璃竖胶囊＋三枚字形钮
        // （与主页缝同一 SeamGlyph93 工厂、同一选中语言：
        // 白 pill＋深字形）；帧位见 layoutSubviews。
        layoutSwitch93.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        layoutSwitch93.layer.borderWidth = 0.5
        layoutSwitch93.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        layoutSwitch93.layer.cornerRadius = 25
        spineContent.addSubview(layoutSwitch93)
        let layoutGlyphs93: [SeamGlyph93.Kind] = [.layoutGrid, .layoutList, .layoutAlbum]
        let layoutNames93 = ["现行版式", "杂志式", "唱片架式"]
        for (index, glyph) in layoutGlyphs93.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(SeamGlyph93.image(glyph, pointSize: 16), for: .normal)
            button.layer.cornerRadius = 15
            button.tag = index
            button.accessibilityLabel = layoutNames93[index]
            button.addTarget(self, action: #selector(layoutModeTapped93(_:)),
                             for: .touchUpInside)
            layoutSwitch93.addSubview(button)
            layoutButtons93.append(button)
        }
        refreshLayoutSwitch93()

        fullBackButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        fullBackButton.tintColor = .white
        fullBackButton.accessibilityLabel = "返回"
        fullBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        fullContent.addSubview(fullBackButton)
        fullTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        fullTitleLabel.textColor = .white
        fullTitleLabel.numberOfLines = 2
        fullContent.addSubview(fullTitleLabel)
        fullMetaLabel.font = .systemFont(ofSize: 12)
        fullMetaLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        fullContent.addSubview(fullMetaLabel)
        for (button, title, glyph, action) in [
            (fullPlayButton, "播放全部", "play.fill", #selector(playTapped)),
            (fullAppendButton, "加入队列", "text.badge.plus", #selector(appendTapped)),
        ] as [(UIButton, String, String, Selector)] {
            button.setImage(UIImage(systemName: glyph), for: .normal)
            button.setTitle("  " + title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.tintColor = .white
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            button.layer.cornerRadius = 12
            button.contentHorizontalAlignment = .left
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 0)
            button.accessibilityLabel = title
            button.addTarget(self, action: action, for: .touchUpInside)
            fullContent.addSubview(button)
        }
        fullFoldButton.setTitle("收起", for: .normal)
        fullFoldButton.titleLabel?.font = .systemFont(ofSize: 13)
        fullFoldButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        fullFoldButton.accessibilityLabel = "收起信息条"
        fullFoldButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        fullContent.addSubview(fullFoldButton)
        // (93) C1：展开档控制台钮（同排钮式：字形＋标题＋
        // 白 0.10 底），字形走 SeamGlyph93 双音符。
        fullConsoleButton93.setImage(SeamGlyph93.image(.consoleNotes), for: .normal)
        fullConsoleButton93.setTitle("  控制台", for: .normal)
        fullConsoleButton93.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        fullConsoleButton93.tintColor = .white
        fullConsoleButton93.setTitleColor(.white, for: .normal)
        fullConsoleButton93.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        fullConsoleButton93.layer.cornerRadius = 12
        fullConsoleButton93.contentHorizontalAlignment = .left
        fullConsoleButton93.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 0)
        fullConsoleButton93.accessibilityLabel = "控制台"
        fullConsoleButton93.addTarget(self, action: #selector(consoleTapped93),
                                      for: .touchUpInside)
        fullContent.addSubview(fullConsoleButton93)
        // port88 见证：歌单缝建成即无头像位（站点存活自证）。
        Breadcrumbs.log("port88 seam=avatarless host=wall")
    }

    /// 数据回填（标题/计数）：宿主在种子落地与条目变化时调。
    func setPlaylist85(title: String, count: Int) {
        titleButton.setTitle(Seam85Text.vertical(title), for: .normal)
        countLabel.text = "\(count) 首"
        fullTitleLabel.text = title
        fullMetaLabel.text = "\(count) 首"
    }

    func setExpanded85(_ expanded: Bool) {
        self.expanded = expanded
        spineContent.isHidden = expanded
        fullContent.isHidden = !expanded
        setNeedsLayout()
    }

    /// (93) C3：胶囊选中态回刷（与主页缝同一语言）。
    private func refreshLayoutSwitch93() {
        for (index, button) in layoutButtons93.enumerated() {
            let selected = index == layoutMode93
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.9) : .clear
            button.tintColor = selected
                ? UIColor(red: 22.0 / 255, green: 22.0 / 255,
                          blue: 27.0 / 255, alpha: 1)
                : UIColor.white.withAlphaComponent(0.62)
        }
    }

    @objc private func layoutModeTapped93(_ sender: UIButton) {
        layoutMode93 = sender.tag
        onLayoutMode93?(sender.tag)
    }

    /// (93) C1：展开档控制台点按。
    @objc private func consoleTapped93() {
        Breadcrumbs.log("sidebar85 tap dest=console")
        onConsole93?()
    }

    // port88：书脊头像回填（setAccount85）随头像摘除整组退役。

    // port90：缝长按切主题已随油画背景退役（handler 删除）。

    override func layoutSubviews() {
        super.layoutSubviews()
        // port90：无倾斜容器，排版坐标即本视图坐标。
        let areaW = bounds.width
        backdrop86.frame = bounds
        let top = contentTopInset
        let contentH = max(0, bounds.height - contentTopInset - contentBottomInset)
        // 书脊内容（64 宽居中）。
        spineContent.frame = CGRect(
            x: (areaW - 64) / 2, y: top, width: 64, height: contentH)
        let cx: CGFloat = 32
        let H = contentH
        // (86) 第 1 条：书脊改网页相对比例（BRAVAIS_SPINE_
        // GEOMETRY 同数，基准＝内容高 H）：back top 0.024、
        // fold 0.088、title top 0.16 高 0.38、count top
        // 0.56 高 0.06、play top 0.84、expand top 0.905；
        // 钮宽网页 0.6×缝宽≈38、原生触控帧 32 居中代偿
        // （报告注明）。标题不再弹性拉满、计数不再随标题
        // 底漂移（(85) 走样两处）。
        backButton.frame = CGRect(x: cx - 16, y: 0.024 * H, width: 32, height: 32)
        // (89) §5-7：书脊折叠钮 32 → 36（网页缝图标钮 36×36）。
        foldButton.frame = CGRect(x: cx - 18, y: 0.088 * H, width: 36, height: 36)
        titleButton.frame = CGRect(
            x: 12, y: 0.16 * H, width: 40, height: 0.38 * H)
        // port90：计数横排单行，帧高 18、整缝宽居中（旧 0.06H 高装不下竖排 5 行）。
        countLabel.frame = CGRect(
            x: 4, y: 0.56 * H, width: 56, height: 18)
        // 计数（止 0.62H）与播放（起 0.84H）之间空段：
        // port88 前为头像位（0.70H 起 32 圆），已摘除留空。
        playButton.frame = CGRect(x: cx - 18, y: 0.84 * H, width: 36, height: 36)
        // (89) §5-7：展开钮 28 → 36（网页缝图标钮 36×36）。
        expandButton.frame = CGRect(x: cx - 18, y: 0.905 * H, width: 36, height: 36)
        // (93) C3：三段胶囊居计数（止 0.56H＋18）与播放
        // （起 0.84H）之间空段：宽 50、三钮 44×29＋间 2、
        // 总高 97；空段不足 97 时隐藏（版式仍可经主页缝切）。
        let capsuleY = 0.56 * H + 22
        let capsuleH: CGFloat = 97
        layoutSwitch93.isHidden = (0.84 * H - capsuleY) < capsuleH
        if !layoutSwitch93.isHidden {
            layoutSwitch93.frame = CGRect(
                x: cx - 25, y: capsuleY, width: 50, height: capsuleH)
            for (index, button) in layoutButtons93.enumerated() {
                button.frame = CGRect(
                    x: 3, y: 3 + CGFloat(index) * 31,
                    width: 44, height: 29)
            }
        }
        // 展开档内容（300 宽居中、左对齐排版）。
        fullContent.frame = CGRect(
            x: (areaW - 300) / 2, y: top, width: 300, height: contentH)
        // (89) §5-7：展开档返回钮 28 → 32（网页返回钮 32×32）。
        fullBackButton.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        fullTitleLabel.frame = CGRect(x: 36, y: 2, width: 264, height: 44)
        fullMetaLabel.frame = CGRect(x: 36, y: 48, width: 264, height: 18)
        fullPlayButton.frame = CGRect(x: 16, y: 84, width: 268, height: 44)
        fullAppendButton.frame = CGRect(x: 16, y: 136, width: 268, height: 44)
        fullFoldButton.frame = CGRect(x: 16, y: 188, width: 60, height: 28)
        // (93) C1：展开档控制台钮（收起行之下、同排钮宽）。
        fullConsoleButton93.frame = CGRect(x: 16, y: 224, width: 268, height: 44)
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 点按（逐项落痕 sidebar85）

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
}
