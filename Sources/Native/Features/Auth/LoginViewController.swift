import UIKit

/// (53) B 组：三家原生登录页（网易云 / QQ / 酷狗分段）。
///
/// 网易云段保持 (51) 行为零回归：key → create（qrimg base64，
/// 缺图用 qrurl 本地生成）→ 每 2 秒轮询 check、总时长 5 分钟、
/// 800 过期自动刷新、803 过 MUSIC_U 校验才存
/// NativeSessionStore 并 adoptNativeSession；面包屑
/// login.qr.begin/success/expired/cancel 不变。
///
/// QQ 段（login.qq.*）：/login/channels 声明通道（未声明回落
/// QQ/微信）→ qr/key?channel= → qr/create → qr/check
/// （801/802/803/800 同网易云码义，800 带上游拒绝信息时是
/// 失败不是过期）→ 803 整串 cookie 过 qqmusic_session 校验
/// 组装 envelope 落存 → login_status 复核（无 profile =
/// 后端不认，清本家会话并报失败；网络失败不清、按已登录
/// 处理）。QQ 二维码后端 TTL 180 秒，前端 175 秒收手。
///
/// 酷狗段（login.kugou.*）：qr/key（20028 设备验证先
/// register/dev 重试）→ qr/create?qrimg=true → qr/check
/// （status 0/1/2/3/4）→ status 4 的 token/userid 成对校验
/// 后组装整串 cookie 落存 → user/detail 复核补资料。
///
/// 三家轮询统一走 PollingCoordinator：同一时刻只一个活跃
/// 会话，切换分段/离开页面/退后台必 cancel；落存前校验
/// generation token。退出登录只清本家（clear(provider:)）。
/// 面包屑绝不记 cookie/凭据原文，只记 len/hash8。
final class LoginViewController: UIViewController {

    /// 登录成功回调（存会话完成后在主线程调用，任一家成功
    /// 都触发；设置页据此刷新账号段）。
    var onLoginSuccess: (() -> Void)?

    /// (62) 预选平台：账户弹层/墙上入口指定时，viewDidLoad
    /// 按此落 selectedProvider 与段控（nil = 缺省网易云）。
    var initialProvider: NativeSessionStore.Provider?

    /// port90（任务 12）：专用扫码模式——由指定平台入口打开时
    /// （initialProvider 非空），页面只剩该平台扫码：平台行组/
    /// 账号区/同步钮/酷狗方式段全隐，与网页版「点平台直接出
    /// 二维码弹层」同形。其余入口（不设 initialProvider）仍为
    /// 通用登录中心、形态不变。
    var dedicated90: Bool { initialProvider != nil }
    private var providerRowsStack89View: UIStackView?

    private let neteaseClient = NeteaseQRLoginClient()
    private let qqClient = QQLoginClient()
    private let kugouClient = KugouLoginClient()
    private let coordinator = PollingCoordinator.shared

    private var selectedProvider: NativeSessionStore.Provider = .netease
    private var loginSucceeded = false
    private var neteaseFlowActive = false
    /// 网易云流程在本页开过（login.qr.cancel 的旧口径：开过、
    /// 未成功、页面消失即记 cancel，不受流程是否已收尾影响）。
    private var neteaseFlowStarted = false
    private var flowActive = false

    // QQ 通道（探测前按网页版回落集 [qq, wechat]）。
    private var qqChannels: [String] = QQLoginClient.fallbackChannels
    private var qqChannel = "qq"
    private var qqChannelsProbed = false

    private let providerSegment = UISegmentedControl(items: ["网易云", "QQ", "酷狗"])
    private let channelSegment = UISegmentedControl()
    // (62) §2 酷狗三方式：方式段控 + 凭据字段组（扫码/账号
    // 密码/手机验证码；后两式端点 2026-11-21 线上实测在）。
    private let kugouMethodSegment = UISegmentedControl(
        items: ["扫码", "账号密码", "验证码"])
    private let kugouPrimaryField = UITextField()
    private let kugouSecondaryField = UITextField()
    private let kugouCaptchaButton = UIButton(type: .system)
    private let kugouFieldStack = UIStackView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let accountStatusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    /// (62) 同步数据钮与结果回显行（§2）。
    private let syncButton = UIButton(type: .system)
    private let syncStatusLabel = UILabel()
    private let qrImageView = UIImageView()
    private let qrStatusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var qrViews: [UIView] = []
    private var backgroundObserver: NSObjectProtocol?

