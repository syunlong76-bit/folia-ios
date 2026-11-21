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
    /// 运行位切换后且切换的是当前样式（3.7 (67) A3）：舞台据此
    /// 立即按新运行位重呈现；非当前样式只落存储、选择器自刷新。
    var onPickRuntime: ((String) -> Void)?
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
        note.text = "网页样式可逐式切换运行方式：「网页运行」＝在原生台面内嵌网页原版特效，点样式名即以当前运行方式打开；带「调参」的样式点右侧按钮打开其专属调参面板。"
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 随机池面板/调参面板关回后刷新入口行计数与徽标。
        tableView.reloadData()
    }

    // MARK: UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { 4 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 2 ? "背景" : nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return styles.count
        case 2: return 3
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "style", for: indexPath)
        if indexPath.section == 1 {
            // 随机池入口（3.7 (69) P3）：计数实时派生自
            // StageStylePoolStore，未启用过滤时如实标注。
            var config = UIListContentConfiguration.valueCell()
            config.text = "随机池"
            let total = StageStylePoolStore.universe.count
            let picked = StageStylePoolStore.displaySelection.count
            if StageStylePoolStore.isFilterActive {
                config.secondaryText = "已选 \(picked)/\(total) · 每首歌从选中的样式里换一种"
            } else if picked == 0 {
                config.secondaryText = "未启用过滤 · 全部 \(total) 只（已全部关闭）"
            } else {
                config.secondaryText = "未启用过滤 · 全部 \(total) 只"
            }
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
        if indexPath.section == 2 {
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
            } else if indexPath.row == 1 {
                // (62) 背景体系（StageBackdrop62）：9 档模式行，
                // 当前值回显；与自定义背景互斥——已设自定义背景
                // 时本行注明让位关系，点按进模式选择。
                config.text = "舞台背景体系"
                let modeNames: [String: String] = [
                    "none": "无（样式自带）", "common": "通用",
                    "latentCover": "隐现 · 封面", "latentLyric": "隐现 · 歌词",
                    "latentSpectrum": "隐现 · 频谱", "monet": "莫奈",
                    "nomand": "漫游", "sora": "星空", "url": "远程图",
                ]
                let modeName = modeNames[SettingsStore.backdropMode62] ?? "无"
                config.secondaryText = current != nil
                    ? "当前：\(modeName)（自定义背景生效中，体系让位）"
                    : "当前：\(modeName) · 点按切换"
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
        if indexPath.section == 3 {
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
        // (60) 第 4 条：锁定样式（machi）整行置灰——文字降至系统
        // tertiary 量级（深色外观下仍可读）、徽标换「锁」、调参钮
        // 禁用、点选在 didSelect 直接返回不发任何回调。
        let locked = style.isLocked
        var config = UIListContentConfiguration.valueCell()
        config.text = style.displayName
        config.secondaryText = style.id
        config.textProperties.color = locked
            ? UIColor.white.withAlphaComponent(0.35) : .white
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        cell.accessoryType = .none
        cell.selectionStyle = locked ? .none : .default
        cell.isUserInteractionEnabled = true
        let isActive = style.id == activeStyleId && !locked
        // 运行位徽标（3.7 (67) A3）：网页 17 式按当前运行位标
        // 「原生」/「网页运行」；自有样式恒「原生」。
        let isWebRuntime = StageRuntimeStore.isWeb(style.id)
        let badge = UILabel()
        badge.text = locked ? " 锁 " : (isWebRuntime ? " 网页运行 " : (style.isNativeAvailable ? " 原生 " : " 网页版 "))
        badge.font = .systemFont(ofSize: 11, weight: .medium)
        badge.textColor = locked
            ? UIColor.white.withAlphaComponent(0.45)
            : (isWebRuntime
                ? UIColor(red: 1.0, green: 0.78, blue: 0.42, alpha: 1)
                : (style.isNativeAvailable
                    ? UIColor(red: 0.55, green: 0.9, blue: 0.65, alpha: 1)
                    : UIColor.white.withAlphaComponent(0.55)))
        badge.layer.borderWidth = 1
        badge.layer.borderColor = badge.textColor.cgColor
        badge.layer.cornerRadius = 7
        badge.clipsToBounds = true
        badge.sizeToFit()
        let badgeWidth = badge.bounds.width
        // 逐样式调参入口（3.7 (57)）：有调参面板的样式在徽章
        // 左侧加一颗「调参」钮，点按呈现该样式的专属面板
        // （面板本体由各样式 Tuning 文件提供，本选择器只呈现）。
        // (60) 第 4 条：锁定样式的调参入口一并禁用（置灰不可点）。
        let hasTuning = style.tuningPanelFactory != nil
        let tuningWidth: CGFloat = hasTuning ? 46 : 0
        // 运行位切换钮（3.7 (67) A3）：仅网页 17 式且未锁定才有；
        // 钮面写目标运行方式（当前原生→「网页」，当前网页→「原生」）。
        let hasRuntimeToggle = style.hasWebRuntime && !locked
        let runtimeWidth: CGFloat = hasRuntimeToggle ? 40 : 0
        let wrapWidth = runtimeWidth + tuningWidth + badgeWidth + (isActive ? 26 : 0)
        let wrap = UIView(frame: CGRect(x: 0, y: 0, width: wrapWidth, height: 24))
        if hasRuntimeToggle {
            let runtimeButton = UIButton(type: .system)
            runtimeButton.setTitle(isWebRuntime ? "原生" : "网页", for: .normal)
            runtimeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            runtimeButton.setTitleColor(UIColor(red: 1.0, green: 0.78, blue: 0.42, alpha: 1), for: .normal)
            runtimeButton.tag = indexPath.row
            runtimeButton.addTarget(self, action: #selector(handleRuntimeTap(_:)), for: .touchUpInside)
            runtimeButton.frame = CGRect(x: 0, y: 0, width: 40, height: 24)
            wrap.addSubview(runtimeButton)
        }
        if hasTuning {
            let tuningButton = UIButton(type: .system)
            tuningButton.setTitle("调参", for: .normal)
            tuningButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            tuningButton.setTitleColor(UIColor(red: 0.55, green: 0.9, blue: 0.65, alpha: 1), for: .normal)
            tuningButton.setTitleColor(UIColor.white.withAlphaComponent(0.3), for: .disabled)
            tuningButton.isEnabled = !locked
            tuningButton.tag = indexPath.row
            tuningButton.addTarget(self, action: #selector(handleTuningTap(_:)), for: .touchUpInside)
            tuningButton.frame = CGRect(x: runtimeWidth, y: 0, width: 40, height: 24)
            wrap.addSubview(tuningButton)
        }
        badge.frame = CGRect(x: runtimeWidth + tuningWidth, y: 1, width: badgeWidth, height: 22)
        wrap.addSubview(badge)
        if isActive {
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = .white
            check.frame = CGRect(x: runtimeWidth + tuningWidth + badgeWidth + 6, y: 3, width: 18, height: 18)
            wrap.addSubview(check)
        }
        cell.accessoryView = wrap
        return cell
    }

    /// 运行位切换（3.7 (67) A3）：落 StageRuntimeStore 持久化；
    /// 切的是当前样式时经 onPickRuntime 让舞台立即重呈现，其余
    /// 只刷新本行徽标。
    @objc private func handleRuntimeTap(_ sender: UIButton) {
        let style = styles[sender.tag]
        guard style.hasWebRuntime, !style.isLocked else { return }
        let next: StageRuntime = StageRuntimeStore.isWeb(style.id) ? .native : .web
        StageRuntimeStore.setRuntime(next, for: style.id)
        if style.id == activeStyleId {
            onPickRuntime?(style.id)
        } else {
            tableView.reloadData()
        }
    }

    /// 调参面板呈现（3.7 (57)）：面板自身无关闭钮，统一以
    /// 导航控制器包裹并给出「完成」——点按即写存储，关掉即
    /// 回选择器，舞台重挂样式时新参数生效。
    @objc private func handleTuningTap(_ sender: UIButton) {
        let style = styles[sender.tag]
        // (60) 第 4 条：锁定样式调参入口禁用（钮已 isEnabled=false，
        // 此处再兜底一道，防程序化触发）。
        guard !style.isLocked, let makePanel = style.tuningPanelFactory else { return }
        let panel = makePanel()
        panel.title = style.displayName + "调参"
        let nav = UINavigationController(rootViewController: panel)
        panel.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self,
            action: #selector(handleTuningDone))
        present(nav, animated: true)
    }

    /// 背景体系模式选择（(62)）：9 档 actionSheet，写
    /// SettingsStore.backdropMode62 并通知 StageBackdrop62。
    private func presentBackdropModePicker62() {
        let modes: [(String, String)] = [
            ("none", "无（样式自带背景）"), ("common", "通用 · 光晕几何"),
            ("latentCover", "隐现 · 封面"), ("latentLyric", "隐现 · 歌词"),
            ("latentSpectrum", "隐现 · 频谱"), ("monet", "莫奈 · 色彩 Wash"),
            ("nomand", "漫游 · 纸感"), ("sora", "星空"),
            ("url", "远程图（设置页填地址）"),
        ]
        let sheet = UIAlertController(
            title: "舞台背景体系",
            message: "与自定义背景互斥：已设自定义背景时体系自动让位，清除自定义背景后恢复。",
            preferredStyle: .actionSheet)
        for (value, name) in modes {
            let isCurrent = SettingsStore.backdropMode62 == value
            sheet.addAction(UIAlertAction(
                title: isCurrent ? "\(name) ✓" : name, style: .default) { _ in
                SettingsStore.backdropMode62 = value
                StageBackdrop62.modeDidChange()
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func handleTuningDone() {
        dismiss(animated: true)
    }

    // MARK: UITableViewDelegate

    /// 随机池面板呈现（3.7 (69) P3）：与调参面板同形态——
    /// 导航包裹＋「完成」，关回选择器时 viewWillAppear 刷新
    /// 入口行计数。
    private func presentPoolPanel() {
        let panel = StageStylePoolViewController()
        let nav = UINavigationController(rootViewController: panel)
        panel.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self,
            action: #selector(handleTuningDone))
        present(nav, animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            presentPoolPanel()
            return
        }
        if indexPath.section == 2 {
            if indexPath.row == 0 { onPickCustomBackground?() }
            else if indexPath.row == 1 { presentBackdropModePicker62() }
            else { onClearCustomBackground?() }
            return
        }
        if indexPath.section == 3 {
            onOpenWebStage?()
            return
        }
        let style = styles[indexPath.row]
        // (60) 第 4 条：锁定样式点选直接返回，不发 onPickNative/
        // onPickWeb 任何回调（选不到、用不了；代码与资源保留）。
        if style.isLocked {
            Breadcrumbs.log("style.lock picker tap ignored style=\(style.id)")
            return
        }
        if style.isNativeAvailable {
            onPickNative?(style.id)
        } else {
            onPickWeb?(style)
        }
    }
}
