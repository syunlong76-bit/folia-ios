import UIKit

/// (62) WB §4.7：思索（Ponder）教程提示系统。
///
/// - 教程提示：功能面首访时一次性气泡（队列面板 / 日记本 /
///   命令面板 / 舞台样式等已落地面），已读态落盘
///   （SettingsStore.ponderSeenIDs），读过不再弹；总开关
///   ponderTipsEnabled 关时全停。
/// - 触屏思索按钮：墙面悬浮「?」钮（WB62HomeWallHooks 安
///   装），点开 PonderListViewController62 教程列表面，可重
///   读全部提示、也可一键重置已读态。
enum Ponder62 {

    struct Tip {
        let id: String
        /// (73) 导播台章节 id（见 chapters）：学网页版
        /// Ponder 的分章讲法——按使用区域分章、每章逐面讲
        /// 「这是什么、在哪、怎么用/怎么设」。
        let chapter: String
        let title: String
        let body: String
    }

    /// (73) 导播台章节（顺序即导览顺序，组织学网页版
    /// Ponder 的 basics/library/player/panel/settings/
    /// studio 分章；内容只收原生真实存在的功能与设置）。
    static let chapters: [(id: String, title: String)] = [
        ("start", "入门"),
        ("wall", "照片墙"),
        ("player", "播放与舞台"),
        ("pets", "宠物"),
        ("desk", "工作台"),
        ("settings", "设置")
    ]