    // (89)B b-login-form：平台列按手机纵排转译——顶部三行平台
    // 行组取代段控的呈出（providerSegment 本体保留作状态持有，
    // 不入视图层级；点行写回其 selectedSegmentIndex 并直调
    // providerChanged，与原 valueChanged 同一处理函数）。
    private var providerRows89: [UIButton] = []
    private var providerRowStatusLabels89: [UILabel] = []
    private static let providerRowProviders89: [NativeSessionStore.Provider] =
        [.netease, .qq, .kugou]
    private static let providerRowNames89 = ["网易云", "QQ", "酷狗"]
    private static let providerRowColors89: [UIColor] = [
        UIColor(red: 0.91, green: 0.10, blue: 0.05, alpha: 1),   // 网易云红
        UIColor(red: 0.19, green: 0.76, blue: 0.49, alpha: 1),   // QQ 音乐绿
        UIColor(red: 0.16, green: 0.47, blue: 1.0, alpha: 1),    // 酷狗蓝
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride() // (62) INT-1：明暗三段读主题系统，不再写死深色
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)
        // (62) 预选平台落位（段控下标与 providerChanged 同映射）。
        if let initialProvider {
            selectedProvider = initialProvider
            providerSegment.selectedSegmentIndex =
                initialProvider == .qq ? 1 : (initialProvider == .kugou ? 2 : 0)
        }
        buildLayout()
        Breadcrumbs.log("login.qr.begin")
        refreshAccountUI()
        // (62) QQ keepalive：打开登录页时检查到期窗口并续期。
        Task { [weak self] in await self?.qqClient.keepaliveIfNeeded() }
        // (51) 旧口径保留：打开页面时网易云未登录直接出码。
        // (62) 预选非网易云时改判预选平台未登录即出码。
        let entryProvider = initialProvider ?? .netease
        if ProviderSessionStatusQuery.status(for: entryProvider).isLoggedIn == false {
            startFlow()
        }
        // (62) 预选 QQ 时补通道探测（与 providerChanged 同路）。
        if initialProvider == .qq && !qqChannelsProbed {
            qqChannelsProbed = true
            Task { [weak self] in
                guard let self else { return }
                if let channels = await self.qqClient.fetchChannels() {
                    self.qqChannels = channels
                }
                await MainActor.run { self.rebuildChannelSegment() }
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, self.flowActive else { return }
                self.coordinator.cancelActive(reason: "background")
                self.flowActive = false
                self.neteaseFlowActive = false
                self.qrStatusLabel.text = "扫码已取消（应用退后台）"
                self.spinner.stopAnimating()
            }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 离开页面停轮询；网易云非成功关闭沿用 login.qr.cancel。
        if flowActive {
            coordinator.cancelActive(reason: "leave")
            flowActive = false
            neteaseFlowActive = false
        }
        if neteaseFlowStarted && !loginSucceeded {
            Breadcrumbs.log("login.qr.cancel")
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
    }

    // MARK: - 布局

    private func buildLayout() {
        // (62) 尊重 viewDidLoad 的预选平台（缺省仍为 0=网易云）。
        providerSegment.selectedSegmentIndex =
            selectedProvider == .qq ? 1 : (selectedProvider == .kugou ? 2 : 0)
        providerSegment.addTarget(self, action: #selector(providerChanged), for: .valueChanged)

        channelSegment.isHidden = true
        channelSegment.addTarget(self, action: #selector(channelChanged), for: .valueChanged)
        rebuildChannelSegment()

        avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        avatarView.layer.cornerRadius = 28
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        // (89)B b-login-form：主区说明标题对齐网页 20 semibold
        // （nameLabel 即现标题 label，只改字号、文案不动）；说明
        // 行 accountStatusLabel 现 13pt 与网页说明 13 一致、不动。
        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center

        accountStatusLabel.font = .systemFont(ofSize: 13)
        accountStatusLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        accountStatusLabel.textAlignment = .center

        actionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        actionButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        actionButton.layer.cornerRadius = 12
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        actionButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 12
        qrImageView.clipsToBounds = true
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        qrStatusLabel.font = .systemFont(ofSize: 13)
        qrStatusLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        qrStatusLabel.textAlignment = .center
        qrStatusLabel.numberOfLines = 0

        spinner.color = .white
        spinner.hidesWhenStopped = true
        qrViews = [qrImageView, qrStatusLabel, spinner]
        qrViews.forEach { $0.isHidden = true }

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        closeButton.layer.cornerRadius = 12
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        syncButton.setTitle("同步数据", for: .normal)
        syncButton.setTitleColor(.white, for: .normal)
        syncButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        syncButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        syncButton.layer.cornerRadius = 12
        syncButton.addTarget(self, action: #selector(syncTapped), for: .touchUpInside)
        syncButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        syncStatusLabel.font = .systemFont(ofSize: 12)
        syncStatusLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        syncStatusLabel.textAlignment = .center
        syncStatusLabel.numberOfLines = 2

        // (62) 酷狗方式段与字段组。
        kugouMethodSegment.selectedSegmentIndex = 0
        kugouMethodSegment.addTarget(
            self, action: #selector(kugouMethodChanged62), for: .valueChanged)
        for field in [kugouPrimaryField, kugouSecondaryField] {
            field.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            field.textColor = .white
            field.font = .systemFont(ofSize: 14)
            field.layer.cornerRadius = 10
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
            field.leftViewMode = .always
            field.heightAnchor.constraint(equalToConstant: 42).isActive = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        kugouPrimaryField.returnKeyType = .next
        kugouSecondaryField.returnKeyType = .go
        kugouCaptchaButton.setTitle("获取验证码", for: .normal)
        kugouCaptchaButton.setTitleColor(.white, for: .normal)
        kugouCaptchaButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        kugouCaptchaButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        kugouCaptchaButton.layer.cornerRadius = 10
        kugouCaptchaButton.addTarget(
            self, action: #selector(kugouCaptchaTapped62), for: .touchUpInside)
        kugouCaptchaButton.widthAnchor.constraint(equalToConstant: 96).isActive = true
        let kugouSecondaryRow = UIStackView(arrangedSubviews: [
            kugouSecondaryField, kugouCaptchaButton])
        kugouSecondaryRow.axis = .horizontal
        kugouSecondaryRow.spacing = 8
        kugouFieldStack.axis = .vertical
        kugouFieldStack.spacing = 10
        kugouFieldStack.addArrangedSubview(kugouPrimaryField)
        kugouFieldStack.addArrangedSubview(kugouSecondaryRow)
        kugouFieldStack.widthAnchor.constraint(equalToConstant: 260).isActive = true
        kugouMethodSegment.isHidden = true
        kugouFieldStack.isHidden = true

        // (89)B b-login-form：平台行组（三行纵排，每行平台色点
        // 10＋平台名 15＋右侧状态字 11.5 白 0.55，行高 44，选中
        // 行白 0.08 底圆角 10）。providerSegment 不再入层级。
        providerSegment.isHidden = true
        let providerRowsStack89 = UIStackView()
        providerRowsStack89.axis = .vertical
        providerRowsStack89.spacing = 6
        providerRows89 = []
        providerRowStatusLabels89 = []
        for index in Self.providerRowProviders89.indices {
            let row = UIButton(type: .system)
            row.tag = index
            row.layer.cornerRadius = 10
            row.clipsToBounds = true
            row.addTarget(self, action: #selector(providerRowTapped89(_:)),
                          for: .touchUpInside)
            row.translatesAutoresizingMaskIntoConstraints = false
            let dot = UIView()
            dot.backgroundColor = Self.providerRowColors89[index]
            dot.layer.cornerRadius = 5
            dot.isUserInteractionEnabled = false
            dot.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(dot)
            let name = UILabel()
            name.text = Self.providerRowNames89[index]
            name.font = .systemFont(ofSize: 15)
            name.textColor = .white
            name.isUserInteractionEnabled = false
            name.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(name)
            let status = UILabel()
            status.font = .systemFont(ofSize: 11.5)
            status.textColor = UIColor.white.withAlphaComponent(0.55)
            status.isUserInteractionEnabled = false
            status.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(status)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 44),
                dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10),
                name.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
                name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                status.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                status.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            providerRows89.append(row)
            providerRowStatusLabels89.append(status)
            providerRowsStack89.addArrangedSubview(row)
        }
        providerRowsStack89.widthAnchor.constraint(equalToConstant: 272).isActive = true
        providerRowsStack89View = providerRowsStack89
        refreshProviderRows89()
        Breadcrumbs.log("port89 login=rows")

        let stack = UIStackView(arrangedSubviews: [
            providerRowsStack89, channelSegment, kugouMethodSegment,
            kugouFieldStack, avatarView, nameLabel,
            accountStatusLabel, actionButton, syncButton, syncStatusLabel,
            qrImageView, qrStatusLabel,
            spinner, closeButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),
            // (89) §12-2：码瓷砖 220 → 200（网页 LoginTile 200×200）。
            qrImageView.widthAnchor.constraint(equalToConstant: 200),
            qrImageView.heightAnchor.constraint(equalToConstant: 200),
            actionButton.widthAnchor.constraint(equalToConstant: 200),
            syncButton.widthAnchor.constraint(equalToConstant: 200),
            closeButton.widthAnchor.constraint(equalToConstant: 160)
        ])
        // port90：专用模式装配即隐中间层（nameLabel 留作平台名标题；
        // QR 区由 startFlow 点亮）。后续回刷路径各自并入 dedicated90。
        if dedicated90 {
            providerRowsStack89View?.isHidden = true
            avatarView.isHidden = true
            accountStatusLabel.isHidden = true
            actionButton.isHidden = true
            syncButton.isHidden = true
            syncStatusLabel.isHidden = true
            Breadcrumbs.log("port90 login dedicated provider=\(selectedProvider.rawValue)")
        }
    }

    private func rebuildChannelSegment() {
        channelSegment.removeAllSegments()
        for (index, channel) in qqChannels.enumerated() {
            channelSegment.insertSegment(
                withTitle: QQLoginClient.channelLabels[channel] ?? channel,
                at: index, animated: false)
        }
        let selected = qqChannels.firstIndex(of: qqChannel) ?? 0
        if !qqChannels.isEmpty {
            qqChannel = qqChannels[min(selected, qqChannels.count - 1)]
            channelSegment.selectedSegmentIndex = min(selected, qqChannels.count - 1)
        }
        // 网页版口径：只剩一个通道时不显示选择器。
        // port90：专用模式恒隐（通道走默认）。
        channelSegment.isHidden = dedicated90 || selectedProvider != .qq || qqChannels.count <= 1
    }

    // MARK: - 分段与账号区

    /// (89)B b-login-form 接线点：点平台行 → 写回 providerSegment
    /// 的 selectedSegmentIndex（与 viewDidLoad 预选平台同一映射）
    /// → 直调 providerChanged（即段控 valueChanged 的原处理函
    /// 数）；登录/轮询/通道探测逻辑一字不动。
    @objc private func providerRowTapped89(_ sender: UIButton) {
        providerSegment.selectedSegmentIndex = sender.tag
        providerChanged()
    }

    /// (89)B 平台行选中态与状态字刷新（选中行白 0.08 底；状态
    /// 字走 ProviderSessionStatusQuery 同步缓存，与账号区同源）。
    private func refreshProviderRows89() {
        for (index, row) in providerRows89.enumerated() {
            let provider = Self.providerRowProviders89[index]
            row.backgroundColor = provider == selectedProvider
                ? UIColor.white.withAlphaComponent(0.08) : .clear
            if providerRowStatusLabels89.indices.contains(index) {
                let status = ProviderSessionStatusQuery.status(for: provider)
                providerRowStatusLabels89[index].text =
                    status.isLoggedIn ? "已登录" : "未登录"
            }
        }
    }

    @objc private func providerChanged() {
        if flowActive {
            coordinator.cancelActive(reason: "switch")
            flowActive = false
            neteaseFlowActive = false
        }
        setQRVisible(false)
        switch providerSegment.selectedSegmentIndex {
        case 1: selectedProvider = .qq
        case 2: selectedProvider = .kugou
        default: selectedProvider = .netease
        }
        if selectedProvider == .qq && !qqChannelsProbed {
            qqChannelsProbed = true
            Task { [weak self] in
                guard let self else { return }
                if let channels = await self.qqClient.fetchChannels() {
                    self.qqChannels = channels
                }
                await MainActor.run { self.rebuildChannelSegment() }
            }
        }
        rebuildChannelSegment()
        refreshAccountUI()
    }

    @objc private func channelChanged() {
        let index = channelSegment.selectedSegmentIndex
        guard qqChannels.indices.contains(index) else { return }
        qqChannel = qqChannels[index]
        // 通道变了，正在跑的 QQ 码作废重开。
        if flowActive && selectedProvider == .qq {
            startFlow()
        }
    }

    private static func displayName(for provider: NativeSessionStore.Provider) -> String {
        switch provider {
        case .netease: return "网易云"
        case .qq: return "QQ 音乐"
        case .kugou: return "酷狗"
        }
    }

    /// 账号区刷新：状态走 ProviderSessionStatus 同步缓存；
    /// 已登录但缺昵称时异步补资料（失败保留「已登录」）。
    private func refreshAccountUI() {
        let provider = selectedProvider
        let status = ProviderSessionStatusQuery.status(for: provider)
        refreshProviderRows89() // (89)B：平台行选中态/状态字随账号区同拍刷新
        nameLabel.text = Self.displayName(for: provider)
        if status.isLoggedIn {
            // (62) §2：已登录态补用户 ID 显示（accountId 走
            // ProviderSessionStatusQuery 资料缓存，缺失显 —）。
            let name = status.displayName ?? "已登录"
            accountStatusLabel.text = "已登录 · \(name) · ID \(status.accountId ?? "—")"
            actionButton.setTitle("退出登录", for: .normal)
        } else {
            accountStatusLabel.text = "未登录"
            actionButton.setTitle("扫码登录", for: .normal)
        }
        syncButton.isHidden = dedicated90 || !status.isLoggedIn
        updateKugouMethodUI62(loggedIn: status.isLoggedIn)
        avatarView.image = nil
        if let avatarURL = status.avatarURL {
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: avatarURL),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    if self?.selectedProvider == provider { self?.avatarView.image = image }
                }
            }
        }
        // (62) 尾波第 3 组：门控放宽——昵称或头像任一缺失都补。
        // 旧门控只看 displayName，存量用户昵称非空时 enrich 永
        // 不触发、资料缓存的 avatarURL 键永不回填（avatar=0 定因）。
        if status.isLoggedIn && (status.displayName == nil || status.avatarURL == nil) {
            enrichProfile(for: provider)
        }
    }

    /// 补资料：只写资料缓存，不动会话；失败静默（下次打开再补）。
    private func enrichProfile(for provider: NativeSessionStore.Provider) {
        Task { [weak self] in
            guard let self else { return }
            switch provider {
            case .netease:
                guard let status = try? await NativeDataClient.shared.fetchLoginStatus(),
                      status.loggedIn else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .netease, accountId: status.userId,
                    displayName: status.nickname, avatarURLString: status.avatarURL)
            case .qq:
                guard let cookie = NativeSessionStore.shared.qqCookieString(),
                      let profile = try? await self.qqClient.fetchLoginStatus(cookie: cookie)
                else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .qq, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
            case .kugou:
                guard let cookie = NativeSessionStore.shared.kugouCookieString(),
                      let profile = try? await self.kugouClient.fetchUserDetail(
                        cookie: cookie, userId: Self.kugouUserId(in: cookie)) else { return }
                NativeSessionStore.shared.saveProfile(
                    provider: .kugou, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
            }
            await MainActor.run {
                if self.selectedProvider == provider { self.refreshAccountUI() }
            }
        }
    }

    private static func kugouUserId(in cookie: String) -> String? {
        for entry in cookie.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "userid" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - 动作（登录/退出）

    @objc private func actionTapped() {
        let status = ProviderSessionStatusQuery.status(for: selectedProvider)
        if status.isLoggedIn {
            confirmLogout()
        } else if selectedProvider == .kugou
                    && kugouMethodSegment.selectedSegmentIndex != 0 {
            runKugouCredentialLogin62()
        } else {
            startFlow()
        }
    }

    // MARK: - (62) 酷狗三方式

    @objc private func kugouMethodChanged62() {
        updateKugouMethodUI62(
            loggedIn: ProviderSessionStatusQuery
                .status(for: selectedProvider).isLoggedIn)
    }

    /// 方式段/字段组显隐与占位文案：仅酷狗未登录时出段控；
    /// 非扫码方式出字段组并把主钮改「登录」。
    private func updateKugouMethodUI62(loggedIn: Bool) {
        let isKugou = selectedProvider == .kugou
        // port90：专用模式强制扫码法——方式段恒隐、字段组恒隐、下标钉 0。
        if dedicated90 { kugouMethodSegment.selectedSegmentIndex = 0 }
        kugouMethodSegment.isHidden = dedicated90 || !isKugou || loggedIn
        let method = kugouMethodSegment.selectedSegmentIndex
        let showFields = isKugou && !loggedIn && method != 0
        kugouFieldStack.isHidden = !showFields
        if showFields {
            if method == 1 {
                kugouPrimaryField.placeholder = "酷狗账号（手机号/邮箱）"
                kugouSecondaryField.placeholder = "密码"
                kugouSecondaryField.isSecureTextEntry = true
                kugouSecondaryField.keyboardType = .default
                kugouPrimaryField.keyboardType = .default
                kugouCaptchaButton.isHidden = true
            } else {
                kugouPrimaryField.placeholder = "手机号"
                kugouSecondaryField.placeholder = "短信验证码"
                kugouSecondaryField.isSecureTextEntry = false
                kugouSecondaryField.keyboardType = .numberPad
                kugouPrimaryField.keyboardType = .phonePad
                kugouCaptchaButton.isHidden = false
            }
            if !loggedIn { actionButton.setTitle("登录", for: .normal) }
        } else if isKugou && !loggedIn {
            actionButton.setTitle("扫码登录", for: .normal)
        }
        let light = [NSAttributedString.Key.foregroundColor:
                        UIColor.white.withAlphaComponent(0.4)]
        kugouPrimaryField.attributedPlaceholder = NSAttributedString(
            string: kugouPrimaryField.placeholder ?? "", attributes: light)
        kugouSecondaryField.attributedPlaceholder = NSAttributedString(
            string: kugouSecondaryField.placeholder ?? "", attributes: light)
    }

    @objc private func kugouCaptchaTapped62() {
        let mobile = kugouPrimaryField.text?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard mobile.count >= 11 else {
            accountStatusLabel.text = "先填正确的手机号"
            return
        }
        kugouCaptchaButton.isEnabled = false
        accountStatusLabel.text = "验证码发送中…"
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.kugouClient.sendCaptcha(mobile: mobile)
                Breadcrumbs.log("login62.kugou captcha sent")
                await MainActor.run {
                    self.accountStatusLabel.text = "验证码已发送，请查收短信"
                    self.kugouCaptchaButton.isEnabled = true
                }
            } catch let error as KugouLoginClient.KugouLoginError {
                let message: String
                if case .failed(let text) = error { message = text }
                else { message = "验证码发送失败" }
                await MainActor.run {
                    self.accountStatusLabel.text = message
                    self.kugouCaptchaButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.accountStatusLabel.text = "验证码发送失败（网络异常）"
                    self.kugouCaptchaButton.isEnabled = true
                }
            }
        }
    }

