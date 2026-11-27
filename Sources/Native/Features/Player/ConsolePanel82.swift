import UIKit
import Combine

/// (85) 第 7 条改版（Miller 22:44 定）：(82) 的 55% 高底
/// 部 sheet 改为紧凑悬浮毛玻璃卡——宽 82% 屏宽、高按内
/// 容（≤62% 屏高）、大圆角、居中浮在墙面上、点卡外关
/// 闭、入场弹簧缩放淡入；面板内每个可点元素带点击特效
/// （系统弹簧缩放回弹＋闪光环＋像素方点，v2 定版语言克
/// 制版），逐元素落 console85。
///
/// (82) 第 8 条：控制台面板（G3 紧凑版定版，Miller 18:15
/// 新口径＋18:20 去文字＋18:53 v2 收紧凑）——台面让出的全
/// 部功能收进一只底部升起的大圆角毛玻璃 sheet（高约 55%
/// 屏高、系统 sheet 弹簧升起/下拉关闭）：
/// 1. 播放队列（露 3.5 行＋底部渐隐、当前行琥珀高亮、右
///    上垃圾桶清空；点行即播）；
/// 2. 纯图标功能行（播放模式/随机/特效/宠物/喜欢/速记
///    簿，无文字标签）——全部真接通既有通路；
/// 3. 音量滑杆（PlaybackEngine.volume 同源）；
/// 4. 墙面外观：透光/实色图标分段（映射 gridCardMin-
///    Opacity 0.55/1.0，写后发 .foliaSettings62AChanged
///    让墙面即时重读）＋海报聚焦叠色开关（WallLight82
///    .focusEnabled82 门控）；
/// 5. 图形灯钮 LightSwitch82（开灯/关灯）＋帮助钮。
/// 逐钮落 tap82（host=console）。呈现入口 present(from:)
/// 按宿主接特效/日记本钩子：舞台走其自有选择器通路、主
/// 页墙走日记本抽屉；其余宿主特效走通用选择器（写
/// StageStyleStore，舞台下次打开/在场时读同源）。
///
/// (87) 控制台改版（样片定版移植）：①顶部队列文字表撤
/// 除，换可横滑封面条带（CoverTile87，从当前曲起轮转、
/// 在播金环＋律动、点封面切歌）＋右上清空钮保留；②顶部
/// 加圆形玻璃钮排（上一曲/播放/下一曲——台面撤下的两
/// 键藏处，播放键金底）；③功能行随机与循环合并为一个
/// 播放模式钮（单击循环 随机→顺序→循环→单曲，纯图
/// 标），腾位放歌曲列表钮（切卡内封面网格视图）；④图
/// 层行旁加四特效钮（烟花/孔明灯/下雪/刮风，圆形毛玻
/// 璃、点亮才上系统色，接 GlobalFx87 全局叠加层）；⑤
/// 卡几何沿 (86)：贴底 −90、竖单列/横双列紧凑卡。
final class ConsolePanel82: UIViewController,
                            UITableViewDataSource,
                            UITableViewDelegate,
                            UIGestureRecognizerDelegate {

    private var onEffects: (() -> Void)?
    private var onSketchbook: (() -> Void)?
    /// (89)B 功能行改网页 WallTools 快捷格构成后的新回调：
    /// 去处（宿主间表面切换）与进播放页（舞台），由
    /// present(from:) 按宿主类型装配；为 nil 时该格隐藏
    /// （网页快捷格「缺的格跳过」同式）。
    private var onDestination89: (() -> Void)?
    private var onPlayer89: (() -> Void)?
    private var onSettings89: (() -> Void)?

    private var queueTracks: [FoliaTrack] = []
    private var queueCurrent = -1
    private var cancellables = Set<AnyCancellable>()

    private let modeButton = UIButton(type: .system)
    private let listButton87 = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    private let pawButton = UIButton(type: .system)
    private let transPrev87 = UIButton(type: .system)
    private let transPlay87 = UIButton(type: .system)
    private let transNext87 = UIButton(type: .system)
    private let volumeSlider = UISlider()
    /// (89) §4 音量数值：网页两处控制台均有音量数值显示
    /// （宽 38、12px/600、右对齐），原生原缺，补齐。
    private let volumeValue89 = UILabel()
    private let segTranslucent = UIButton(type: .system)
    private let segSolid = UIButton(type: .system)
    /// (89)B 聚焦行：系统 UISwitch 退役，改网页同款
    /// 30×18 胶囊开关（钮点 12、开时右移 12）。
    private let focusToggle89 = CapsuleToggle89()
    /// (89)B 功能行新格：主题/去处/播放器/设置（网页
    /// WallTools 快捷格 6 格构成的后四格之新面孔）。
    private let themeButton89 = UIButton(type: .system)
    private let destButton89 = UIButton(type: .system)
    private let playerButton89 = UIButton(type: .system)
    private let settingsButton89 = UIButton(type: .system)
    private let lightSwitch = LightSwitch82()
    private var fxButtons87: [UIButton] = []

    /// (93) A2 契约：卡在 window 中的帧（viewDidLayoutSubviews/
    /// viewDidAppear 时赋值、viewWillDisappear 清 nil），供 Fx
    /// 覆层推荐卡对齐消费；本组只暴露、不消费。
    static var presentedCardFrame: CGRect?
    /// (93) A3：present 起点时刻（present(from:) 注入），
    /// viewDidAppear 算弹出间隔落 p93 pop 自证。
    private var p93PopStart93: CFTimeInterval = 0
    /// (93) A1：关闭原因已落痕标记（多入口去重＋宿主消失兜底判读）。
    private var p93DismissReason93: String?

    // MARK: (94) 94-1/94-2 仪器与分段装载状态
    /// 94-2 分段计时：tap 为零点（present(from:) 注入，与
    /// p93PopStart93 同刻），其余为各段完成时刻（CACurrent-
    /// MediaTime），齐后由 p94TryEmitSeg94 一行落盘。
    private var p94Tap94: CFTimeInterval = 0
    private var p94PresentDone94: CFTimeInterval = 0
    private var p94LoadDone94: CFTimeInterval = 0
    private var p94LayoutDone94: CFTimeInterval = 0
    private var p94First94: CFTimeInterval = 0
    private var p94Inter94: CFTimeInterval = 0
    private var p94SegEmitted94 = false
    private var p94DisplayLink94: CADisplayLink?
    /// 94-1 几何自证去重：上一行 geo 串（scr/bounds/calc/
    /// frame 任一变化才再落一行）。
    private var p94LastGeo94 = ""
    private var p94LastCalc94: CGSize = .zero
    /// 94-2 骨架先行：首帧占位骨架（卡框＋钮排圆占位＋行条
    /// 占位），重内容装载段 A 完成后淡出移除。
    private var skeleton94: UIView?
    private var p94ContentBuilt94 = false
    private var p94StagesStarted94 = false
    private var p94Stages94: [() -> Void] = []
    private var p94StageIndex94 = 0
    /// 条带分片装载代次（队列回刷时递增，旧分片自动作废）。
    private var p94StripGen94 = 0

    /// (87) 主视图（条带＋钮排＋功能行＋音量＋图层＋灯）
    /// 与队列网格视图（卡内切换、弹簧交叉）。
    /// port90（任务 21/24）：主视图改纵向滚动容器——拍立得区
    /// 加在上方后内容总高超卡高上限时区内滚动，下方各行原
    /// 尺寸原间距零改动；内容锚点走 contentLayoutGuide（纵向）
    /// ＋frameLayoutGuide（横向恒等于卡宽）。
    private let mainView87 = UIScrollView()
    /// port90（任务 21）：拍立得照片墙区（控制台上方新增）。
    private let polaroidZone90 = PolaroidZone90View()
    private let queueView87 = UIView()
    private let stripScroll87 = UIScrollView()
    private let stripStack87 = UIStackView()
    private var stripTiles87: [CoverTile87] = []
    /// port90：卡内队列视图由封面网格改文字行 48 表（任务 1 定版形态）。
    private var table87: UITableView!
    private var showingGrid87 = false

    /// (85) 第 7 条：悬浮卡本体与高度约束（高度在布局时
    /// 按 min(内容高, 62% 屏高) 收口）。
    /// (86) 第 7 条：卡改底部锚定（cardBottom85）＋宽度代
    /// 码收口（cardWidth85）；内容约束分横/竖两套
    /// （portraitConstraints85／landscapeConstraints85），
    /// 朝向切换时整组换——(85) 横屏满宽大空卡的定案修法
    /// （单列固定高链被 62% 上限裁掉、宽度按屏宽拉满）。
    private let card85 = UIView()
    private var cardHeight85: NSLayoutConstraint?
    private var cardWidth85: NSLayoutConstraint?
    private var cardBottom85: NSLayoutConstraint?
    private var portraitConstraints85: [NSLayoutConstraint] = []
    private var landscapeConstraints85: [NSLayoutConstraint] = []
    private var consoleLandscape86: Bool?

    static func present(from host: UIViewController) {
        let panel = ConsolePanel82()
        if let stage = host as? StageViewController {
            panel.onEffects = { [weak stage] in stage?.openStylePicker82() }
            // (89)B 去处（舞台宿主）＝回浏览（关台回墙）；
            // 播放器格已在播放页内、不装配（该格隐藏）。
            panel.onDestination89 = { [weak stage] in
                stage?.dismiss(animated: true)
            }
        }
        if let home = host as? HomeWallViewController {
            panel.onSketchbook = { [weak home] in home?.toggleSketchbook82() }
            // (89)B 去处（主页墙宿主）＝去歌单拼贴墙（网页
            // Bravais 去处→Lattice 同义，走统一落点）。
            panel.onDestination89 = { [weak home] in
                guard let home else { return }
                QueueLatticeViewController.present(from: home)
            }
            // (89)B 播放器格：开原生舞台（与主页墙既有开台
            // 同式：fullScreen present StageViewController）。
            panel.onPlayer89 = { [weak home] in
                let stage = StageViewController()
                stage.modalPresentationStyle = .fullScreen
                home?.present(stage, animated: true)
            }
        }
        if let proto = host as? WallPrototypeViewController {
            // (89)B 去处（原型墙宿主）＝回主页墙（关本面）；
            // 播放器格同主页墙式开台。
            panel.onDestination89 = { [weak proto] in
                proto?.dismiss(animated: true)
            }
            panel.onPlayer89 = { [weak proto] in
                let stage = StageViewController()
                stage.modalPresentationStyle = .fullScreen
                proto?.present(stage, animated: true)
            }
        }
        // (89)B 设置格：全宿主通用（与主页缝设置入口同
        // 呈现口径 overFullScreen＋不动画）。
        panel.onSettings89 = { [weak host] in
            let settings = SettingsViewController()
            settings.modalPresentationStyle = .overFullScreen
            host?.present(settings, animated: false)
        }
        // (85) 第 7 条：全屏覆盖＋交叉淡入，卡本体再走自
        // 有弹簧缩放入场（viewDidAppear）；盖过 (82) 的
        // pageSheet 55% detent。
        panel.modalPresentationStyle = .overFullScreen
        panel.modalTransitionStyle = .crossDissolve
        // (93) A3：弹出起点打点（首帧渲染后在 viewDidAppear 对账）。
        panel.p93PopStart93 = CACurrentMediaTime()
        // (94) 94-2：分段计时零点与点按同刻（与 A3 同源打点）。
        panel.p94Tap94 = panel.p93PopStart93
        Breadcrumbs.log("console82 present host=\(type(of: host))")
        Breadcrumbs.log("console85 present form=card")
        host.present(panel, animated: true)
        // (94) 94-2：present 段＝present 调用返回时刻（转场
        // 本身异步进行、不在此等待）。
        panel.p94PresentDone94 = CACurrentMediaTime()
    }

    /// (93) A1：根视图用 ConsoleDimRoot93——hitTest 对卡外点
    /// 直接认领根视图本身，卡内子视图（滚动容器/拍立得卡/特效
    /// 点缀层）无论哪层越界或吞点，都挡不住卡外点按到达 dim。
    override func loadView() {
        view = ConsoleDimRoot93()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // (85) 第 7 条：根视图＝压暗层（点卡外关闭）；卡
        // 居中悬浮（宽 82% 屏宽、高 ≤62% 屏高、大圆角、
        // 毛玻璃＋描边）。
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let dimTap = UITapGestureRecognizer(target: self, action: #selector(dimTapped85(_:)))
        // (93) A1：识别器只收卡外点（delegate 按点位放行），免被
        // 卡内识别器竞争吞掉；另有根视图 touchesEnded 第二路兜底
        // （ConsoleDimRoot93.onDimTouch93），两路同入 dismissConsole93 去重。
        dimTap.delegate = self
        dimTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dimTap)
        (view as? ConsoleDimRoot93)?.onDimTouch93 = { [weak self] in
            self?.dismissConsole93(reason: "dim")
        }
        card85.backgroundColor = .clear
        // (89) §4：卡圆角 28 → 24（网页 WallTools 面板圆角 24）。
        // port91（任务 5）：样板控制台定版圆角 20，改从样板
        // （与 (89) 的 24 取舍差异在 (91) 报告注明）。
        card85.layer.cornerRadius = 20
        card85.layer.borderWidth = 1
        card85.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card85.clipsToBounds = true
        card85.translatesAutoresizingMaskIntoConstraints = false
        card85.alpha = 0
        card85.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            .translatedBy(x: 0, y: 10)
        view.addSubview(card85)
        (view as? ConsoleDimRoot93)?.cardView93 = card85
        cardHeight85 = card85.heightAnchor.constraint(equalToConstant: 658)
        cardWidth85 = card85.widthAnchor.constraint(equalToConstant: 322)
        // (86) 第 7 条：底部锚定——卡底＝安全区底 −90（账：
        // 点播台展开态顶边＝安全区底 −80＝台底锚 −10＋台
        // 高 70；卡底再上 10pt 间隙，落在 8–12pt 任务带
        // 内）。(85) 的 centerY 居中退役；宽度改代码收口
        // （横 min(0.86×屏宽, 640)；(89) §4 竖屏宽对齐网页
        // 面板 min(296, 屏宽−32)，竖屏高改为内容链高 400）。
        cardBottom85 = card85.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90)
        // (89) §4 定位：卡片改右对齐贴边（网页 WallTools 面板
        // 右对齐、手机档右边距 16），底锚 −90 贴播放条不变
        // （(85)「向下贴近播放条」口径保留，仅水平轴对齐）。
        NSLayoutConstraint.activate([
            card85.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            cardWidth85!,
            cardBottom85!,
            cardHeight85!,
        ])
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(blur)
        let tint = UIView()
        tint.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        tint.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(tint)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: card85.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: card85.trailingAnchor),
            blur.topAnchor.constraint(equalTo: card85.topAnchor),
            blur.bottomAnchor.constraint(equalTo: card85.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: card85.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: card85.trailingAnchor),
            tint.topAnchor.constraint(equalTo: card85.topAnchor),
            tint.bottomAnchor.constraint(equalTo: card85.bottomAnchor),
        ])

        mainView87.translatesAutoresizingMaskIntoConstraints = false
        mainView87.showsVerticalScrollIndicator = false
        mainView87.showsHorizontalScrollIndicator = false
        card85.addSubview(mainView87)
        queueView87.translatesAutoresizingMaskIntoConstraints = false
        queueView87.alpha = 0
        queueView87.isHidden = true
        card85.addSubview(queueView87)
        NSLayoutConstraint.activate([
            mainView87.leadingAnchor.constraint(equalTo: card85.leadingAnchor),
            mainView87.trailingAnchor.constraint(equalTo: card85.trailingAnchor),
            mainView87.topAnchor.constraint(equalTo: card85.topAnchor),
            mainView87.bottomAnchor.constraint(equalTo: card85.bottomAnchor),
            queueView87.leadingAnchor.constraint(equalTo: card85.leadingAnchor),
            queueView87.trailingAnchor.constraint(equalTo: card85.trailingAnchor),
            queueView87.topAnchor.constraint(equalTo: card85.topAnchor),
            queueView87.bottomAnchor.constraint(equalTo: card85.bottomAnchor),
        ])

        // (94) 94-2 骨架先行：viewDidLoad 到此为止——首帧只
        // 有卡框（毛玻璃＋描边）＋钮排/行条占位骨架；下方原
        // viewDidLoad 的全部重内容（条带封面/队列表/拍立得
        // 区/各功能行）移入 buildFullContent94()，由转场完成
        // 后（viewDidAppear）的分段装载队列逐段构建。
        buildSkeleton94()
        p94LoadDone94 = CACurrentMediaTime()
    }

    /// (94) 94-2 装载段 A：原 viewDidLoad 后半段整体迁入
    /// （构成/尺寸/间距逐项不变）。由 startStagedLoad94 在
    /// 转场完成后调用一次；调用前 p94ContentBuilt94=false，
    /// bindState 的队列回刷被 refreshQueueViews87 的门控挡
    /// 住、待本段末置位后走分片装载。
    private func buildFullContent94() {
        // (87) 队列头行：封面条带＋右上清空钮（既有功能
        // 保留，样片无此钮——报告注明）。
        let clearButton = UIButton(type: .system)
        clearButton.setImage(DeckGlyph82.image(.trash, pointSize: 16), for: .normal)
        clearButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        clearButton.accessibilityLabel = "清空队列"
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearQueueTapped), for: .touchUpInside)
        mainView87.addSubview(clearButton)

        // port90（任务 21）：拍立得区装入主视图顶部（条带之上，
        // 既有各行零改动——任务 24）；点照片切歌＝在播池内定位
        // 起播后收控制台；日记本以全屏页盖在控制台上打开。
        polaroidZone90.translatesAutoresizingMaskIntoConstraints = false
        polaroidZone90.onPlay = { [weak self] track in
            guard let self else { return }
            if let index = QueueManager.shared.queue.firstIndex(where: { $0.id == track.id }) {
                QueueManager.shared.playAtIndex(index)
            } else {
                // 推荐池里的历史歌曲：插到队首起播，不清用户队列。
                QueueManager.shared.setQueue(
                    [track] + QueueManager.shared.queue, startingAt: 0, source: "polaroid90")
            }
            Breadcrumbs.log("port90 polaroid play id=\(track.id)")
            self.dismissConsole93(reason: "action")
        }
        polaroidZone90.onOpenDiary = { [weak self] track in
            guard let self else { return }
            let diary = DiaryViewController90(tagged: track)
            diary.modalPresentationStyle = .fullScreen
            self.present(diary, animated: true)
        }
        mainView87.addSubview(polaroidZone90)

        stripScroll87.showsHorizontalScrollIndicator = false
        stripScroll87.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(stripScroll87)
        stripStack87.axis = .horizontal
        stripStack87.spacing = 10
        stripStack87.alignment = .center
        stripStack87.translatesAutoresizingMaskIntoConstraints = false
        stripScroll87.addSubview(stripStack87)
        NSLayoutConstraint.activate([
            stripStack87.leadingAnchor.constraint(equalTo: stripScroll87.contentLayoutGuide.leadingAnchor),
            stripStack87.trailingAnchor.constraint(equalTo: stripScroll87.contentLayoutGuide.trailingAnchor),
            stripStack87.topAnchor.constraint(equalTo: stripScroll87.contentLayoutGuide.topAnchor),
            stripStack87.bottomAnchor.constraint(equalTo: stripScroll87.contentLayoutGuide.bottomAnchor),
            stripStack87.heightAnchor.constraint(equalTo: stripScroll87.frameLayoutGuide.heightAnchor),
        ])

        // (87) 顶部圆形玻璃钮排：上一曲/播放/下一曲（台
        // 面撤下两键的藏处）；播放键 54 金底。
        configureTransButton87(transPrev87, glyph: .prev, size: 46, label: "上一曲")
        transPrev87.addTarget(self, action: #selector(transPrevTapped87), for: .touchUpInside)
        configureTransButton87(transPlay87, glyph: .play, size: 54, label: "播放")
        // port90（任务 14）：播放钮去金色实心、改圆形毛玻璃透出卡面底色；
        // 字形 tint 回白、尺寸/位置不变。blur 子视图不接手势、置字形之下。
        transPlay87.backgroundColor = .clear
        transPlay87.tintColor = .white
        let playBlur90 = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        playBlur90.isUserInteractionEnabled = false
        playBlur90.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        playBlur90.layer.cornerRadius = 27
        playBlur90.clipsToBounds = true
        transPlay87.insertSubview(playBlur90, at: 0)
        transPlay87.addTarget(self, action: #selector(transPlayTapped87), for: .touchUpInside)
        configureTransButton87(transNext87, glyph: .next, size: 46, label: "下一曲")
        transNext87.addTarget(self, action: #selector(transNextTapped87), for: .touchUpInside)
        let transRow87 = UIStackView(arrangedSubviews: [transPrev87, transPlay87, transNext87])
        transRow87.axis = .horizontal
        transRow87.spacing = 26
        transRow87.alignment = .center
        transRow87.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(transRow87)

        // (89)B 功能行改网页 WallTools 快捷格构成（纯图
        // 标、无文字标签）：洗牌（播放模式合并钮承接）/
        // 生成主题/队列/去处/播放器/设置——6 格等分网格
        // （gap 4、格高 40、图标 18，网页 .lattice-tools-
        // quick 同账）。(87) 的特效/宠物/喜欢/日记本四格
        // 撤出本行：特效归舞台样式选择器、宠物归设置、
        // 喜欢归舞台顶栏与播放台、日记本归主页墙左缘抽
        // 屉把手，入口不灭、只迁位（paw/like 两钮对象与
        // 回刷逻辑保留、不再入行）。
        configureIconButton(modeButton, glyph: .modeRepeat, label: "播放模式")
        modeButton.addTarget(self, action: #selector(modeTapped87), for: .touchUpInside)
        // (92) 任务 4：主题格换 A4 手绘调色板（SF paintpalette 退役）。
        configureIconButton(themeButton89, glyph: .themePalette92, label: "主题")
        themeButton89.addTarget(self, action: #selector(themeTapped89), for: .touchUpInside)
        configureIconButton(listButton87, glyph: .list, label: "歌曲列表")
        listButton87.addTarget(self, action: #selector(listTapped87), for: .touchUpInside)
        // (92) 任务 4：去处格换 A4 手绘 2×2 格（SF square.grid 退役）。
        configureIconButton(destButton89, glyph: .destGrid92, label: "去处")
        destButton89.addTarget(self, action: #selector(destTapped89), for: .touchUpInside)
        // (92) 任务 4：播放器格换 A4 手绘圆盘（SF play.circle 退役）。
        configureIconButton(playerButton89, glyph: .playerDisc92, label: "播放器")
        playerButton89.addTarget(self, action: #selector(playerTapped89), for: .touchUpInside)
        // port91（任务 3）：设置格换 A4 sliders 字形（DeckGlyph82
        // .sliders 手绘），SF gearshape 退役——控制台内部图标同换。
        configureIconButton(settingsButton89, glyph: .sliders, label: "设置")
        settingsButton89.addTarget(self, action: #selector(settingsTapped89), for: .touchUpInside)
        configureIconButton(pawButton, glyph: .paw, label: "宠物")
        pawButton.addTarget(self, action: #selector(pawTapped), for: .touchUpInside)
        configureIconButton(likeButton, glyph: .heart, label: "喜欢")
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        // 缺格隐藏（网页快捷格同式）：回调未装配的格不占位。
        destButton89.isHidden = onDestination89 == nil
        playerButton89.isHidden = onPlayer89 == nil
        // (92) 任务 5：宠物召唤钮装回功能行（(89) 提交
        // 669b75b89 撤行未删对象，审计 Q5 定案）——位置在
        // 队列格之后，行变 7 格等分；召唤行为走 perform-
        // PawToggle77 同一通路（见 pawTapped）。
        let functionRow = UIStackView(arrangedSubviews: [
            modeButton, themeButton89, listButton87, pawButton,
            destButton89, playerButton89, settingsButton89])
        functionRow.axis = .horizontal
        functionRow.distribution = .fillEqually
        functionRow.spacing = 4
        functionRow.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(functionRow)

        // 音量行。
        // (89) §4：音量图标对齐网页 17px（盒 30×30 见约束集）。
        let speaker = UIImageView(image: DeckGlyph82.image(.speaker, pointSize: 17))
        speaker.tintColor = UIColor.white.withAlphaComponent(0.8)
        speaker.contentMode = .center
        speaker.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(speaker)
        volumeSlider.minimumTrackTintColor = .white
        volumeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        volumeSlider.value = PlaybackEngine.shared.volume
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        // (85) 第 7 条：滑杆点按特效只走闪光环（不缩放，
        // 免拖动中拇指抖动），按下即落 console85。
        volumeSlider.addTarget(self, action: #selector(volumeTouched85), for: .touchDown)
        mainView87.addSubview(volumeSlider)
        // (89) §4 音量数值标签：12pt semibold、白 0.66、右对齐，
        // 初值与滑杆同源（PlaybackEngine 音量 0…1 → 百分比）。
        volumeValue89.font = .systemFont(ofSize: 12, weight: .semibold)
        volumeValue89.textColor = UIColor.white.withAlphaComponent(0.66)
        volumeValue89.textAlignment = .right
        volumeValue89.text = "\(Int((PlaybackEngine.shared.volume * 100).rounded()))"
        volumeValue89.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(volumeValue89)

        // port90（任务 3＋追加 11）：图层行与聚焦行合并回一行——
        // (87) 引入 focusIcon 第二图层图标、(89)B 又拆行，竖屏 296 卡宽下
        // 分段胶囊压住烟花钮、聚焦开关独占空行。现单行 stack：
        // layers 20＋分段 62×26＋四特效钮 30×30（间距 4）＋聚焦胶囊 30×18，
        // equalSpacing 均分间隙（合计 244 ≤ 竖屏可用 272）。
        let layers = UIImageView(image: DeckGlyph82.image(.layers, pointSize: 17))
        layers.tintColor = UIColor.white.withAlphaComponent(0.8)
        layers.contentMode = .center
        layers.translatesAutoresizingMaskIntoConstraints = false
        let segContainer = UIView()
        segContainer.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        segContainer.layer.cornerRadius = 13
        segContainer.translatesAutoresizingMaskIntoConstraints = false
        for (button, translucent) in [(segTranslucent, true), (segSolid, false)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.cornerRadius = 10
            button.accessibilityLabel = translucent ? "透光" : "实色"
            button.addTarget(self, action: #selector(segTapped(_:)), for: .touchUpInside)
            segContainer.addSubview(button)
        }
        segTranslucent.tag = 0
        segSolid.tag = 1
        let fxGroup87 = UIStackView()
        fxGroup87.axis = .horizontal
        fxGroup87.spacing = 4
        fxGroup87.translatesAutoresizingMaskIntoConstraints = false
        let fxKinds: [DeckGlyph82.Kind] = [.fxFirework, .fxLantern, .fxSnow, .fxWind]
        let fxLabels = ["烟花", "孔明灯", "下雪", "刮风"]
        fxButtons87 = []
        for (index, kind) in fxKinds.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(DeckGlyph82.image(kind, pointSize: 16), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            button.layer.cornerRadius = 15
            button.layer.borderWidth = 0.5
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            button.accessibilityLabel = fxLabels[index]
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(fxKindTapped87(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 30),
                button.heightAnchor.constraint(equalToConstant: 30),
            ])
            fxGroup87.addArrangedSubview(button)
            fxButtons87.append(button)
            // port91（任务 3）：特效钮面换 A4 玻璃面。
            A4Chrome91.apply(to: button, cornerRadius: 15)
        }
        // 聚焦开关（30×18 胶囊、开态金底）并入同一行行尾。
        focusToggle89.isOn = WallLight82.focusEnabled82
        focusToggle89.translatesAutoresizingMaskIntoConstraints = false
        focusToggle89.accessibilityLabel = "海报聚焦叠色"
        focusToggle89.onToggle = { [weak self] on in
            self?.focusToggled89(on)
        }
        let fxRow90 = UIStackView(arrangedSubviews: [
            layers, segContainer, fxGroup87, focusToggle89])
        fxRow90.axis = .horizontal
        fxRow90.alignment = .center
        fxRow90.distribution = .equalSpacing
        fxRow90.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(fxRow90)

        // 底部行：灯钮＋帮助钮。
        lightSwitch.translatesAutoresizingMaskIntoConstraints = false
        lightSwitch.setOn(WallLight82.isOn, animated: false)
        lightSwitch.onToggle = { on in
            DeckTap82.log(host: "console", zone: "light", view: self.lightSwitch)
            ConsoleFX85.tap(self.lightSwitch, el: "light")
            // port90（任务 19）运行时自证：切换链第 2 环（控制台回调）。
            Breadcrumbs.log("port90 light toggle on=\(on ? 1 : 0)")
            WallLight82.setOn(on, source: "console")
        }
        mainView87.addSubview(lightSwitch)
        let helpButton = UIButton(type: .system)
        helpButton.setImage(DeckGlyph82.image(.help, pointSize: 17), for: .normal)
        helpButton.tintColor = .white
        helpButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        // (89) §4：帮助钮 38 → 32（网页帮助触发钮 32×32）。
        helpButton.layer.cornerRadius = 16
        helpButton.accessibilityLabel = "帮助"
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        mainView87.addSubview(helpButton)
        // port91（任务 3）：帮助钮面换 A4 玻璃面。
        A4Chrome91.apply(to: helpButton, cornerRadius: 16)

        // port91（任务 5）：发丝线分组（样板控制台骨架）——拍
        // 立得区↔条带之间、音量行↔特效行之间各一条（白 .08、
        // 0.5pt），以相对锚悬挂、不入主链、不改各行尺寸间距。
        for (hairline, anchor) in [(UIView(), 0), (UIView(), 1)] as [(UIView, Int)] {
            hairline.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            hairline.isUserInteractionEnabled = false
            hairline.translatesAutoresizingMaskIntoConstraints = false
            mainView87.addSubview(hairline)
            if anchor == 0 {
                NSLayoutConstraint.activate([
                    hairline.topAnchor.constraint(equalTo: polaroidZone90.bottomAnchor, constant: 5),
                    hairline.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
                    hairline.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
                    hairline.heightAnchor.constraint(equalToConstant: 0.5),
                ])
            } else {
                NSLayoutConstraint.activate([
                    hairline.bottomAnchor.constraint(equalTo: fxRow90.topAnchor, constant: -7),
                    hairline.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
                    hairline.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
                    hairline.heightAnchor.constraint(equalToConstant: 0.5),
                ])
            }
        }

        // port90 队列列表视图：返回钮＋文字行 48 表（封面网格退役）。
        let backButton87 = UIButton(type: .system)
        backButton87.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton87.tintColor = .white
        backButton87.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        backButton87.layer.cornerRadius = 18
        backButton87.accessibilityLabel = "返回"
        backButton87.translatesAutoresizingMaskIntoConstraints = false
        backButton87.addTarget(self, action: #selector(backTapped87), for: .touchUpInside)
        queueView87.addSubview(backButton87)
        table87 = UITableView(frame: .zero, style: .plain)
        table87.backgroundColor = .clear
        table87.separatorStyle = .none
        table87.showsVerticalScrollIndicator = false
        table87.dataSource = self
        table87.delegate = self
        table87.rowHeight = 48
        table87.register(ConsoleQueueRowCell90.self,
                         forCellReuseIdentifier: ConsoleQueueRowCell90.reuseId)
        table87.translatesAutoresizingMaskIntoConstraints = false
        queueView87.addSubview(table87)
        NSLayoutConstraint.activate([
            backButton87.topAnchor.constraint(equalTo: queueView87.topAnchor, constant: 12),
            backButton87.leadingAnchor.constraint(equalTo: queueView87.leadingAnchor, constant: 16),
            backButton87.widthAnchor.constraint(equalToConstant: 36),
            backButton87.heightAnchor.constraint(equalToConstant: 36),
            table87.topAnchor.constraint(equalTo: backButton87.bottomAnchor, constant: 8),
            table87.leadingAnchor.constraint(equalTo: queueView87.leadingAnchor, constant: 12),
            table87.trailingAnchor.constraint(equalTo: queueView87.trailingAnchor, constant: -12),
            table87.bottomAnchor.constraint(equalTo: queueView87.bottomAnchor, constant: -12),
        ])

        // 朝向无关的内层约束（分段两钮恒在 segContainer
        // 内、两钮尺寸恒定）先恒激活。
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: 32),
            clearButton.heightAnchor.constraint(equalToConstant: 28),
            // port90：合并行内件定尺寸（stack 只管分布、尺寸在此恒钉）。
            layers.widthAnchor.constraint(equalToConstant: 20),
            layers.heightAnchor.constraint(equalToConstant: 20),
            segContainer.widthAnchor.constraint(equalToConstant: 62),
            segContainer.heightAnchor.constraint(equalToConstant: 26),
            segTranslucent.leadingAnchor.constraint(equalTo: segContainer.leadingAnchor, constant: 3),
            segTranslucent.centerYAnchor.constraint(equalTo: segContainer.centerYAnchor),
            segTranslucent.widthAnchor.constraint(equalToConstant: 27),
            segTranslucent.heightAnchor.constraint(equalToConstant: 20),
            segSolid.trailingAnchor.constraint(equalTo: segContainer.trailingAnchor, constant: -3),
            segSolid.centerYAnchor.constraint(equalTo: segContainer.centerYAnchor),
            segSolid.widthAnchor.constraint(equalToConstant: 27),
            segSolid.heightAnchor.constraint(equalToConstant: 20),
            helpButton.widthAnchor.constraint(equalToConstant: 32),
            helpButton.heightAnchor.constraint(equalToConstant: 32),
            // (89) §4：音量行高对齐网页 38（滑杆命中高）。
            volumeSlider.heightAnchor.constraint(equalToConstant: 38),
            // (89)B：聚焦胶囊开关定尺寸（网页 toggle 30×18）。
            focusToggle89.widthAnchor.constraint(equalToConstant: 30),
            focusToggle89.heightAnchor.constraint(equalToConstant: 18),
            // port90：开灯长条定版尺寸 200×46 代码可证（旧靠 intrinsicContentSize）。
            lightSwitch.widthAnchor.constraint(equalToConstant: 200),
            lightSwitch.heightAnchor.constraint(equalToConstant: 46),
        ])
        // (87) 竖屏单列链（自上而下：条带/钮排/功能行/
        // 音量/图层/聚焦/灯行；(89) 后总高 390 ≤ 400 卡高）。
        portraitConstraints85 = [
            // port90（任务 21/24）：拍立得区钉在滚动内容顶部
            // （头行 40＋舞台 232）；下方条带起整链相对锚点与
            // 间距与加区前逐项相同，仅首锚改挂区底。
            polaroidZone90.topAnchor.constraint(equalTo: mainView87.contentLayoutGuide.topAnchor, constant: 10),
            polaroidZone90.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            polaroidZone90.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
            polaroidZone90.heightAnchor.constraint(equalToConstant: 272),

            clearButton.topAnchor.constraint(equalTo: stripScroll87.topAnchor),
            clearButton.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),

            stripScroll87.topAnchor.constraint(equalTo: polaroidZone90.bottomAnchor, constant: 10),
            stripScroll87.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            stripScroll87.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            stripScroll87.heightAnchor.constraint(equalToConstant: 86),

            transRow87.topAnchor.constraint(equalTo: stripScroll87.bottomAnchor, constant: 10),
            transRow87.centerXAnchor.constraint(equalTo: mainView87.frameLayoutGuide.centerXAnchor),
            transRow87.heightAnchor.constraint(equalToConstant: 54),

            // (89) §4：功能行边距 24 → 12（296 卡宽下六格
            // 42 宽＋间隙 4 的网页账）、行高 44 → 40。
            functionRow.topAnchor.constraint(equalTo: transRow87.bottomAnchor, constant: 12),
            functionRow.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            functionRow.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
            functionRow.heightAnchor.constraint(equalToConstant: 40),

            speaker.topAnchor.constraint(equalTo: functionRow.bottomAnchor, constant: 12),
            speaker.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            speaker.widthAnchor.constraint(equalToConstant: 30),
            speaker.heightAnchor.constraint(equalToConstant: 30),
            volumeSlider.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeSlider.leadingAnchor.constraint(equalTo: speaker.trailingAnchor, constant: 10),
            volumeSlider.trailingAnchor.constraint(equalTo: volumeValue89.leadingAnchor, constant: -8),
            volumeValue89.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeValue89.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
            volumeValue89.widthAnchor.constraint(equalToConstant: 38),

            // port90 合并行：图层/分段/特效/聚焦同行，行高 30。
            fxRow90.topAnchor.constraint(equalTo: speaker.bottomAnchor, constant: 14),
            fxRow90.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            fxRow90.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
            fxRow90.heightAnchor.constraint(equalToConstant: 30),

            lightSwitch.topAnchor.constraint(equalTo: fxRow90.bottomAnchor, constant: 14),
            lightSwitch.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            // port90：滚动内容底锚（内容高由链尾定义）。
            lightSwitch.bottomAnchor.constraint(equalTo: mainView87.contentLayoutGuide.bottomAnchor, constant: -10),
            helpButton.centerYAnchor.constraint(equalTo: lightSwitch.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
        ]
        // (87) 横屏双列链：左列＝条带＋钮排＋功能行；右
        // 列＝音量/图层/聚焦/灯光四行（卡高 232 内成立）。
        landscapeConstraints85 = [
            // port90（任务 21/24）：拍立得区横屏同构置顶（头行
            // 40＋舞台 146）；双列链整体下移、列内相对锚点与
            // 间距不变，卡高不足时整视图纵向滚动（任务 24 口径）。
            polaroidZone90.topAnchor.constraint(equalTo: mainView87.contentLayoutGuide.topAnchor, constant: 10),
            polaroidZone90.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            polaroidZone90.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
            polaroidZone90.heightAnchor.constraint(equalToConstant: 186),

            clearButton.topAnchor.constraint(equalTo: stripScroll87.topAnchor),
            clearButton.trailingAnchor.constraint(equalTo: stripScroll87.trailingAnchor),

            stripScroll87.topAnchor.constraint(equalTo: polaroidZone90.bottomAnchor, constant: 8),
            stripScroll87.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            stripScroll87.widthAnchor.constraint(equalTo: mainView87.frameLayoutGuide.widthAnchor, multiplier: 0.44),
            stripScroll87.heightAnchor.constraint(equalToConstant: 82),

            transRow87.topAnchor.constraint(equalTo: stripScroll87.bottomAnchor, constant: 8),
            transRow87.centerXAnchor.constraint(equalTo: stripScroll87.centerXAnchor),
            transRow87.heightAnchor.constraint(equalToConstant: 54),

            functionRow.topAnchor.constraint(equalTo: transRow87.bottomAnchor, constant: 8),
            functionRow.leadingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.leadingAnchor, constant: 12),
            functionRow.trailingAnchor.constraint(equalTo: stripScroll87.trailingAnchor),
            functionRow.heightAnchor.constraint(equalToConstant: 40),
            // port90：左列底不越内容底（内容高取双列较高者）。
            functionRow.bottomAnchor.constraint(lessThanOrEqualTo: mainView87.contentLayoutGuide.bottomAnchor, constant: -12),

            speaker.topAnchor.constraint(equalTo: polaroidZone90.bottomAnchor, constant: 8),
            speaker.leadingAnchor.constraint(equalTo: stripScroll87.trailingAnchor, constant: 28),
            speaker.widthAnchor.constraint(equalToConstant: 30),
            speaker.heightAnchor.constraint(equalToConstant: 30),
            volumeSlider.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeSlider.leadingAnchor.constraint(equalTo: speaker.trailingAnchor, constant: 10),
            volumeSlider.trailingAnchor.constraint(equalTo: volumeValue89.leadingAnchor, constant: -8),
            volumeValue89.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeValue89.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -24),
            volumeValue89.widthAnchor.constraint(equalToConstant: 38),

            // port90 合并行（横屏右列同式单行）。
            fxRow90.topAnchor.constraint(equalTo: speaker.bottomAnchor, constant: 14),
            fxRow90.leadingAnchor.constraint(equalTo: speaker.leadingAnchor),
            fxRow90.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -12),
            fxRow90.heightAnchor.constraint(equalToConstant: 30),

            lightSwitch.topAnchor.constraint(equalTo: fxRow90.bottomAnchor, constant: 14),
            lightSwitch.leadingAnchor.constraint(equalTo: speaker.leadingAnchor),
            // port90：滚动内容底锚（右列链尾定义内容高）。
            lightSwitch.bottomAnchor.constraint(equalTo: mainView87.contentLayoutGuide.bottomAnchor, constant: -12),
            helpButton.centerYAnchor.constraint(equalTo: lightSwitch.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: mainView87.frameLayoutGuide.trailingAnchor, constant: -24),
        ]
        // (94) 94-2：本段在转场后才跑，初始集按构建时刻的
        // 真实朝向落位并同步 consoleLandscape86（骨架期布局
        // 回调因约束集为空跳过切换、见 viewDidLayoutSubviews
        // 门控）；后续旋转仍由布局回调整组换。
        let builtLandscape = view.bounds.width > view.bounds.height
        consoleLandscape86 = builtLandscape
        NSLayoutConstraint.activate(
            builtLandscape ? landscapeConstraints85 : portraitConstraints85)

        refreshModeButton()
        refreshLikeButton()
        refreshPawButton()
        refreshSegButtons()
        refreshTrans87()
        refreshFxButtons87()
        GlobalFx87.shared.onStateChanged = { [weak self] in
            self?.refreshFxButtons87()
        }
        // (94) 94-2：内容建成置位后才放行队列回刷（条带分片
        // ＋队列表 reload 各自成段，见 refreshQueueViews87）。
        p94ContentBuilt94 = true
        bindState()
        Breadcrumbs.log("port89 console=right/w296/r24/fn42x40/vol30+val")
        // (89)B 见证：功能行网页 6 格构成＋高生长＋聚焦胶囊。
        Breadcrumbs.log("port89 consoleB row=web6/hgrow/focuscap")
        // port90 见证：队列文字行 48＋图层聚焦合并一行＋灯条 200×46 恒约束＋拍立得区置顶。
        Breadcrumbs.log("port90 console queue=rows48/fxrow=merged/light=200x46/polaroid=top")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // (86) 第 7 条＋横屏核查：朝向定布局集与卡尺寸
        // （切换只在朝向真变时发生、防布局回环）。
        // (94) 94-2 门控：骨架期约束集尚未构建（两组皆空），
        // 跳过整组切换，待 buildFullContent94 按真实朝向落位。
        let bounds = view.bounds
        let landscape = bounds.width > bounds.height
        if consoleLandscape86 != landscape,
           !portraitConstraints85.isEmpty || !landscapeConstraints85.isEmpty {
            consoleLandscape86 = landscape
            NSLayoutConstraint.deactivate(
                landscape ? portraitConstraints85 : landscapeConstraints85)
            NSLayoutConstraint.activate(
                landscape ? landscapeConstraints85 : portraitConstraints85)
            Breadcrumbs.log("console86 land=\(landscape ? 1 : 0)")
        }
        // (94) 94-1 几何回滚（Miller 2026-11-27 10:56 点选）：
        // 宽回 (92) 源码公式——竖屏 min(296, bounds.width−32)、
        // 横屏 min(bounds.width×0.86, 640)；(93) 的横竖同式
        // min(620, 屏宽−20) 退役。
        let cardW = landscape
            ? min(bounds.width * 0.86, 640)
            : min(296, bounds.width - 32)
        if let cardWidth85, abs(cardWidth85.constant - cardW) > 0.5 {
            cardWidth85.constant = cardW
        }
        // (94) 94-1 高改回 (82) 定版：竖横同为屏高×0.549
        // （呈现上下文 bounds.height×0.549 取整）。横屏取值
        // 口径：再与 (92) 横屏 cap 取 min——cap 沿现行 cap89
        // 口径＝屏高−safeAreaInsets.bottom−90（卡底锚）−56
        // （顶距），防横屏矮高时卡顶冲出可用区；竖屏不套 cap，
        // 按 Miller 点选原文直取 0.549 屏高。(89)B 内容生长
        // 高（竖 min(658,cap)/横 min(396,cap)）退役；内容超
        // 卡高时主视图纵向滚动（port90 任务 24 口径不变）。
        let cap89 = bounds.height - view.safeAreaInsets.bottom - 90 - 56
        let cardH = landscape
            ? min((bounds.height * 0.549).rounded(), cap89)
            : (bounds.height * 0.549).rounded()
        if let cardHeight85, abs(cardHeight85.constant - cardH) > 0.5 {
            cardHeight85.constant = cardH
        }
        // (93) A2：布局后回写卡帧（window 未挂时保留旧值不造数）。
        if let win = view.window {
            Self.presentedCardFrame = card85.convert(card85.bounds, to: win)
        }
        // (94) 94-2：首次布局完成打点（seg 的 layout 段）。
        if p94LayoutDone94 == 0 {
            p94LayoutDone94 = CACurrentMediaTime()
        }
        // (94) 94-1 几何自证：四数同行、变化才落（见 p94LogGeo94）。
        p94LastCalc94 = CGSize(width: cardW, height: cardH)
        p94LogGeo94(calc: p94LastCalc94)
    }

    /// (94) 94-1 几何自证面包屑：`p94 console geo scr=WxH
    /// bounds=WxH calc=WxH frame=WxH`——scr=UIScreen.main.
    /// bounds、bounds=呈现上下文 view.bounds、calc=94-1 公
    /// 式算出的卡宽高、frame=card85 实际 frame 宽高。布局
    /// 回调每遍调用、串变化才落盘（present 时首遍布局即落
    /// 第一行，viewDidAppear 再补调一次收 frame 定值）。
    private func p94LogGeo94(calc: CGSize) {
        guard calc.width > 0, calc.height > 0 else { return }
        let scr = UIScreen.main.bounds.size
        let b = view.bounds.size
        let f = card85.frame.size
        func wh(_ s: CGSize) -> String {
            "\(Int(s.width.rounded()))x\(Int(s.height.rounded()))"
        }
        let line = "p94 console geo scr=\(wh(scr)) bounds=\(wh(b))"
            + " calc=\(wh(calc)) frame=\(wh(f))"
        guard line != p94LastGeo94 else { return }
        p94LastGeo94 = line
        Breadcrumbs.log(line)
    }

    /// (94) 94-2：首帧 commit 量测——装一次性 CADisplayLink，
    /// 其首个回调近似首帧已提交显示的时刻（seg 的 first 段
    /// 取此值；取不到时 p94TryEmitSeg94 以 viewDidAppear 时
    /// 刻兜底，见彼处注释）。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if p94First94 == 0, p94DisplayLink94 == nil {
            let link = CADisplayLink(target: self,
                                     selector: #selector(p94FirstFrame94(_:)))
            link.add(to: .main, forMode: .common)
            p94DisplayLink94 = link
        }
    }

    @objc private func p94FirstFrame94(_ link: CADisplayLink) {
        if p94First94 == 0 {
            p94First94 = CACurrentMediaTime()
        }
        link.invalidate()
        p94DisplayLink94 = nil
        p94TryEmitSeg94()
    }

    /// (85) 第 7 条：入场——卡弹簧缩放＋淡入（iOS 系统
    /// 弹簧口径，禁线性）。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // (94) 94-1：present 完成时刻补落一行 geo（frame 此
        // 时已定值；与布局行同串则去重不重落）。
        p94LogGeo94(calc: p94LastCalc94)
        // (94) 94-2：转场已完成——启动分段装载（骨架→重内
        // 容逐段构建）；入场弹簧动画与装载并行、互不等待。
        startStagedLoad94()
        // (93) A3 自证：弹出起点→首帧渲染后间隔（目标 <50ms；
        // 拍立得打印已移出本路径，见下方动画 completion）。
        if p93PopStart93 > 0 {
            let gap = (CACurrentMediaTime() - p93PopStart93) * 1000
            Breadcrumbs.log("p93 pop gap=\(Int(gap.rounded()))ms")
            p93PopStart93 = 0
        }
        // (93) A2：出现后回写卡帧（此刻 window 必在）。
        if let win = view.window {
            Self.presentedCardFrame = card85.convert(card85.bounds, to: win)
        }
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction]) {
            self.card85.alpha = 1
            self.card85.transform = .identity
        } completion: { _ in
            // (94) 94-2：拍立得备池＋打印不再挂本 completion——
            // 已并入 startStagedLoad94 的装载段 B（转场完成后
            // 逐段装载，打印本身在 Polaroid90 内再分帧，沿
            // (93) A3 移出弹出关键路径的口径）。
        }
        refreshTrans87()
    }

    /// (93) A1/A2：消失时清契约帧；若本次消失未经任一已落痕
    /// 入口（宿主被关/被系统摘除等），以 hostgone 兜底落痕。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Self.presentedCardFrame = nil
        if isBeingDismissed, p93DismissReason93 == nil {
            p93DismissReason93 = "hostgone"
            Breadcrumbs.log("p93 dismiss r=hostgone")
        }
    }

    /// (93) A1：全入口统一关闭口——落 p93 dismiss 痕（reason=
    /// dim/button/action/hostgone）后关台；重复调用只落一次痕。
    private func dismissConsole93(reason: String,
                                  completion: (() -> Void)? = nil) {
        if p93DismissReason93 == nil {
            p93DismissReason93 = reason
            Breadcrumbs.log("p93 dismiss r=\(reason)")
        }
        dismiss(animated: true, completion: completion)
    }

    /// (93) A1：dim 识别器只收卡外点——点位换算走 convert＋
    /// bounds（不读 card85.frame，免入场 transform 期帧账偏差
    /// 把卡外点误判成卡内提前 return，旧 dimTapped85 的隐患）。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: view)
        return !card85.bounds.contains(card85.convert(point, from: view))
    }

    /// (85) 第 7 条：点卡外（压暗区）关闭。
    @objc private func dimTapped85(_ recognizer: UITapGestureRecognizer) {
        // (93) A1：点位判定改 convert＋bounds（旧 frame 判定在
        // transform/布局未稳时可误判）；关台走统一口落 reason。
        let point = recognizer.location(in: view)
        guard !card85.bounds.contains(card85.convert(point, from: view)) else { return }
        Breadcrumbs.log("console85 tap el=outside")
        // port91（任务 1）自证：点外关闭同入 p91 tap 口径。
        Breadcrumbs.log("p91 tap zone=outside")
        dismissConsole93(reason: "dim")
    }

    // MARK: (94) 94-2 骨架＋分段装载＋seg 落盘

    /// 骨架（首帧唯一内容，卡框在 viewDidLoad 已建）：钮排
    /// 三圆占位（46/54/46、间距/行高与真钮排同账）＋两条行
    /// 条占位。纯 UIView、无图无字、isUserInteractionEnabled
    /// =false 不吞点按；真内容在下层 mainView87 建成后淡出。
    private func buildSkeleton94() {
        let skel = UIView()
        skel.isUserInteractionEnabled = false
        skel.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(skel)
        let circles = UIStackView()
        circles.axis = .horizontal
        circles.spacing = 26
        circles.alignment = .center
        circles.translatesAutoresizingMaskIntoConstraints = false
        for size in [CGFloat(46), 54, 46] {
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            dot.layer.cornerRadius = size / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: size),
                dot.heightAnchor.constraint(equalToConstant: size),
            ])
            circles.addArrangedSubview(dot)
        }
        skel.addSubview(circles)
        var bars: [UIView] = []
        for _ in 0..<2 {
            let bar = UIView()
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            bar.layer.cornerRadius = 6
            bar.translatesAutoresizingMaskIntoConstraints = false
            skel.addSubview(bar)
            bars.append(bar)
        }
        NSLayoutConstraint.activate([
            skel.leadingAnchor.constraint(equalTo: card85.leadingAnchor),
            skel.trailingAnchor.constraint(equalTo: card85.trailingAnchor),
            skel.topAnchor.constraint(equalTo: card85.topAnchor),
            skel.bottomAnchor.constraint(equalTo: card85.bottomAnchor),
            circles.topAnchor.constraint(equalTo: skel.topAnchor, constant: 24),
            circles.centerXAnchor.constraint(equalTo: skel.centerXAnchor),
            circles.heightAnchor.constraint(equalToConstant: 54),
            bars[0].topAnchor.constraint(equalTo: circles.bottomAnchor, constant: 12),
            bars[0].leadingAnchor.constraint(equalTo: skel.leadingAnchor, constant: 12),
            bars[0].trailingAnchor.constraint(equalTo: skel.trailingAnchor, constant: -12),
            bars[0].heightAnchor.constraint(equalToConstant: 40),
            bars[1].topAnchor.constraint(equalTo: bars[0].bottomAnchor, constant: 12),
            bars[1].leadingAnchor.constraint(equalTo: skel.leadingAnchor, constant: 12),
            bars[1].trailingAnchor.constraint(equalTo: skel.trailingAnchor, constant: -12),
            bars[1].heightAnchor.constraint(equalToConstant: 38),
        ])
        skeleton94 = skel
    }

    /// 分段装载队列：段 A＝重内容构建（buildFullContent94，
    /// 其内的条带/队列表再各自异步分片、见 refreshQueue-
    /// Views87）；段 B＝拍立得备池启动。每段独立一轮主队列
    /// 派发、段间让出主线程供帧提交，段内不对整树
    /// layoutIfNeeded；目标每段主线程工作 <8ms（条带按 6
    /// 张/片切分即为此设）。装载全程不动 view 的
    /// allowUserInteraction 语义：根视图/手势/弹簧动画均带
    /// .allowUserInteraction，骨架不接点按，装载中点按不吞。
    /// 横竖屏弹出共用本队列同一条路。
    private func startStagedLoad94() {
        guard !p94StagesStarted94 else { return }
        p94StagesStarted94 = true
        p94Stages94 = [
            { [weak self] in
                guard let self else { return }
                self.buildFullContent94()
                // inter 段＝核心控件建成、骨架撤下、可交互时刻。
                self.p94Inter94 = CACurrentMediaTime()
                self.liftSkeleton94()
                self.p94TryEmitSeg94()
            },
            { [weak self] in
                self?.polaroidZone90.beginIfNeeded()
            },
        ]
        p94StageIndex94 = 0
        runNextStage94()
    }

    private func runNextStage94() {
        guard p94StageIndex94 < p94Stages94.count else {
            p94Stages94 = []
            return
        }
        let stage = p94Stages94[p94StageIndex94]
        p94StageIndex94 += 1
        DispatchQueue.main.async { [weak self] in
            stage()
            self?.runNextStage94()
        }
    }

    /// 骨架撤下：真内容已在下层建成，骨架只淡出不位移——
    /// 无闪烁/跳变（入场 crossDissolve＋卡弹簧维持原样）。
    private func liftSkeleton94() {
        guard let skel = skeleton94 else { return }
        skeleton94 = nil
        UIView.animate(withDuration: 0.2, delay: 0,
                       options: [.allowUserInteraction, .curveEaseOut]) {
            skel.alpha = 0
        } completion: { _ in
            skel.removeFromSuperview()
        }
    }

    /// (94) 94-2 分段计时落盘：`p94 pop seg tap=0 present=..
    /// load=.. layout=.. first=.. inter=..`（相对 tap 的累计
    /// ms、一行）。first 取 CADisplayLink 首回调（见
    /// viewWillAppear 装载处）；若 seg 齐时 link 尚未回调，
    /// 以 viewDidAppear 时刻兜底（本函数在 viewDidAppear 后
    /// 的段 A 完成时调用、届时已出现）。
    /// 目标口径：tap→首帧 commit ≤ 转场时长＋50ms——达标
    /// 与否以本行真机数据裁，此处不宣称已达标。
    private func p94TryEmitSeg94() {
        guard !p94SegEmitted94, p94Tap94 > 0, p94PresentDone94 > 0,
              p94LoadDone94 > 0, p94LayoutDone94 > 0, p94Inter94 > 0
        else { return }
        let first = p94First94 > 0 ? p94First94 : CACurrentMediaTime()
        p94SegEmitted94 = true
        func ms(_ t: CFTimeInterval) -> Int {
            Int(((t - p94Tap94) * 1000).rounded())
        }
        Breadcrumbs.log("p94 pop seg tap=0 present=\(ms(p94PresentDone94))"
            + " load=\(ms(p94LoadDone94)) layout=\(ms(p94LayoutDone94))"
            + " first=\(ms(first)) inter=\(ms(p94Inter94))")
    }

    private func bindState() {
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                self?.queueTracks = tracks
                self?.refreshQueueViews87()
            }
            .store(in: &cancellables)
        QueueManager.shared.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                self?.queueCurrent = index
                self?.refreshQueueViews87()
            }
            .store(in: &cancellables)
        QueueManager.shared.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshModeButton() }
            .store(in: &cancellables)
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLikeButton()
                self?.refreshTrans87()
            }
            .store(in: &cancellables)
        PlaybackEngine.shared.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, !self.volumeSlider.isTracking else { return }
                self.volumeSlider.value = value
            }
            .store(in: &cancellables)
        queueTracks = QueueManager.shared.queue
        queueCurrent = QueueManager.shared.currentIndex
        refreshQueueViews87()
    }

    // MARK: (87) 队列封面条带＋网格

    /// 条带与网格同源回刷：条带按样片口径从当前曲起轮
    /// 转全队列；网格按队列原序。
    /// (94) 94-2 分段装载：内容未建成（骨架期）直接返回，
    /// bindState 的初值在本段末由 p94ContentBuilt94 置位后
    /// 的调用承接；条带改为异步分片构建（6 张/片、每片一轮
    /// 主队列、目标单片 <8ms、片内不对整树 layoutIfNeeded），
    /// 队列表 reloadData 独立成段另起一轮主队列；新回刷递
    /// 增代次、未完旧分片自动作废。
    private func refreshQueueViews87() {
        guard p94ContentBuilt94 else { return }
        p94StripGen94 += 1
        let gen = p94StripGen94
        stripTiles87.forEach { $0.removeFromSuperview() }
        stripTiles87 = []
        let count = queueTracks.count
        var order: [Int] = []
        if count > 0 {
            let start = queueCurrent >= 0 && queueCurrent < count ? queueCurrent : 0
            order = (0..<count).map { (start + $0) % count }
        }
        buildStripSlice94(gen: gen, order: order, cursor: 0)
        DispatchQueue.main.async { [weak self] in
            guard let self, gen == self.p94StripGen94 else { return }
            self.table87?.reloadData()
        }
    }

    /// (94) 94-2 条带分片：单片最多 6 张封面，余量让给下
    /// 一轮主队列续建（分片间帧可提交、点按不被长任务吞）。
    private func buildStripSlice94(gen: Int, order: [Int], cursor: Int) {
        guard gen == p94StripGen94, cursor < order.count else { return }
        let end = min(cursor + 6, order.count)
        for position in cursor..<end {
            let index = order[position]
            // 分片跨多轮主队列，期间队列可能被清空/缩短——越界即停片。
            guard index < queueTracks.count else { return }
            let tile = CoverTile87()
            tile.configure(track: queueTracks[index],
                           index: index,
                           isCurrent: index == queueCurrent,
                           isPlaying: PlaybackEngine.shared.isPlaying)
            tile.tag = index
            tile.addTarget(self, action: #selector(stripTileTapped87(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                tile.widthAnchor.constraint(equalToConstant: 74),
                tile.heightAnchor.constraint(equalToConstant: 74),
            ])
            stripStack87.addArrangedSubview(tile)
            stripTiles87.append(tile)
        }
        if end < order.count {
            DispatchQueue.main.async { [weak self] in
                self?.buildStripSlice94(gen: gen, order: order, cursor: end)
            }
        }
    }

    @objc private func stripTileTapped87(_ sender: CoverTile87) {
        ConsoleFX85.tap(sender, el: "queue")
        Breadcrumbs.log("console87 strip play idx=\(sender.tag)")
        QueueManager.shared.playAtIndex(sender.tag)
        dismissConsole93(reason: "action")
    }

    @objc private func listTapped87(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "list87", view: sender)
        ConsoleFX85.tap(sender, el: "list")
        showQueueView87(true)
    }

    @objc private func backTapped87(_ sender: UIButton) {
        ConsoleFX85.tap(sender, el: "back")
        showQueueView87(false)
    }

    /// 卡内主视图⇄队列网格切换（系统弹簧交叉＋微缩放，
    /// 与样片 panel 视图切换同语言）。
    private func showQueueView87(_ show: Bool) {
        showingGrid87 = show
        Breadcrumbs.log("console87 view=\(show ? "grid" : "main")")
        if show {
            table87.reloadData()
            queueView87.isHidden = false
            queueView87.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        } else {
            mainView87.isHidden = false
            mainView87.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0.3,
                       options: [.allowUserInteraction]) {
            self.queueView87.alpha = show ? 1 : 0
            self.queueView87.transform = .identity
            self.mainView87.alpha = show ? 0 : 1
            self.mainView87.transform = .identity
        } completion: { _ in
            self.mainView87.isHidden = show
            self.queueView87.isHidden = !show
        }
    }

    // port90：卡内队列表数据（文字行 48，规格镜像 QueueTrackCell＋34 封面缩略）。
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        queueTracks.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ConsoleQueueRowCell90.reuseId,
            for: indexPath) as! ConsoleQueueRowCell90
        cell.configure90(track: queueTracks[indexPath.row],
                         isCurrent: indexPath.row == queueCurrent)
        return cell
    }

    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Breadcrumbs.log("port90 console row play idx=\(indexPath.row)")
        QueueManager.shared.playAtIndex(indexPath.row)
        dismissConsole93(reason: "action")
    }

    // MARK: 功能行装配

    private func makeIconButton(_ glyph: DeckGlyph82.Kind,
                                action: Selector, label: String) -> UIButton {
        let button = UIButton(type: .system)
        configureIconButton(button, glyph: glyph, label: label)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func configureIconButton(_ button: UIButton,
                                     glyph: DeckGlyph82.Kind, label: String) {
        // (89) §4＋B：功能格对齐网页快捷格——图标 18、格
        // 高 40；宽度由行内 6 列等分网格（fillEqually＋
        // gap 4）分配、不再钉死 42。
        button.setImage(DeckGlyph82.image(glyph, pointSize: 18), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 12
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        // port91（任务 3）：功能格钮面换 A4 玻璃面。
        A4Chrome91.apply(to: button, cornerRadius: 12)
    }

    /// (89)B 功能行 SF 字形格（主题/去处/播放器/设置）：
    /// 与 DeckGlyph82 格同底同角同高，字形走 SF Symbols
    /// 18pt（DeckGlyph82 表内无此四格字形，不扩表）。
    private func configureIconButtonSF89(_ button: UIButton,
                                         systemName: String, label: String) {
        button.setImage(UIImage(systemName: systemName,
                                withConfiguration: UIImage.SymbolConfiguration(
                                    pointSize: 18, weight: .regular)), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 12
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        // port91（任务 3）：钮面同换 A4 玻璃面（字形仍 SF 的
        // 三格以钮面语言统一，报告注明）。
        A4Chrome91.apply(to: button, cornerRadius: 12)
    }

    /// (87) 顶部钮排圆玻璃钮（样片 .tbtn）。
    private func configureTransButton87(_ button: UIButton,
                                        glyph: DeckGlyph82.Kind,
                                        size: CGFloat, label: String) {
        // port90（任务 20）：字号与播放台严格对齐（播放/暂停 21、上下曲 19），
        // 字形同走 DeckGlyph82 核心 M 字形单一工厂、无第二套绘制。
        button.setImage(DeckGlyph82.image(glyph, pointSize: size >= 54 ? 21 : 19), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = size / 2
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])
        // port91（任务 3）：钮排圆钮换 A4 玻璃面（边框 .38 由
        // chrome 收口、覆盖上方 .2 描边；中央播放钮的毛玻璃
        // 子层随后插入 index 0、位于渐变层之下同为玻璃语言）。
        A4Chrome91.apply(to: button, cornerRadius: size / 2)
    }

    private func refreshTrans87() {
        let playing = PlaybackEngine.shared.isPlaying
        transPlay87.setImage(
            DeckGlyph82.image(playing ? .pause : .play, pointSize: 21), for: .normal)
        transPlay87.accessibilityLabel = playing ? "暂停" : "播放"
    }

    /// (87) 播放模式合并钮回刷：字形随当前模式（随机走
    /// shuffle 字形、其余走 mode 三字形），顺序模式弱化。
    private func refreshModeButton() {
        let mode = QueueManager.shared.playMode
        let glyph: DeckGlyph82.Kind
        switch mode {
        case .off: glyph = .modeSequence
        case .loopAll: glyph = .modeRepeat
        case .repeatOne: glyph = .modeRepeatOne
        case .shuffle: glyph = .shuffle
        }
        modeButton.setImage(DeckGlyph82.image(glyph, pointSize: 18), for: .normal)
        modeButton.tintColor = mode == .off
            ? UIColor.white.withAlphaComponent(0.55) : .white
        modeButton.backgroundColor = mode == .shuffle
            ? UIColor.white.withAlphaComponent(0.22)
            : UIColor.white.withAlphaComponent(0.10)
    }

    private func refreshLikeButton() {
        let liked = PlaybackEngine.shared.currentTrack
            .map { LikesStore.shared.isLiked($0.id) } ?? false
        likeButton.setImage(
            DeckGlyph82.image(liked ? .heartFill : .heart, pointSize: 18), for: .normal)
        likeButton.tintColor = liked
            ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1) : .white
    }

    private func refreshPawButton() {
        let on = StickerSettings.miniPetsEnabled
        pawButton.tintColor = on
            ? .white : UIColor.white.withAlphaComponent(0.45)
    }

    /// (87) 四特效钮点亮回刷（点亮才上系统色，样片
    /// .fxbtn.on 口径；状态源 GlobalFx87）。
    private func refreshFxButtons87() {
        let fx = GlobalFx87.shared
        let states = [fx.isFireworks, fx.isLanterns, fx.isSnow, fx.isWind]
        let colors: [UIColor] = [
            UIColor(red: 1, green: 0.69, blue: 0.18, alpha: 1),
            UIColor(red: 1, green: 0.60, blue: 0.24, alpha: 1),
            UIColor(red: 0.49, green: 0.77, blue: 1, alpha: 1),
            UIColor(red: 0.37, green: 0.83, blue: 0.75, alpha: 1),
        ]
        for (index, button) in fxButtons87.enumerated() {
            let on = states[index]
            button.tintColor = on ? colors[index] : .white
            button.backgroundColor = on
                ? colors[index].withAlphaComponent(0.22)
                : UIColor.white.withAlphaComponent(0.10)
        }
    }

    private func refreshSegButtons() {
        let translucent = SettingsStore.gridCardMinOpacity < 0.99
        for (button, isTranslucent) in [(segTranslucent, true), (segSolid, false)] {
            let selected = translucent == isTranslucent
            button.backgroundColor = selected ? .white : .clear
            button.setImage(
                Self.segIcon(translucent: isTranslucent,
                             selected: selected),
                for: .normal)
            button.tintColor = selected ? .black : .white
        }
    }

    /// 透光/实色图形分段字形（G2 口径：透光＝左半实心＋描
    /// 边方块、实色＝实心方块），代码绘制、无文字。
    private static func segIcon(translucent: Bool, selected: Bool) -> UIImage {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(x: 1.5, y: 1.5, width: 13, height: 13)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)
            UIColor.white.setStroke()
            path.lineWidth = 1.4
            if translucent {
                path.stroke()
                let half = UIBezierPath(roundedRect: CGRect(
                    x: 1.5, y: 1.5, width: 6.5, height: 13), cornerRadius: 3)
                UIColor.white.setFill()
                half.fill()
            } else {
                UIColor.white.setFill()
                path.fill()
            }
        }.withRenderingMode(.alwaysTemplate)
    }

    // MARK: 动作

    @objc private func clearQueueTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "qclear", view: sender)
        ConsoleFX85.tap(sender, el: "clear")
        QueueManager.shared.clearQueue()
        Breadcrumbs.log("console82 queue clear")
    }

    /// (87) 播放模式合并钮：单击循环 随机→顺序→循环→
    /// 单曲（样片 MODES 序），撤菜单与独立随机钮。
    @objc private func modeTapped87(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "mode", view: sender)
        ConsoleFX85.tap(sender, el: "mode")
        let queue = QueueManager.shared
        queue.playMode = Deck87.nextMode(after: queue.playMode)
        Breadcrumbs.log("console87 mode=\(queue.playMode.rawValue)")
        refreshModeButton()
    }

    @objc private func transPrevTapped87(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "prev87", view: sender)
        ConsoleFX85.tap(sender, el: "prev")
        QueueManager.shared.playPrevious()
        Breadcrumbs.log("console87 trans=prev")
    }

    @objc private func transNextTapped87(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "next87", view: sender)
        ConsoleFX85.tap(sender, el: "next")
        QueueManager.shared.playNext(manual: true)
        Breadcrumbs.log("console87 trans=next")
    }

    @objc private func transPlayTapped87(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "play87", view: sender)
        ConsoleFX85.tap(sender, el: "play")
        PlaybackEngine.shared.togglePlayPause()
        refreshTrans87()
        Breadcrumbs.log("console87 trans=play")
    }

    /// (87) 四特效钮：接 GlobalFx87 全局叠加层（与歌词
    /// 特效三击线互不相干）；互斥/叠加规则在引擎内收口。
    @objc private func fxKindTapped87(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "fx87", view: sender)
        ConsoleFX85.tap(sender, el: "fx87")
        let fx = GlobalFx87.shared
        switch sender.tag {
        case 0: _ = fx.toggleFireworks()
        case 1: _ = fx.toggleLanterns()
        case 2: _ = fx.toggleSnow()
        default: _ = fx.toggleWind()
        }
        refreshFxButtons87()
    }

    @objc private func effectsTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "fx", view: sender)
        ConsoleFX85.tap(sender, el: "fx")
        if let onEffects {
            dismissConsole93(reason: "action") { onEffects() }
            return
        }
        // 通用宿主（墙）：选择器写同一 StageStyleStore，
        // 舞台下次打开读同源生效。
        let picker = StageStylePickerViewController(
            activeStyleId: StageStyleStore.currentStyleId)
        picker.onPickNative = { styleId in
            StageStyleStore.currentStyleId = styleId
            Breadcrumbs.log("console82 fx pick=\(styleId)")
            picker.presentingViewController?.dismiss(animated: true)
        }
        picker.onPickWeb = { info in
            StageStyleStore.currentStyleId = info.id
            Breadcrumbs.log("console82 fx pick=\(info.id)")
            picker.presentingViewController?.dismiss(animated: true)
        }
        present(picker, animated: true)
    }

    @objc private func pawTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "paw", view: sender)
        ConsoleFX85.tap(sender, el: "paw")
        let was = StickerSettings.miniPetsEnabled
        // (92) 任务 5：召唤/关闭改走共享切换核 performPaw-
        // Toggle77（与窗口爪印/台面爪印同路：开关双写＋告
        // 别离场/掉落入场＋广播兜底＋岛民对账）；旧实现直
        // 写 StickerSettings 跳过了整条收口链。烟花保留为
        // 召唤成功的卡内点缀（原 (85) 口径不动）。
        PetSummonButton70.performPawToggle77(
            window: view.window,
            src: was ? "console3s" : "console2s",
            via: was ? "console3s" : "console2s",
            actCrumb: "paw.act92")
        if !was {
            // (85) 第 7 条：烟花宿主改卡内坐标（内容已迁卡）。
            PawFirework81.burst(in: card85,
                                at: sender.convert(
                                    CGPoint(x: sender.bounds.midX,
                                            y: sender.bounds.midY), to: card85))
        }
        refreshPawButton()
        Breadcrumbs.log("p92 paw src=console on=\(!was ? 1 : 0)")
    }

    @objc private func likeTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "like", view: sender)
        ConsoleFX85.tap(sender, el: "like")
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        refreshLikeButton()
        NativePlaybackFailureToast.show(message: newState ? "已喜欢" : "已取消喜欢")
        Breadcrumbs.log("console82 like id=\(id) on=\(newState ? 1 : 0)")
        Task {
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                await MainActor.run { self.refreshLikeButton() }
            }
        }
    }

    @objc private func sketchbookTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "sketch", view: sender)
        ConsoleFX85.tap(sender, el: "sketch")
        if let onSketchbook {
            dismissConsole93(reason: "action") { onSketchbook() }
        } else {
            NativePlaybackFailureToast.show(message: "日记本在主页墙左缘打开")
            Breadcrumbs.log("console82 sketch host=unsupported")
        }
    }

    @objc private func volumeChanged(_ sender: UISlider) {
        PlaybackEngine.shared.setVolume(sender.value)
        // (89) §4：数值标签与滑杆同拍更新。
        volumeValue89.text = "\(Int((sender.value * 100).rounded()))"
    }

    @objc private func volumeTouched85(_ sender: UISlider) {
        ConsoleFX85.tap(sender, el: "volume", pulse: false)
    }

    @objc private func segTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "seg", view: sender)
        ConsoleFX85.tap(sender, el: "seg")
        let translucent = sender.tag == 0
        SettingsStore.gridCardMinOpacity = translucent ? 0.55 : 1.0
        NotificationCenter.default.post(name: .foliaSettings62AChanged, object: nil)
        refreshSegButtons()
        Breadcrumbs.log("console82 seg=\(translucent ? "translucent" : "solid")")
    }

    /// (89)B 聚焦胶囊开关回调（行为与原 UISwitch 通路
    /// 一致：写 WallLight82.focusEnabled82 单源）。
    private func focusToggled89(_ on: Bool) {
        DeckTap82.log(host: "console", zone: "focus", view: focusToggle89)
        ConsoleFX85.tap(focusToggle89, el: "focus")
        WallLight82.focusEnabled82 = on
        Breadcrumbs.log("port89 focus=capsule on=\(on ? 1 : 0)")
    }

    /// (89)B 主题格：生成主题——与缝/点播台长按同通路
    /// （SeamThemeCycle86.cycle：写 MiniPlayerTheme.
    /// stored.next＋发同一通知，特效总开关关时停用）。
    @objc private func themeTapped89(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "theme89", view: sender)
        ConsoleFX85.tap(sender, el: "theme")
        SeamThemeCycle86.cycle()
        Breadcrumbs.log("port89 console theme=\(MiniPlayerTheme.stored.rawValue)")
    }

    /// (89)B 去处格：宿主表面切换（present(from:) 装配：
    /// 主页墙→歌单拼贴墙、舞台→回墙、原型墙→回主页墙）。
    @objc private func destTapped89(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "dest89", view: sender)
        ConsoleFX85.tap(sender, el: "dest")
        guard let onDestination89 else { return }
        Breadcrumbs.log("port89 console dest")
        dismissConsole93(reason: "action") { onDestination89() }
    }

    /// (89)B 播放器格：进播放页（原生舞台）。
    @objc private func playerTapped89(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "player89", view: sender)
        ConsoleFX85.tap(sender, el: "player")
        guard let onPlayer89 else { return }
        Breadcrumbs.log("port89 console player")
        dismissConsole93(reason: "action") { onPlayer89() }
    }

    /// (89)B 设置格：打开设置页（全宿主通用装配）。
    @objc private func settingsTapped89(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "settings89", view: sender)
        ConsoleFX85.tap(sender, el: "settings")
        guard let onSettings89 else { return }
        Breadcrumbs.log("port89 console settings")
        dismissConsole93(reason: "action") { onSettings89() }
    }

    @objc private func helpTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "help", view: sender)
        ConsoleFX85.tap(sender, el: "help")
        let alert = UIAlertController(
            title: "控制台",
            message: "队列：顶部封面条左右滑，点封面立即播放；列表钮打开封面网格，右上垃圾桶清空队列。\n"
                + "顶部圆钮：上一曲、播放/暂停、下一曲。\n"
                + "功能行：播放模式（点一下换一种：随机→顺序→循环→单曲）、主题（换油画主题）、歌曲列表、去处（换墙面）、播放器（进播放页）、设置。特效在播放页选样式，宠物开关在设置里，日记本在主页墙左缘。\n"
                + "图层行：透光/实色切换墙面卡片质感；旁边四钮是全屏特效（烟花、孔明灯、下雪、刮风）；聚焦叠色开时，关灯后只有点中的封面亮起。\n"
                + "灯钮：开灯＝全部封面亮起；关灯＝整墙暗下、点哪张亮哪张。\n"
                + "播放台 5 秒无操作自动收成细条，点细条恢复。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

/// (93) A1：控制台根视图（压暗层本体）——hitTest 对卡外点
/// 直接返回自身：卡内任何子视图（滚动容器/拍立得舞台/打印
/// 中的卡/点按特效层）即使帧越界或带识别器，也无从吞掉卡
/// 外点按；touchesEnded 再作第二路把卡外点直送关闭口（与
/// dim 手势识别器互为兜底、同入 dismissConsole93 去重）。
final class ConsoleDimRoot93: UIView {

    weak var cardView93: UIView?
    var onDimTouch93: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let card = cardView93,
           card.bounds.contains(card.convert(point, from: self)) {
            return super.hitTest(point, with: event)
        }
        return self
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // 卡内点按会沿响应链冒泡到此——必须按点位复核卡外才关，
        // 只认 hitTest 已直认的 dim 点与真正落在卡外的冒泡点。
        guard let touch = touches.first, let card = cardView93,
              !card.bounds.contains(card.convert(touch.location(in: self), from: self))
        else { return }
        onDimTouch93?()
    }
}

