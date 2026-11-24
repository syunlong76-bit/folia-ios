import Combine
import UIKit

/// 点播台上排（网页播放卡顶排）的 UIKit 唯一实现。
///
/// 沿革：(54) 工作流 H 按网页功能矩阵接入五钮（喜欢/打乱/
/// 模式/睡眠/设置）；(55) 工作流 C 按 Miller 03:00 口径推翻
/// 其构成，改为网页播放卡顶排六钮——构成以网页
/// CapsuleQuickActions＋播放卡顶排为准，不再自创组合：
///
/// - 喜欢：LikesStore.toggle ＋ NativeDataClient.setLike 云端
///   同步（失败回滚），回显 = LikesStore 本地真源。沿用 (54)。
/// - 星标：StarStore 本地真源（(55) C 新建，UserDefaults 集
///   合 folia.starredTrackIDs），按当前歌曲实时显态、点按切
///   换；网页星标＝加入歌单（AddToPlaylist 本体未迁），本期
///   星标只落本地集合＋FoliaStarChanged 通知，不冒充入歌单。
/// - 打乱队列：(77) ⑤撤下台面（原钮位由爪印接管），
///   QueueManager.shuffleQueue 本体保留，入口存于队列面
///   板与命令面板（去向见 (77) 报告⑤）。
/// - 格子（面板）/ 命令键：本体在别的工作流，本视图只发信
///   号——点按 post .foliaMiniBarPanel / .foliaMiniBarCommand
///   （名称定死，宿主工作流按此订阅），并落同词根面包屑。
///   字幕钮已于 (60) 第 11 条整组删除（字幕层/面板/store 一
///   并退役，.foliaMiniBarSubtitle 通知随之作废）。
///
/// 退出顶排（(55) C 定案，不许再放回本排）：播放模式（队列
/// 面板与设置里已有四档切换）、睡眠定时（改走命令面板/面
/// 板控制页签）、设置（侧栏设置行与面板承接）。
///
/// 每钮图标＋小字标签双通道（标签 喜欢/星标/打乱/面板/
/// 命令，10pt），根治 (54) 真机点名的「打乱与模式随机档图
/// 标几乎一样、又无文字」。五钮等宽平分整排，任一屏宽下单
/// 钮命中宽 ≥40pt。按下态反馈：configurationUpdateHandler
/// 给高亮态加白 14% 圆角底＋0.92 缩放（系统式即时反馈，不
/// 用罩体染色）。
///
/// 展开高度单一出处：rowHeight / expandedBarHeight 两常量
/// 为宿主应读的唯一真源。(60) 第 7 条起本排迁出点播台本
/// 体、改住透明浮层（MiniBarQuickRowOverlayView），台高回
/// 落为不含上排的 70；rowHeight 仍是浮层胶囊内本排的高度。
///
/// 宿主接线：onUserInteraction（任一键点按先回调，宿主据此
/// 重置 5 秒无操作计时，与台面其他操作同口径续命）；
/// onLikeStateChanged（喜欢态变化后回调，舞台宿主据此刷新
/// 顶栏红心）；onOpenSettings（(54) 遗留属性：(55) C 起顶
/// 排已无设置钮、本回调不再被触发，保留仅为不打断宿主现
/// 有接线编译，宿主工作流移除接线后可删）。形态名单由宿
/// 主收口：宿主把本视图加入收起态 alpha 淡出名单、并以
/// isUserInteractionEnabled 整体开关交互（收起细条上不许
/// 点）。播放列表入口不在本排也不在台面（(53) H 修正定
/// 版）：舞台在顶栏隐藏排、曲目墙在顶部 chrome 排、主页
/// 墙台面无此钮。
final class MiniBarQuickRowView: UIView {

    /// 上排自身高度：图标 17pt＋图标/标签间距 2＋标签 10pt
    /// 行高约 12＋上下内距 5×2 ≈ 41，取 48 留呼吸。宿主给
    /// 本排的 heightAnchor 应改读本值（现写死 44）。
    static let rowHeight: CGFloat = 48