    /// 凭据登录执行：成功回包走 handleKugouAuthorized 同路落存
    /// 与复核；失败把后端文案回显到状态行（不假装）。
    private func runKugouCredentialLogin62() {
        let method = kugouMethodSegment.selectedSegmentIndex
        let primary = kugouPrimaryField.text?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let secondary = kugouSecondaryField.text?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !primary.isEmpty, !secondary.isEmpty else {
            accountStatusLabel.text = method == 1 ? "账号和密码都要填" : "手机号和验证码都要填"
            return
        }
        let gen = coordinator.begin(provider: .kugou)
        flowActive = true
        setQRVisible(true)
        qrImageView.isHidden = true
        qrStatusLabel.text = "登录中…"
        Breadcrumbs.log("login62.kugou credential begin method=\(method == 1 ? "password" : "cellphone")")
        let task = Task { [weak self] in
            guard let self else { return }
            let result: KugouLoginClient.CheckResult
            do {
                result = method == 1
                    ? try await self.kugouClient.loginByPassword(
                        username: primary, password: secondary)
                    : try await self.kugouClient.loginByCellphone(
                        mobile: primary, code: secondary)
            } catch {
                await MainActor.run {
                    self.flowActive = false
                    self.setQRVisible(false)
                    self.accountStatusLabel.text = "登录失败（网络异常），请重试"
                }
                self.coordinator.finish(generation: gen)
                return
            }
            switch result {
            case .authorized(let cookie, let userId):
                _ = await self.handleKugouAuthorized(
                    cookie, userId: userId, gen: gen)
            case .failed(let message):
                Breadcrumbs.log("login62.kugou credential fail msg=\(message ?? "-")")
                await MainActor.run {
                    self.flowActive = false
                    self.setQRVisible(false)
                    self.accountStatusLabel.text = message ?? "登录失败，请重试"
                }
            default:
                await MainActor.run {
                    self.flowActive = false
                    self.setQRVisible(false)
                    self.accountStatusLabel.text = "登录回包异常，请重试"
                }
            }
            self.coordinator.finish(generation: gen)
        }
        coordinator.attach(task, generation: gen)
    }

