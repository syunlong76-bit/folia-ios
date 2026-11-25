import UIKit

// WorkbenchCommon.swift
//
// (53) A 组工作台共用件：配色（与 SettingsViewController 的
// FoliaUI 同值，改一处须同步）、封面加载（走墙面同链
// NativeCoverLoader 的代理/缓存，不裸直下）、分区页通用骨架
// （顶栏 + 状态视图）。

enum WorkbenchTheme {
    static let background = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1) // #16161A
    static let primary = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)    // #F5F5F7
    static let secondary = UIColor(red: 0.604, green: 0.604, blue: 0.639, alpha: 1)  // #9A9AA3
    static let accent = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 1)     // #8B7CF0
    static let hairline = UIColor.white.withAlphaComponent(0.07)
    static let rowFill = UIColor.white.withAlphaComponent(0.05)
}

/// 封面加载（列表小图）：与 HomeWall 迷你台同链——NativeCoverLoader
/// 代理地址 + 内存缓存命中直出，未命中异步拉取，落地前由调用方
/// 的 isCurrent 判定防 cell 复用串图。
enum WorkbenchCover {
    static func load(raw: String?, into imageView: UIImageView,
                     isCurrent: @escaping () -> Bool) {
        imageView.image = nil
        guard let raw, !raw.isEmpty else { return }
        let tier = NativeCoverLoader.tier(forPixelExtent: 150)
        guard let proxied = NativeCoverLoader.shared.proxiedURLString(raw, tier: tier)
        else { return }
        if let cached = NativeCoverLoader.shared.cachedImage(for: proxied) {
            imageView.image = cached
            return
        }
        Task {
            let image = await NativeCoverLoader.shared.image(for: proxied, tier: tier)
            await MainActor.run {
                if isCurrent() { imageView.image = image }
            }
        }
    }

    /// 头像加载：先走同链；代理给不出地址（如 LocalServer 未就绪）
    /// 时回退一次直下（头像是公开图，无凭据）。
    /// (78) 第 3 条：新增 completion（置于 isCurrent 之前，既有
    /// 调用点的尾随闭包仍绑 isCurrent、语义不变）——true 表示
    /// 真图已置入 imageView，供工具条在图落地时整层摘除占位
    /// 字图层；缓存同步命中在本函数返回前同步回调。
    static func loadAvatar(url: URL?, into imageView: UIImageView,
                           completion: ((Bool) -> Void)? = nil,
                           isCurrent: @escaping () -> Bool) {
        imageView.image = nil
        guard let url else { completion?(false); return }
        let raw = url.absoluteString
        let tier = NativeCoverLoader.tier(forPixelExtent: 120)
        if let proxied = NativeCoverLoader.shared.proxiedURLString(raw, tier: tier) {
            if let cached = NativeCoverLoader.shared.cachedImage(for: proxied) {
                imageView.image = cached
                completion?(true)
                return
            }
            Task {
                if let image = await NativeCoverLoader.shared.image(for: proxied, tier: tier) {
                    await MainActor.run {
                        if isCurrent() {
                            imageView.image = image
                            completion?(true)
                        }
                    }
                    return
                }
                let image = await directImage(url)
                await MainActor.run {
                    if isCurrent() {
                        imageView.image = image
                        completion?(image != nil)
                    }
                }
            }
        } else {
            Task {
                let image = await directImage(url)
                await MainActor.run {
                    if isCurrent() {
                        imageView.image = image
                        completion?(image != nil)
                    }
                }
            }
        }
    }

