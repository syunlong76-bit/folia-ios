import UIKit

// 原生样式选择器（M2'，DS R40 对账 Q1）：17 种样式全量列出
// （顺序/名称与网页侧注册表一致）；已原生化的可选、未原生化的
// 标「网页版」——点选即关原生舞台跳网页舞台。网页舞台打开时用
// 它自己保存的样式（原生无指定通道，见实施报告），页头说明里
// 如实写明。列表末尾另设常设「网页版播放页」入口（3.7 (26)
// 补 R40 对账的设置保留网页舞台入口一项）：不改当前样式
// 记录，随时可直达网页舞台。
// 自定义背景段（3.7 (47)）：样式段之后加一段——「自定义
// 背景」（从相册选图片/动图/视频，副文案回显当前槽位状态）
// 与「恢复样式背景」（未设置时置灰禁用）。选入与清除的实际
// 动作经回调由舞台 VC 执行（相册选择器从舞台呈现）。
final class StageStylePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    var onPickNative: ((String) -> Void)?
    var onPickWeb: ((LyricStageStyleInfo) -> Void)?
    var onOpenWebStage: (() -> Void)?
    var onPickCustomBackground: (() -> Void)?
    var onClearCustomBackground: (() -> Void)?

    private let activeStyleId: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let styles = LyricStageRegistry.allStyles.sorted { $0.order < $1.order }

    init(activeStyleId: String) {
        self.activeStyleId = activeStyleId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        let header = UILabel()
        header.text = "歌词样式"
        header.font = .systemFont(ofSize: 17, weight: .semibold)
        header.textColor = .white
        let note = UILabel()
        note.text = "网页样式已全部原生化；带「调参」的样式点右侧按钮打开其专属调参面板。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = UIColor.white.withAlphaComponent(0.55)
        note.numberOfLines = 0
        header.translatesAutoresizingMaskIntoConstraints = false
        note.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(note)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "style")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            note.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            note.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            note.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "背景" : nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return styles.count
        case 1: return 2
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "style", for: indexPath)
        if indexPath.section == 1 {
            var config = UIListContentConfiguration.valueCell()
            let current = CustomBackgroundStore.current
            if indexPath.row == 0 {
                config.text = "自定义背景"
                switch current?.kind {
                case .image: config.secondaryText = "当前：图片 · 点按更换"
                case .animated: config.secondaryText = "当前：动图 · 点按更换"
                case .video: config.secondaryText = "当前：视频（静音循环）· 点按更换"
                case nil: config.secondaryText = "从相册选择图片 / 动图 / 视频"
                }
                config.textProperties.color = .white
                config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
                cell.contentConfiguration = config
                cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
                cell.accessoryType = .disclosureIndicator
                cell.accessoryView = nil
                cell.selectionStyle = .default
                cell.isUserInteractionEnabled = true
            } else {
                config.text = "恢复样式背景"
                config.secondaryText = current == nil
                    ? "尚未设置自定义背景" : "切回当前样式自带背景"
                let enabled = current != nil
                config.textProperties.color = enabled
                    ? .white : UIColor.white.withAlphaComponent(0.35)
                config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
                cell.contentConfiguration = config
                cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
                cell.accessoryType = .none
                cell.accessoryView = nil
                cell.selectionStyle = enabled ? .default : .none
                cell.isUserInteractionEnabled = enabled
            }
            return cell
        }
        if indexPath.section == 2 {
            var config = UIListContentConfiguration.valueCell()
            config.text = "网页版播放页"
            config.secondaryText = "打开网页舞台（样式以网页版当前设置为准）"
            config.textProperties.color = .white
            config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
            cell.contentConfiguration = config
            cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
            cell.selectionStyle = .default
            cell.isUserInteractionEnabled = true
            return cell
        }
        let style = styles[indexPath.row]
        var config = UIListContentConfiguration.valueCell()
        config.text = style.displayName
        config.secondaryText = style.id
        config.textProperties.color = .white
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = true
        let isActive = style.id == activeStyleId
        let badge = UILabel()
        badge.text = style.isNativeAvailable ? " 原生 " : " 网页版 "
        badge.font = .systemFont(ofSize: 11, weight: .medium)
        badge.textColor = style.isNativeAvailable
            ? UIColor(red: 0.55, green: 0.9, blue: 0.65, alpha: 1)
            : UIColor.white.withAlphaComponent(0.55)
        badge.layer.borderWidth = 1
        badge.layer.borderColor = badge.textColor.cgColor
        badge.layer.cornerRadius = 7
        badge.clipsToBounds = true
        badge.sizeToFit()
        let badgeWidth = badge.bounds.width
        // 逐样式调参入口（3.7 (57)）：有调参面板的样式在徽章
        // 左侧加一颗「调参」钮，点按呈现该样式的专属面板
        // （面板本体由各样式 Tuning 文件提供，本选择器只呈现）。
        let hasTuning = style.tuningPanelFactory != nil
        let tuningWidth: CGFloat = hasTuning ? 46 : 0
        let wrapWidth = tuningWidth + badgeWidth + (isActive ? 26 : 0)
        let wrap = UIView(frame: CGRect(x: 0, y: 0, width: wrapWidth, height: 24))
        if hasTuning {
            let tuningButton = UIButton(type: .system)
            tuningButton.setTitle("调参", for: .normal)
            tuningButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            tuningButton.setTitleColor(UIColor(red: 0.55, green: 0.9, blue: 0.65, alpha: 1), for: .normal)
            tuningButton.tag = indexPath.row
            tuningButton.addTarget(self, action: #selector(handleTuningTap(_:)), for: .touchUpInside)
            tuningButton.frame = CGRect(x: 0, y: 0, width: 40, height: 24)
            wrap.addSubview(tuningButton)
        }
        badge.frame = CGRect(x: tuningWidth, y: 1, width: badgeWidth, height: 22)
        wrap.addSubview(badge)
        if isActive {
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = .white
            check.frame = CGRect(x: tuningWidth + badgeWidth + 6, y: 3, width: 18, height: 18)
            wrap.addSubview(check)
        }
        cell.accessoryView = wrap
        return cell
    }

    /// 调参面板呈现（3.7 (57)）：面板自身无关闭钮，统一以
    /// 导航控制器包裹并给出「完成」——点按即写存储，关掉即
    /// 回选择器，舞台重挂样式时新参数生效。
    @objc private func handleTuningTap(_ sender: UIButton) {
        let style = styles[sender.tag]
        guard let makePanel = style.tuningPanelFactory else { return }
        let panel = makePanel()
        panel.title = style.displayName + "调参"
        let nav = UINavigationController(rootViewController: panel)
        panel.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self,
            action: #selector(handleTuningDone))
        present(nav, animated: true)
    }

    @objc private func handleTuningDone() {
        dismiss(animated: true)
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            if indexPath.row == 0 { onPickCustomBackground?() }
            else { onClearCustomBackground?() }
            return
        }
        if indexPath.section == 2 {
            onOpenWebStage?()
            return
        }
        let style = styles[indexPath.row]
        if style.isNativeAvailable {
            onPickNative?(style.id)
        } else {
            onPickWeb?(style)
        }
    }
}
