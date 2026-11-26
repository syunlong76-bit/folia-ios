import UIKit

// (62) WD §1/§2：墙上账户弹层。点工具条头像在头像下方
// popover 出账户卡（数据走 ProviderSessionStatusQuery 同步
// 缓存），卡内登录走压墙弹层（pageSheet）开 LoginView
// Controller 并预选平台，退出与 LoginVC performLogout 同路。
//
// (74) 账户区改版（Miller 图1/图3 纠正）：
// ①去掉头像旁「大皂先生」式大字名行——三家只以头像阵列
//   呈现（52pt 圆盘 + 盘下 10pt 平台小字 + 登录态点），点
//   选中的一家才在下方出一行小字详情（昵称 · ID）与退出；
// ②QQ/酷狗未登录点头像直接弹扫码登录面（LoginView
//   Controller 的网页式扫码面：平台页签 + 通道 + 220 二维
//   码 + 状态行，pageSheet + medium/large detents + 下拉关
//   闭，与网页版弹层同流程；网易云同面既有原生扫码）；
// ③黑头像根因修复：旧版头像只走 NativeCoverLoader 单链
//   （经本机代理），代理给不出图时恒留深灰空盘（图3 三盘
//   全黑）；改走 WorkbenchCover.loadAvatar（同链优先、失
//   败回退 URLSession 直下——工具条/侧栏头像同路，那两处
//   头像真显示即为此路通的实证）。

final class AccountCard62ViewController: UIViewController {

    /// 登录成功后回调（宿主刷墙面账户态/重拉 entries）。
    var onLoginSuccess: (() -> Void)?
    /// 退出任一平台后回调（宿主刷账户态）。
    var onSessionChanged: (() -> Void)?