    /// 展开态点播台总高（唯一出处）：(82) 第 7 条 E 极简
    /// 台定版改 132（封面行 14+46／进度行／控制行三段）；
    /// 与 DeckLayout82.expandedHeight 同值，宿主读本常量
    /// 处自动跟随，四宿主同台同尺寸由此收口。
    static let expandedBarHeight: CGFloat = 132

    var onUserInteraction: (() -> Void)?
    var onLikeStateChanged: (() -> Void)?
    /// (54) 遗留：顶排设置钮已随 (55) C 移除，本回调不再
    /// 触发；保留声明避免打断宿主现有接线，待宿主工作流
    /// 移除接线后删除。
    var onOpenSettings: (() -> Void)?

    private let likeButton = UIButton(type: .system)
    /// (68) A1：喜欢填充态（refreshLike 写、configurationUpdateHandler 读）。
    private var likeFilled = false
    private let starButton = UIButton(type: .system)
    /// (77) ⑤：原打乱钮位由爪印接管，与退役的窗口爪印
    /// 同一切换核 PetSummonButton70.performPawToggle77。
    /// 打乱队列撤下台面——去向：队列面板与命令面板内仍
    /// 可达（见 (77) 报告⑤）。(81) 第 10 条：交互改单击
    /// 切换（原长按 2s/3s 退役）。
    private let pawButton = UIButton(type: .system)
    private let panelButton = UIButton(type: .system)
    private let commandButton = UIButton(type: .system)

