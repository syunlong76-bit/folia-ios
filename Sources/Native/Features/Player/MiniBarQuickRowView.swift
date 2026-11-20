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
/// - 打乱队列：QueueManager.shuffleQueue，队列不足 2 首禁用。
///   沿用 (54)。
/// - 字幕 / 格子（面板）/ 命令键：本体在别的工作流，本视图
///   只发信号——点按 post .foliaMiniBarSubtitle /
///   .foliaMiniBarPanel / .foliaMiniBarCommand（名称定死，
///   宿主工作流按此订阅），并落同词根面包屑。
///
/// 退出顶排（(55) C 定案，不许再放回本排）：播放模式（队列
/// 面板与设置里已有四档切换）、睡眠定时（改走命令面板/面
/// 板控制页签）、设置（侧栏设置行与面板承接）。
///
/// 每钮图标＋小字标签双通道（标签 喜欢/星标/打乱/字幕/
/// 面板/命令，10pt），根治 (54) 真机点名的「打乱与模式随机
/// 档图标几乎一样、又无文字」。六钮等宽平分整排，任一屏宽
/// 下单钮命中宽 ≥40pt（核算见 (55) C 报告自查节）。按下态
/// 反馈：configurationUpdateHandler 给高亮态加白 14% 圆角
/// 底＋0.92 缩放（系统式即时反馈，不用罩体染色）。
///
/// 展开高度单一出处：rowHeight / expandedBarHeight 两常量
/// 为宿主应读的唯一真源——宿主现写死台高 118、上排高 44
/// （清单见 (55) C 报告），改读常量后上排 44→48、台高
/// 118→122 自动跟随；本视图内部不依赖宿主给的高度数字，
/// 钮高由宿主约束撑满本排。
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

    /// 展开态点播台总高（唯一出处）：旧 118 ＝ 顶距 3 ＋
    /// 上排 44 ＋ 主排/seek 区 71；上排 44→48 后 ＝ 3 ＋
    /// 48 ＋ 71 ＝ 122。宿主写死的 118 应改读本值，主排中
    /// 心/seek 带等相对量由宿主按 +4 复核顺延。
    static let expandedBarHeight: CGFloat = 122

    var onUserInteraction: (() -> Void)?
    var onLikeStateChanged: (() -> Void)?
    /// (54) 遗留：顶排设置钮已随 (55) C 移除，本回调不再
    /// 触发；保留声明避免打断宿主现有接线，待宿主工作流
    /// 移除接线后删除。
    var onOpenSettings: (() -> Void)?

    private let likeButton = UIButton(type: .system)
    private let starButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let subtitleButton = UIButton(type: .system)
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
        configure(shuffleButton, symbol: "shuffle", pointSize: 16,
                  title: "打乱", accessibility: "打乱队列",
                  action: #selector(shuffleTapped))
        configure(subtitleButton, symbol: "captions.bubble", pointSize: 16,
                  title: "字幕", accessibility: "字幕",
                  action: #selector(subtitleTapped))
        configure(panelButton, symbol: "square.grid.2x2", pointSize: 16,
                  title: "面板", accessibility: "面板",
                  action: #selector(panelTapped))
        configure(commandButton, symbol: "command", pointSize: 16,
                  title: "命令", accessibility: "命令",
                  action: #selector(commandTapped))

        // 六钮等宽平分整排：链式等宽＋首尾贴边，钮高撑满
        // 本排。等宽保证任一台宽下每钮命中宽一致（自查核
        // 算：最窄台宽 353pt 时单钮 ≈58.8pt）。
        let buttons = [likeButton, starButton, shuffleButton,
                       subtitleButton, panelButton, commandButton]
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
        button.configurationUpdateHandler = { btn in
            btn.transform = btn.isHighlighted
                ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            var updated = btn.configuration
            updated?.background.backgroundColor = btn.isHighlighted
                ? UIColor.white.withAlphaComponent(0.14) : .clear
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

    /// 状态订阅：切歌刷新喜欢与星标、队列变化刷新打乱可用
    /// 性、星标外部变更（他面切换）刷新星标——全部回主线程。
    private func bindState() {
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLike()
                self?.refreshStar()
            }
            .store(in: &cancellables)
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshShuffle() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            self, selector: #selector(starChanged),
            name: .foliaStarChanged, object: nil)
    }

    func refreshAll() {
        refreshLike()
        refreshStar()
        refreshShuffle()
    }

    // MARK: - 回显

    private func refreshLike() {
        let liked = PlaybackEngine.shared.currentTrack
            .map { LikesStore.shared.isLiked($0.id) } ?? false
        setButtonState(likeButton,
            symbol: liked ? "heart.fill" : "heart", pointSize: 17,
            color: liked
                ? UIColor(red: 1, green: 0.35, blue: 0.45, alpha: 1)
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

    private func refreshShuffle() {
        let enabled = QueueManager.shared.queue.count >= 2
        shuffleButton.isEnabled = enabled
        shuffleButton.alpha = enabled ? 1 : 0.35
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

    @objc private func starTapped() {
        onUserInteraction?()
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        let newState = StarStore.shared.toggle(track.id)
        refreshStar()
        Breadcrumbs.log("minibar.webrow.star id=\(track.id) on=\(newState)")
    }

    @objc private func shuffleTapped() {
        onUserInteraction?()
        Breadcrumbs.log("minibar.webrow shuffleQueue")
        QueueManager.shared.shuffleQueue()
    }

    /// 字幕本体未在本文件域：只发定名信号，宿主工作流订阅
    /// .foliaMiniBarSubtitle 后呈现字幕调节面。
    @objc private func subtitleTapped() {
        onUserInteraction?()
        Breadcrumbs.log("minibar.webrow subtitle")
        NotificationCenter.default.post(name: .foliaMiniBarSubtitle, object: self)
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
    /// 点播台顶排字幕钮信号（3.7 (55) C 定名）：MiniBarQuickRowView
    /// 点按发出（object = 发出信号的 quick row），宿主订阅后
    /// 呈现字幕调节面。
    static let foliaMiniBarSubtitle = Notification.Name("FoliaMiniBarSubtitle")
    /// 点播台顶排格子（面板）钮信号（3.7 (55) C 定名）：同上，
    /// 宿主订阅后呈现面板。
    static let foliaMiniBarPanel = Notification.Name("FoliaMiniBarPanel")
    /// 点播台顶排命令键信号（3.7 (55) C 定名）：同上，宿主订
    /// 阅后呈现命令面板。
    static let foliaMiniBarCommand = Notification.Name("FoliaMiniBarCommand")
}
