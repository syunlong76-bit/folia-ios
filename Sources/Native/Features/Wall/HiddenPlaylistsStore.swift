import UIKit

/// 隐藏歌单存储（3.7 (55) 工作流 E，「…」菜单·管理隐藏）：
/// UserDefaults 存隐藏歌单 ID 集 + 名称快照（管理面离线可列，
/// 不依赖再拉一次歌单列表）。隐藏过滤点在 HomeWall 的数据
/// 装配处（applyWallData），墙面与网格两形态同源同过滤。
/// 变更经 .foliaHiddenPlaylistsChanged 通知，HomeWall 订阅后
/// 重装配数据（隐藏/取消隐藏即时生效）。
final class HiddenPlaylistsStore {

    static let shared = HiddenPlaylistsStore()

    private let idsKey = "folia.hiddenPlaylistIds"
    private let namesKey = "folia.hiddenPlaylistNames"

    private init() {}

    var hiddenIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: idsKey) ?? [])
    }

    func isHidden(_ id: String) -> Bool {
        hiddenIds.contains(id)
    }

    /// 管理面条目：(id, 名称快照)，按名称排序、稳定可读。
    var items: [(id: String, name: String)] {
        let names = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        return hiddenIds
            .map { (id: $0, name: names[$0] ?? "歌单 \($0)") }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func hide(id: String, name: String) {
        var ids = hiddenIds
        guard !ids.contains(id) else { return }
        ids.insert(id)
        var names = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        names[id] = name
        UserDefaults.standard.set(Array(ids), forKey: idsKey)
        UserDefaults.standard.set(names, forKey: namesKey)
        Breadcrumbs.log("wall.menu.hide id=\(id)")
        NotificationCenter.default.post(name: .foliaHiddenPlaylistsChanged, object: nil)
    }

    func unhide(id: String) {
        var ids = hiddenIds
        guard ids.contains(id) else { return }
        ids.remove(id)
        var names = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        names.removeValue(forKey: id)
        UserDefaults.standard.set(Array(ids), forKey: idsKey)
        UserDefaults.standard.set(names, forKey: namesKey)
        Breadcrumbs.log("wall.menu.unhide id=\(id)")
        NotificationCenter.default.post(name: .foliaHiddenPlaylistsChanged, object: nil)
    }
}

extension Notification.Name {
    /// 隐藏集变更（HiddenPlaylistsStore.hide/unhide 发出，
    /// HomeWall 订阅重装配墙面数据）。
    static let foliaHiddenPlaylistsChanged = Notification.Name("FoliaHiddenPlaylistsChanged")
}

/// 管理隐藏面（3.7 (55) 工作流 E）：列出已隐藏歌单，点按
/// 一行即取消隐藏（行尾有「取消隐藏」明示钮，同动作）；空态
/// 诚实说明隐藏入口（主页墙歌单卡长按菜单）。全屏呈现、
/// 左上关闭回墙。
final class HiddenPlaylistsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var items: [(id: String, name: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        overrideUserInterfaceStyle = .dark

        let titleLabel = UILabel()
        titleLabel.text = "管理隐藏"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
            for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "关闭"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(close)

        let hint = UILabel()
        hint.text = "点按一行即可取消隐藏，歌单会回到主页墙。"
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = UIColor.white.withAlphaComponent(0.55)
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "hiddenCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "没有隐藏的歌单。\n在主页墙长按歌单卡，选「隐藏歌单」即可隐藏。"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            hint.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            tableView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
        reload()
        Breadcrumbs.log("wall.menu.hiddenManage open n=\(items.count)")
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func reload() {
        items = HiddenPlaylistsStore.shared.items
        emptyLabel.isHidden = !items.isEmpty
        tableView.isHidden = items.isEmpty
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "hiddenCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.text = items[indexPath.row].name
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 14)
        let unhide = UIButton(type: .system)
        unhide.setTitle("取消隐藏", for: .normal)
        unhide.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        unhide.tintColor = UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
        unhide.tag = indexPath.row
        unhide.sizeToFit()
        unhide.addTarget(self, action: #selector(unhideButtonTapped(_:)), for: .touchUpInside)
        cell.accessoryView = unhide
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        unhide(at: indexPath.row)
    }

    @objc private func unhideButtonTapped(_ sender: UIButton) {
        unhide(at: sender.tag)
    }

    private func unhide(at row: Int) {
        guard row < items.count else { return }
        HiddenPlaylistsStore.shared.unhide(id: items[row].id)
        reload()
    }
}