    private func confirmLogout() {
        let provider = selectedProvider
        let alert = UIAlertController(
            title: "退出登录",
            message: "退出后将清除本机保存的\(Self.displayName(for: provider))登录状态（不影响其他平台）。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            self?.performLogout(provider: provider)
        })
        present(alert, animated: true)
    }

    /// 退出只清本家：网易云走 NativeDataClient 既有清法（含
    /// Web 侧两键与迁移旗标，与设置页口径一致）；QQ/酷狗先
    /// 本地清（clear(provider:)）再 best effort 通知后端。
    /// 同步数据（(62) §2）：重拉当前平台资料（enrichProfile
    /// 同路）+ 网易云附带歌单数校验，结果与时间回显到
    /// syncStatusLabel；失败诚实报错不假装成功。
    @objc private func syncTapped() {
        let provider = selectedProvider
        syncButton.isEnabled = false
        syncStatusLabel.text = "同步中…"
        Breadcrumbs.log("login62.sync begin provider=\(provider.rawValue)")
        Task { [weak self] in
            guard let self else { return }
            var parts: [String] = []
            var failed = false
            // 资料重拉：按平台走既有状态端点并回写资料缓存。
            switch provider {
            case .netease:
                if let status = try? await NativeDataClient.shared.fetchLoginStatus(),
                   status.loggedIn {
                    NativeSessionStore.shared.saveProfile(
                        provider: .netease, accountId: status.userId,
                        displayName: status.nickname,
                        avatarURLString: status.avatarURL)
                    parts.append("资料已更新")
                    if let userId = status.userId,
                       let playlists = try? await NativeDataClient.shared
                           .fetchUserPlaylists(userId: userId) {
                        parts.append("歌单 \(playlists.count) 个")
                    }
                } else { failed = true }
            case .qq:
                if let cookie = NativeSessionStore.shared.qqCookieString(),
                   let profile = try? await self.qqClient.fetchLoginStatus(cookie: cookie) {
                    NativeSessionStore.shared.saveProfile(
                        provider: .qq, accountId: profile.accountId,
                        displayName: profile.nickname,
                        avatarURLString: profile.avatarURLString)
                    parts.append("资料已更新")
                } else { failed = true }
            case .kugou:
                if let cookie = NativeSessionStore.shared.kugouCookieString(),
                   let profile = try? await self.kugouClient.fetchUserDetail(
                       cookie: cookie, userId: Self.kugouUserId(in: cookie)) {
                    NativeSessionStore.shared.saveProfile(
                        provider: .kugou, accountId: profile.accountId,
                        displayName: profile.nickname,
                        avatarURLString: profile.avatarURLString)
                    parts.append("资料已更新")
                } else { failed = true }
            }
            await MainActor.run {
                self.syncButton.isEnabled = true
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                if failed {
                    self.syncStatusLabel.text = "同步失败（\(formatter.string(from: Date()))）：会话可能已失效，请重新登录"
                    Breadcrumbs.log("login62.sync fail provider=\(provider.rawValue)")
                } else {
                    self.syncStatusLabel.text = "已同步 · \(parts.joined(separator: " · ")) · \(formatter.string(from: Date()))"
                    Breadcrumbs.log("login62.sync ok provider=\(provider.rawValue)")
                }
                self.refreshAccountUI()
            }
        }
    }

    private func performLogout(provider: NativeSessionStore.Provider) {
        Breadcrumbs.log("login.logout provider=\(provider.rawValue)")
        switch provider {
        case .netease:
            NativeDataClient.shared.clearNativeSession()
            SessionMigrator.state = .pending
        case .qq:
            let cookie = NativeSessionStore.shared.qqCookieString()
            NativeSessionStore.shared.clear(provider: .qq, reason: "logout")
            if let cookie { Task { await self.qqClient.logout(cookie: cookie) } }
        case .kugou:
            let cookie = NativeSessionStore.shared.kugouCookieString()
            NativeSessionStore.shared.clear(provider: .kugou, reason: "logout")
            if let cookie { Task { await self.kugouClient.logout(cookie: cookie) } }
        }
        refreshAccountUI()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - 扫码流程调度

    private func setQRVisible(_ visible: Bool) {
        qrViews.forEach { $0.isHidden = !visible }
        if visible { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    private func startFlow() {
        let gen = coordinator.begin(provider: selectedProvider)
        flowActive = true
        neteaseFlowActive = selectedProvider == .netease
        if selectedProvider == .netease { neteaseFlowStarted = true }
        setQRVisible(true)
        qrImageView.image = nil
        qrStatusLabel.text = "正在生成二维码…"
        let task: Task<Void, Never>
        switch selectedProvider {
        case .netease:
            task = Task { [weak self] in await self?.runNeteaseFlow(gen: gen) }
        case .qq:
            task = Task { [weak self] in await self?.runQQFlow(gen: gen) }
        case .kugou:
            task = Task { [weak self] in await self?.runKugouFlow(gen: gen) }
        }
        coordinator.attach(task, generation: gen)
    }

    private func flowFinished(gen: Int) {
        coordinator.finish(generation: gen)
        flowActive = false
        neteaseFlowActive = false
    }

    private func handleLoginSuccess(gen: Int) {
        loginSucceeded = true
        flowFinished(gen: gen)
        onLoginSuccess?()
        dismiss(animated: true)
    }

    // MARK: - 网易云流程（(51) 语义逐项保留）

    private enum FlowOutcome { case done, refresh, fatal }

    private func runNeteaseFlow(gen: Int) async {
        let deadline = Date().addingTimeInterval(5 * 60)
        while !Task.isCancelled, coordinator.isCurrent(gen), Date() < deadline {
            let proceed = await runOneNeteaseQRCode(gen: gen, deadline: deadline)
            if proceed == .done || proceed == .fatal || Task.isCancelled { break }
            // .refresh：800 过期后换新码继续（总时长仍受 deadline 限）。
        }
        if !coordinator.isCurrent(gen) { return }
        await MainActor.run {
            if !self.loginSucceeded && self.flowActive {
                self.flowFinished(gen: gen)
                if Date() >= deadline {
                    self.qrStatusLabel.text = "二维码已过期，请关闭后重试"
                    self.spinner.stopAnimating()
                }
            }
        }
    }

    private func runOneNeteaseQRCode(gen: Int, deadline: Date) async -> FlowOutcome {
        let qr: NeteaseQRLoginClient.QRCode
        do {
            let key = try await neteaseClient.fetchKey()
            qr = try await neteaseClient.createQR(key: key)
        } catch {
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败，请检查网络后重试"
                self.spinner.stopAnimating()
            }
            return .fatal
        }
        if Task.isCancelled || !coordinator.isCurrent(gen) { return .done }
        await MainActor.run {
            self.showQRImage(base64: qr.qrimgBase64, content: qr.qrurl)
            self.qrStatusLabel.text = "请用网易云音乐 App 扫码"
            self.spinner.stopAnimating()
        }
        while !Task.isCancelled, coordinator.isCurrent(gen), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || !coordinator.isCurrent(gen) { return .done }
            let result: NeteaseQRLoginClient.CheckResult
            do {
                result = try await neteaseClient.check(key: qr.key)
            } catch {
                continue // 单次轮询失败不终止，下一轮重试。
            }
            switch result {
            case .waiting:
                break
            case .scanned:
                await MainActor.run { self.qrStatusLabel.text = "已扫码，请在手机上确认登录" }
            case .expired:
                Breadcrumbs.log("login.qr.expired")
                await MainActor.run { self.qrStatusLabel.text = "二维码已过期，正在刷新…" }
                return .refresh
            case .authorized(let cookie):
                // 落存前校验代次：旧轮询回调不许串写。
                guard coordinator.isCurrent(gen) else { return .done }
                return await handleNeteaseAuthorized(cookie, gen: gen)
            case .unknown:
                break
            }
        }
        return .done
    }

    private func handleNeteaseAuthorized(_ cookie: String, gen: Int) async -> FlowOutcome {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NativeSessionStore.isValidNeteaseCookie(value) else {
            Breadcrumbs.log("login.qr.fail reason=invalid-cookie len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "登录回包异常（会话校验未过），请重试"
            }
            return .fatal
        }
        Breadcrumbs.log("login.qr.success len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
        await MainActor.run {
            NativeDataClient.shared.adoptNativeSession(value)
        }
        // (61) WA 4②：扫码落盘即补真资料（含 avatarUrl），不再
        // 等下次打开登录页 enrich——失败静默，会话已收编、成功
        // 语义不变，资料下次 enrichProfile 再补。
        if let status = try? await NativeDataClient.shared.fetchLoginStatus(),
           status.loggedIn {
            NativeSessionStore.shared.saveProfile(
                provider: .netease, accountId: status.userId,
                displayName: status.nickname, avatarURLString: status.avatarURL)
            Breadcrumbs.log("login.qr.profile avatar=\(status.avatarURL != nil ? 1 : 0)")
        }
        await MainActor.run {
            self.handleLoginSuccess(gen: gen)
        }
        return .done
    }

    // MARK: - QQ 流程

    private func runQQFlow(gen: Int) async {
        // 后端 QR_TTL 180 秒，前端 175 秒收手（网页版同口径）。
        let deadline = Date().addingTimeInterval(175)
        var lastKey: String?
        while !Task.isCancelled, coordinator.isCurrent(gen), Date() < deadline {
            let proceed = await runOneQQQRCode(gen: gen, deadline: deadline, keySink: { lastKey = $0 })
            if proceed == .done || proceed == .fatal || Task.isCancelled { break }
        }
        if let lastKey, !coordinator.isCurrent(gen) {
            await qqClient.cancelQR(key: lastKey)
        }
        if !coordinator.isCurrent(gen) { return }
        await MainActor.run {
            if !self.loginSucceeded && self.flowActive {
                self.flowFinished(gen: gen)
                if Date() >= deadline {
                    self.qrStatusLabel.text = "二维码已过期，请关闭后重试"
                    self.spinner.stopAnimating()
                }
            }
        }
    }

    private func runOneQQQRCode(gen: Int, deadline: Date,
                                keySink: @escaping (String) -> Void) async -> FlowOutcome {
        let qr: QQLoginClient.QRCode
        do {
            let key = try await qqClient.fetchKey(channel: qqChannel)
            keySink(key)
            qr = try await qqClient.createQR(key: key)
        } catch {
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败，请检查网络后重试"
                self.spinner.stopAnimating()
            }
            return .fatal
        }
        if Task.isCancelled || !coordinator.isCurrent(gen) { return .done }
        guard let image = qr.qrimgBase64, !image.isEmpty else {
            Breadcrumbs.log("login.qq.fail reason=no-qrimg")
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败（后端未回图），请重试"
                self.spinner.stopAnimating()
            }
            return .fatal
        }
        await MainActor.run {
            self.showQRImage(base64: image, content: nil)
            self.qrStatusLabel.text = "请用\(QQLoginClient.channelLabels[self.qqChannel] ?? "QQ")扫码"
            self.spinner.stopAnimating()
        }
        while !Task.isCancelled, coordinator.isCurrent(gen), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || !coordinator.isCurrent(gen) { return .done }
            let result: QQLoginClient.CheckResult
            do {
                result = try await qqClient.check(key: qr.key)
            } catch {
                continue // 单次轮询失败不终止（不清会话、不终止流程）。
            }
            switch result {
            case .waiting:
                break
            case .scanned:
                await MainActor.run { self.qrStatusLabel.text = "已扫码，请在手机上确认登录" }
            case .expired:
                Breadcrumbs.log("login.qq.expired")
                await MainActor.run { self.qrStatusLabel.text = "二维码已过期，正在刷新…" }
                return .refresh
            case .failed(let message):
                Breadcrumbs.log("login.qq.fail reason=upstream-rejected msg=\(message ?? "-")")
                await MainActor.run {
                    self.qrStatusLabel.text = "登录被上游拒绝，请稍后重试"
                    self.spinner.stopAnimating()
                }
                return .fatal
            case .authorized(let cookie):
                guard coordinator.isCurrent(gen) else { return .done }
                return await handleQQAuthorized(cookie, gen: gen)
            case .unknown:
                break
            }
        }
        return .done
    }

    private func handleQQAuthorized(_ cookie: String, gen: Int) async -> FlowOutcome {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NativeSessionStore.isValidQQCookie(value) else {
            Breadcrumbs.log("login.qq.fail reason=invalid-cookie len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "登录回包异常（会话校验未过），请重试"
            }
            return .fatal
        }
        // sealed 会话约 3 天到期（元数据，失效仍以 login_status 为准）。
        let expires = Date().addingTimeInterval(3 * 24 * 3600)
        guard NativeSessionStore.shared.saveQQSession(
            cookie: value, accountId: nil, displayName: nil,
            loginType: 2, expiresAt: expires) else {
            Breadcrumbs.log("login.qq.fail reason=keychain-write len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "会话保存失败，请重试"
            }
            return .fatal
        }
        Breadcrumbs.log("login.qq.success len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
        // login_status 复核：后端不认 = 失效（只清 QQ 本家）；
        // 网络/5xx 失败按 transient 保留会话、照常算登录成功。
        do {
            if let profile = try await qqClient.fetchLoginStatus(cookie: value) {
                NativeSessionStore.shared.saveProfile(
                    provider: .qq, accountId: profile.accountId,
                    displayName: profile.nickname,
                    avatarURLString: profile.avatarURLString)
                _ = NativeSessionStore.shared.saveQQSession(
                    cookie: value, accountId: profile.accountId,
                    displayName: profile.nickname, loginType: 2, expiresAt: expires)
            } else {
                let verdict = NativeSessionStore.classifyAuthFailure(
                    provider: .qq, httpStatus: 200, businessCode: nil,
                    errorCode: nil, hasProfile: false)
                if verdict == .sessionInvalid {
                    Breadcrumbs.log("login.qq.fail reason=status-unrecognized")
                    NativeSessionStore.shared.clear(provider: .qq, reason: "status-unrecognized")
                    await MainActor.run {
                        self.qrStatusLabel.text = "后端未确认登录，请重试"
                        self.spinner.stopAnimating()
                        self.refreshAccountUI()
                    }
                    return .fatal
                }
            }
        } catch {
            Breadcrumbs.log("login.qq.status-check result=transient")
        }
        await MainActor.run { self.handleLoginSuccess(gen: gen) }
        return .done
    }

    // MARK: - 酷狗流程

    private func runKugouFlow(gen: Int) async {
        let deadline = Date().addingTimeInterval(5 * 60)
        while !Task.isCancelled, coordinator.isCurrent(gen), Date() < deadline {
            let proceed = await runOneKugouQRCode(gen: gen, deadline: deadline)
            if proceed == .done || proceed == .fatal || Task.isCancelled { break }
        }
        if !coordinator.isCurrent(gen) { return }
        await MainActor.run {
            if !self.loginSucceeded && self.flowActive {
                self.flowFinished(gen: gen)
                if Date() >= deadline {
                    self.qrStatusLabel.text = "二维码已过期，请关闭后重试"
                    self.spinner.stopAnimating()
                }
            }
        }
    }

    private func runOneKugouQRCode(gen: Int, deadline: Date) async -> FlowOutcome {
        let qr: KugouLoginClient.QRCode
        do {
            let key = try await kugouClient.fetchKey()
            qr = try await kugouClient.createQR(key: key)
        } catch {
            await MainActor.run {
                self.qrStatusLabel.text = "二维码生成失败，请检查网络后重试"
                self.spinner.stopAnimating()
            }
            return .fatal
        }
        if Task.isCancelled || !coordinator.isCurrent(gen) { return .done }
        await MainActor.run {
            self.showQRImage(base64: qr.qrimgBase64, content: qr.qrContent)
            self.qrStatusLabel.text = "请用酷狗音乐 App 扫码"
            self.spinner.stopAnimating()
        }
        while !Task.isCancelled, coordinator.isCurrent(gen), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || !coordinator.isCurrent(gen) { return .done }
            let result: KugouLoginClient.CheckResult
            do {
                result = try await kugouClient.check(key: qr.key)
            } catch {
                continue // 单次轮询失败不终止（不清会话、不终止流程）。
            }
            switch result {
            case .waiting:
                break
            case .scanned:
                await MainActor.run { self.qrStatusLabel.text = "已扫码，请在手机上确认登录" }
            case .expired:
                Breadcrumbs.log("login.kugou.expired")
                await MainActor.run { self.qrStatusLabel.text = "二维码已过期，正在刷新…" }
                return .refresh
            case .failed(let message):
                Breadcrumbs.log("login.kugou.fail reason=check-failed msg=\(message ?? "-")")
                await MainActor.run {
                    self.qrStatusLabel.text = "登录失败，请重试"
                    self.spinner.stopAnimating()
                }
                return .fatal
            case .authorized(let cookie, let userId):
                guard coordinator.isCurrent(gen) else { return .done }
                return await handleKugouAuthorized(cookie, userId: userId, gen: gen)
            case .unknown:
                break
            }
        }
        return .done
    }

    private func handleKugouAuthorized(_ cookie: String, userId: String,
                                       gen: Int) async -> FlowOutcome {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NativeSessionStore.shared.saveKugouCookie(value) else {
            // saveKugouCookie 内含成对校验与回读比对：不过即不落存。
            Breadcrumbs.log("login.kugou.fail reason=invalid-or-write len=\(value.count)")
            await MainActor.run {
                self.qrStatusLabel.text = "登录回包异常（会话校验未过），请重试"
            }
            return .fatal
        }
        Breadcrumbs.log("login.kugou.success len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
        // (62) 尾波第 3 组：saveProfile 已改合并语义（nil=不改
        // 字段），新会话先显式全清旧资料再只存 accountId，防上
        // 一账号的昵称/头像在 detail 复核失败时残留串号（旧整
        // 表覆盖写时代靠覆盖顺带清，此处改显式）。
        NativeSessionStore.shared.saveProfile(
            provider: .kugou, accountId: nil, displayName: nil,
            avatarURLString: nil)
        NativeSessionStore.shared.saveProfile(
            provider: .kugou, accountId: userId, displayName: nil,
            avatarURLString: nil)
        // user/detail 复核补资料：失败按判据处理——只有明确
        // 失效（401/403/152）才清本家，其余保留会话照常成功。
        do {
            let profile = try await kugouClient.fetchUserDetail(cookie: value, userId: userId)
            NativeSessionStore.shared.saveProfile(
                provider: .kugou, accountId: profile.accountId ?? userId,
                displayName: profile.nickname,
                avatarURLString: profile.avatarURLString)
        } catch ProviderLoginTransport.TransportError.http(let status) {
            let verdict = NativeSessionStore.classifyAuthFailure(
                provider: .kugou, httpStatus: status, businessCode: nil,
                errorCode: nil, hasProfile: nil)
            if verdict == .sessionInvalid {
                Breadcrumbs.log("login.kugou.fail reason=status-rejected status=\(status)")
                NativeSessionStore.shared.clear(provider: .kugou, reason: "status-rejected")
                await MainActor.run {
                    self.qrStatusLabel.text = "后端未确认登录，请重试"
                    self.spinner.stopAnimating()
                    self.refreshAccountUI()
                }
                return .fatal
            }
            Breadcrumbs.log("login.kugou.status-check result=transient status=\(status)")
        } catch {
            Breadcrumbs.log("login.kugou.status-check result=transient")
        }
        await MainActor.run { self.handleLoginSuccess(gen: gen) }
        return .done
    }

    // MARK: - 二维码图（base64 优先，缺图用内容串本地生成）

    private func showQRImage(base64: String?, content: String?) {
        if let raw = base64, !raw.isEmpty {
            let body = raw.contains(",")
                ? String(raw.split(separator: ",", maxSplits: 1).last ?? "") : raw
            if let data = Data(base64Encoded: body), let image = UIImage(data: data) {
                qrImageView.image = Self.tileQRImage89(image)
                return
            }
        }
        if let content, let image = Self.makeQRImage(text: content) {
            qrImageView.image = Self.tileQRImage89(image)
        }
    }

    /// (89) §12-2：网页码瓷砖口径——白瓷砖 200×200 内码图
    /// 176×176 居中（四周 12 白边）。两条图源（服务端图／
    /// 本地生成）统一在此垫边，视图侧只管 200 见方。
    private static func tileQRImage89(_ image: UIImage) -> UIImage {
        let tile: CGFloat = 200, code: CGFloat = 176
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: tile, height: tile), format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: tile, height: tile))
            image.draw(in: CGRect(
                x: (tile - code) / 2, y: (tile - code) / 2,
                width: code, height: code))
        }
    }

    private static func makeQRImage(text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