/// (89)B 聚焦行胶囊开关（网页 .lattice-tools-toggle 同
/// 规格：30×18 胶囊、钮点 12×12、开时钮点右移 12；开
/// 态金底＝原 UISwitch onTint 金（0.96/0.72/0.25）、关
/// 态白 0.25 底）。点按切换、系统弹簧动画（禁线性）。
final class CapsuleToggle89: UIView {

    var onToggle: ((Bool) -> Void)?

    var isOn: Bool = false {
        didSet { applyState89(animated: false) }
    }

    private let knob89 = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 9
        knob89.backgroundColor = .white
        knob89.layer.cornerRadius = 6
        knob89.isUserInteractionEnabled = false
        addSubview(knob89)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(tapped89)))
        applyState89(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionKnob89()
    }

    @objc private func tapped89() {
        isOn.toggle()
        applyState89(animated: true)
        onToggle?(isOn)
    }

    private func positionKnob89() {
        let x: CGFloat = isOn ? bounds.width - 12 - 3 : 3
        knob89.frame = CGRect(x: x, y: 3, width: 12, height: 12)
    }

    private func applyState89(animated: Bool) {
        let apply = { [self] in
            backgroundColor = isOn
                ? UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
                : UIColor.white.withAlphaComponent(0.25)
            positionKnob89()
            accessibilityValue = isOn ? "开" : "关"
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0,
                           usingSpringWithDamping: 0.7,
                           initialSpringVelocity: 0.6,
                           options: [.allowUserInteraction,
                                     .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }
}

/// (85) 第 7 条：控制台点击特效（Miller (84)⑦「每个点
/// 击要有特效」）——按下缩放回弹（iOS 系统弹簧）＋一圈
/// 闪光环＋6 颗像素方点外迸（v2 定版「像素方点＋闪光
/// 带」语言的克制版，与爪印烟花/灯钮同族）。逐元素落
/// console85 见证（el=元素名）。pulse=false 时只走闪光
/// 环＋方点（滑杆类不缩放、免拖动抖动）。
enum ConsoleFX85 {
    static func tap(_ target: UIView, el: String, pulse: Bool = true) {
        Breadcrumbs.log("console85 tap el=\(el)")
        // port91（任务 1）自证：控制台任一点按到达——特效开着
        // 时本行须照常出现（与 p91 lamp hit 对位判读点按链）。
        Breadcrumbs.log("p91 tap zone=\(el)")
        if pulse {
            target.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 1.2,
                           options: [.allowUserInteraction,
                                     .beginFromCurrentState]) {
                target.transform = .identity
            }
        }
        guard let host = target.superview else { return }
        let center = target.center
        let ring = UIView(frame: target.frame.insetBy(dx: -3, dy: -3))
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        ring.layer.borderWidth = 1.5
        ring.layer.cornerRadius = max(target.layer.cornerRadius + 3, 10)
        ring.isUserInteractionEnabled = false
        host.addSubview(ring)
        var squares: [UIView] = []
        for _ in 0..<6 {
            let sq = UIView(frame: CGRect(x: 0, y: 0, width: 3, height: 3))
            sq.backgroundColor = UIColor.white.withAlphaComponent(0.9)
            sq.center = center
            sq.isUserInteractionEnabled = false
            host.addSubview(sq)
            squares.append(sq)
        }
        UIView.animate(withDuration: 0.38, delay: 0,
                       options: [.curveEaseOut]) {
            ring.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            ring.alpha = 0
            for (index, sq) in squares.enumerated() {
                let angle = CGFloat(index) / 6 * .pi * 2 + 0.4
                sq.center = CGPoint(x: center.x + cos(angle) * 30,
                                    y: center.y + sin(angle) * 30)
                sq.alpha = 0
            }
        } completion: { _ in
            ring.removeFromSuperview()
            squares.forEach { $0.removeFromSuperview() }
        }
    }
}

