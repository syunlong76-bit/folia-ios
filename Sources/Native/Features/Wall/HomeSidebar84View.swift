import UIKit

/// (84) 第 6 条：主页左缘竖条侧栏（网页版式，Miller 图三/图四）。
///
/// 构成（自上而下）：头像登录区 → 「书库」竖排标题 → 分区
/// 入口（歌单/电台/专辑/本地，竖排文字）→ 搜索/设置图标。
/// 去向全部接已有原生面（接线在 HomeWallViewController）；
/// 「书库」无独立可达原生面（工作台桌已于 (74) 撤下主页），
/// 只作竖排标题呈现、不做假按钮（(84) 报告明示）。
///
/// 手势纪律：本视图 hitTest 只认按钮本体，背景一律返回
/// nil——竖条区域不吞墙面平移手势（墙的 UIPanGesture-
/// Recognizer 挂在墙视图上，点在条背景处等同点在墙上）。
/// 竖条本体宽 48（命中）/视觉条 44，锚主页左缘安全区，
/// 横屏同在左缘成立（装配约束见宿主）。
final class HomeSidebar84View: UIView {

    var onAvatar: (() -> Void)?
    var onPlaylists: (() -> Void)?
    var onRadio: (() -> Void)?
    var onAlbums: (() -> Void)?
    var onLocal: (() -> Void)?
    var onSearch: (() -> Void)?
    var onSettings: (() -> Void)?

    private let avatarButton = UIButton(type: .custom)
    private let avatarImageView = UIImageView()
    private let avatarInitialLabel = UILabel()
    private var avatarTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    // MARK: 装配

    private func build() {
        // 视觉条：半透明深底＋右缘发丝线（网页侧栏观感，
        // 不拦手势——命中纪律在 hitTest 收口）。
        let bar = UIView()
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isUserInteractionEnabled = false
        addSubview(bar)
        let hairline = UIView()
        hairline.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.isUserInteractionEnabled = false
        addSubview(hairline)

        // 头像登录区（32 圆，与缝合工具条头像同口径回显）。
        avatarButton.layer.cornerRadius = 16
        avatarButton.clipsToBounds = true
        avatarButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        avatarButton.accessibilityLabel = "账户"
        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isUserInteractionEnabled = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.addSubview(avatarImageView)
        avatarInitialLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarInitialLabel.textColor = .white
        avatarInitialLabel.textAlignment = .center
        avatarInitialLabel.isUserInteractionEnabled = false
        avatarInitialLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.addSubview(avatarInitialLabel)
        addSubview(avatarButton)
        setAccount84(nickname: nil, loggedIn: false, avatarURLString: nil)

        // 「书库」竖排标题（非交互，见类头注）。
        let libraryLabel = UILabel()
        libraryLabel.text = "书\n库"
        libraryLabel.numberOfLines = 0
        libraryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        libraryLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        libraryLabel.textAlignment = .center
        libraryLabel.isUserInteractionEnabled = false
        libraryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(libraryLabel)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.addArrangedSubview(avatarButton)
        stack.addArrangedSubview(libraryLabel)
        for (title, action) in [
            ("歌单", #selector(playlistsTapped)),
            ("电台", #selector(radioTapped)),
            ("专辑", #selector(albumsTapped)),
            ("本地", #selector(localTapped)),
        ] {
            stack.addArrangedSubview(makeEntryButton(title: title, action: action))
        }
        let spacer = UIView()
        spacer.isUserInteractionEnabled = false
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(makeIconButton(
            systemName: "magnifyingglass", label: "搜索", action: #selector(searchTapped)))
        stack.addArrangedSubview(makeIconButton(
            systemName: "gearshape", label: "设置", action: #selector(settingsTapped)))

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 44),
            hairline.leadingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.widthAnchor.constraint(equalToConstant: 0.5),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            avatarButton.widthAnchor.constraint(equalToConstant: 32),
            avatarButton.heightAnchor.constraint(equalToConstant: 32),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarButton.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: avatarButton.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor),
            avatarInitialLabel.centerXAnchor.constraint(equalTo: avatarButton.centerXAnchor),
            avatarInitialLabel.centerYAnchor.constraint(equalTo: avatarButton.centerYAnchor),
        ])
    }

    private func makeEntryButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        // 竖排文字：字间换行（网页侧栏竖排入口同式）。
        button.setTitle(title.map { String($0) }.joined(separator: "\n"), for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(UIColor.white.withAlphaComponent(0.85), for: .normal)
        button.accessibilityLabel = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    private func makeIconButton(systemName: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.85)
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    // MARK: 命中纪律

    /// 只认按钮本体：命中点向上找到 UIControl 才认领，
    /// 其余（视觉条/间隔/标题）一律穿透给墙面。
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

    // MARK: 账户回显（与 SeamToolbarView.setAccount 同口径）

    func setAccount84(nickname: String?, loggedIn: Bool, avatarURLString: String?) {
        avatarTask?.cancel()
        avatarTask = nil
        if loggedIn, let nickname, !nickname.isEmpty {
            avatarInitialLabel.text = String(nickname.prefix(1))
            avatarButton.setImage(nil, for: .normal)
        } else {
            // 无昵称可用（未登录/未取到）：人形系统图占位
            // （诚实空态，与 WorkbenchAvatarView 同口径，不
            // 用「?」糊脸）；点按进既有登录区。
            avatarInitialLabel.text = nil
            avatarButton.setImage(
                UIImage(systemName: "person.crop.circle"), for: .normal)
            avatarButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        }
        avatarImageView.image = nil
        avatarInitialLabel.isHidden = false
        guard loggedIn, let avatarURLString,
              let url = URL(string: avatarURLString) else { return }
        avatarTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.avatarImageView.image = image
                self?.avatarInitialLabel.isHidden = true
            }
        }
        avatarTask?.resume()
    }

    // MARK: 点按（逐项落痕 sidebar84）

    @objc private func avatarTapped() {
        Breadcrumbs.log("sidebar84 tap dest=avatar")
        onAvatar?()
    }

    @objc private func playlistsTapped() {
        Breadcrumbs.log("sidebar84 tap dest=playlists")
        onPlaylists?()
    }

    @objc private func radioTapped() {
        Breadcrumbs.log("sidebar84 tap dest=radio")
        onRadio?()
    }

    @objc private func albumsTapped() {
        Breadcrumbs.log("sidebar84 tap dest=albums")
        onAlbums?()
    }

    @objc private func localTapped() {
        Breadcrumbs.log("sidebar84 tap dest=local")
        onLocal?()
    }

    @objc private func searchTapped() {
        Breadcrumbs.log("sidebar84 tap dest=search")
        onSearch?()
    }

    @objc private func settingsTapped() {
        Breadcrumbs.log("sidebar84 tap dest=settings")
        onSettings?()
    }
}