    private var cancellables = Set<AnyCancellable>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildButtons()
        bindState()
        refreshAll()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight)
    }

    private func buildButtons() {
        configure(likeButton, symbol: "heart", pointSize: 17,
                  title: "喜欢", accessibility: "喜欢",
                  action: #selector(likeTapped))
        configure(starButton, symbol: "star", pointSize: 16,
                  title: "星标", accessibility: "星标",
                  action: #selector(starTapped))
        configure(pawButton, symbol: "pawprint.fill", pointSize: 16,
                  title: "宠物", accessibility: "宠物开关",
                  action: #selector(pawTapped))
        // (81) 第 10 条：长按识别器整套摘除（长按语义退
        // 役），单击切换；按下即回调宿主续命浮层闲置钟。
        pawButton.addTarget(self, action: #selector(pawTouchDown),
                            for: .touchDown)
        configure(panelButton, symbol: "square.grid.2x2", pointSize: 16,
                  title: "面板", accessibility: "面板",
                  action: #selector(panelTapped))
        configure(commandButton, symbol: "command", pointSize: 16,
                  title: "命令", accessibility: "命令",
                  action: #selector(commandTapped))

        // 星标长按（(62) 网页语义分工）：长按 = 切换本地星标，
        // 点按 = 开收藏弹层（见 starTapped）。
        let starLongPress = UILongPressGestureRecognizer(
            target: self, action: #selector(starLongPressed(_:)))
        starLongPress.minimumPressDuration = 0.45
        starButton.addGestureRecognizer(starLongPress)

        // 五钮等宽平分整排：链式等宽＋首尾贴边，钮高撑满
        // 本排。等宽保证任一台宽下每钮命中宽一致（最窄台
        // 宽 353pt 时单钮 ≈70pt）。
        let buttons = [likeButton, starButton, pawButton,
                       panelButton, commandButton]
        for (index, button) in buttons.enumerated() {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: topAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            if index == 0 {
                button.leadingAnchor.constraint(
                    equalTo: leadingAnchor).isActive = true
            } else {
                let previous = buttons[index - 1]
                button.leadingAnchor.constraint(
                    equalTo: previous.trailingAnchor).isActive = true
                button.widthAnchor.constraint(
                    equalTo: previous.widthAnchor).isActive = true
            }
            if index == buttons.count - 1 {
                button.trailingAnchor.constraint(
                    equalTo: trailingAnchor).isActive = true
            }
        }
        // (81) 第 8 条：主题变更自刷整套图标 + 首装即按现
        // 行主题落字形（configure 的 SF 符号只是装配占位）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged81),
            name: .foliaMiniPlayerThemeChanged, object: nil)
        themeChanged81()
    }

    /// 图标在上、标签在下的双通道钮（UIButton.Configuration，
    /// iOS 17 基线，与 WorkbenchOverlayHostView 的 Configuration
    /// 写法同路）。标签恒 10pt medium 白 75%（深底白字，与台
    /// 面深色玻璃底的对比见自查节）；状态色由 refresh* 改
    /// baseForegroundColor（图标与标签同色切换）。
    private func configure(_ button: UIButton, symbol: String,
                           pointSize: CGFloat, title: String,
                           accessibility: String, action: Selector) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize))
        config.imagePlacement = .top
        config.imagePadding = 2
        config.title = title
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.75)
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 5, leading: 2, bottom: 5, trailing: 2)
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 10, weight: .medium)
                return outgoing
            }
        button.configuration = config
        button.accessibilityLabel = accessibility
        // 按下态反馈：高亮时圆角白底 14%＋轻微缩放，松手即
        // 复原。不碰 alpha（打乱钮的禁用态靠 alpha 表达，
        // 两者不许打架）。
        // (68) A1：喜欢钮已喜欢态整钮填充喜欢色——填充由本
        // handler 统一裁决（高亮优先，其次喜欢填充），避免
        // setButtonState 写回 configuration 时被高亮分支冲掉。
        button.configurationUpdateHandler = { [weak self] btn in
            btn.transform = btn.isHighlighted
                ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            var updated = btn.configuration
            let likeFilled = self?.likeButton === btn && (self?.likeFilled ?? false)
            updated?.background.backgroundColor = btn.isHighlighted
                ? UIColor.white.withAlphaComponent(0.14)
                : (likeFilled
                    ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1)
                    : .clear)
            updated?.background.cornerRadius = 10
            btn.configuration = updated
        }
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// 状态显态切换：只换图标与前景色，保留标签与按下态
    /// 配置（configuration 整体替换会丢 updateHandler 写入
    /// 的背景，故在此基础上改两项再写回）。
    private func setButtonState(_ button: UIButton, symbol: String,
                                pointSize: CGFloat, color: UIColor) {
        guard var config = button.configuration else { return }
        config.image = UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize))
        config.baseForegroundColor = color
        button.configuration = config
    }

    /// (81) 第 8 条：主题图标版（DeckIconSet81 字形图）。
    private func setButtonState(_ button: UIButton, image: UIImage,
                                color: UIColor) {
        guard var config = button.configuration else { return }
        config.image = image
        config.baseForegroundColor = color
        button.configuration = config
    }

    /// (81) 第 8 条：当前主题，图标刷新（喜欢/星标状态回
    /// 显）按它取整套字形。宿主不向浮层推主题（applyMini-
    /// Theme 只管主题层与进度 chrome），故浮层自订主题变
    /// 更通知刷新，与三宿主同源同拍。
    private var theme81: MiniPlayerTheme = MiniPlayerTheme.effective

    @objc private func themeChanged81() {
        theme81 = MiniPlayerTheme.effective
        refreshLike()
        refreshStar()
        setButtonState(pawButton,
            image: DeckGlyph82.image(.paw, pointSize: 17) ?? UIImage(),
            color: UIColor.white.withAlphaComponent(0.75))
        setButtonState(panelButton,
            image: DeckGlyph82.image(.sliders, pointSize: 17) ?? UIImage(),
            color: UIColor.white.withAlphaComponent(0.75))
        setButtonState(commandButton,
            image: DeckGlyph82.image(.command, pointSize: 17) ?? UIImage(),
            color: UIColor.white.withAlphaComponent(0.75))
    }

    /// 状态订阅：切歌刷新喜欢与星标、星标外部变更（他面
    /// 切换）刷新星标——全部回主线程。（77）⑤：原队列变
    /// 化刷新打乱可用性随打乱钮撤下台面一并退役。
    private func bindState() {
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLike()
                self?.refreshStar()
            }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            self, selector: #selector(starChanged),
            name: .foliaStarChanged, object: nil)
    }

    func refreshAll() {
        refreshLike()
        refreshStar()
    }

    /// (77) ⑤爪印阈值新鲜度（与窗口爪印同纪律）：触摸落
    /// 到爪印钮前现读开关刷新长按阈值——外部路径（设置/
    /// 长按宠物本体/另一台爪印）改过开关后，本钮下一次按
    /// 下读到的恒为现态。
    // (81) 第 10 条：原 hitTest 覆写只为按宠物开关态动态
    // 改爪印长按时长——长按语义退役后整件删除，命中走默认。

    // MARK: - 回显

    private func refreshLike() {
        let liked = PlaybackEngine.shared.currentTrack
            .map { LikesStore.shared.isLiked($0.id) } ?? false
        // (68) A1：先落填充标志再写回 configuration（handler
        // 据此填整钮喜欢色）；填充后图标与标签转白保证可读，
        // 未喜欢维持现行（白 75% 前景、无填充）。
        likeFilled = liked
        setButtonState(likeButton,
            image: DeckGlyph82.image(liked ? .heartFill : .heart, pointSize: 17) ?? UIImage(),
            color: liked
                ? .white
                : UIColor.white.withAlphaComponent(0.75))
        likeButton.accessibilityLabel = liked ? "取消喜欢" : "喜欢"
        onLikeStateChanged?()
    }

    private func refreshStar() {
        let starred = PlaybackEngine.shared.currentTrack
            .map { StarStore.shared.isStarred($0.id) } ?? false
        setButtonState(starButton,
            image: DeckGlyph82.image(starred ? .starFill : .star, pointSize: 16) ?? UIImage(),
            color: starred
                ? UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1)
                : UIColor.white.withAlphaComponent(0.75))
        starButton.accessibilityLabel = starred ? "取消星标" : "星标"
    }

    @objc private func starChanged() {
        refreshStar()
    }

    // MARK: - 动作（面包屑续用 minibar.webrow 词根）

    @objc private func likeTapped() {
        onUserInteraction?()
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        refreshLike()
        // (62) toast 补齐：点按即给文字反馈（既有 toast 通路）。
        NativePlaybackFailureToast.show(
            message: newState ? "已喜欢" : "已取消喜欢")
        Breadcrumbs.log("minibar.webrow like id=\(id) on=\(newState)")
        Task { [weak self] in
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                await MainActor.run { self?.refreshLike() }
            }
        }
    }

    /// 长按已触发标记：长按抬手时 touchUpInside 仍会到，
    /// starTapped 见标记即吞掉本次点按（防长按后误开弹层）。
    private var starLongPressFired62 = false

    /// 星标点按（(62) 网页语义）：开 AddToPlaylist 收藏弹层
    /// 把当前歌加入歌单；本地星标改由长按切换（见下）。
    @objc private func starTapped() {
        if starLongPressFired62 {
            starLongPressFired62 = false
            return
        }
        onUserInteraction?()
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        Breadcrumbs.log("minibar.webrow.star id=\(track.id) openAddToPlaylist")
        presentAddToPlaylist62(track: track)
    }

    /// 星标长按：切换 StarStore 本地星标（(55) C 本地态保留）。
    @objc private func starLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        starLongPressFired62 = true
        onUserInteraction?()
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        let newState = StarStore.shared.toggle(track.id)
        refreshStar()
        NativePlaybackFailureToast.show(
            message: newState ? "已星标（本地）" : "已取消星标")
        Breadcrumbs.log("minibar.webrow.starLong id=\(track.id) on=\(newState)")
    }

    /// 收藏弹层呈现（(62)）：沿响应链找宿主控制器呈现
    /// AddToPlaylist（与搜索页 pageSheet 同形态）；找不到宿主
    /// 时退到 keyWindow 顶层控制器。
    private func presentAddToPlaylist62(track: FoliaTrack) {
        var responder: UIResponder? = self
        var host: UIViewController?
        while let current = responder {
            if let vc = current as? UIViewController { host = vc; break }
            responder = current.next
        }
        if host == nil {
            host = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.rootViewController
            while let presented = host?.presentedViewController {
                host = presented
            }
        }
        guard let host else {
            NativePlaybackFailureToast.show(message: "暂时无法打开收藏")
            return
        }
        let nav = UINavigationController(
            rootViewController: AddToPlaylistViewController(track: track))
        nav.modalPresentationStyle = .pageSheet
        host.present(nav, animated: true)
    }

    /// (81) 第 10 条：浮层爪印同步改单击切换（长按语义
    /// 退役、全页统一），点击带闪光＋烟花（PawFirework81），
    /// 切换走共享核、src 按浮层入口记 deck-tap。
    @objc private func pawTapped() {
        onUserInteraction?()
        let wasEnabled = StickerSettings.miniPetsEnabled
        PawFirework81.burst(in: self,
                            at: CGPoint(x: pawButton.frame.midX,
                                        y: pawButton.frame.midY))
        PawFirework81.pop(pawButton)
        Breadcrumbs.log("paw.tap81 on=\(wasEnabled ? 0 : 1) src=deck")
        PetSummonButton70.performPawToggle77(
            window: window,
            src: "deck-tap",
            via: "deck-tap",
            actCrumb: "paw.act81")
    }

    /// 爪印按下瞬间：续命浮层闲置钟（与 (77) 同纪律）。
    @objc private func pawTouchDown() {
        onUserInteraction?()
    }

    /// 格子（面板）本体未在本文件域：只发定名信号，宿主工
    /// 作流订阅 .foliaMiniBarPanel 后呈现面板。
    @objc private func panelTapped() {
        onUserInteraction?()
        Breadcrumbs.log("minibar.webrow panel")
        NotificationCenter.default.post(name: .foliaMiniBarPanel, object: self)
    }

    /// 命令键本体未在本文件域：只发定名信号，宿主工作流
    /// 订阅 .foliaMiniBarCommand 后呈现命令面板（睡眠定时
    /// 亦改走此路承接）。
    @objc private func commandTapped() {
        onUserInteraction?()
        Breadcrumbs.log("minibar.webrow command")
        NotificationCenter.default.post(name: .foliaMiniBarCommand, object: self)
    }
}