/// port90 控制台卡内队列行（文字行 48）：规格镜像独立队列页
/// QueueTrackCell（当前行左侧 3pt 强调条 ThemeSystem62.currentAccent、
/// 标题 13（当前行 semibold）/歌手 12/时长 12 等宽右对齐宽 46），
/// 另加 34×34 封面缩略（走 proxiedURLString 规范化通路，与墙面同路）。
final class ConsoleQueueRowCell90: UITableViewCell {

    static let reuseId = "ConsoleQueueRowCell90"

    private let accentBar = UIView()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let durationLabel = UILabel()
    private var coverTask: Task<Void, Never>?
    private var trackId: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        accentBar.backgroundColor = ThemeSystem62.currentAccent
        accentBar.isHidden = true
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(accentBar)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 6
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artistLabel)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        durationLabel.textAlignment = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            accentBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 34),
            coverView.heightAnchor.constraint(equalToConstant: 34),
            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 46),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverTask?.cancel()
        coverView.image = nil
        trackId = nil
        titleLabel.text = nil
        artistLabel.text = nil
        durationLabel.text = nil
        accentBar.isHidden = true
    }

    func configure90(track: FoliaTrack, isCurrent: Bool) {
        trackId = track.id
        titleLabel.text = track.title
        artistLabel.text = track.artist
        titleLabel.font = .systemFont(ofSize: 13, weight: isCurrent ? .semibold : .regular)
        accentBar.isHidden = !isCurrent
        if isCurrent {
            accentBar.backgroundColor = ThemeSystem62.currentAccent
        }
        durationLabel.text = Self.durationText90(track.duration)
        loadCover90(track: track)
    }

    private func loadCover90(track: FoliaTrack) {
        coverTask?.cancel()
        coverView.image = nil
        guard let raw = track.artworkURL?.absoluteString else { return }
        let loader = NativeCoverLoader.shared
        let proxy = loader.proxiedURLString(raw, tier: 256)
        if let key = proxy, let cached = loader.cachedImage(for: key) {
            coverView.image = cached
            return
        }
        if let cached = loader.cachedImageAnyTier(raw: raw, excludingTier: 256) {
            coverView.image = cached
            return
        }
        let id = track.id
        coverTask = Task { [weak self] in
            let image = await loader.image(for: proxy ?? raw, tier: 256)
            guard let self, self.trackId == id, let image else { return }
            self.coverView.image = image
        }
    }

    /// 时长 m:ss（无有效时长留空，不造数；与 QueueTrackCell 同式）。
    private static func durationText90(_ seconds: TimeInterval) -> String {
        guard seconds > 0, seconds.isFinite else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