    private static func directImage(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

/// 分区页状态视图：加载转圈 / 一句人话 + 可选动作按钮（重试或
/// 去登录）。盖在列表上方居中，hidden 时不拦手势。
final class WorkbenchStateView: UIView {

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private let actionButton = UIButton(type: .system)
    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        spinner.color = .white
        spinner.hidesWhenStopped = true
        label.font = .systemFont(ofSize: 14)
        label.textColor = WorkbenchTheme.secondary
        label.textAlignment = .center
        label.numberOfLines = 0
        actionButton.setTitleColor(WorkbenchTheme.accent, for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        actionButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        actionButton.layer.cornerRadius = 12
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, label, actionButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            actionButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    @objc private func actionTapped() { onAction?() }

    func showLoading(_ text: String) {
        isHidden = false
        spinner.startAnimating()
        label.text = text
        actionButton.isHidden = true
        onAction = nil
    }

    func showMessage(_ text: String, actionTitle: String? = nil,
                     action: (() -> Void)? = nil) {
        isHidden = false
        spinner.stopAnimating()
        label.text = text
        if let actionTitle, let action {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.isHidden = false
            onAction = action
        } else {
            actionButton.isHidden = true
            onAction = nil
        }
    }

    func hide() {
        isHidden = true
        spinner.stopAnimating()
    }
}

/// 分区页骨架：近黑底 + 顶栏（关闭键 + 标题）。各分区页继承后
/// 用 contentView 承载自己的列表，状态视图经 stateView 盖顶层。
class WorkbenchSectionViewController: UIViewController {

    /// 点播后回墙的收口（宿主注入）：一路 dismiss 到主页墙，
    /// 让墙上迷你台接管播放呈现。未注入时退化为关本页。
    var dismissToWall: (() -> Void)?

    let contentView = UIView()
    let stateView = WorkbenchStateView()
    private let sectionTitle: String

    init(title: String) {
        sectionTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride() // (62) INT-1：明暗三段读主题系统，不再写死深色
        view.backgroundColor = WorkbenchTheme.background

        let titleLabel = UILabel()
        titleLabel.text = sectionTitle
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = WorkbenchTheme.primary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        closeButton.tintColor = WorkbenchTheme.primary
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(workbenchCloseTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        stateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            contentView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 10),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    @objc func workbenchCloseTapped() {
        dismiss(animated: true)
    }

    /// 未登录落定态：状态视图给「扫码登录」入口（与主页墙未登录
    /// 胶囊同路：LoginViewController 成功回调后由调用方重拉）。
    func showLoginPrompt(message: String, onSuccess: @escaping () -> Void) {
        stateView.showMessage(message, actionTitle: "扫码登录") { [weak self] in
            guard let self else { return }
            let login = LoginViewController()
            login.modalPresentationStyle = .overFullScreen
            login.onLoginSuccess = onSuccess
            self.present(login, animated: true)
        }
    }
}

/// 通用曲目行 cell（分区页各列表共用）：序号/封面 + 标题 + 歌手
/// + 时长。representedId 防复用串图与串高亮。
final class WorkbenchTrackCell: UITableViewCell {

    static let reuseId = "WorkbenchTrackCell"

    private(set) var representedId: String?
    let coverView = UIImageView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let durationLabel = UILabel()
    /// 「已在队列」角标（3.7 (69) P9）：行尾小片，出角标时
    /// 时长标签左移让位；显隐由 configure 的 inQueue 驱动，
    /// 宿主列表经 $queue 订阅重配，不许陈旧。
    let queueBadge = UILabel()
    private var durationToEdge: NSLayoutConstraint?
    private var durationToBadge: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)
        // (89) §5-6：分区行字号对齐网页列表行（歌名 13/700、
        // 歌手 11、时长 11）；行高 64 网页为运行时值、无从对。
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = WorkbenchTheme.primary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = WorkbenchTheme.secondary
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = WorkbenchTheme.secondary
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)
        queueBadge.text = " ✓ 已在队列 "
        queueBadge.font = .systemFont(ofSize: 10, weight: .medium)
        queueBadge.textColor = WorkbenchTheme.accent
        queueBadge.layer.borderWidth = 1
        queueBadge.layer.borderColor = WorkbenchTheme.accent.cgColor
        queueBadge.layer.cornerRadius = 7
        queueBadge.clipsToBounds = true
        queueBadge.textAlignment = .center
        queueBadge.isHidden = true
        queueBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(queueBadge)
        durationToEdge = durationLabel.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor, constant: -16)
        durationToBadge = durationLabel.trailingAnchor.constraint(
            equalTo: queueBadge.leadingAnchor, constant: -8)
        durationToEdge?.isActive = true
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 44),
            coverView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            queueBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            queueBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            queueBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    /// (69) P9 角标显隐统一出口：出角标时时长标签改靠角标
    /// 左侧，两约束互斥切换，不叠加不冲突。
    private func setInQueue(_ inQueue: Bool) {
        queueBadge.isHidden = !inQueue
        durationToEdge?.isActive = !inQueue
        durationToBadge?.isActive = inQueue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedId = nil
        coverView.image = nil
        setInQueue(false)
    }

    func configure(track: FoliaTrack, isCurrent: Bool, inQueue: Bool = false) {
        representedId = track.id
        titleLabel.text = track.title
        subtitleLabel.text = track.album.isEmpty ? track.artist : "\(track.artist) · \(track.album)"
        durationLabel.text = track.duration > 0 ? Self.formatDuration(track.duration) : ""
        titleLabel.textColor = isCurrent ? WorkbenchTheme.accent : WorkbenchTheme.primary
        setInQueue(inQueue)
        let id = track.id
        WorkbenchCover.load(raw: track.artworkURL?.absoluteString, into: coverView) { [weak self] in
            self?.representedId == id
        }
    }

    func configure(title: String, subtitle: String, coverRaw: String?, representedId: String) {
        self.representedId = representedId
        titleLabel.text = title
        subtitleLabel.text = subtitle
        durationLabel.text = ""
        titleLabel.textColor = WorkbenchTheme.primary
        // 集合行（歌单/专辑）非曲目行，恒不出队列角标。
        setInQueue(false)
        let id = representedId
        WorkbenchCover.load(raw: coverRaw, into: coverView) { [weak self] in
            self?.representedId == id
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
