import UIKit

/// (62) WB §4.7：思索（Ponder）教程提示系统。
///
/// - 教程提示：功能面首访时一次性气泡（队列面板 / 速记簿 /
///   命令面板 / 舞台样式等已落地面），已读态落盘
///   （SettingsStore.ponderSeenIDs），读过不再弹；总开关
///   ponderTipsEnabled 关时全停。
/// - 触屏思索按钮：墙面悬浮「?」钮（WB62HomeWallHooks 安
///   装），点开 PonderListViewController62 教程列表面，可重
///   读全部提示、也可一键重置已读态。
enum Ponder62 {

    struct Tip {
        let id: String
        let title: String
        let body: String
    }

    /// 真内容：只覆盖已落地的功能面，不给未迁面写假教程。
    static let tips: [Tip] = [
        Tip(id: "queue", title: "队列面板",
            body: "点播台上排「面板」键打开播放面板，队列页签里可拖动排序、左滑移除、批量多选，还能把当前队列存成本机歌单。"),
        Tip(id: "sketchbook", title: "速记簿",
            body: "屏幕左缘的小把手是速记簿：搜索结果行尾第一个钮把歌暂存进来，抽屉里可分组、看历史、把草稿队列一键替换当前队列。"),
        Tip(id: "command", title: "命令面板",
            body: "点播台上排「命令」键打开命令面板：播放控制、队列操作、当前歌曲与工具命令集中在一处，顶部可搜索。"),
        Tip(id: "stage-style", title: "歌词样式",
            body: "舞台上三击屏幕可洗牌切换下一个歌词特效；样式选择器里每个样式都有自己的调参面板，逐条按你的验收为准。"),
        Tip(id: "minibar", title: "播放台",
            body: "播放台 5 秒无操作会收成进度细条，宠物会跟着掉到细条上玩；点细条恢复完整形态，任何操作都会重新计时。"),
        Tip(id: "seam", title: "缝合工具条",
            body: "墙顶工具条可切换歌 / 推 / 探三段、切换网格与墙面布局；「…」菜单里有喜欢的音乐、云盘、过滤与隐藏管理。")
    ]

    static func tip(for id: String) -> Tip? { tips.first { $0.id == id } }

    static var seenIDs: Set<String> { Set(SettingsStore.ponderSeenIDs) }

    static func markSeen(_ id: String) {
        var seen = seenIDs
        guard !seen.contains(id) else { return }
        seen.insert(id)
        SettingsStore.ponderSeenIDs = Array(seen)
    }

    static func resetSeen() {
        SettingsStore.ponderSeenIDs = []
        Breadcrumbs.log("ponder62.resetSeen")
    }

    /// 首访提示：未读过且总开关开时，在宿主顶部弹一条一次
    /// 性气泡（系统弹簧入场、4.5 秒后自动收起，点按立即收起
    /// 并标已读）。功能面在自己首次呈现时调本函数（队列面 /
    /// 速记簿 / 命令面板的宿主可一行接入；设置页「思索教程
    /// 提示」行即本系统的开关面）。
    static func showTipIfNeeded(id: String, in host: UIViewController) {
        guard SettingsStore.ponderTipsEnabled,
              !seenIDs.contains(id),
              let tip = tip(for: id),
              let hostView = host.view, hostView.window != nil else { return }
        markSeen(id)
        let bubble = UIView()
        bubble.backgroundColor = UIColor(red: 0.13, green: 0.12, blue: 0.2, alpha: 0.97)
        bubble.layer.cornerRadius = 14
        bubble.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "\(tip.title)：\(tip.body)"
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)
        hostView.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bubble.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bubble.topAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.topAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12)
        ])
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(translationX: 0, y: -10)
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0.3,
                       options: [.curveEaseOut]) {
            bubble.alpha = 1
            bubble.transform = .identity
        }
        let dismiss = { [weak bubble] in
            UIView.animate(withDuration: 0.3, animations: { bubble?.alpha = 0 }) { _ in
                bubble?.removeFromSuperview()
            }
        }
        PonderTapTarget.shared.handler = dismiss
        bubble.addGestureRecognizer(UITapGestureRecognizer(
            target: PonderTapTarget.shared, action: #selector(PonderTapTarget.tapped)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { dismiss() }
        Breadcrumbs.log("ponder62.tip shown id=\(id)")
    }

    /// 打开教程列表面（触屏思索按钮与设置行共用入口）。
    static func presentList(from host: UIViewController) {
        let list = PonderListViewController62()
        list.modalPresentationStyle = .pageSheet
        host.present(list, animated: true)
        Breadcrumbs.log("ponder62.list presented")
    }
}

