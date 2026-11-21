import UIKit

// (62) WD §1/§2：墙上账户弹层。点工具条头像不再整页 present
// 登录页，改在头像下方 popover 出账户卡：三平台的头像/昵称/
// 用户 ID/登录态一览（数据走 ProviderSessionStatusQuery 同步
// 缓存，accountId 已在其中），平台丸切换登录平台（关卡后以
// 压墙弹层形态开 LoginViewController 并预选平台），已登录平
// 台给退出钮（与 LoginVC performLogout 同路清会话）。
// 侧栏深处入口仍走整页 LoginViewController，不受影响。

final class AccountCard62ViewController: UIViewController {

    /// 登录成功后回调（宿主刷墙面账户态/重拉 entries）。
    var onLoginSuccess: (() -> Void)?
    /// 退出任一平台后回调（宿主刷账户态）。
    var onSessionChanged: (() -> Void)?

    private let stack = UIStackView()
    private var avatarViews: [NativeSessionStore.Provider: UIImageView] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        preferredContentSize = CGSize(width: 300, height: 340)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -14),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -28),
        ])
        rebuild()
    }

    static func displayName(for provider: NativeSessionStore.Provider) -> String {
        switch provider {
        case .netease: return "网易云"
        case .qq: return "QQ 音乐"
        case .kugou: return "酷狗"
        }
    }

    private func rebuild() {
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        avatarViews = [:]
        let title = UILabel()
        title.text = "账户"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .label
        stack.addArrangedSubview(title)

        for status in ProviderSessionStatusQuery.allStatuses() {
            stack.addArrangedSubview(providerRow(status))
        }

        let hint = UILabel()
        hint.text = "点平台行登录或切换；退出只清该平台本机会话。"
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
    }

    private func providerRow(_ status: ProviderSessionStatus) -> UIView {
        let card = UIView()
        card.backgroundColor = .tertiarySystemBackground
        card.layer.cornerRadius = 12

        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        avatar.backgroundColor = .systemGray5
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatarViews[status.provider] = avatar
        if let url = status.avatarURL {
            Task { [weak avatar] in
                let image = await NativeCoverLoader.shared.image(for: url.absoluteString, tier: 128)
                await MainActor.run { avatar?.image = image }
            }
        }

        let name = UILabel()
        name.text = status.displayName ?? Self.displayName(for: status.provider)
        name.font = .systemFont(ofSize: 14, weight: .medium)
        name.textColor = .label
        let detail = UILabel()
        if status.isLoggedIn {
            detail.text = "\(Self.displayName(for: status.provider)) · ID \(status.accountId ?? "—")"
        } else {
            detail.text = "\(Self.displayName(for: status.provider)) · 未登录"
        }
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 2
        let texts = UIStackView(arrangedSubviews: [name, detail])
        texts.axis = .vertical
        texts.spacing = 2
        texts.translatesAutoresizingMaskIntoConstraints = false

        let action = UIButton(type: .system)
        action.setTitle(status.isLoggedIn ? "退出" : "登录", for: .normal)
        action.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        action.translatesAutoresizingMaskIntoConstraints = false
        action.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if status.isLoggedIn {
                self.logout(provider: status.provider)
            } else {
                self.openLogin(provider: status.provider)
            }
        }, for: .touchUpInside)

        card.addSubview(avatar)
        card.addSubview(texts)
        card.addSubview(action)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            avatar.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
            texts.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            texts.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            texts.trailingAnchor.constraint(equalTo: action.leadingAnchor, constant: -8),
            action.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            action.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            card.heightAnchor.constraint(equalToConstant: 60),
        ])
        return card
    }

    /// 压墙弹层开登录页（(62) §2 登录层形态）：pageSheet +
    /// medium/large detents，预选目标平台。
    private func openLogin(provider: NativeSessionStore.Provider) {
        dismiss(animated: true) { [weak self] in
            guard let presenter = self?.presentingViewController ?? self else { return }
            let login = LoginViewController()
            login.initialProvider = provider
            login.modalPresentationStyle = .pageSheet
            if let sheet = login.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            login.onLoginSuccess = { [weak self] in self?.onLoginSuccess?() }
            presenter.present(login, animated: true)
        }
    }

    /// 退出（与 LoginViewController.performLogout 同路）。
    private func logout(provider: NativeSessionStore.Provider) {
        Breadcrumbs.log("account62.logout provider=\(provider.rawValue)")
        switch provider {
        case .netease:
            NativeDataClient.shared.clearNativeSession()
            SessionMigrator.state = .pending
        case .qq:
            let cookie = NativeSessionStore.shared.qqCookieString()
            NativeSessionStore.shared.clear(provider: .qq, reason: "logout")
            if let cookie { Task { await QQLoginClient().logout(cookie: cookie) } }
        case .kugou:
            let cookie = NativeSessionStore.shared.kugouCookieString()
            NativeSessionStore.shared.clear(provider: .kugou, reason: "logout")
            if let cookie { Task { await KugouLoginClient().logout(cookie: cookie) } }
        }
        onSessionChanged?()
        rebuild()
    }
}
