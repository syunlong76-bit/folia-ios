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
/// 按宿主接特效/速记簿钩子：舞台走其自有选择器通路、主
/// 页墙走速记簿抽屉；其余宿主特效走通用选择器（写
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
                            UICollectionViewDataSource,
                            UICollectionViewDelegateFlowLayout {

    private var onEffects: (() -> Void)?
    private var onSketchbook: (() -> Void)?

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
    private let focusSwitch = UISwitch()
    private let lightSwitch = LightSwitch82()
    private var fxButtons87: [UIButton] = []

    /// (87) 主视图（条带＋钮排＋功能行＋音量＋图层＋灯）
    /// 与队列网格视图（卡内切换、弹簧交叉）。
    private let mainView87 = UIView()
    private let queueView87 = UIView()
    private let stripScroll87 = UIScrollView()
    private let stripStack87 = UIStackView()
    private var stripTiles87: [CoverTile87] = []
    private var grid87: UICollectionView!
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
        }
        if let home = host as? HomeWallViewController {
            panel.onSketchbook = { [weak home] in home?.toggleSketchbook82() }
        }
        // (85) 第 7 条：全屏覆盖＋交叉淡入，卡本体再走自
        // 有弹簧缩放入场（viewDidAppear）；盖过 (82) 的
        // pageSheet 55% detent。
        panel.modalPresentationStyle = .overFullScreen
        panel.modalTransitionStyle = .crossDissolve
        Breadcrumbs.log("console82 present host=\(type(of: host))")
        Breadcrumbs.log("console85 present form=card")
        host.present(panel, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // (85) 第 7 条：根视图＝压暗层（点卡外关闭）；卡
        // 居中悬浮（宽 82% 屏宽、高 ≤62% 屏高、大圆角、
        // 毛玻璃＋描边）。
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let dimTap = UITapGestureRecognizer(target: self, action: #selector(dimTapped85(_:)))
        view.addGestureRecognizer(dimTap)
        card85.backgroundColor = .clear
        // (89) §4：卡圆角 28 → 24（网页 WallTools 面板圆角 24）。
        card85.layer.cornerRadius = 24
        card85.layer.borderWidth = 1
        card85.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card85.clipsToBounds = true
        card85.translatesAutoresizingMaskIntoConstraints = false
        card85.alpha = 0
        card85.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            .translatedBy(x: 0, y: 10)
        view.addSubview(card85)
        cardHeight85 = card85.heightAnchor.constraint(equalToConstant: 400)
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

        // (87) 队列头行：封面条带＋右上清空钮（既有功能
        // 保留，样片无此钮——报告注明）。
        let clearButton = UIButton(type: .system)
        clearButton.setImage(DeckGlyph82.image(.trash, pointSize: 16), for: .normal)
        clearButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        clearButton.accessibilityLabel = "清空队列"
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearQueueTapped), for: .touchUpInside)
        mainView87.addSubview(clearButton)

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
        transPlay87.backgroundColor = UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 0.22)
        transPlay87.tintColor = UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 1)
        transPlay87.addTarget(self, action: #selector(transPlayTapped87), for: .touchUpInside)
        configureTransButton87(transNext87, glyph: .next, size: 46, label: "下一曲")
        transNext87.addTarget(self, action: #selector(transNextTapped87), for: .touchUpInside)
        let transRow87 = UIStackView(arrangedSubviews: [transPrev87, transPlay87, transNext87])
        transRow87.axis = .horizontal
        transRow87.spacing = 26
        transRow87.alignment = .center
        transRow87.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(transRow87)

        // (87) 功能行（纯图标、无文字标签）：模式合并钮/
        // 歌曲列表/特效/宠物/喜欢/速记簿。
        let fxButton = makeIconButton(.sparkles, action: #selector(effectsTapped), label: "特效")
        let sketchButton = makeIconButton(.pencil, action: #selector(sketchbookTapped), label: "速记簿")
        configureIconButton(modeButton, glyph: .modeRepeat, label: "播放模式")
        modeButton.addTarget(self, action: #selector(modeTapped87), for: .touchUpInside)
        configureIconButton(listButton87, glyph: .list, label: "歌曲列表")
        listButton87.addTarget(self, action: #selector(listTapped87), for: .touchUpInside)
        configureIconButton(pawButton, glyph: .paw, label: "宠物")
        pawButton.addTarget(self, action: #selector(pawTapped), for: .touchUpInside)
        configureIconButton(likeButton, glyph: .heart, label: "喜欢")
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        let functionRow = UIStackView(arrangedSubviews: [
            modeButton, listButton87, fxButton, pawButton, likeButton, sketchButton])
        functionRow.axis = .horizontal
        functionRow.distribution = .equalSpacing
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

        // 图层行：layers 图标＋透光/实色图形分段＋四特效钮。
        let layers = UIImageView(image: DeckGlyph82.image(.layers, pointSize: 17))
        layers.tintColor = UIColor.white.withAlphaComponent(0.8)
        layers.contentMode = .center
        layers.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(layers)
        let segContainer = UIView()
        segContainer.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        segContainer.layer.cornerRadius = 14
        segContainer.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(segContainer)
        for (button, translucent) in [(segTranslucent, true), (segSolid, false)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.cornerRadius = 11
            button.accessibilityLabel = translucent ? "透光" : "实色"
            button.addTarget(self, action: #selector(segTapped(_:)), for: .touchUpInside)
            segContainer.addSubview(button)
        }
        segTranslucent.tag = 0
        segSolid.tag = 1
        let fxGroup87 = UIStackView()
        fxGroup87.axis = .horizontal
        fxGroup87.spacing = 6
        fxGroup87.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(fxGroup87)
        let fxKinds: [DeckGlyph82.Kind] = [.fxFirework, .fxLantern, .fxSnow, .fxWind]
        let fxLabels = ["烟花", "孔明灯", "下雪", "刮风"]
        fxButtons87 = []
        for (index, kind) in fxKinds.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(DeckGlyph82.image(kind, pointSize: 19), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            button.layer.cornerRadius = 18
            button.layer.borderWidth = 0.5
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            button.accessibilityLabel = fxLabels[index]
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(fxKindTapped87(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 36),
                button.heightAnchor.constraint(equalToConstant: 36),
            ])
            fxGroup87.addArrangedSubview(button)
            fxButtons87.append(button)
        }

        // 聚焦行：layers 图标＋海报聚焦叠色开关。
        let focusIcon = UIImageView(image: DeckGlyph82.image(.layers, pointSize: 17))
        focusIcon.tintColor = UIColor.white.withAlphaComponent(0.8)
        focusIcon.contentMode = .center
        focusIcon.translatesAutoresizingMaskIntoConstraints = false
        mainView87.addSubview(focusIcon)
        focusSwitch.isOn = WallLight82.focusEnabled82
        focusSwitch.onTintColor = UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
        focusSwitch.translatesAutoresizingMaskIntoConstraints = false
        focusSwitch.accessibilityLabel = "海报聚焦叠色"
        focusSwitch.addTarget(self, action: #selector(focusSwitchChanged), for: .valueChanged)
        mainView87.addSubview(focusSwitch)

        // 底部行：灯钮＋帮助钮。
        lightSwitch.translatesAutoresizingMaskIntoConstraints = false
        lightSwitch.setOn(WallLight82.isOn, animated: false)
        lightSwitch.onToggle = { on in
            DeckTap82.log(host: "console", zone: "light", view: self.lightSwitch)
            ConsoleFX85.tap(self.lightSwitch, el: "light")
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

        // (87) 队列网格视图：返回钮＋封面网格。
        let backButton87 = UIButton(type: .system)
        backButton87.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton87.tintColor = .white
        backButton87.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        backButton87.layer.cornerRadius = 18
        backButton87.accessibilityLabel = "返回"
        backButton87.translatesAutoresizingMaskIntoConstraints = false
        backButton87.addTarget(self, action: #selector(backTapped87), for: .touchUpInside)
        queueView87.addSubview(backButton87)
        let gridLayout = UICollectionViewFlowLayout()
        gridLayout.scrollDirection = .vertical
        gridLayout.minimumInteritemSpacing = 10
        gridLayout.minimumLineSpacing = 12
        grid87 = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        grid87.backgroundColor = .clear
        grid87.showsVerticalScrollIndicator = false
        grid87.dataSource = self
        grid87.delegate = self
        grid87.register(CoverGridCell87.self, forCellWithReuseIdentifier: "grid87")
        grid87.translatesAutoresizingMaskIntoConstraints = false
        queueView87.addSubview(grid87)
        NSLayoutConstraint.activate([
            backButton87.topAnchor.constraint(equalTo: queueView87.topAnchor, constant: 12),
            backButton87.leadingAnchor.constraint(equalTo: queueView87.leadingAnchor, constant: 16),
            backButton87.widthAnchor.constraint(equalToConstant: 36),
            backButton87.heightAnchor.constraint(equalToConstant: 36),
            grid87.topAnchor.constraint(equalTo: backButton87.bottomAnchor, constant: 8),
            grid87.leadingAnchor.constraint(equalTo: queueView87.leadingAnchor, constant: 12),
            grid87.trailingAnchor.constraint(equalTo: queueView87.trailingAnchor, constant: -12),
            grid87.bottomAnchor.constraint(equalTo: queueView87.bottomAnchor, constant: -12),
        ])

        // 朝向无关的内层约束（分段两钮恒在 segContainer
        // 内、两钮尺寸恒定）先恒激活。
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: 32),
            clearButton.heightAnchor.constraint(equalToConstant: 28),
            segTranslucent.leadingAnchor.constraint(equalTo: segContainer.leadingAnchor, constant: 3),
            segTranslucent.centerYAnchor.constraint(equalTo: segContainer.centerYAnchor),
            segTranslucent.widthAnchor.constraint(equalToConstant: 34),
            segTranslucent.heightAnchor.constraint(equalToConstant: 22),
            segSolid.trailingAnchor.constraint(equalTo: segContainer.trailingAnchor, constant: -3),
            segSolid.centerYAnchor.constraint(equalTo: segContainer.centerYAnchor),
            segSolid.widthAnchor.constraint(equalToConstant: 34),
            segSolid.heightAnchor.constraint(equalToConstant: 22),
            helpButton.widthAnchor.constraint(equalToConstant: 32),
            helpButton.heightAnchor.constraint(equalToConstant: 32),
            // (89) §4：音量行高对齐网页 38（滑杆命中高）。
            volumeSlider.heightAnchor.constraint(equalToConstant: 38),
        ])
        // (87) 竖屏单列链（自上而下：条带/钮排/功能行/
        // 音量/图层/聚焦/灯行；(89) 后总高 390 ≤ 400 卡高）。
        portraitConstraints85 = [
            clearButton.topAnchor.constraint(equalTo: mainView87.topAnchor, constant: 12),
            clearButton.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -16),

            stripScroll87.topAnchor.constraint(equalTo: mainView87.topAnchor, constant: 12),
            stripScroll87.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 16),
            stripScroll87.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            stripScroll87.heightAnchor.constraint(equalToConstant: 86),

            transRow87.topAnchor.constraint(equalTo: stripScroll87.bottomAnchor, constant: 10),
            transRow87.centerXAnchor.constraint(equalTo: mainView87.centerXAnchor),
            transRow87.heightAnchor.constraint(equalToConstant: 54),

            // (89) §4：功能行边距 24 → 12（296 卡宽下六格
            // 42 宽＋间隙 4 的网页账）、行高 44 → 40。
            functionRow.topAnchor.constraint(equalTo: transRow87.bottomAnchor, constant: 12),
            functionRow.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 12),
            functionRow.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -12),
            functionRow.heightAnchor.constraint(equalToConstant: 40),

            speaker.topAnchor.constraint(equalTo: functionRow.bottomAnchor, constant: 12),
            speaker.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 24),
            speaker.widthAnchor.constraint(equalToConstant: 30),
            speaker.heightAnchor.constraint(equalToConstant: 30),
            volumeSlider.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeSlider.leadingAnchor.constraint(equalTo: speaker.trailingAnchor, constant: 10),
            volumeSlider.trailingAnchor.constraint(equalTo: volumeValue89.leadingAnchor, constant: -8),
            volumeValue89.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeValue89.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -24),
            volumeValue89.widthAnchor.constraint(equalToConstant: 38),

            layers.topAnchor.constraint(equalTo: speaker.bottomAnchor, constant: 14),
            layers.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 24),
            layers.widthAnchor.constraint(equalToConstant: 24),
            layers.heightAnchor.constraint(equalToConstant: 24),
            segContainer.centerYAnchor.constraint(equalTo: layers.centerYAnchor),
            segContainer.leadingAnchor.constraint(equalTo: layers.trailingAnchor, constant: 10),
            segContainer.widthAnchor.constraint(equalToConstant: 76),
            segContainer.heightAnchor.constraint(equalToConstant: 28),
            fxGroup87.centerYAnchor.constraint(equalTo: layers.centerYAnchor),
            fxGroup87.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -16),

            focusIcon.topAnchor.constraint(equalTo: layers.bottomAnchor, constant: 12),
            focusIcon.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 24),
            focusIcon.widthAnchor.constraint(equalToConstant: 24),
            focusIcon.heightAnchor.constraint(equalToConstant: 24),
            focusSwitch.centerYAnchor.constraint(equalTo: focusIcon.centerYAnchor),
            focusSwitch.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -24),

            lightSwitch.topAnchor.constraint(equalTo: focusIcon.bottomAnchor, constant: 14),
            lightSwitch.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 24),
            helpButton.centerYAnchor.constraint(equalTo: lightSwitch.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -24),
        ]
        // (87) 横屏双列链：左列＝条带＋钮排＋功能行；右
        // 列＝音量/图层/聚焦/灯光四行（卡高 232 内成立）。
        landscapeConstraints85 = [
            clearButton.topAnchor.constraint(equalTo: mainView87.topAnchor, constant: 12),
            clearButton.trailingAnchor.constraint(equalTo: stripScroll87.trailingAnchor),

            stripScroll87.topAnchor.constraint(equalTo: mainView87.topAnchor, constant: 12),
            stripScroll87.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 16),
            stripScroll87.widthAnchor.constraint(equalTo: mainView87.widthAnchor, multiplier: 0.44),
            stripScroll87.heightAnchor.constraint(equalToConstant: 82),

            transRow87.topAnchor.constraint(equalTo: stripScroll87.bottomAnchor, constant: 8),
            transRow87.centerXAnchor.constraint(equalTo: stripScroll87.centerXAnchor),
            transRow87.heightAnchor.constraint(equalToConstant: 54),

            functionRow.topAnchor.constraint(equalTo: transRow87.bottomAnchor, constant: 8),
            functionRow.leadingAnchor.constraint(equalTo: mainView87.leadingAnchor, constant: 16),
            functionRow.trailingAnchor.constraint(equalTo: stripScroll87.trailingAnchor),
            functionRow.heightAnchor.constraint(equalToConstant: 40),

            speaker.topAnchor.constraint(equalTo: mainView87.topAnchor, constant: 16),
            speaker.leadingAnchor.constraint(equalTo: stripScroll87.trailingAnchor, constant: 28),
            speaker.widthAnchor.constraint(equalToConstant: 30),
            speaker.heightAnchor.constraint(equalToConstant: 30),
            volumeSlider.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeSlider.leadingAnchor.constraint(equalTo: speaker.trailingAnchor, constant: 10),
            volumeSlider.trailingAnchor.constraint(equalTo: volumeValue89.leadingAnchor, constant: -8),
            volumeValue89.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeValue89.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -24),
            volumeValue89.widthAnchor.constraint(equalToConstant: 38),

            layers.topAnchor.constraint(equalTo: speaker.bottomAnchor, constant: 14),
            layers.leadingAnchor.constraint(equalTo: speaker.leadingAnchor),
            layers.widthAnchor.constraint(equalToConstant: 24),
            layers.heightAnchor.constraint(equalToConstant: 24),
            segContainer.centerYAnchor.constraint(equalTo: layers.centerYAnchor),
            segContainer.leadingAnchor.constraint(equalTo: layers.trailingAnchor, constant: 10),
            segContainer.widthAnchor.constraint(equalToConstant: 76),
            segContainer.heightAnchor.constraint(equalToConstant: 28),
            fxGroup87.centerYAnchor.constraint(equalTo: layers.centerYAnchor),
            fxGroup87.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -16),

            focusIcon.topAnchor.constraint(equalTo: layers.bottomAnchor, constant: 14),
            focusIcon.leadingAnchor.constraint(equalTo: speaker.leadingAnchor),
            focusIcon.widthAnchor.constraint(equalToConstant: 24),
            focusIcon.heightAnchor.constraint(equalToConstant: 24),
            focusSwitch.centerYAnchor.constraint(equalTo: focusIcon.centerYAnchor),
            focusSwitch.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -24),

            lightSwitch.topAnchor.constraint(equalTo: focusIcon.bottomAnchor, constant: 14),
            lightSwitch.leadingAnchor.constraint(equalTo: speaker.leadingAnchor),
            helpButton.centerYAnchor.constraint(equalTo: lightSwitch.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: mainView87.trailingAnchor, constant: -24),
        ]
        // 初始按竖屏集落位；首个布局回调按真实朝向校正。
        NSLayoutConstraint.activate(portraitConstraints85)

        refreshModeButton()
        refreshLikeButton()
        refreshPawButton()
        refreshSegButtons()
        refreshTrans87()
        refreshFxButtons87()
        GlobalFx87.shared.onStateChanged = { [weak self] in
            self?.refreshFxButtons87()
        }
        bindState()
        Breadcrumbs.log("port89 console=right/w296/r24/fn42x40/vol30+val")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // (86) 第 7 条＋横屏核查：朝向定布局集与卡尺寸
        // （切换只在朝向真变时发生、防布局回环）。
        let bounds = view.bounds
        let landscape = bounds.width > bounds.height
        if consoleLandscape86 != landscape {
            consoleLandscape86 = landscape
            NSLayoutConstraint.deactivate(
                landscape ? portraitConstraints85 : landscapeConstraints85)
            NSLayoutConstraint.activate(
                landscape ? landscapeConstraints85 : portraitConstraints85)
            grid87?.collectionViewLayout.invalidateLayout()
            Breadcrumbs.log("console86 land=\(landscape ? 1 : 0)")
        }
        // (89) §4：竖屏卡宽对齐网页面板 min(296, 屏宽−32)；
        // 横屏双列 640 系 (86) 定案，不在本次对齐面。
        let cardW = landscape ? min(bounds.width * 0.86, 640)
                              : min(296, bounds.width - 32)
        if let cardWidth85, abs(cardWidth85.constant - cardW) > 0.5 {
            cardWidth85.constant = cardW
        }
        // 卡高：竖屏 (89) §4 改内容链高口径 min(400, 62%
        // 屏高)——链账：顶 12＋条带 86＋10＋钮排 54＋12＋
        // 功能 40＋12＋音量 30＋14＋图层 24＋12＋聚焦 24
        // ＋14＋灯 46＝390，底留 10；横屏按双列内容高
        // 232 与贴底可用高（屏高−安全底−90 锚距−顶距 8）
        // 取小——贴底锚下不超屏。
        let cardH: CGFloat
        if landscape {
            let avail = bounds.height - view.safeAreaInsets.bottom - 90 - 8
            cardH = min(232, avail)
        } else {
            cardH = min(400, bounds.height * 0.62)
        }
        if let cardHeight85, abs(cardHeight85.constant - cardH) > 0.5 {
            cardHeight85.constant = cardH
        }
    }

    /// (85) 第 7 条：入场——卡弹簧缩放＋淡入（iOS 系统
    /// 弹簧口径，禁线性）。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction]) {
            self.card85.alpha = 1
            self.card85.transform = .identity
        }
        refreshTrans87()
    }

    /// (85) 第 7 条：点卡外（压暗区）关闭。
    @objc private func dimTapped85(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.view === view,
              !card85.frame.contains(recognizer.location(in: view)) else { return }
        Breadcrumbs.log("console85 tap el=outside")
        dismiss(animated: true)
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
    private func refreshQueueViews87() {
        stripTiles87.forEach { $0.removeFromSuperview() }
        stripTiles87 = []
        let count = queueTracks.count
        if count > 0 {
            let start = queueCurrent >= 0 && queueCurrent < count ? queueCurrent : 0
            for offset in 0..<count {
                let index = (start + offset) % count
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
        }
        grid87?.reloadData()
    }

    @objc private func stripTileTapped87(_ sender: CoverTile87) {
        ConsoleFX85.tap(sender, el: "queue")
        Breadcrumbs.log("console87 strip play idx=\(sender.tag)")
        QueueManager.shared.playAtIndex(sender.tag)
        dismiss(animated: true)
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
            grid87.reloadData()
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

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        queueTracks.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "grid87", for: indexPath) as! CoverGridCell87
        cell.configure(track: queueTracks[indexPath.item],
                       index: indexPath.item,
                       isCurrent: indexPath.item == queueCurrent,
                       isPlaying: PlaybackEngine.shared.isPlaying)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        Breadcrumbs.log("console87 grid play idx=\(indexPath.item)")
        QueueManager.shared.playAtIndex(indexPath.item)
        dismiss(animated: true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let columns: CGFloat = width > 500 ? 6 : 4
        let side = floor((width - (columns - 1) * 10) / columns)
        return CGSize(width: side, height: side + 30)
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
        // (89) §4：功能格对齐网页快捷格——图标 18、格 42×40。
        button.setImage(DeckGlyph82.image(glyph, pointSize: 18), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 12
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    /// (87) 顶部钮排圆玻璃钮（样片 .tbtn）。
    private func configureTransButton87(_ button: UIButton,
                                        glyph: DeckGlyph82.Kind,
                                        size: CGFloat, label: String) {
        button.setImage(DeckGlyph82.image(glyph, pointSize: size >= 54 ? 22 : 19), for: .normal)
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
    }

    private func refreshTrans87() {
        let playing = PlaybackEngine.shared.isPlaying
        transPlay87.setImage(
            DeckGlyph82.image(playing ? .pause : .play, pointSize: 22), for: .normal)
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
            dismiss(animated: true) { onEffects() }
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
        StickerSettings.miniPetsEnabled = !was
        if !was {
            // (85) 第 7 条：烟花宿主改卡内坐标（内容已迁卡）。
            PawFirework81.burst(in: card85,
                                at: sender.convert(
                                    CGPoint(x: sender.bounds.midX,
                                            y: sender.bounds.midY), to: card85))
        }
        refreshPawButton()
        Breadcrumbs.log("console82 paw on=\(!was ? 1 : 0)")
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
            dismiss(animated: true) { onSketchbook() }
        } else {
            NativePlaybackFailureToast.show(message: "速记簿在主页墙左缘打开")
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

    @objc private func focusSwitchChanged(_ sender: UISwitch) {
        DeckTap82.log(host: "console", zone: "focus", view: sender)
        ConsoleFX85.tap(sender, el: "focus")
        WallLight82.focusEnabled82 = sender.isOn
        Breadcrumbs.log("console82 focus=\(sender.isOn ? 1 : 0)")
    }

    @objc private func helpTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "help", view: sender)
        ConsoleFX85.tap(sender, el: "help")
        let alert = UIAlertController(
            title: "控制台",
            message: "队列：顶部封面条左右滑，点封面立即播放；列表钮打开封面网格，右上垃圾桶清空队列。\n"
                + "顶部圆钮：上一曲、播放/暂停、下一曲。\n"
                + "功能行：播放模式（点一下换一种：随机→顺序→循环→单曲）、歌曲列表、特效、宠物开关、喜欢、速记簿。\n"
                + "图层行：透光/实色切换墙面卡片质感；旁边四钮是全屏特效（烟花、孔明灯、下雪、刮风）；聚焦叠色开时，关灯后只有点中的封面亮起。\n"
                + "灯钮：开灯＝全部封面亮起；关灯＝整墙暗下、点哪张亮哪张。\n"
                + "播放台 5 秒无操作自动收成细条，点细条恢复。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
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
