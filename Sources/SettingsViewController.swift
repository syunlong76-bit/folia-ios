import UIKit

/// 原生设置页（UIKit）：壳/前端版本信息、自动更新开关、手动检查、应用新版本提示。
final class SettingsViewController: UIViewController {

    private let shellVersionLabel = UILabel()
    private let activeVersionLabel = UILabel()
    private let pendingVersionLabel = UILabel()
    private let portLabel = UILabel()
    private let lastResultLabel = UILabel()
    private let autoSwitch = UISwitch()
    private let checkButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close))

        buildLayout()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    // MARK: - 布局

    private func buildLayout() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)
        ])

        stack.addArrangedSubview(makeRow(title: "壳版本", valueLabel: shellVersionLabel))
        stack.addArrangedSubview(makeRow(title: "当前前端版本", valueLabel: activeVersionLabel))
        stack.addArrangedSubview(makeRow(title: "待生效版本", valueLabel: pendingVersionLabel))
        stack.addArrangedSubview(makeRow(title: "本地服务端口", valueLabel: portLabel))
        stack.addArrangedSubview(makeRow(title: "上次检查结果", valueLabel: lastResultLabel))

        // 自动更新开关行
        let autoRow = UIStackView()
        autoRow.axis = .horizontal
        autoRow.alignment = .center
        let autoTitle = UILabel()
        autoTitle.text = "自动更新"
        autoTitle.font = .systemFont(ofSize: 16)
        autoSwitch.addTarget(self, action: #selector(autoSwitchChanged), for: .valueChanged)
        autoRow.addArrangedSubview(autoTitle)
        autoRow.addArrangedSubview(UIView())
        autoRow.addArrangedSubview(autoSwitch)
        stack.addArrangedSubview(autoRow)

        let autoHint = UILabel()
        autoHint.text = "开启后，每次冷启动在后台检查一次前端更新；下载完成的新版本在下次启动时生效。"
        autoHint.font = .systemFont(ofSize: 12)
        autoHint.textColor = .secondaryLabel
        autoHint.numberOfLines = 0
        stack.addArrangedSubview(autoHint)

        // 检查更新按钮 + 转圈
        let checkRow = UIStackView()
        checkRow.axis = .horizontal
        checkRow.spacing = 10
        checkRow.alignment = .center
        checkButton.setTitle("检查更新", for: .normal)
        checkButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        checkButton.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)
        checkRow.addArrangedSubview(checkButton)
        checkRow.addArrangedSubview(spinner)
        checkRow.addArrangedSubview(UIView())
        stack.addArrangedSubview(checkRow)

        // 应用新版本按钮（仅 pending 存在时可见）
        applyButton.setTitle("重启应用新版本", for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        applyButton.setTitleColor(.systemRed, for: .normal)
        applyButton.contentHorizontalAlignment = .leading
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        stack.addArrangedSubview(applyButton)
    }

    private func makeRow(title: String, valueLabel: UILabel) -> UIView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 2
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabel
        valueLabel.font = .systemFont(ofSize: 16)
        valueLabel.numberOfLines = 0
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    // MARK: - 数据刷新

    private func refresh() {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        shellVersionLabel.text = "\(short) (\(build))"
        activeVersionLabel.text = "v\(WebRootManager.shared.activeWebVersion)"
        let pending = WebRootManager.shared.pendingWebVersion
        pendingVersionLabel.text = pending > 0 ? "v\(pending)（重启应用后生效）" : "无"
        portLabel.text = LocalServer.shared.isRunning ? "127.0.0.1:\(LocalServer.shared.port)" : "未启动"
        lastResultLabel.text = UpdateManager.shared.lastCheckResult
        autoSwitch.isOn = UpdateManager.shared.autoUpdateEnabled
        applyButton.isHidden = pending <= 0
    }

    // MARK: - 动作

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func autoSwitchChanged() {
        UpdateManager.shared.autoUpdateEnabled = autoSwitch.isOn
    }

    @objc private func checkTapped() {
        checkButton.isEnabled = false
        spinner.startAnimating()
        UpdateManager.shared.checkNow { [weak self] _ in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.checkButton.isEnabled = true
            self.refresh()
        }
    }

    @objc private func applyTapped() {
        // 不强杀进程：按 iOS 规范引导用户手动关闭重开，冷启动时 WebRootManager 自动切换版本
        let alert = UIAlertController(
            title: "新版本已就绪",
            message: "请将 Folia 从多任务界面上滑关闭，再重新打开，新版本即会生效。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}