extension Notification.Name {
    // 点播台顶排字幕钮信号 .foliaMiniBarSubtitle 已于 (60) 第
    // 11 条随字幕钮整组删除，三处宿主订阅一并摘除。
    /// 点播台顶排格子（面板）钮信号（3.7 (55) C 定名）：同上，
    /// 宿主订阅后呈现面板。
    static let foliaMiniBarPanel = Notification.Name("FoliaMiniBarPanel")
    /// 点播台顶排命令键信号（3.7 (55) C 定名）：同上，宿主订
    /// 阅后呈现命令面板。
    static let foliaMiniBarCommand = Notification.Name("FoliaMiniBarCommand")
}

/// 点播台附加功能透明浮层（3.7 (60) 第 7 条）：承载从三处点播
/// 台本体迁出的五钮行（喜欢/星标/打乱/面板/命令）。容器本身
/// clear 透明，只有胶囊本体一块毛玻璃；挂在宿主 VC 的 view
/// 上、z 序在点播台之上，底边锚点播台顶边上方 8pt、横向与台
/// 同宽（宿主约束）。触摸纪律：bounds 内只有胶囊算命中（胶囊
/// 外穿透回下层），收起态整体不接手势。显隐动画由本类收口：
/// 系统弹簧（damping 0.85）自台顶方向滑入＋淡入、收起反之；
/// 触发/闲置自动收起/点外收起的时机由宿主掌握（与点播台 5 秒
/// 闲置同钟），宿主在 show/hide 落点打 quickrow.overlay 面包屑。
final class MiniBarQuickRowOverlayView: UIView {

