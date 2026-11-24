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
final class ConsolePanel82: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var onEffects: (() -> Void)?
    private var onSketchbook: (() -> Void)?

    private let queueTable = UITableView(frame: .zero, style: .plain)
    private var queueTracks: [FoliaTrack] = []
    private var queueCurrent = -1
    private var cancellables = Set<AnyCancellable>()

    private let modeButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    private let pawButton = UIButton(type: .system)
    private let volumeSlider = UISlider()
    private let segTranslucent = UIButton(type: .system)
    private let segSolid = UIButton(type: .system)
    private let focusSwitch = UISwitch()
    private let lightSwitch = LightSwitch82()
    /// (85) 第 7 条：悬浮卡本体与高度约束（高度在布局时
    /// 按 min(内容高, 62% 屏高) 收口）。
    private let card85 = UIView()
    private var cardHeight85: NSLayoutConstraint?

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
        card85.layer.cornerRadius = 28
        card85.layer.borderWidth = 1
        card85.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card85.clipsToBounds = true
        card85.translatesAutoresizingMaskIntoConstraints = false
        card85.alpha = 0
        card85.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            .translatedBy(x: 0, y: 10)
        view.addSubview(card85)
        cardHeight85 = card85.heightAnchor.constraint(equalToConstant: 424)
        NSLayoutConstraint.activate([
            card85.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card85.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card85.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
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

        // 队列头行：仅右上清空钮（G2 去字口径，无标题）。
        let clearButton = UIButton(type: .system)
        clearButton.setImage(DeckGlyph82.image(.trash, pointSize: 16), for: .normal)
        clearButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        clearButton.accessibilityLabel = "清空队列"
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearQueueTapped), for: .touchUpInside)
        card85.addSubview(clearButton)

        queueTable.dataSource = self
        queueTable.delegate = self
        queueTable.backgroundColor = .clear
        queueTable.separatorStyle = .none
        queueTable.rowHeight = 44
        queueTable.showsVerticalScrollIndicator = false
        queueTable.register(UITableViewCell.self, forCellReuseIdentifier: "q82")
        queueTable.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(queueTable)
        // 底部渐隐（露约 3.5 行后淡出，示意可滚动）。
        let fade = CAGradientLayer()
        fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor,
                       UIColor.clear.cgColor]
        fade.locations = [0, 0.82, 1]
        queueTable.layer.mask = fade
        queueTable.layer.name = "fade82"

        // 功能行（纯图标、无文字标签）。
        let fxButton = makeIconButton(.sparkles, action: #selector(effectsTapped), label: "特效")
        let sketchButton = makeIconButton(.pencil, action: #selector(sketchbookTapped), label: "速记簿")
        configureIconButton(modeButton, glyph: .modeRepeat, label: "播放模式")
        modeButton.showsMenuAsPrimaryAction = true
        configureIconButton(shuffleButton, glyph: .shuffle, label: "随机")
        shuffleButton.addTarget(self, action: #selector(shuffleTapped), for: .touchUpInside)
        configureIconButton(pawButton, glyph: .paw, label: "宠物")
        pawButton.addTarget(self, action: #selector(pawTapped), for: .touchUpInside)
        configureIconButton(likeButton, glyph: .heart, label: "喜欢")
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        let functionRow = UIStackView(arrangedSubviews: [
            modeButton, shuffleButton, fxButton, pawButton, likeButton, sketchButton])
        functionRow.axis = .horizontal
        functionRow.distribution = .equalSpacing
        functionRow.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(functionRow)

        // 音量行。
        let speaker = UIImageView(image: DeckGlyph82.image(.speaker, pointSize: 16))
        speaker.tintColor = UIColor.white.withAlphaComponent(0.8)
        speaker.contentMode = .center
        speaker.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(speaker)
        volumeSlider.minimumTrackTintColor = .white
        volumeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        volumeSlider.value = PlaybackEngine.shared.volume
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        // (85) 第 7 条：滑杆点按特效只走闪光环（不缩放，
        // 免拖动中拇指抖动），按下即落 console85。
        volumeSlider.addTarget(self, action: #selector(volumeTouched85), for: .touchDown)
        card85.addSubview(volumeSlider)

        // 外观行：layers 图标＋透光/实色图形分段＋聚焦开关。
        let layers = UIImageView(image: DeckGlyph82.image(.layers, pointSize: 16))
        layers.tintColor = UIColor.white.withAlphaComponent(0.8)
        layers.contentMode = .center
        layers.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(layers)
        let segContainer = UIView()
        segContainer.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        segContainer.layer.cornerRadius = 14
        segContainer.translatesAutoresizingMaskIntoConstraints = false
        card85.addSubview(segContainer)
        for (button, translucent) in [(segTranslucent, true), (segSolid, false)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.cornerRadius = 11
            button.accessibilityLabel = translucent ? "透光" : "实色"
            button.addTarget(self, action: #selector(segTapped(_:)), for: .touchUpInside)
            segContainer.addSubview(button)
        }
        segTranslucent.tag = 0
        segSolid.tag = 1
        focusSwitch.isOn = WallLight82.focusEnabled82
        focusSwitch.onTintColor = UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
        focusSwitch.translatesAutoresizingMaskIntoConstraints = false
        focusSwitch.accessibilityLabel = "海报聚焦叠色"
        focusSwitch.addTarget(self, action: #selector(focusSwitchChanged), for: .valueChanged)
        card85.addSubview(focusSwitch)

        // 底部行：灯钮＋帮助钮。
        lightSwitch.translatesAutoresizingMaskIntoConstraints = false
        lightSwitch.setOn(WallLight82.isOn, animated: false)
        lightSwitch.onToggle = { on in
            DeckTap82.log(host: "console", zone: "light", view: self.lightSwitch)
            ConsoleFX85.tap(self.lightSwitch, el: "light")
            WallLight82.setOn(on, source: "console")
        }
        card85.addSubview(lightSwitch)
        let helpButton = UIButton(type: .system)
        helpButton.setImage(DeckGlyph82.image(.help, pointSize: 17), for: .normal)
        helpButton.tintColor = .white
        helpButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        helpButton.layer.cornerRadius = 19
        helpButton.accessibilityLabel = "帮助"
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        card85.addSubview(helpButton)

        // (85) 第 7 条：内容约束整体改锚卡内边（原锚根视
        // 图边）；卡内布局数值与 (82) 一致、功能不丢。
        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: card85.topAnchor, constant: 16),
            clearButton.trailingAnchor.constraint(equalTo: card85.trailingAnchor, constant: -16),
            clearButton.widthAnchor.constraint(equalToConstant: 32),
            clearButton.heightAnchor.constraint(equalToConstant: 28),

            queueTable.topAnchor.constraint(equalTo: clearButton.bottomAnchor, constant: 2),
            queueTable.leadingAnchor.constraint(equalTo: card85.leadingAnchor, constant: 12),
            queueTable.trailingAnchor.constraint(equalTo: card85.trailingAnchor, constant: -12),
            queueTable.heightAnchor.constraint(equalToConstant: 150),

            functionRow.topAnchor.constraint(equalTo: queueTable.bottomAnchor, constant: 12),
            functionRow.leadingAnchor.constraint(equalTo: card85.leadingAnchor, constant: 24),
            functionRow.trailingAnchor.constraint(equalTo: card85.trailingAnchor, constant: -24),
            functionRow.heightAnchor.constraint(equalToConstant: 44),

            speaker.topAnchor.constraint(equalTo: functionRow.bottomAnchor, constant: 14),
            speaker.leadingAnchor.constraint(equalTo: card85.leadingAnchor, constant: 24),
            speaker.widthAnchor.constraint(equalToConstant: 24),
            speaker.heightAnchor.constraint(equalToConstant: 24),
            volumeSlider.centerYAnchor.constraint(equalTo: speaker.centerYAnchor),
            volumeSlider.leadingAnchor.constraint(equalTo: speaker.trailingAnchor, constant: 10),
            volumeSlider.trailingAnchor.constraint(equalTo: card85.trailingAnchor, constant: -24),

            layers.topAnchor.constraint(equalTo: speaker.bottomAnchor, constant: 16),
            layers.leadingAnchor.constraint(equalTo: card85.leadingAnchor, constant: 24),
            layers.widthAnchor.constraint(equalToConstant: 24),
            layers.heightAnchor.constraint(equalToConstant: 24),
            segContainer.centerYAnchor.constraint(equalTo: layers.centerYAnchor),
            segContainer.leadingAnchor.constraint(equalTo: layers.trailingAnchor, constant: 10),
            segContainer.widthAnchor.constraint(equalToConstant: 76),
            segContainer.heightAnchor.constraint(equalToConstant: 28),
            segTranslucent.leadingAnchor.constraint(equalTo: segContainer.leadingAnchor, constant: 3),
            segTranslucent.centerYAnchor.constraint(equalTo: segContainer.centerYAnchor),
            segTranslucent.widthAnchor.constraint(equalToConstant: 34),
            segTranslucent.heightAnchor.constraint(equalToConstant: 22),
            segSolid.trailingAnchor.constraint(equalTo: segContainer.trailingAnchor, constant: -3),
            segSolid.centerYAnchor.constraint(equalTo: segContainer.centerYAnchor),
            segSolid.widthAnchor.constraint(equalToConstant: 34),
            segSolid.heightAnchor.constraint(equalToConstant: 22),
            focusSwitch.centerYAnchor.constraint(equalTo: layers.centerYAnchor),
            focusSwitch.trailingAnchor.constraint(equalTo: card85.trailingAnchor, constant: -24),

            lightSwitch.topAnchor.constraint(equalTo: layers.bottomAnchor, constant: 18),
            lightSwitch.leadingAnchor.constraint(equalTo: card85.leadingAnchor, constant: 24),
            helpButton.centerYAnchor.constraint(equalTo: lightSwitch.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: card85.trailingAnchor, constant: -24),
            helpButton.widthAnchor.constraint(equalToConstant: 38),
            helpButton.heightAnchor.constraint(equalToConstant: 38),
        ])

        refreshModeButton()
        refreshShuffleButton()
        refreshLikeButton()
        refreshPawButton()
        refreshSegButtons()
        bindState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let fade = queueTable.layer.mask as? CAGradientLayer {
            fade.frame = queueTable.bounds
        }
        // (85) 第 7 条：卡高＝内容高 424 与 62% 屏高取小
        // （横屏矮屏不超屏）；宽度 82% 由乘数约束恒成立，
        // 横竖屏均居中（centerX/centerY 约束）。
        let cap = view.bounds.height * 0.62
        let target = min(424, cap)
        if let cardHeight85, abs(cardHeight85.constant - target) > 0.5 {
            cardHeight85.constant = target
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
                self?.queueTable.reloadData()
            }
            .store(in: &cancellables)
        QueueManager.shared.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                self?.queueCurrent = index
                self?.queueTable.reloadData()
            }
            .store(in: &cancellables)
        QueueManager.shared.$playMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshModeButton()
                self?.refreshShuffleButton()
            }
            .store(in: &cancellables)
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLikeButton() }
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
        button.setImage(DeckGlyph82.image(glyph, pointSize: 17), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 12
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func refreshModeButton() {
        let mode = QueueManager.shared.playMode
        let glyph: DeckGlyph82.Kind
        switch mode {
        case .off: glyph = .modeSequence
        case .loopAll: glyph = .modeRepeat
        case .repeatOne: glyph = .modeRepeatOne
        case .shuffle: glyph = .shuffle
        }
        modeButton.setImage(DeckGlyph82.image(glyph, pointSize: 17), for: .normal)
        modeButton.tintColor = mode == .off
            ? UIColor.white.withAlphaComponent(0.55) : .white
        let items: [(QueueManager.PlayMode, String)] = [
            (.off, "顺序"), (.loopAll, "循环"), (.repeatOne, "单曲"), (.shuffle, "随机"),
        ]
        modeButton.menu = UIMenu(children: items.map { item in
            let action = UIAction(title: item.1) { [weak self] _ in
                guard let self else { return }
                DeckTap82.log(host: "console", zone: "mode", view: self.modeButton)
                ConsoleFX85.tap(self.modeButton, el: "mode")
                QueueManager.shared.playMode = item.0
                Breadcrumbs.log("console82 mode=\(item.0.rawValue)")
            }
            action.state = item.0 == mode ? .on : .off
            return action
        })
    }

    private func refreshShuffleButton() {
        let on = QueueManager.shared.playMode == .shuffle
        shuffleButton.tintColor = on
            ? UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1) : .white
        shuffleButton.backgroundColor = on
            ? UIColor.white.withAlphaComponent(0.22)
            : UIColor.white.withAlphaComponent(0.10)
    }

    private func refreshLikeButton() {
        let liked = PlaybackEngine.shared.currentTrack
            .map { LikesStore.shared.isLiked($0.id) } ?? false
        likeButton.setImage(
            DeckGlyph82.image(liked ? .heartFill : .heart, pointSize: 17), for: .normal)
        likeButton.tintColor = liked
            ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1) : .white
    }

    private func refreshPawButton() {
        let on = StickerSettings.miniPetsEnabled
        pawButton.tintColor = on
            ? .white : UIColor.white.withAlphaComponent(0.45)
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

    @objc private func shuffleTapped(_ sender: UIButton) {
        DeckTap82.log(host: "console", zone: "shuffle", view: sender)
        ConsoleFX85.tap(sender, el: "shuffle")
        let queue = QueueManager.shared
        queue.playMode = queue.playMode == .shuffle ? .off : .shuffle
        Breadcrumbs.log("console82 shuffle=\(queue.playMode == .shuffle ? 1 : 0)")
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
            message: "队列：点任意一行立即播放，右上垃圾桶清空队列。\n"
                + "功能行：播放模式、随机、特效、宠物开关、喜欢、速记簿。\n"
                + "外观：透光/实色切换墙面卡片质感；聚焦叠色开时，关灯后只有点中的封面亮起。\n"
                + "灯钮：开灯＝全部封面亮起；关灯＝整墙暗下、点哪张亮哪张。\n"
                + "播放台 5 秒无操作自动收成细条，点细条恢复。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    // MARK: 队列列表

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        queueTracks.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "q82", for: indexPath)
        let track = queueTracks[indexPath.row]
        let isCurrent = indexPath.row == queueCurrent
        var config = UIListContentConfiguration.valueCell()
        config.text = track.title
        config.secondaryText = track.artist
        config.textProperties.color = isCurrent
            ? UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1) : .white
        config.textProperties.font = .systemFont(ofSize: 14, weight: isCurrent ? .semibold : .regular)
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.55)
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        cell.contentConfiguration = config
        cell.backgroundColor = isCurrent
            ? UIColor.white.withAlphaComponent(0.08) : .clear
        cell.selectionStyle = .none
        cell.accessoryView = isCurrent
            ? UIImageView(image: DeckGlyph82.image(.speaker, pointSize: 14))
            : nil
        (cell.accessoryView as? UIImageView)?.tintColor =
            UIColor(red: 0.96, green: 0.72, blue: 0.25, alpha: 1)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        DeckTap82.log(host: "console", zone: "qrow",
                      point: CGPoint(x: indexPath.row, y: 0))
        if let cell = tableView.cellForRow(at: indexPath) {
            ConsoleFX85.tap(cell, el: "queue")
        } else {
            Breadcrumbs.log("console85 tap el=queue")
        }
        Breadcrumbs.log("console82 queue play idx=\(indexPath.row)")
        QueueManager.shared.playAtIndex(indexPath.row)
        dismiss(animated: true)
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
