import UIKit

// 随机池可见可配（3.7 (69) P3，社区版借鉴 A2＋DS 对账 Q5 定案）：
// 样式轮换（洗牌袋 StageStyleCycleBag）的候选集过滤层。
//
// 语义（DS Q5 全条采纳）：
// - 池子只决定候选集，轮换语义仍是洗牌袋（一轮内不重复、过
//   完重洗、新轮首只≠上轮末只——袋在开新轮时剔除当前样式，
//   强于「首只不同」）；各样式用自己保存的参数（调参/运行位
//   各自持久化，本池不碰）。
// - 空池/全关＝未启用过滤→回退全集，不许空池死局；全选同理
//   视为未启用过滤。以上两种状态与单只退化态都在面板内明示。
// - 池变更只重建袋的余量（StageStyleCycleBag 订阅本通知清余
//   量），当前正在播的样式不跳变。
// - 计数实时派生（displaySelection 一处真源，面板/选择器入
//   口行/袋三处同读），不存第二份计数。
//
// 全集口径：候选全集＝洗牌袋的可选全集 selectableStyleIds
// （注册表全量减锁定样式）——(74) machi 恢复后代码实证为
// 21 只（网页 17 式＋原创三稿＋汪汪队开大会），不是社区版
// 的 17 只；池子必须覆盖袋的全部候选，否则三只自有样式
// 永远过滤不掉。

enum StageStylePoolStore {

    private static let key = "folia.stage.pool69.selectedIds"

    /// 池变更通知：袋清余量、选择器入口行刷新都订这一处。
    static let changedNotification = Notification.Name("FoliaStagePool69Changed")

    /// 候选全集（与洗牌袋同源同序）。
    static var universe: [String] { StageStyleCycleBag.selectableStyleIds }

    /// 面板显示选择（唯一真源）：未配置过＝全选；已存值按存
    /// 值（可为空集＝全关）。派生计数/勾选都读这一处。
    static var displaySelection: Set<String> {
        let universeSet = Set(universe)
        guard let raw = UserDefaults.standard.stringArray(forKey: key) else {
            return universeSet
        }
        return Set(raw).intersection(universeSet)
    }

    /// 过滤是否真正生效：显示选择是全集的真子集且非空。
    static var isFilterActive: Bool {
        let selection = displaySelection
        return !selection.isEmpty && selection.count < universe.count
    }

    /// 袋的实际候选集：过滤未启用（空/全选）时回退全集。
    static var effectiveCandidates: [String] {
        guard isFilterActive else { return universe }
        let selection = displaySelection
        return universe.filter { selection.contains($0) }
    }