    /// 五钮行本体（宿主接 onUserInteraction 等回调的唯一对象）。
    let quickRow = MiniBarQuickRowView()
    private let capsule = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private(set) var isShown = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        capsule.layer.cornerRadius = MiniBarQuickRowView.rowHeight / 2
        capsule.layer.borderWidth = 1
        capsule.layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
        capsule.clipsToBounds = true
        capsule.isUserInteractionEnabled = false
        capsule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)
        quickRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quickRow)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),
            quickRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            quickRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            quickRow.topAnchor.constraint(equalTo: topAnchor),
            quickRow.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // 初始收起态：隐藏、不接手势、停在滑入起点位形。
        alpha = 0
        isHidden = true
        isUserInteractionEnabled = false
        transform = CGAffineTransform(translationX: 0, y: 10)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 只认胶囊：胶囊外（含容器其余透明区）一律穿透；收起态不命中。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isShown, capsule.frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    /// 显隐切换（系统弹簧 damping 0.85）：呼出 = 自台顶上方滑
    /// 入＋淡入；收起 = 反向滑出＋淡出，落定后置 hidden。重复
    /// 同态调用为空操作。
    func setShown(_ shown: Bool, animated: Bool = true) {
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            isHidden = false
            isUserInteractionEnabled = true
            if animated {
                alpha = 0
                transform = CGAffineTransform(translationX: 0, y: 10)
                UIView.animate(withDuration: 0.45, delay: 0,
                               usingSpringWithDamping: 0.85,
                               initialSpringVelocity: 0,
                               options: [.beginFromCurrentState,
                                         .allowUserInteraction]) {
                    self.alpha = 1
                    self.transform = .identity
                }
            } else {
                alpha = 1
                transform = .identity
            }
        } else {
            isUserInteractionEnabled = false
            if animated {
                UIView.animate(withDuration: 0.3, delay: 0,
                               usingSpringWithDamping: 0.85,
                               initialSpringVelocity: 0,
                               options: [.beginFromCurrentState,
                                         .allowUserInteraction]) {
                    self.alpha = 0
                    self.transform = CGAffineTransform(translationX: 0, y: 10)
                } completion: { _ in
                    if !self.isShown { self.isHidden = true }
                }
            } else {
                alpha = 0
                transform = CGAffineTransform(translationX: 0, y: 10)
                isHidden = true
            }
        }
    }
}