    private let stack = UIStackView()
    private var avatarViews: [NativeSessionStore.Provider: UIImageView] = [:]
    private var avatarKeys: [NativeSessionStore.Provider: String] = [:]
    private var ringViews: [NativeSessionStore.Provider: UIView] = [:]
    private var selectedProvider: NativeSessionStore.Provider = .netease
    /// (92) 任务 10：外部指定初始选中家（侧栏点头像行落本页
    /// 时带入）；nil 时沿旧口径（第一家已登录、否则网易云）。
    var initialProvider92: NativeSessionStore.Provider?
    /// port90（任务 11）：资料自愈每家每次呈现只试一次（防 rebuild 循环）。
    private var enrichAttempted90: Set<NativeSessionStore.Provider> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        preferredContentSize = CGSize(width: 300, height: 208)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
        ])
        // 默认选中：外部指定优先，其次第一家已登录的，没有则网易云。
        let statuses = ProviderSessionStatusQuery.allStatuses()
        selectedProvider = initialProvider92
            ?? statuses.first(where: \.isLoggedIn)?.provider ?? .netease
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
        ringViews = [:]
        let title = UILabel()
        title.text = "账户"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .label
        stack.addArrangedSubview(title)

        let statuses = ProviderSessionStatusQuery.allStatuses()
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 20
        row.alignment = .top
        for status in statuses {
            row.addArrangedSubview(avatarCell(status))
        }
        row.addArrangedSubview(UIView()) // 左对齐占位（弹性空位）
        stack.addArrangedSubview(row)

        if let selected = statuses.first(where: { $0.provider == selectedProvider }) {
            stack.addArrangedSubview(detailRow(selected))
        }

        let hint = UILabel()
        hint.text = "点头像登录或切换；退出只清该平台本机会话。"
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)

        // port90（任务 11）：已登录但资料缓存缺头像/昵称的家当场回填。
        // 根因：enrich 此前只存在于 LoginViewController（打开登录页且选中
        // 该家才触发），账户卡只读缓存、从不回填；网易云另有墙面主流常刷、
        // QQ/酷狗无此路，存量会话缺头像即恒占位、无自愈。
        for status in statuses
        where status.isLoggedIn
            && (status.avatarURL == nil || status.displayName == nil
                || status.vipLevel == nil)
            && !enrichAttempted90.contains(status.provider) {
            enrichAttempted90.insert(status.provider)
            enrichProfile90(for: status.provider)
        }
    }

    /// 补资料（与 LoginViewController.enrichProfile 同源同路）：只写
    /// 资料缓存、不动会话；成功后主线程重排；失败静默（下次呈现再试）。
    private func enrichProfile90(for provider: NativeSessionStore.Provider) {
        Task { [weak self] in
            switch provider {
            case .netease:
                guard let status = try? await NativeDataClient.shared.fetchLoginStatus(),
                      status.loggedIn else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .netease, accountId: status.userId,
                    displayName: status.nickname, avatarURLString: status.avatarURL)
                // (92) 任务 10：VIP 顺手落缓存（profile.vipType 同路回）。
                NativeSessionStore.shared.saveVIP(
                    provider: .netease, level: status.vipType)
            case .qq:
                let client = QQLoginClient()
                guard let cookie = NativeSessionStore.shared.qqCookieString(),
                      let profile = try? await client.fetchLoginStatus(cookie: cookie)
                else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .qq, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
                // (92) 任务 10：QQ VIP 走独立端点 /user/vip 复核落缓存。
                if let vip = await client.fetchVIPLevel(cookie: cookie) {
                    NativeSessionStore.shared.saveVIP(provider: .qq, level: vip)
                }
            case .kugou:
                let client = KugouLoginClient()
                guard let cookie = NativeSessionStore.shared.kugouCookieString(),
                      let profile = try? await client.fetchUserDetail(
                        cookie: cookie, userId: Self.kugouUserId90(in: cookie))
                else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .kugou, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
                // (92) 任务 10：酷狗 VIP 先落资料内初值、再以
                // /user/vip/detail 复核覆盖（网页版同序）。
                if let initial = profile.vipLevel {
                    NativeSessionStore.shared.saveVIP(provider: .kugou, level: initial)
                }
                if let vip = await client.fetchVIPLevel(cookie: cookie) {
                    NativeSessionStore.shared.saveVIP(provider: .kugou, level: vip)
                }
            }
            Breadcrumbs.log("port90 account enrich provider=\(provider.rawValue)")
            await MainActor.run { self?.rebuild() }
        }
    }

    private static func kugouUserId90(in cookie: String) -> String? {
        for entry in cookie.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "userid" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// 单家头像格：圆盘（真头像/默认占位）+ 登录态点 + 盘下
    /// 平台小字；整格可点（未登录 → 扫码面；已登录 → 选中
    /// 并在下方出详情/退出）。
    private func avatarCell(_ status: ProviderSessionStatus) -> UIView {
        let cell = UIStackView()
        cell.axis = .vertical
        cell.spacing = 5
        cell.alignment = .center

        let discWrap = UIView()
        discWrap.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        discWrap.layer.cornerRadius = 27
        discWrap.clipsToBounds = true
        discWrap.translatesAutoresizingMaskIntoConstraints = false
        let ring = UIView()
        ring.layer.cornerRadius = 27
        ring.layer.borderWidth = 2
        ring.layer.borderColor = (status.provider == selectedProvider
            ? UIColor.white.withAlphaComponent(0.85)
            : UIColor.clear).cgColor
        ring.translatesAutoresizingMaskIntoConstraints = false
        discWrap.addSubview(ring)
        ringViews[status.provider] = ring

        // 默认头像位：盘底浅色 + 平台首字（在图下层）——图未
        // 到时透出占位字、图到后被真头像盖住，不再是黑盘。
        let placeholder = UILabel()
        placeholder.text = String(Self.displayName(for: status.provider).prefix(1))
        placeholder.font = .systemFont(ofSize: 17, weight: .semibold)
        placeholder.textColor = UIColor.white.withAlphaComponent(0.55)
        placeholder.textAlignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        discWrap.addSubview(placeholder)

        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 24
        avatar.backgroundColor = .clear
        avatar.translatesAutoresizingMaskIntoConstraints = false
        discWrap.addSubview(avatar)
        avatarViews[status.provider] = avatar

        let dot = UIView()
        dot.backgroundColor = status.isLoggedIn
            ? UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1)
            : UIColor.white.withAlphaComponent(0.30)
        dot.layer.cornerRadius = 5
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = UIColor.secondarySystemBackground.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        discWrap.addSubview(dot)

        NSLayoutConstraint.activate([
            discWrap.widthAnchor.constraint(equalToConstant: 54),
            discWrap.heightAnchor.constraint(equalToConstant: 54),
            ring.centerXAnchor.constraint(equalTo: discWrap.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: discWrap.centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 54),
            ring.heightAnchor.constraint(equalToConstant: 54),
            avatar.centerXAnchor.constraint(equalTo: discWrap.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: discWrap.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),
            placeholder.centerXAnchor.constraint(equalTo: discWrap.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: discWrap.centerYAnchor),
            dot.trailingAnchor.constraint(equalTo: discWrap.trailingAnchor, constant: -1),
            dot.bottomAnchor.constraint(equalTo: discWrap.bottomAnchor, constant: -1),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])
        cell.addArrangedSubview(discWrap)

        let caption = UILabel()
        caption.text = Self.displayName(for: status.provider)
        caption.font = .systemFont(ofSize: 10)
        caption.textColor = .secondaryLabel
        cell.addArrangedSubview(caption)

        if let url = status.avatarURL {
            let key = url.absoluteString
            avatarKeys[status.provider] = key
            let provider = status.provider
            WorkbenchCover.loadAvatar(url: url, into: avatar) { [weak self] in
                self?.avatarKeys[provider] == key
            }
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(avatarCellTapped(_:)))
        cell.addGestureRecognizer(tap)
        cell.isUserInteractionEnabled = true
        cell.tag = providerTag(status.provider)
        return cell
    }

    /// 选中家详情行（小字一行 + 退出钮）：已登录出昵称 · ID；
    /// 未登录出一行提示（点头像即去扫码）。
    private func detailRow(_ status: ProviderSessionStatus) -> UIView {
        let row = UIView()
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        if status.isLoggedIn {
            let name = status.displayName.flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.displayName(for: status.provider)
            // (92) 任务 10：VIP 皇冠（网页版账户页同口径：昵
            // 称旁一枚、vipType != 0 才显，0/未知不显）。
            if (status.vipLevel ?? 0) > 0 {
                let baseAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
                let text = NSMutableAttributedString(
                    string: "\(name) ", attributes: baseAttrs)
                let crown = NSTextAttachment()
                crown.image = UIImage(
                    systemName: "crown.fill",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 11, weight: .semibold))?
                    .withTintColor(UIColor(red: 1, green: 0.78, blue: 0.25, alpha: 1),
                                   renderingMode: .alwaysOriginal)
                crown.bounds = CGRect(x: 0, y: -1.5, width: 13, height: 10)
                text.append(NSAttributedString(attachment: crown))
                text.append(NSAttributedString(
                    string: " · ID \(status.accountId ?? "—")",
                    attributes: baseAttrs))
                label.attributedText = text
            } else {
                label.text = "\(name) · ID \(status.accountId ?? "—")"
            }
        } else {
            label.text = "\(Self.displayName(for: status.provider)) · 未登录，点头像扫码登录"
        }
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        if status.isLoggedIn {
            let logoutButton = UIButton(type: .system)
            logoutButton.setTitle("退出", for: .normal)
            logoutButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .medium)
            logoutButton.translatesAutoresizingMaskIntoConstraints = false
            let provider = status.provider
            logoutButton.addAction(UIAction { [weak self] _ in
                self?.logout(provider: provider)
            }, for: .touchUpInside)
            row.addSubview(logoutButton)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(lessThanOrEqualTo: logoutButton.leadingAnchor, constant: -8),
                logoutButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                logoutButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            ])
        }
        return row
    }

    private func providerTag(_ provider: NativeSessionStore.Provider) -> Int {
        switch provider {
        case .netease: return 0
        case .qq: return 1
        case .kugou: return 2
        }
    }

    @objc private func avatarCellTapped(_ gesture: UITapGestureRecognizer) {
        guard let tag = gesture.view?.tag else { return }
        let provider: NativeSessionStore.Provider =
            tag == 1 ? .qq : (tag == 2 ? .kugou : .netease)
        Breadcrumbs.log("account74.tap provider=\(provider.rawValue)")
        let status = ProviderSessionStatusQuery.allStatuses()
            .first(where: { $0.provider == provider })
        if let status, status.isLoggedIn {
            selectedProvider = provider
            rebuild()
        } else {
            // 未登录：点头像直接弹该家扫码登录面（网页式）。
            openLogin(provider: provider)
        }
    }

    /// 压墙弹层开登录页（(62) §2 登录层形态）：pageSheet +
    /// medium/large detents + 抓手（下拉关闭），预选目标平台。
    /// LoginViewController 内即三家扫码面（平台页签/通道/
    /// 二维码/状态行），QQ/酷狗走各自原生客户端全链
    /// （key→create→check→status），非假界面。
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