    static func setSelection(_ selection: Set<String>) {
        let cleaned = selection.intersection(Set(universe))
        UserDefaults.standard.set(universe.filter { cleaned.contains($0) }, forKey: key)
        Breadcrumbs.log("pool.set n=\(cleaned.count)/\(universe.count) active=\(isFilterActive ? 1 : 0)")
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func toggle(_ styleId: String) {
        var selection = displaySelection
        if selection.contains(styleId) {
            selection.remove(styleId)
        } else {
            selection.insert(styleId)
        }
        setSelection(selection)
    }

    static func selectAll() { setSelection(Set(universe)) }
    static func clearAll() { setSelection([]) }

    /// 逐只图标（SF Symbol 名）：注册表条目无图标字段，本表
    /// 为池面板/后续池 UI 的唯一映射；取不到名时面板回退占位。
    static func iconName(for styleId: String) -> String {
        switch styleId {
        case "sonnet": return "music.note"
        case "tempera": return "paintpalette"
        case "lumiere": return "lightbulb"
        case "hanabi": return "sparkles"
        case "nebbia": return "cloud.fog"
        case "classic": return "waveform"
        case "cadenza": return "heart"
        case "partita": return "cloud"
        case "fume": return "wind"
        case "tilt": return "message"
        case "claddagh": return "repeat"
        case "monet": return "photo"
        case "pendolo": return "clock"
        case "cappella": return "person.3"
        case "diorama": return "square.on.square"
        case "still": return "pause.circle"
        case "tuning": return "dot.radiowaves.left.and.right"
        case "corridor": return "perspective"
        case "afterglow": return "sunset"
        case "petconcert": return "pawprint"
        case "christmas": return "tree"
        default: return "sparkle"
        }
    }
}

/// 随机池多选面板：逐只图标＋勾选，点行即切换并落存储；
/// 状态行实时明示未启用过滤/单只退化。由样式选择器以导航
/// 包裹＋「完成」呈现（与调参面板同形态）。
final class StageStylePoolViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let noteLabel = UILabel()
    private let stateLabel = UILabel()
    private let styles: [LyricStageStyleInfo] = StageStylePoolStore.universe
        .compactMap { LyricStageRegistry.info(for: $0) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        title = "随机池"
        Breadcrumbs.log("pool.open")

        noteLabel.text = "每首歌从选中的样式里换一种，各样式用自己保存的参数。"
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        noteLabel.numberOfLines = 0
        stateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        stateLabel.textColor = UIColor(red: 1.0, green: 0.78, blue: 0.42, alpha: 1)
        stateLabel.numberOfLines = 0

        let allButton = UIButton(type: .system)
        allButton.setTitle("全选", for: .normal)
        allButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        allButton.setTitleColor(.white, for: .normal)
        allButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        allButton.layer.cornerRadius = 10
        allButton.addTarget(self, action: #selector(selectAllTapped), for: .touchUpInside)
        let noneButton = UIButton(type: .system)
        noneButton.setTitle("全不选", for: .normal)
        noneButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        noneButton.setTitleColor(.white, for: .normal)
        noneButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        noneButton.layer.cornerRadius = 10
        noneButton.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)
        let buttonRow = UIStackView(arrangedSubviews: [allButton, noneButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually

        for sub in [noteLabel, stateLabel, buttonRow, tableView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "pool")
        NSLayoutConstraint.activate([
            noteLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            noteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            noteLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stateLabel.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
            stateLabel.leadingAnchor.constraint(equalTo: noteLabel.leadingAnchor),
            stateLabel.trailingAnchor.constraint(equalTo: noteLabel.trailingAnchor),
            buttonRow.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 10),
            buttonRow.leadingAnchor.constraint(equalTo: noteLabel.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: noteLabel.trailingAnchor),
            buttonRow.heightAnchor.constraint(equalToConstant: 34),
            tableView.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        refreshState()
    }

    /// 状态行（计数实时派生＋三种边界态明示，DS Q5）。
    private func refreshState() {
        let total = StageStylePoolStore.universe.count
        let n = StageStylePoolStore.displaySelection.count
        if n == 0 {
            stateLabel.text = "已选 0/\(total)：已全部关闭＝未启用过滤，轮换仍走全部 \(total) 只，不会无样式可换。"
        } else if n == total {
            stateLabel.text = "已选 \(n)/\(total)：全部都在池中（未启用过滤）。"
        } else if n == 1 {
            stateLabel.text = "已选 1/\(total)：只选了 1 只，轮换没有可换的样式，每首歌都会用它。"
        } else {
            stateLabel.text = "已选 \(n)/\(total)：每首歌从这 \(n) 只里换一种。"
        }
    }

    @objc private func selectAllTapped() {
        StageStylePoolStore.selectAll()
        tableView.reloadData()
        refreshState()
    }

    @objc private func clearAllTapped() {
        StageStylePoolStore.clearAll()
        tableView.reloadData()
        refreshState()
    }

    // MARK: UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        styles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "pool", for: indexPath)
        let style = styles[indexPath.row]
        var config = UIListContentConfiguration.valueCell()
        config.text = style.displayName
        config.secondaryText = style.id
        config.image = UIImage(systemName: StageStylePoolStore.iconName(for: style.id))
            ?? UIImage(systemName: "sparkle")
        config.imageProperties.tintColor = UIColor.white.withAlphaComponent(0.75)
        config.textProperties.color = .white
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        cell.accessoryType = StageStylePoolStore.displaySelection.contains(style.id)
            ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        StageStylePoolStore.toggle(styles[indexPath.row].id)
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshState()
    }
}