/// (81) 第 10 条：爪印点按烟花——点击瞬间爪印闪光亮起＋
/// 烟花炸开（Miller 定版）。实现纪律：粒子走一发即停的
/// CAEmitterLayer（birthRate 冲一拍即归零、层 1.2s 后摘
/// 除），总量约 30 颗、寿命 ≤0.9s，克制不掉帧；闪光为一
/// 圈径向光晕视图弹簧放大淡出；宿主视图须 clipsToBounds
/// =false（三宿主台面均满足）。颜色取白/金/粉/青四色，
/// 与四套主题都可读。
enum PawFirework81 {

    private static func particleImage() -> CGImage? {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(
                in: CGRect(origin: .zero, size: size))
        }
        return image.cgImage
    }

    /// 在 host 坐标系的 center 点炸开一次。
    static func burst(in host: UIView, at center: CGPoint) {
        // 闪光光晕：自 6pt 弹簧放大到 54pt 并淡出。
        let glow = UIView(frame: CGRect(x: center.x - 3, y: center.y - 3,
                                        width: 6, height: 6))
        glow.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        glow.layer.cornerRadius = 3
        glow.isUserInteractionEnabled = false
        host.addSubview(glow)
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.4,
                       options: [.beginFromCurrentState]) {
            glow.transform = CGAffineTransform(scaleX: 9, y: 9)
            glow.alpha = 0
        } completion: { _ in glow.removeFromSuperview() }

        // 烟花粒子：一发即停。
        guard let image = particleImage() else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = center
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        let colors: [UIColor] = [
            .white,
            UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1),
            UIColor(red: 1.0, green: 0.55, blue: 0.70, alpha: 1),
            UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1),
        ]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 9
            cell.lifetime = 0.85
            cell.lifetimeRange = 0.25
            cell.velocity = 118
            cell.velocityRange = 52
            cell.emissionRange = .pi * 2
            cell.scale = 0.55
            cell.scaleRange = 0.3
            cell.alphaSpeed = -1.4
            cell.color = color.cgColor
            cell.yAcceleration = 150
            return cell
        }
        host.layer.addSublayer(emitter)
        // 冲一拍（约 36 颗）即停发，余粒子自然燃尽后摘层。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            emitter.removeFromSuperlayer()
        }
    }

    /// 爪印本体的点按回弹：冲亮放大、系统弹簧回落。
    static func pop(_ button: UIView) {
        button.transform = CGAffineTransform(scaleX: 1.28, y: 1.28)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 0.6,
                       options: [.beginFromCurrentState]) {
            button.transform = .identity
        }
    }
}

