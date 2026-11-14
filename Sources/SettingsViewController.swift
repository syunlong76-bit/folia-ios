import UIKit

/// 原生设置页：壳/前端版本信息、自动更新开关、手动检查、应用新版本提示。
///
/// v2 视觉重做（2026-11-14 真机反馈）：原白底大字 + 系统绿开关 + 英文 Done 的
/// 原生表单风与 Folia 深色流光界面完全割裂。本版按 Folia 设计语言重做呈现：
/// - 半透明黑色遮罩 + 近黑浮层卡片从底部滑入，底下的播放器页面隐约透出；
/// - 信息项收进深灰圆角分组卡（灰色小标签 + 白色值），密度对齐 Folia 设置页；
/// - 开关/按钮用柔和紫强调色与胶囊形，去掉系统绿与系统默认排版；
/// - 打开/关闭为淡入 + 上滑的弹簧缓动，替代系统生硬 sheet 弹跳。
/// 功能与数据绑定与旧版一致：仍读 WebRootManager / LocalServer / UpdateManager。
final class SettingsViewController: UIViewController {

    /// 双壳统一设计规格（安卓 SettingsActivity 同值，改一处须同步另一处）
    private enum FoliaUI {
        static let card = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)      // #16161A
        static let group = UIColor.white.withAlphaComponent(0.06)                       // 分组卡底
        static let primary = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)    // #F5F5F7
        static let secondary = UIColor(red: 0.604, green: 0.604, blue: 0.639, alpha: 1)  // #9A9AA3
        static let accent = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 1)     // #8B7CF0
        static let danger = UIColor(red: 1.0, green: 0.42, blue: 0.376, alpha: 1)        // #FF6B60
        static let hairline = UIColor.white.withAlphaComponent(0.07)
        static let buttonFill = UIColor.white.withAlphaComponent(0.08)
    }

    private let shellVersionLabel = UILabel()
    private let activeVersionLabel = UILabel()
    private let pendingVersionLabel = UILabel()
    private let portLabel = UILabel()
    private let lastResultLabel = UILabel()
    private let autoSwitch = UISwitch()
    private let checkButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private let backdropView = UIView()
    private let cardView = UIView()
    private var didRunEntrance = false
    private var isDismissing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // 让 UIAlertController 等系统子界面跟随深色，避免弹出白框跳戏
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear

        buildLayout()
        refresh()

        // 入场初始态：遮罩透明、卡片下沉，viewDidAppear 里弹簧滑入
        backdropView.alpha = 0
        cardView.transform = CGAffineTransform(translationX: 0, y: 56)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didRunEntrance else { return }
        didRunEntrance = true
        UIView.animate(withDuration: 0.55, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4,
                       options: [.curveEaseOut]) {
            self.backdropView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    // MARK: - 布局

    private func buildLayout() {
        // 遮罩：半透明黑，点按关闭；底下页面透出
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(close)))
        view.addSubview(backdropView)

        // 浮层卡片：近黑、24 圆角、四周留 12 边距的底部浮卡
        cardView.backgroundColor = FoliaUI.card
        cardView.layer.cornerRadius = 24
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)
        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            cardView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            cardView.topAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])

        // 卡内整体走一个 ScrollView：卡片高度默认贴合内容（下方 height 约束），
        // 内容超高（小屏/横屏）时卡片封顶 88% 屏高、内部滚动。
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        cardView.addSubview(scroll)
        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = 12
        cardStack.isLayoutMarginsRelativeArrangement = true
        cardStack.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 20, right: 20)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(cardStack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: cardView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            cardStack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor)
        ])
        let hugHeight = cardView.heightAnchor.constraint(equalTo: cardStack.heightAnchor)
        hugHeight.priority = .defaultHigh
        let maxHeight = cardView.heightAnchor.constraint(
            lessThanOrEqualTo: view.heightAnchor, multiplier: 0.88)
        NSLayoutConstraint.activate([hugHeight, maxHeight])

        // 顶部小横条（sheet 抓手）
        let grabber = UIView()
        grabber.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        grabber.layer.cornerRadius = 2
        grabber.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 4)
        ])
        let grabberRow = UIView()
        grabberRow.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.centerXAnchor.constraint(equalTo: grabberRow.centerXAnchor),
            grabber.topAnchor.constraint(equalTo: grabberRow.topAnchor),
            grabber.bottomAnchor.constraint(equalTo: grabberRow.bottomAnchor)
        ])
        cardStack.addArrangedSubview(grabberRow)

        // 页眉：标题 + 「完成」文字按钮
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        let titleLabel = UILabel()
        titleLabel.text = "设置"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = FoliaUI.primary
        let doneButton = UIButton(type: .system)
        doneButton.setTitle("完成", for: .normal)
        doneButton.setTitleColor(FoliaUI.accent, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(doneButton)
        cardStack.addArrangedSubview(header)

        // 信息分组卡：5 项版本/状态信息，行间发丝线
        let infoGroup = makeGroupCard()
        let infoRows: [(String, UILabel)] = [
            ("壳版本", shellVersionLabel),
            ("当前前端版本", activeVersionLabel),
            ("待生效版本", pendingVersionLabel),
            ("本地服务端口", portLabel),
            ("上次检查结果", lastResultLabel)
        ]
        for (index, pair) in infoRows.enumerated() {
            if index > 0 { infoGroup.addArrangedSubview(makeHairline()) }
            infoGroup.addArrangedSubview(makeInfoRow(title: pair.0, valueLabel: pair.1))
        }
        cardStack.addArrangedSubview(infoGroup)

        // 自动更新分组卡：开关行 + 说明
        let autoGroup = makeGroupCard()
        let autoRow = UIStackView()
        autoRow.axis = .horizontal
        autoRow.alignment = .center
        autoRow.isLayoutMarginsRelativeArrangement = true
        autoRow.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let autoTitle = UILabel()
        autoTitle.text = "自动更新"
        autoTitle.font = .systemFont(ofSize: 15)
        autoTitle.textColor = FoliaUI.primary
        autoSwitch.onTintColor = FoliaUI.accent
        // 细长胶囊感：整体略缩小，去掉系统开关的粗笨比例（绑定与事件不变）
        autoSwitch.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        autoSwitch.addTarget(self, action: #selector(autoSwitchChanged), for: .valueChanged)
        autoRow.addArrangedSubview(autoTitle)
        autoRow.addArrangedSubview(UIView())
        autoRow.addArrangedSubview(autoSwitch)
        autoGroup.addArrangedSubview(autoRow)
        autoGroup.addArrangedSubview(makeHairline())
        let autoHint = UILabel()
        autoHint.text = "开启后，每次冷启动在后台检查一次前端更新；下载完成的新版本在下次启动时生效。"
        autoHint.font = .systemFont(ofSize: 12)
        autoHint.textColor = FoliaUI.secondary
        autoHint.numberOfLines = 0
        let hintWrap = UIView()
        hintWrap.addSubview(autoHint)
        autoHint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            autoHint.topAnchor.constraint(equalTo: hintWrap.topAnchor, constant: 10),
            autoHint.bottomAnchor.constraint(equalTo: hintWrap.bottomAnchor, constant: -12),
            autoHint.leadingAnchor.constraint(equalTo: hintWrap.leadingAnchor, constant: 14),
            autoHint.trailingAnchor.constraint(equalTo: hintWrap.trailingAnchor, constant: -14)
        ])
        autoGroup.addArrangedSubview(hintWrap)
        cardStack.addArrangedSubview(autoGroup)

        // 检查更新：整宽胶囊按钮，spinner 叠在按钮右侧
        let checkWrap = UIView()
        checkWrap.translatesAutoresizingMaskIntoConstraints = false
        checkButton.setTitle("检查更新", for: .normal)
        checkButton.setTitleColor(FoliaUI.primary, for: .normal)
        checkButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        checkButton.backgroundColor = FoliaUI.buttonFill
        checkButton.layer.cornerRadius = 12
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        checkButton.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        checkWrap.addSubview(checkButton)
        checkWrap.addSubview(spinner)
        NSLayoutConstraint.activate([
            checkWrap.heightAnchor.constraint(equalToConstant: 46),
            checkButton.topAnchor.constraint(equalTo: checkWrap.topAnchor),
            checkButton.bottomAnchor.constraint(equalTo: checkWrap.bottomAnchor),
            checkButton.leadingAnchor.constraint(equalTo: checkWrap.leadingAnchor),
            checkButton.trailingAnchor.constraint(equalTo: checkWrap.trailingAnchor),
            spinner.centerYAnchor.constraint(equalTo: checkWrap.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: checkWrap.trailingAnchor, constant: -16)
        ])
        cardStack.addArrangedSubview(checkWrap)

        // 应用新版本（仅 pending 存在时可见）：同款胶囊，危险色文字
        applyButton.setTitle("重启应用新版本", for: .normal)
        applyButton.setTitleColor(FoliaUI.danger, for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        applyButton.backgroundColor = FoliaUI.group
        applyButton.layer.cornerRadius = 12
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        applyButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        cardStack.addArrangedSubview(applyButton)
    }

    /// 分组卡容器：深灰底、16 圆角，内部纵向堆行
    private func makeGroupCard() -> UIStackView {
        let group = UIStackView()
        group.axis = .vertical
        group.spacing = 0
        group.backgroundColor = FoliaUI.group
        group.layer.cornerRadius = 16
        group.clipsToBounds = true
        return group
    }

    private func makeHairline() -> UIView {
        let line = UIView()
        line.backgroundColor = FoliaUI.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let wrap = UIView()
        wrap.addSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: wrap.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14)
        ])
        return wrap
    }

    private func makeInfoRow(title: String, valueLabel: UILabel) -> UIView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 2
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = FoliaUI.secondary
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = FoliaUI.primary
        valueLabel.numberOfLines = 0
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    // MARK: - 数据刷新（与旧版一致，未改数据源与口径）

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
        guard !isDismissing else { return }
        isDismissing = true
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: {
            self.backdropView.alpha = 0
            self.cardView.transform = CGAffineTransform(translationX: 0, y: 56)
            self.cardView.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false)
        })
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
