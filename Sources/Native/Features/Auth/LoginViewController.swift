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
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let accountStatusLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let qrImageView = UIImageView()
    private let qrStatusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var qrViews: [UIView] = []
    private var backgroundObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)
        buildLayout()
        Breadcrumbs.log("login.qr.begin")
        refreshAccountUI()
        // (51) 旧口径保留：打开页面时网易云未登录直接出码。
        if ProviderSessionStatusQuery.status(for: .netease).isLoggedIn == false {
            startFlow()
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
        providerSegment.selectedSegmentIndex = 0
        providerSegment.addTarget(self, action: #selector(providerChanged), for: .valueChanged)

        channelSegment.isHidden = true
        channelSegment.addTarget(self, action: #selector(channelChanged), for: .valueChanged)
        rebuildChannelSegment()

        avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        avatarView.layer.cornerRadius = 28
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
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

        let stack = UIStackView(arrangedSubviews: [
            providerSegment, channelSegment, avatarView, nameLabel,
            accountStatusLabel, actionButton, qrImageView, qrStatusLabel,
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
            qrImageView.widthAnchor.constraint(equalToConstant: 220),
            qrImageView.heightAnchor.constraint(equalToConstant: 220),
            actionButton.widthAnchor.constraint(equalToConstant: 200),
            closeButton.widthAnchor.constraint(equalToConstant: 160)
        ])
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
        channelSegment.isHidden = selectedProvider != .qq || qqChannels.count <= 1
    }

    // MARK: - 分段与账号区

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
        nameLabel.text = Self.displayName(for: provider)
        if status.isLoggedIn {
            accountStatusLabel.text = status.displayName.map { "已登录 · \($0)" } ?? "已登录"
            actionButton.setTitle("退出登录", for: .normal)
        } else {
            accountStatusLabel.text = "未登录"
            actionButton.setTitle("扫码登录", for: .normal)
        }
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
        if status.isLoggedIn && status.displayName == nil {
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
                    displayName: status.nickname, avatarURLString: nil)
            case .qq:
                guard let cookie = NativeSessionStore.shared.qqCookieString(),
                      let profile = try? await self.qqClient.fetchLoginStatus(cookie: cookie),
                      let profile else { return }
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
        } else {
            startFlow()
        }
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
                qrImageView.image = image
                return
            }
        }
        if let content, let image = Self.makeQRImage(text: content) {
            qrImageView.image = image
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