/// (79) 第 1 条：台面常驻爪印钮（主排右端簇、展开台面恒
/// 可见）。(81) 第 10 条交互改版——长按语义整套退役，改
/// 单击切换（点一下宠物出现、再点一下消失，全页统一），
/// 点击瞬间闪光＋烟花炸开（PawFirework81），切换仍走
/// PetSummonButton70.performPawToggle77 收口。
///
/// 长按失效根因（(81) 施工定案，代码坐实）：(79) 版的
/// 2s/3s 长按识别器挂在本钮上，而三宿主台身都挂着 0.55s
/// 长按切主题识别器（祖先视图）——按住爪印满 0.55s 时
/// 祖先识别器先行认领（其 handler 对按键区落点虽早退、
/// 认领本身照常发生），按 UIKit 手势互斥默认，本钮的
/// 识别器收到取消、永远到不了 .began；且 (79) 真机日志
/// 窗内 paw.face79 init ×6 在位、fire 零样本，与此机制
/// 互证。单击走 UIControl .touchUpInside 本体追踪、不
/// 经识别器链，不受此害（三宿主其余按键同路已验）。
final class DeckPawButton79: UIButton {

    var onUserInteraction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityLabel = "宠物开关"
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        // (81) 第 8 条：字形随主题整套切换（自订主题通知）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshFace81),
            name: .foliaMiniPlayerThemeChanged, object: nil)
        refreshFace81()
        Breadcrumbs.log("paw.face81 init mode=tap")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 字形（当前主题套）＋明暗（宠物开=亮白、关=灰 0.45，
    /// 即 (79) 真机所见灰态的语义，保留作状态信号）。
    @objc private func refreshFace81() {
        setImage(DeckGlyph82.image(.paw, pointSize: 16),
                 for: .normal)
        tintColor = StickerSettings.miniPetsEnabled
            ? .white : UIColor.white.withAlphaComponent(0.45)
    }

    @objc private func touchDown() { onUserInteraction?() }

    @objc private func tapped() {
        onUserInteraction?()
        let wasEnabled = StickerSettings.miniPetsEnabled
        if let host = superview {
            PawFirework81.burst(in: host,
                                at: CGPoint(x: frame.midX, y: frame.midY))
        }
        PawFirework81.pop(self)
        Breadcrumbs.log("paw.tap81 on=\(wasEnabled ? 0 : 1)")
        PetSummonButton70.performPawToggle77(
            window: window,
            src: "face-tap",
            via: "face-tap",
            actCrumb: "paw.act81")
        refreshFace81()
    }
}