/// 气泡点按目标（单例小靶，气泡同一时刻至多一条）。
final class PonderTapTarget: NSObject {
    static let shared = PonderTapTarget()
    var handler: (() -> Void)?
    @objc func tapped() { handler?(); handler = nil }
}

/// 思索教程列表面：全部提示真内容 + 已读态 + 重置钮。
final class PonderListViewController62: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
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
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)
        ])
        let title = UILabel()
        title.text = FoliaLanguage62.text("ponderTitle")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white
        stack.addArrangedSubview(title)
        let seen = Ponder62.seenIDs
        for tip in Ponder62.tips {
            let label = UILabel()
            label.text = "· \(tip.title)\(seen.contains(tip.id) ? "（已读）" : "（未读）")\n\(tip.body)"
            label.font = .systemFont(ofSize: 13)
            label.textColor = UIColor.white.withAlphaComponent(0.75)
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        let reset = UIButton(type: .system)
        reset.setTitle("重置已读（重新显示全部提示）", for: .normal)
        reset.addAction(UIAction { _ in
            Ponder62.resetSeen()
            self.dismiss(animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(reset)
        let done = UIButton(type: .system)
        done.setTitle(FoliaLanguage62.text("done"), for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) },
                       for: .touchUpInside)
        stack.addArrangedSubview(done)
    }
}

/// (62) WB §4.8：快捷命令固定槽位存取面。WC 的
/// CommandPalette 置顶区读 `PinnedCommands62.pinnedIDs` 渲
/// 染、编辑后写回；存储即 SettingsStore.pinnedCommandIDs。
enum PinnedCommands62 {

    static var pinnedIDs: [String] { SettingsStore.pinnedCommandIDs }

    static func setPinned(_ ids: [String]) {
        SettingsStore.pinnedCommandIDs = ids
        Breadcrumbs.log("shortcuts62.pinned set n=\(ids.count)")
    }

    static func toggle(_ id: String) {
        var ids = pinnedIDs
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        setPinned(ids)
    }

    static func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) }
}

/// (62) WB §4.7：界面语言有限文案表。覆盖范围（如实）：设
/// 置页签标题、思索面标题、完成钮等关键面文案；全量文案本
/// 地化不在本包能力内（其余面仍为简体中文写死文案）。
enum FoliaLanguage62 {

    static var current: String { SettingsStore.appLanguage }

    private static let table: [String: [String: String]] = [
        "settingsTitle": ["zh-Hans": "设置", "en": "Settings"],
        "done": ["zh-Hans": "完成", "en": "Done"],
        "ponderTitle": ["zh-Hans": "思索教程", "en": "Ponder Guide"],
        "tab.0": ["zh-Hans": "外观", "en": "Appearance"],
        "tab.1": ["zh-Hans": "播放页", "en": "Player"],
        "tab.2": ["zh-Hans": "主页与歌单", "en": "Home & Playlists"],
        "tab.3": ["zh-Hans": "动画与性能", "en": "Motion & Performance"],
        "tab.4": ["zh-Hans": "播放控制", "en": "Playback"],
        "tab.5": ["zh-Hans": "歌词", "en": "Lyrics"],
        "tab.6": ["zh-Hans": "通用", "en": "General"],
        "tab.7": ["zh-Hans": "快捷操作", "en": "Shortcuts"],
        "tab.8": ["zh-Hans": "连接与集成", "en": "Connections"],
        "tab.9": ["zh-Hans": "存储与备份", "en": "Storage & Backup"],
        "tab.10": ["zh-Hans": "开发者", "en": "Developer"],
        "tab.11": ["zh-Hans": "帮助", "en": "Help"]
    ]

    static func text(_ key: String) -> String {
        table[key]?[current] ?? table[key]?["zh-Hans"] ?? key
    }

    /// 设置页签标题的本地化面（页签本体在 SettingsVC，本函
    /// 数供其后续接线与思索面复用；当前真消费点为思索面与
    /// WB 设置行分组标题）。
    static func tabTitle(_ index: Int) -> String { text("tab.\(index)") }
}
