import UIKit

// 原生样式选择器（M2'，DS R40 对账 Q1）：17 种样式全量列出
// （顺序/名称与网页侧注册表一致）；已原生化的可选、未原生化的
// 标「网页版」——点选即关原生舞台跳网页舞台。网页舞台打开时用
// 它自己保存的样式（原生无指定通道，见实施报告），页头说明里
// 如实写明。
final class StageStylePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    var onPickNative: ((String) -> Void)?
    var onPickWeb: ((LyricStageStyleInfo) -> Void)?

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
        note.text = "标「网页版」的样式会打开网页舞台，样式以网页版当前设置为准。"
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        styles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "style", for: indexPath)
        let style = styles[indexPath.row]
        var config = UIListContentConfiguration.valueCell()
        config.text = style.displayName
        config.secondaryText = style.id
        config.textProperties.color = .white
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.45)
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        cell.accessoryType = .none
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
        let wrapWidth = badgeWidth + (isActive ? 26 : 0)
        let wrap = UIView(frame: CGRect(x: 0, y: 0, width: wrapWidth, height: 24))
        badge.frame = CGRect(x: 0, y: 1, width: badgeWidth, height: 22)
        wrap.addSubview(badge)
        if isActive {
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = .white
            check.frame = CGRect(x: badgeWidth + 6, y: 3, width: 18, height: 18)
            wrap.addSubview(check)
        }
        cell.accessoryView = wrap
        return cell
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let style = styles[indexPath.row]
        if style.isNativeAvailable {
            onPickNative?(style.id)
        } else {
            onPickWeb?(style)
        }
    }
}
