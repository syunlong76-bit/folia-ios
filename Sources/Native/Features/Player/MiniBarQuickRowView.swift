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

    /// 展开态点播台总高（唯一出处）：(60) 第 7 条起上排迁出
    /// 台本体住透明浮层，台高恢复为不含上排的 70（＝ (54) 前
    /// 的主排/seek 区口径）。宿主读本常量处自动跟随；主排
    /// centerY 等相对量由宿主按 70 台口径复核（展开 −5）。
    static let expandedBarHeight: CGFloat = 70

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
    /// (77) ⑤：原打乱钮位由爪印接管（长按 2s 召唤/3s 告
    /// 别，与退役的窗口爪印同一切换核 PetSummonButton70
    /// .performPawToggle77）。打乱队列撤下台面——去向：
    /// 队列面板与命令面板内仍可达（见 (77) 报告⑤）。
    private let pawButton = UIButton(type: .system)
    private let pawPressRecognizer = UILongPressGestureRecognizer()
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
                  title: "宠物", accessibility: "宠物开关（长按）",
                  action: #selector(pawTapped))
        // (77) ⑤爪印长按：阈值按按下瞬间开关态（开 3.0s
        // 关/关 2.0s 召唤），在 hitTest 现读刷新（与窗口
        // 爪印同纪律）；按下即回调宿主续命浮层 5 秒钟，
        // 防长按未满先被闲置收起打断。
        pawPressRecognizer.minimumPressDuration =
            StickerSettings.miniPetsEnabled ? 3.0 : 2.0
        pawPressRecognizer.allowableMovement = 12
        pawPressRecognizer.cancelsTouchesInView = false
        pawPressRecognizer.addTarget(
            self, action: #selector(pawLongPressed(_:)))
        pawButton.addGestureRecognizer(pawPressRecognizer)
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
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === pawButton {
            pawPressRecognizer.minimumPressDuration =
                StickerSettings.miniPetsEnabled ? 3.0 : 2.0
        }
        return hit
    }

    // MARK: - 回显

    private func refreshLike() {
        let liked = PlaybackEngine.shared.currentTrack
            .map { LikesStore.shared.isLiked($0.id) } ?? false
        // (68) A1：先落填充标志再写回 configuration（handler
        // 据此填整钮喜欢色）；填充后图标与标签转白保证可读，
        // 未喜欢维持现行（白 75% 前景、无填充）。
        likeFilled = liked
        setButtonState(likeButton,
            symbol: liked ? "heart.fill" : "heart", pointSize: 17,
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
            symbol: starred ? "star.fill" : "star", pointSize: 16,
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

    /// 长按已触发标记：长按抬手时 touchUpInside 仍会到，
    /// pawTapped 见标记即吞掉（与星标长按同款防误报）。
    private var pawLongPressFired = false

    /// (77) ⑤爪印短按：无动作（防误触，与窗口爪印同纪
    /// 律），只给一句长按提示——长按语义靠它可发现。
    @objc private func pawTapped() {
        if pawLongPressFired {
            pawLongPressFired = false
            return
        }
        onUserInteraction?()
        Breadcrumbs.log("minibar.webrow paw tap=hint")
        NativePlaybackFailureToast.show(
            message: StickerSettings.miniPetsEnabled
                ? "长按爪印 3 秒，送小宠物回家"
                : "长按爪印 2 秒，召唤小宠物")
    }

    /// (77) ⑤爪印按下瞬间：先续命浮层闲置钟（长按 3s 不
    /// 被 5 秒闲置收起从中打断）。
    @objc private func pawTouchDown() {
        onUserInteraction?()
    }

    /// (77) ⑤爪印长按触发：走共享切换核（与退役窗口爪印
    /// 同实现、同 src 收口），src/via 按台面入口记 deck。
    @objc private func pawLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        pawLongPressFired = true
        onUserInteraction?()
        let enabled = StickerSettings.miniPetsEnabled
        PetSummonButton70.performPawToggle77(
            window: window,
            src: enabled ? "deck3s" : "deck2s",
            via: enabled ? "deck3s" : "deck2s",
            actCrumb: "paw.act77")
        pawPressRecognizer.minimumPressDuration =
            StickerSettings.miniPetsEnabled ? 3.0 : 2.0
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
