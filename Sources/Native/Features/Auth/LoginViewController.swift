import UIKit

/// (51) A 组：网易云原生扫码登录页。
///
/// 流程：key → create（qrimg base64 图，缺图时用 qrurl 自生成
/// 二维码）→ 每 2 秒轮询 check，总时长上限 5 分钟，页面消失
/// 停轮询。803 成功：cookie 过 MUSIC_U 校验后存
/// NativeSessionStore 并标迁移 done（NativeDataClient
/// .adoptNativeSession）；800 过期自动刷新二维码。
/// 面包屑：login.qr.begin/success/expired/cancel（只记
/// len/hash8，绝不记 cookie 原文）。
final class LoginViewController: UIViewController {

    /// 登录成功回调（存会话完成后、页面关闭前在主线程调用）。
    var onLoginSuccess: (() -> Void)?

    private let client = NeteaseQRLoginClient()
    private var pollTask: Task<Void, Never>?
    private var finished = false

    private let qrImageView = UIImageView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)
        buildLayout()
        Breadcrumbs.log("login.qr.begin")
        startLoginFlow()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 页面消失停轮询；非成功关闭记 cancel。
        pollTask?.cancel()
        pollTask = nil
        if !finished {
            finished = true
            Breadcrumbs.log("login.qr.cancel")
        }
    }

    // MARK: - 布局

    private func buildLayout() {
        let title = UILabel()
        title.text = "网易云扫码登录"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white
        title.textAlignment = .center

        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 12
        qrImageView.clipsToBounds = true
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "正在生成二维码…"
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        spinner.color = .white
        spinner.hidesWhenStopped = true

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        closeButton.layer.cornerRadius = 12
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let stack = UIStackView(arrangedSubviews: [title, qrImageView, statusLabel, spinner, closeButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            qrImageView.widthAnchor.constraint(equalToConstant: 220),
            qrImageView.heightAnchor.constraint(equalToConstant: 220),
            closeButton.widthAnchor.constraint(equalToConstant: 160)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - 登录流程

    private func startLoginFlow() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(5 * 60)
            while !Task.isCancelled, Date() < deadline {
                // 一轮：取 key → 建码 → 轮询到过期/成功。
                let proceed = await self.runOneQRCode(deadline: deadline)
                if proceed == .done || Task.isCancelled { return }
                if proceed == .fatal { return }
                // .refresh：800 过期后换新码继续（总时长仍受 deadline 限）。
            }
            await MainActor.run {
                self.statusLabel.text = "二维码已过期，请关闭后重试"
                self.spinner.stopAnimating()
            }
        }
    }

    private enum FlowOutcome { case done, refresh, fatal }

    private func runOneQRCode(deadline: Date) async -> FlowOutcome {
        let qr: NeteaseQRLoginClient.QRCode
        do {
            let key = try await client.fetchKey()
            qr = try await client.createQR(key: key)
        } catch {
            await MainActor.run {
                self.statusLabel.text = "二维码生成失败，请检查网络后重试"
                self.spinner.stopAnimating()
            }
            return .fatal
        }
        if Task.isCancelled { return .done }
        await MainActor.run {
            self.showQRImage(qr)
            self.statusLabel.text = "请用网易云音乐 App 扫码"
            self.spinner.stopAnimating()
        }
        while !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return .done }
            let result: NeteaseQRLoginClient.CheckResult
            do {
                result = try await client.check(key: qr.key)
            } catch {
                continue // 单次轮询失败不终止，下一轮重试。
            }
            switch result {
            case .waiting:
                break
            case .scanned:
                await MainActor.run { self.statusLabel.text = "已扫码，请在手机上确认登录" }
            case .expired:
                Breadcrumbs.log("login.qr.expired")
                await MainActor.run { self.statusLabel.text = "二维码已过期，正在刷新…" }
                return .refresh
            case .authorized(let cookie):
                return await handleAuthorized(cookie)
            case .unknown:
                break
            }
        }
        return .done
    }

    private func handleAuthorized(_ cookie: String) async -> FlowOutcome {
        let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NativeSessionStore.isValidNeteaseCookie(value) else {
            Breadcrumbs.log("login.qr.fail reason=invalid-cookie len=\(value.count)")
            await MainActor.run {
                self.statusLabel.text = "登录回包异常（会话校验未过），请重试"
            }
            return .fatal
        }
        Breadcrumbs.log("login.qr.success len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
        await MainActor.run {
            self.finished = true
            NativeDataClient.shared.adoptNativeSession(value)
            self.onLoginSuccess?()
            self.dismiss(animated: true)
        }
        return .done
    }

    // MARK: - 二维码图

    private func showQRImage(_ qr: NeteaseQRLoginClient.QRCode) {
        // 优先用函数侧 qrimg（base64 data URL 或纯 base64）。
        if let raw = qr.qrimgBase64 {
            let base64 = raw.contains(",") ? String(raw.split(separator: ",", maxSplits: 1).last ?? "") : raw
            if let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                qrImageView.image = image
                return
            }
        }
        // 回退：用 qrurl 内容本地生成二维码。
        if let urlText = qr.qrurl, let image = Self.makeQRImage(text: urlText) {
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