    /// 真内容：只覆盖已落地的功能面，不给未迁面写假教程。
    static let tips: [Tip] = [
        Tip(id: "login", chapter: "start", title: "登录三家",
            body: "点左上角白色横线打开工作台，点头像区扫码登录网易云 / QQ 音乐 / 酷狗；登录后头像区显示昵称、三家状态行各自亮绿点。未登录时只能播本地与已缓存曲目。"),
        Tip(id: "wall", chapter: "wall", title: "照片墙漫游",
            body: "主页照片墙单指拖动平移浏览，点按任意封面卡展开——展开卡上直接出歌词与播放控制；歌词始终钉在正在播放歌曲自己的封面卡上，随卡一起移动。"),
        Tip(id: "lattice", chapter: "wall", title: "Lattice 拼贴墙",
            body: "拼贴墙把当前队列铺成拼贴格：正在播放的格子带呼吸光环、已经播过的会压暗。从墙面布局切换进入，点任意格子即从那首开始播。"),
        Tip(id: "sketchbook", chapter: "wall", title: "日记本",
            body: "屏幕左缘的小把手是日记本：搜索结果行尾第一个钮把歌暂存进来，抽屉里可分组、看历史、把草稿队列一键替换当前队列。"),
        Tip(id: "seam", chapter: "wall", title: "缝合工具条",
            body: "墙顶工具条可切换歌 / 推 / 探三段、切换网格与墙面布局；「…」菜单里有喜欢的音乐、云盘、过滤与隐藏管理。"),
        Tip(id: "queue", chapter: "player", title: "队列面板",
            body: "点播台上排「面板」键打开播放面板，队列页签里可拖动排序、左滑移除、批量多选，还能把当前队列存成本机歌单。"),
        Tip(id: "command", chapter: "player", title: "命令面板",
            body: "点播台上排「命令」键打开命令面板：播放控制、队列操作、当前歌曲与工具命令集中在一处，顶部可搜索。"),
        Tip(id: "stage-style", chapter: "player", title: "歌词样式",
            body: "舞台上三击屏幕可洗牌切换下一个歌词特效，长按舞台约 5 秒同样切换（洗牌袋一轮内不重复）；样式选择器里每个样式都有自己的调参面板。带「网页运行」徽标的样式是网页特效在原生里无缝切换运行，音频始终原生。"),
        Tip(id: "minibar", chapter: "player", title: "播放台",
            body: "播放台 5 秒无操作会收成进度细条，宠物会跟着掉到细条上玩；点细条恢复完整形态，任何操作都会重新计时。横屏时播放台与竖屏同尺寸、居中显示。"),
        Tip(id: "paw", chapter: "pets", title: "爪印召唤",
            body: "右下角的爪印钮在任意页面都够得着：长按约 2 秒召唤宠物上播放台，长按约 3 秒全员告别离场；长按台上单只宠物约 3 秒，它说完告别词再消失。"),
        Tip(id: "pets-care", chapter: "pets", title: "宠物陪伴",
            body: "宠物会自己玩耍、互相打招呼聊天（各自性格不同），也会冒关心气泡问你累不累、有没有好好吃饭；点气泡可以回应摸摸头 / 亲亲 / 抱抱，它会回话。点宠物本体也会弹对话框。"),
        // (73) island 口径随确定性落座改版更新：固定双人组常驻。
        Tip(id: "island", chapter: "pets", title: "灵动岛宠物",
            body: "灵动岛上住着固定双人组（捂脸小猫在左、爱心小狗在右），常驻陪你听歌、会冒泡说话；点它蹦回播放台。用「汪汪队开大会」样式时它们撤下上台，切走样式即回岛。"),
        Tip(id: "concert", chapter: "pets", title: "汪汪队开大会",
            body: "歌词样式选「汪汪队开大会」时，宠物全员上舞台列队轮唱，独唱者会跑到中央；此样式生效期间点播台与灵动岛的宠物会撤下，切走样式即恢复。"),
        Tip(id: "desk", chapter: "desk", title: "工作台（控制台）",
            body: "屏幕左上角的白色横线是工作台把手：点开后顶部垂下控制设置台，灵动岛嵌在台顶的凹口里露出。台里有账户登录与三家状态、歌单 / 电台 / 搜索 / 专辑 / 本地分区、设置入口和本导播台；点台外区域或上拖即可收起，收起回到左上角白线。"),
        Tip(id: "settings-tour", chapter: "settings", title: "设置导览",
            body: "设置共 12 个页签：外观、播放页、主页与歌单、动画与性能、播放控制、歌词、通用、快捷操作、连接与集成、存储与备份、开发者、帮助。想调什么先按页签找分组，组内每项都有一行说明；思索教程的开关与重置在「通用 → 思索」组。"),
        Tip(id: "theme-park", chapter: "settings", title: "主题乐园",
            body: "设置 → 外观 → 主题乐园：可预览当前歌曲按封面生成的主题、切换配色预设、编辑自定义三色；歌曲主题的自动切换与生成来源在同一页签的「歌曲主题」组。"),
        Tip(id: "local-cache", chapter: "settings", title: "本地曲库与媒体缓存",
            body: "导入的本地歌曲在「本地」分区浏览；听过的歌会自动回填到媒体缓存（设置 → 存储与备份可改缓存目录、看占用），离线时可播已缓存曲目。")
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
    /// 日记本 / 命令面板的宿主可一行接入；设置页「思索教程
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
        title.text = "导播台"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white
        stack.addArrangedSubview(title)
        let intro = UILabel()
        intro.text = "按区域分章，逐个功能讲清在哪、怎么用、去哪设置。条目只收原生里真实存在的功能。"
        intro.font = .systemFont(ofSize: 12.5)
        intro.textColor = UIColor.white.withAlphaComponent(0.55)
        intro.numberOfLines = 0
        stack.addArrangedSubview(intro)
        // (73) 分章呈现（学网页版 Ponder 的分章讲法）：章
        // 标题金色小题，章下条目沿旧行式（已读/未读标记）。
        let seen = Ponder62.seenIDs
        for chapter in Ponder62.chapters {
            let chapterTips = Ponder62.tips.filter { $0.chapter == chapter.id }
            guard !chapterTips.isEmpty else { continue }
            let header = UILabel()
            header.text = chapter.title
            header.font = .systemFont(ofSize: 15, weight: .semibold)
            header.textColor = UIColor(red: 1.0, green: 0.84, blue: 0.40, alpha: 1)
            stack.addArrangedSubview(header)
            for tip in chapterTips {
                let label = UILabel()
                label.text = "· \(tip.title)\(seen.contains(tip.id) ? "（已读）" : "（未读）")\n\(tip.body)"
                label.font = .systemFont(ofSize: 13)
                label.textColor = UIColor.white.withAlphaComponent(0.75)
                label.numberOfLines = 0
                stack.addArrangedSubview(label)
            }
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

    /// (66) 自定义快捷键可绑命令目录：id 与命令面板注册表
    /// （CommandPaletteViewController.buildRegistry62）同
    /// 源，只列墙面宿主有直接执行通路的命令（打开面板/搜
    /// 索/设置/本地/探索/重扫/预缓存/主题乐园/陪伴/海报墙/
    /// 打卡）；执行分发在 HomeWallViewController.wb66CustomKey。
    static let customKeyCatalog66: [(id: String, title: String)] = [
        ("panel.open", "打开播放面板"),
        ("nav.search", "去搜索"),
        ("nav.settings", "打开设置"),
        ("nav.local", "本地曲库"),
        ("nav.explore", "探索页"),
        ("dir.rescanLocal", "重扫本地库"),
        ("dir.precache", "预缓存队列"),
        ("theme.park", "打开主题乐园"),
        ("dafeiyu.open", "打开陪伴面板"),
        ("panel.posterwall", "直播海报墙"),
        ("lyric.checkin", "网易云听歌打卡"),
    ]
}

/// (62) WB §4.7：界面语言有限文案表。覆盖范围（如实）：设
/// 置页签标题、思索面标题、完成钮等关键面文案；全量文案本
/// 地化不在本包能力内（其余面仍为简体中文写死文案）。
enum FoliaLanguage62 {

    /// 当前生效语言：system 按系统首选语言解析（en 系 →
    /// en，其余 → zh-Hans）；zh-TW/vi 暂无译表，text() 查
    /// 不到时回退 zh-Hans（(66) 五档口径，设置行如实标注）。
    static var current: String {
        let raw = SettingsStore.appLanguage
        if raw == "system" {
            let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
            return preferred.hasPrefix("en") ? "en" : "zh-Hans"
        }
        return raw
    }

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
