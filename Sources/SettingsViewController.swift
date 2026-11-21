import UIKit

/// 原生设置页：账号（(51) 原生扫码登录/退出）、播放与歌词
/// 设置、壳信息、桥日志入口。
///
/// v2 视觉（2026-11-14）：半透明黑遮罩 + 近黑浮层卡片底部滑
/// 入，Folia 深色设计语言（深灰分组卡、柔和紫强调色、系统弹
/// 簧入场），与播放器界面同调。
///
/// (53) 工作流 C 全量重做：分组照网页版四组（界面 / 音乐 /
/// 应用 / 系统）重排；落盘统一经 SettingsStore（新键
/// settings.* 为主、旧键兼容读、旧键不删），既有开关行为不
/// 变；新增网页对应物两项——循环模式（消费者 QueueManager
/// .playMode）与歌词时间轴偏移（仅存储+入口，歌词时钟未接
/// 入，文案如实标注）。
/// (55) 工作流 G 页签化重建：按网页十一页签 + 帮助重排为
/// 页签式（见 tabTitles），既有 13 行并入新体系、逻辑不重
/// 写；新增真消费行（歌词偏移做真/速记簿把手/自动跳过/加
/// 队列位置/启动续播/缓存管理/配置码/内存读数等，消费点
/// 见 SettingsStore 各属性注释）；每签底部固定只读「未接
/// 入（子系统未迁）」卡逐项列未落项与原因，无控件。布局不复刻旧病：行标签一律直挂横向
/// 行/带边距的堆叠行，hint 为直挂 UILabel 不再用空 UIView
/// 包裹，信息行改横向行内标签；viewDidAppear 落一条
/// settings.selfcheck 面包屑汇总各组行数与首行校验，供真机
/// 一轮判死旧版空白行问题（诊断 B-1）。
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
    private let portLabel = UILabel()
    // 网易云账号段（(51) A 组）：状态行 + 登录/退出按钮。
    private let accountStatusLabel = UILabel()
    private let accountActionButton = UIButton(type: .system)
    private let themeSwitch = UISwitch()
    // 歌词特效增强（3.7 (49)）：逐词强调 / 粒子换行两开关。
    private let emphasisSwitch = UISwitch()
    private let particleFlipSwitch = UISwitch()
    // 点播台按钮槽位（3.7 (50)）：上一首 / 下一首 / 播放列表。
    private let slotPrevSwitch = UISwitch()
    private let slotNextSwitch = UISwitch()
    private let slotQueueSwitch = UISwitch()

    // 贴纸层（3.7 (24)，纯新增）：贴纸伙伴分组（门面猫/狗 +
    // 迷你台小宠物开关）。
    private let companionSwitch = UISwitch()
    private var settingsCatSticker: StickerView?
    private var settingsCatShowingAlt = false

    // 循环模式（(53) 新增，网页 loopMode 对应物）：分段控件与
    // QueueManager.playMode 一一对应，与队列面板模式按钮同源。
    private let loopModeControl = UISegmentedControl(
        items: ["列表循环", "单曲循环", "随机", "不循环"])
    private static let loopModes: [QueueManager.PlayMode] =
        [.loopAll, .repeatOne, .shuffle, .off]

    // 歌词时间轴偏移（(53) 新增，网页 globalLyricTimeline
    // OffsetMs 对应物）：仅存储+入口，歌词时钟未接入（见
    // SettingsStore 注释与组内 hint 的如实文案）。
    private let offsetStepper = UIStepper()
    private let offsetValueLabel = UILabel()
    private let offsetResetButton = UIButton(type: .system)

    // 自检记账（(53)）：按分组收集本页全部 UILabel，viewDid
    // Appear 时校验 text 非空与 frame 非零，落 settings
    // .selfcheck 面包屑（诊断 B-1 的一轮判死法）。
    private var checkNames: [String] = []
    private var checkLabels: [[UILabel]] = []
    private var didRunSelfCheck = false

    // 页签体系（(55) 工作流 G）：按网页十一页签 + 帮助重建。
    // tabGroups[i] = 第 i 页签的全部顶层组视图，切换时整组
    // 显隐；每页签底部固定一张只读「未接入」卡（纯文本、无
    // 控件），逐项列未落网页项与原因，与交付报告口径一致。
    static let tabTitles = ["外观", "播放页", "主页与歌单", "动画与性能",
                            "播放控制", "歌词", "通用", "快捷操作",
                            "连接与集成", "存储与备份", "开发者", "帮助"]
    private var tabGroups: [[UIView]] = Array(
        repeating: [], count: SettingsViewController.tabTitles.count)
    private var tabButtons: [UIButton] = []
    private var selectedTab = 0
    private var cardStackRef: UIStackView?

    // (55) 新增控件：速记簿把手（主页与歌单页签）
    private let sketchShowSwitch = UISwitch()
    private let sketchPositionSlider = UISlider()
    private let sketchPositionLabel = UILabel()
    private let sketchStyleControl = UISegmentedControl(items: ["线", "点", "图形"])
    // (55) 动画与性能页签
    private let renderScaleControl = UISegmentedControl(
        items: ["0.5×", "0.75×", "1×", "1.5×", "2×"])
    private static let renderScales: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]
    private let reduceMotionSwitch = UISwitch()
    private let systemReduceMotionLabel = UILabel()
    // (55) 播放控制页签
    private let autoSkipSwitch = UISwitch()
    private let queuePositionControl = UISegmentedControl(items: ["队尾", "下一首"])
    // (55) 通用页签
    private let autoPlaySwitch = UISwitch()
    // (55) 存储与备份页签
    private let coverCacheLabel = UILabel()
    private let apiCacheLabel = UILabel()
    private let lyricCacheLabel = UILabel()
    // (55) 开发者页签
    private let memoryLabel = UILabel()
    // (55) 帮助页签
    private let qqGroupLabel = UILabel()

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
        runSelfCheckIfNeeded()
        guard !didRunEntrance else { return }
        didRunEntrance = true
        // 降低动态·跟随系统（(55) 消费点一）：开关开且系统
        // 减弱动态效果开启时，入场弹簧动画跳过、直达终态。
        if SettingsStore.reduceMotionFollowSystem
            && UIAccessibility.isReduceMotionEnabled {
            backdropView.alpha = 1
            cardView.transform = .identity
            Breadcrumbs.log("settings.reduceMotion applied=entrance")
            return
        }
        UIView.animate(withDuration: 0.55, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4,
                       options: [.curveEaseOut]) {
            self.backdropView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    // MARK: - 自检记账

    func beginCheckGroup(_ name: String) {
        checkNames.append(name)
        checkLabels.append([])
    }

    func track(_ label: UILabel) {
        guard !checkLabels.isEmpty else { return }
        checkLabels[checkLabels.count - 1].append(label)
    }

    /// 旧版空白行一轮判死（诊断 B-1 验证法）：强制布局后逐组
    /// 汇总行数、首行 text 长度、首行/全行 frame 非零与 text
    /// 非空，落一条面包屑。frame 异常 → 布局问题；text 为空
    /// → 数据/时序问题；皆正常仍不可见 → 渲染/颜色问题。
    private func runSelfCheckIfNeeded() {
        guard !didRunSelfCheck else { return }
        didRunSelfCheck = true
        view.layoutIfNeeded()
        // (55) 页签化后未选中页签的组整组 hidden：其标签 frame
        // 为零属预期，帧检对「祖先链含 hidden」者豁免，text
        // 检照常（缺字仍判死）。
        func inHiddenTab(_ label: UILabel) -> Bool {
            var view: UIView? = label
            while let current = view {
                if current.isHidden { return true }
                view = current.superview
            }
            return false
        }
        var parts: [String] = []
        var allOK = true
        for (index, name) in checkNames.enumerated() {
            let labels = index < checkLabels.count ? checkLabels[index] : []
            let first = labels.first
            let firstLen = first?.text?.count ?? -1
            let firstFrameOK = first.map {
                inHiddenTab($0) || ($0.bounds.width > 0 && $0.bounds.height > 0)
            } ?? false
            let laidOK = !labels.isEmpty && labels.allSatisfy {
                inHiddenTab($0) || ($0.bounds.width > 0 && $0.bounds.height > 0)
            }
            let textsOK = !labels.isEmpty && labels.allSatisfy {
                !($0.text ?? "").isEmpty
            }
            if !(firstFrameOK && laidOK && textsOK) { allOK = false }
            parts.append("\(name)[n=\(labels.count) firstLen=\(firstLen)"
                + " firstFrame=\(firstFrameOK ? 1 : 0)"
                + " laid=\(laidOK ? 1 : 0) texts=\(textsOK ? 1 : 0)]")
        }
        Breadcrumbs.log("settings.selfcheck ok=\(allOK ? 1 : 0) "
            + parts.joined(separator: " "))
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
        cardStackRef = cardStack

        // 页签栏（(55)）：横向可滚动的页签丸，选中态 accent
        // 填充；下方各组按页签注册显隐（见 reg/selectTab）。
        let tabScroll = UIScrollView()
        tabScroll.showsHorizontalScrollIndicator = false
        tabScroll.translatesAutoresizingMaskIntoConstraints = false
        let tabRow = UIStackView()
        tabRow.axis = .horizontal
        tabRow.spacing = 8
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.addSubview(tabRow)
        for (index, title) in Self.tabTitles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            button.layer.cornerRadius = 16
            button.tag = index
            button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            tabButtons.append(button)
            tabRow.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor),
            tabRow.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
            tabRow.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
            tabScroll.heightAnchor.constraint(equalToConstant: 34)
        ])
        cardStack.addArrangedSubview(tabScroll)

        // ===== 一、界面组（网页：外观 / 播放器 / 主页 / 图形）=====
        beginCheckGroup("外观")

        // 播放台特效分组卡（3.7 (13.5)）：总开关 + 说明。关掉后
        // 两台一律素面、长按切换停用；选中的主题保留。
        let themeGroup = makeGroupCard()
        themeGroup.addArrangedSubview(makeSwitchRow(
            "播放台主题特效", themeSwitch, #selector(themeSwitchChanged)))
        themeGroup.addArrangedSubview(makeHairline())
        themeGroup.addArrangedSubview(makeHintRow(
            "开启后，长按播放台可循环切换花海、雪景、星空、海洋四款主题；关掉后播放台恢复素面，特效全部停用。"))
        cardStack.addArrangedSubview(themeGroup)
        reg(themeGroup, tab: 0)

        // 点播台按钮分组卡（3.7 (50)）：三键显隐，默认全开 =
        // 现状；关掉的键在三台同步隐藏并收拢让位。主页墙台本
        // 无播放列表键，该开关只影响曲目墙台与舞台台。
        let slotGroup = makeGroupCard()
        slotGroup.addArrangedSubview(makeSwitchRow(
            "上一首按钮", slotPrevSwitch, #selector(slotPrevSwitchChanged)))
        slotGroup.addArrangedSubview(makeHairline())
        slotGroup.addArrangedSubview(makeSwitchRow(
            "下一首按钮", slotNextSwitch, #selector(slotNextSwitchChanged)))
        slotGroup.addArrangedSubview(makeHairline())
        slotGroup.addArrangedSubview(makeSwitchRow(
            "播放列表按钮", slotQueueSwitch, #selector(slotQueueSwitchChanged)))
        slotGroup.addArrangedSubview(makeHairline())
        slotGroup.addArrangedSubview(makeHintRow(
            "控制点播台上的按钮显隐，三台同步生效；播放按钮恒显。隐藏的按钮会收拢让位，不留空槽。"))
        cardStack.addArrangedSubview(slotGroup)
        reg(slotGroup, tab: 1)

        // ===== 二、音乐组（网页：播放 / 歌词）=====
        beginCheckGroup("播放页")

        // 播放分组卡（(53) 新增）：循环模式，网页 loopMode 对
        // 应物。消费者 = QueueManager.playMode（完播推进与随
        // 机取序），与播放列表面板的模式按钮同源、双向同步。
        let playbackGroup = makeGroupCard()
        let loopRow = UIStackView()
        loopRow.axis = .vertical
        loopRow.spacing = 10
        loopRow.isLayoutMarginsRelativeArrangement = true
        loopRow.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let loopTitle = UILabel()
        loopTitle.text = "循环模式"
        loopTitle.font = .systemFont(ofSize: 15)
        loopTitle.textColor = FoliaUI.primary
        track(loopTitle)
        loopModeControl.selectedSegmentTintColor = FoliaUI.accent
        loopModeControl.setTitleTextAttributes(
            [.foregroundColor: FoliaUI.primary,
             .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        loopModeControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.white,
             .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
        loopModeControl.addTarget(
            self, action: #selector(loopModeChanged), for: .valueChanged)
        loopRow.addArrangedSubview(loopTitle)
        loopRow.addArrangedSubview(loopModeControl)
        playbackGroup.addArrangedSubview(loopRow)
        playbackGroup.addArrangedSubview(makeHairline())
        playbackGroup.addArrangedSubview(makeHintRow(
            "与播放列表面板的播放模式同步：整队循环、单曲循环、随机播放、播完最后一首停住。"))
        cardStack.addArrangedSubview(playbackGroup)
        reg(playbackGroup, tab: 1)

        // 歌词分组卡：逐词强调 / 粒子换行（3.7 (49)，缺省全开，
        // 关掉即回上一版观感）+ 歌词时间轴偏移（(53) 新增，
        // 仅存储，见 hint 如实文案）。
        let lyricsGroup = makeGroupCard()
        lyricsGroup.addArrangedSubview(makeSwitchRow(
            "逐词强调", emphasisSwitch, #selector(emphasisSwitchChanged)))
        lyricsGroup.addArrangedSubview(makeHairline())
        lyricsGroup.addArrangedSubview(makeSwitchRow(
            "粒子换行", particleFlipSwitch, #selector(particleFlipSwitchChanged)))
        lyricsGroup.addArrangedSubview(makeHairline())
        let offsetRow = UIStackView()
        offsetRow.axis = .horizontal
        offsetRow.alignment = .center
        offsetRow.spacing = 8
        offsetRow.isLayoutMarginsRelativeArrangement = true
        offsetRow.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let offsetTitle = UILabel()
        offsetTitle.text = "歌词时间轴偏移"
        offsetTitle.font = .systemFont(ofSize: 15)
        offsetTitle.textColor = FoliaUI.primary
        track(offsetTitle)
        offsetValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        offsetValueLabel.textColor = FoliaUI.primary
        track(offsetValueLabel)
        offsetStepper.minimumValue = -2000
        offsetStepper.maximumValue = 2000
        offsetStepper.stepValue = 50
        offsetStepper.addTarget(
            self, action: #selector(offsetStepperChanged), for: .valueChanged)
        offsetResetButton.setTitle("归零", for: .normal)
        offsetResetButton.setTitleColor(FoliaUI.accent, for: .normal)
        offsetResetButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        offsetResetButton.addTarget(
            self, action: #selector(offsetResetTapped), for: .touchUpInside)
        offsetRow.addArrangedSubview(offsetTitle)
        offsetRow.addArrangedSubview(UIView())
        offsetRow.addArrangedSubview(offsetValueLabel)
        offsetRow.addArrangedSubview(offsetStepper)
        offsetRow.addArrangedSubview(offsetResetButton)
        lyricsGroup.addArrangedSubview(offsetRow)
        lyricsGroup.addArrangedSubview(makeHairline())
        lyricsGroup.addArrangedSubview(makeHintRow(
            "歌词时间轴偏移（已生效）：整体平移歌词判定时刻，补偿蓝牙等输出延迟——正值歌词提前、负值延后。墙面展开卡歌词即时生效。范围 ±2000 毫秒，步进 50。"))
        cardStack.addArrangedSubview(lyricsGroup)
        reg(lyricsGroup, tab: 5)

        // ===== 三、应用组（网页：通用 / 交互 / 集成 / 存储）=====
        beginCheckGroup("连接与集成")

        // 网易云账号分组卡（(51) A 组）：状态行 + 扫码登录/
        // 退出登录按钮。登录态以 NativeSessionStore 为准。
        let accountGroup = makeGroupCard()
        accountGroup.addArrangedSubview(
            makeInfoRow(title: "网易云账号", valueLabel: accountStatusLabel))
        accountGroup.addArrangedSubview(makeHairline())
        let accountButtonWrap = UIView()
        accountActionButton.setTitle("扫码登录", for: .normal)
        accountActionButton.setTitleColor(FoliaUI.accent, for: .normal)
        accountActionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        accountActionButton.backgroundColor = FoliaUI.buttonFill
        accountActionButton.layer.cornerRadius = 12
        accountActionButton.translatesAutoresizingMaskIntoConstraints = false
        accountActionButton.addTarget(
            self, action: #selector(accountActionTapped), for: .touchUpInside)
        accountButtonWrap.addSubview(accountActionButton)
        NSLayoutConstraint.activate([
            accountActionButton.topAnchor.constraint(equalTo: accountButtonWrap.topAnchor, constant: 10),
            accountActionButton.bottomAnchor.constraint(equalTo: accountButtonWrap.bottomAnchor, constant: -12),
            accountActionButton.leadingAnchor.constraint(equalTo: accountButtonWrap.leadingAnchor, constant: 14),
            accountActionButton.trailingAnchor.constraint(equalTo: accountButtonWrap.trailingAnchor, constant: -14),
            accountActionButton.heightAnchor.constraint(equalToConstant: 42)
        ])
        accountGroup.addArrangedSubview(accountButtonWrap)
        cardStack.addArrangedSubview(accountGroup)
        reg(accountGroup, tab: 8)

        // 贴纸伙伴分组卡（3.7 (24)）：门面猫（cat-01，点按换
        // cat-15 播一次再换回）+ 门面狗（dog-17，透明底承
        // 载）+ 迷你台小宠物开关。贴纸均为 APNG 原素材真帧。
        let stickerGroup = makeGroupCard()
        let stickerHeadRow = UIStackView()
        stickerHeadRow.axis = .horizontal
        stickerHeadRow.alignment = .center
        stickerHeadRow.spacing = 12
        stickerHeadRow.isLayoutMarginsRelativeArrangement = true
        stickerHeadRow.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let catSticker = StickerView()
        catSticker.crumbScene = "settings-cat"
        catSticker.translatesAutoresizingMaskIntoConstraints = false
        catSticker.setSticker("cat-01", mode: .loop)
        catSticker.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(settingsCatTapped)))
        NSLayoutConstraint.activate([
            catSticker.widthAnchor.constraint(equalToConstant: 64),
            catSticker.heightAnchor.constraint(equalToConstant: 64)
        ])
        settingsCatSticker = catSticker
        let stickerTitle = UILabel()
        stickerTitle.text = "贴纸伙伴"
        stickerTitle.font = .systemFont(ofSize: 15)
        stickerTitle.textColor = FoliaUI.primary
        track(stickerTitle)
        let stickerSub = UILabel()
        stickerSub.text = "小猫小狗会在加载、失败、空状态等时刻出来陪你。"
        stickerSub.font = .systemFont(ofSize: 12)
        stickerSub.textColor = FoliaUI.secondary
        stickerSub.numberOfLines = 0
        track(stickerSub)
        let stickerTitles = UIStackView(arrangedSubviews: [stickerTitle, stickerSub])
        stickerTitles.axis = .vertical
        stickerTitles.spacing = 3
        stickerHeadRow.addArrangedSubview(catSticker)
        stickerHeadRow.addArrangedSubview(stickerTitles)
        stickerGroup.addArrangedSubview(stickerHeadRow)
        stickerGroup.addArrangedSubview(makeHairline())
        let dogTileWrap = UIView()
        // (25) 去背景：dog-17 源即透明底，容器只做布局、无底板。
        let dogTile = UIView()
        dogTile.backgroundColor = .clear
        dogTile.translatesAutoresizingMaskIntoConstraints = false
        let dogSticker = StickerView()
        dogSticker.crumbScene = "settings-dog"
        dogSticker.translatesAutoresizingMaskIntoConstraints = false
        dogSticker.setSticker("dog-17", mode: .loop)
        dogTile.addSubview(dogSticker)
        dogTileWrap.addSubview(dogTile)
        NSLayoutConstraint.activate([
            dogTile.widthAnchor.constraint(equalToConstant: 104),
            dogTile.heightAnchor.constraint(equalToConstant: 98),
            dogTile.centerXAnchor.constraint(equalTo: dogTileWrap.centerXAnchor),
            dogTile.topAnchor.constraint(equalTo: dogTileWrap.topAnchor, constant: 12),
            dogTile.bottomAnchor.constraint(equalTo: dogTileWrap.bottomAnchor, constant: -12),
            dogSticker.leadingAnchor.constraint(equalTo: dogTile.leadingAnchor, constant: 4),
            dogSticker.trailingAnchor.constraint(equalTo: dogTile.trailingAnchor, constant: -4),
            dogSticker.topAnchor.constraint(equalTo: dogTile.topAnchor, constant: 1),
            dogSticker.bottomAnchor.constraint(equalTo: dogTile.bottomAnchor, constant: -1)
        ])
        stickerGroup.addArrangedSubview(dogTileWrap)
        stickerGroup.addArrangedSubview(makeHairline())
        stickerGroup.addArrangedSubview(makeSwitchRow(
            "迷你台小宠物", companionSwitch, #selector(companionSwitchChanged)))
        stickerGroup.addArrangedSubview(makeHairline())
        stickerGroup.addArrangedSubview(makeHintRow(
            "开启后，底部播放台的台面上会有小宠物陪你听歌，播放台收起成进度条时它们会轮流上场玩耍：点宠物头顶有小反应、点身上会说话，它们还会互相打招呼、时不时关心你一句（点气泡可以摸摸头、亲亲、抱抱）；按住拖动可以把它安置在台面一处。每首歌主宠物会换一只。"))
        cardStack.addArrangedSubview(stickerGroup)
        reg(stickerGroup, tab: 0)

        // 信息分组卡：壳版本/本地服务端口，横向行（标题左、
        // 值右），行间发丝线。（(51)：前端版本行随
        // UpdateManager 退役删除；(53)：由旧版纵向堆叠行改
        // 横向行内标签，见类头注释。）
        // (55)：壳版本行移入「帮助」页签；本地服务端口行移入
        // 「开发者」页签（buildExtraTabs 内以 portLabel 建行）。
        let infoGroup = makeGroupCard()
        infoGroup.addArrangedSubview(
            makeInfoRow(title: "壳版本", valueLabel: shellVersionLabel))
        cardStack.addArrangedSubview(infoGroup)
        reg(infoGroup, tab: 11)

        // ===== 四、系统组（网页：桌面 / Mods / 开发者 / 帮助）=====
        beginCheckGroup("开发者")

        // 桥日志（3.6 (3) 取证入口）：点歌/切歌/锁屏出问题时在这里看留痕，
        // 可整段复制发回诊断。
        // （(51)：原「检查更新」按钮与「重启应用新版本」按钮随
        // UpdateManager 退役一并删除。）
        let logButton = UIButton(type: .system)
        logButton.setTitle("桥日志", for: .normal)
        logButton.setTitleColor(FoliaUI.primary, for: .normal)
        logButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        logButton.backgroundColor = FoliaUI.buttonFill
        logButton.layer.cornerRadius = 12
        logButton.addTarget(self, action: #selector(logTapped), for: .touchUpInside)
        logButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        if let logTitle = logButton.titleLabel { track(logTitle) }
        cardStack.addArrangedSubview(logButton)
        reg(logButton, tab: 10)
        let logHint = makeHintRow(
            "点歌、切歌、锁屏出问题时，先在这里看留痕，可整段复制发回诊断。")
        cardStack.addArrangedSubview(logHint)
        reg(logHint, tab: 10)

        // (55) 其余页签与每签未接入清单（同文件扩展段建）。
        buildExtraTabs(into: cardStack)
        build62Tabs(into: cardStack)
        applyTabVisibility()
    }

    /// 分组卡容器：深灰底、16 圆角，内部纵向堆行
    func makeGroupCard() -> UIStackView {
        let group = UIStackView()
        group.axis = .vertical
        group.spacing = 0
        group.backgroundColor = FoliaUI.group
        group.layer.cornerRadius = 16
        group.clipsToBounds = true
        return group
    }

    /// 分节标题：直挂 UILabel（自检记账随当前分组）。
    func makeSectionHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = FoliaUI.secondary
        track(label)
        return label
    }

    func makeHairline() -> UIView {
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

    /// 信息行（(53) 改横向）：小灰标题左 + 值右，同处一个横
    /// 向行内——与开关行同构造族（旧版纵向堆叠直挂为诊断
    /// B-1 的失效集合构造，不再复刻）。
    func makeInfoRow(title: String, valueLabel: UILabel) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = FoliaUI.secondary
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = FoliaUI.primary
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 1
        track(titleLabel)
        track(valueLabel)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(valueLabel)
        return row
    }

    /// 开关行：标题 UILabel + 开关，同处一个横向行内。
    func makeSwitchRow(_ title: String, _ toggle: UISwitch,
                               _ action: Selector) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = FoliaUI.primary
        track(label)
        toggle.onTintColor = FoliaUI.accent
        toggle.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        toggle.addTarget(self, action: action, for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(toggle)
        return row
    }

    /// 说明行（(53) 改直挂）：UILabel 直挂带边距的堆叠行，
    /// 不再用空 UIView 包裹（旧构造为诊断 B-1 的失效集合）。
    func makeHintRow(_ text: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = FoliaUI.secondary
        label.numberOfLines = 0
        track(label)
        row.addArrangedSubview(label)
        return row
    }

    // MARK: - 数据刷新

    private func refresh() {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        shellVersionLabel.text = "\(short) (\(build))"
        portLabel.text = LocalServer.shared.isRunning ? "127.0.0.1:\(LocalServer.shared.port)" : "未启动"
        refreshAccountSection()
        // 开关与控件状态一律回读存储/生效面，不靠构建时初值：
        // 外部改动（如队列面板改播放模式）后重开设置页即对齐。
        themeSwitch.isOn = SettingsStore.miniPlayerThemeEffectsEnabled
        emphasisSwitch.isOn = StageEffectSettings.wordEmphasisEnabled
        particleFlipSwitch.isOn = StageEffectSettings.particleFlipEnabled
        slotPrevSwitch.isOn = MiniBarSlotSettings.showPrev
        slotNextSwitch.isOn = MiniBarSlotSettings.showNext
        slotQueueSwitch.isOn = MiniBarSlotSettings.showQueue
        companionSwitch.isOn = SettingsStore.miniPetsEnabled
        if let index = Self.loopModes.firstIndex(of: QueueManager.shared.playMode) {
            loopModeControl.selectedSegmentIndex = index
        }
        let offset = SettingsStore.globalLyricTimelineOffsetMs
        offsetStepper.value = Double(offset)
        offsetValueLabel.text = Self.offsetText(offset)
        // (55) 新控件状态回读（同上方口径：不靠构建初值）。
        sketchShowSwitch.isOn = SettingsStore.sketchbookHandleShow
        sketchPositionSlider.value = Float(SettingsStore.sketchbookHandlePosition)
        sketchPositionLabel.text =
            "\(Int((SettingsStore.sketchbookHandlePosition * 100).rounded()))%"
        sketchStyleControl.selectedSegmentIndex = SettingsStore.sketchbookHandleStyle
        renderScaleControl.selectedSegmentIndex =
            Self.renderScales.firstIndex(of: SettingsStore.lyricRenderScale) ?? 2
        reduceMotionSwitch.isOn = SettingsStore.reduceMotionFollowSystem
        systemReduceMotionLabel.text =
            UIAccessibility.isReduceMotionEnabled ? "已开启" : "未开启"
        autoSkipSwitch.isOn = SettingsStore.autoSkipUnplayableEnabled
        queuePositionControl.selectedSegmentIndex =
            SettingsStore.queueDefaultPosition == "next" ? 1 : 0
        autoPlaySwitch.isOn = SettingsStore.autoPlayOnLaunch
        qqGroupLabel.text = "1125072599"
        refreshMemoryLabel()
        refreshCacheLabels()
    }

    /// 开发者页签内存读数（打开/切签时刷新）。
    private func refreshMemoryLabel() {
        memoryLabel.text = SettingsMemoryMonitor.residentBytes()
            .map { SettingsCacheManager.sizeText($0) } ?? "—"
    }

    /// 存储页签缓存大小（后台统计、回主线程落字）。
    private func refreshCacheLabels() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cover = SettingsCacheManager.sizeBytes(for: .cover)
            let api = SettingsCacheManager.sizeBytes(for: .api)
            DispatchQueue.main.async {
                self?.coverCacheLabel.text = SettingsCacheManager.sizeText(cover)
                self?.apiCacheLabel.text = SettingsCacheManager.sizeText(api)
                self?.refreshLyricCacheLabel()
            }
        }
    }

    private static func offsetText(_ ms: Int) -> String {
        if ms > 0 { return "+\(ms) ms" }
        return "\(ms) ms"
    }

    /// 网易云账号段刷新：以 NativeSessionStore 是否有会话为准；
    /// 有会话时异步补昵称（/login/status），失败保留「已登录」。
    private func refreshAccountSection() {
        if NativeSessionStore.shared.load() != nil {
            accountStatusLabel.text = "已登录"
            accountActionButton.setTitle("退出登录", for: .normal)
            accountActionButton.setTitleColor(FoliaUI.danger, for: .normal)
            Task { [weak self] in
                guard let status = try? await NativeDataClient.shared.fetchLoginStatus(),
                      status.loggedIn, let nickname = status.nickname, !nickname.isEmpty else {
                    return
                }
                await MainActor.run {
                    self?.accountStatusLabel.text = "已登录 · \(nickname)"
                }
            }
        } else {
            accountStatusLabel.text = "未登录"
            accountActionButton.setTitle("扫码登录", for: .normal)
            accountActionButton.setTitleColor(FoliaUI.accent, for: .normal)
        }
    }

    // MARK: - 动作

    @objc private func close() {
        guard !isDismissing else { return }
        isDismissing = true
        // 降低动态·跟随系统（(55) 消费点二）：同入场口径，
        // 命中时关闭动画跳过、直接 dismiss。
        if SettingsStore.reduceMotionFollowSystem
            && UIAccessibility.isReduceMotionEnabled {
            dismiss(animated: false)
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: {
            self.backdropView.alpha = 0
            self.cardView.transform = CGAffineTransform(translationX: 0, y: 56)
            self.cardView.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false)
        })
    }

    /// 账号按钮：未登录 → 原生扫码登录页；已登录 → 确认后退出
    /// （清 NativeSessionStore + NativeDataClient 缓存 + Web 侧
    /// 两键，迁移旗标回 pending 以便日后重新登录再迁）。
    @objc private func accountActionTapped() {
        if NativeSessionStore.shared.load() != nil {
            let alert = UIAlertController(
                title: "退出登录",
                message: "退出后将清除本机保存的网易云登录状态。",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
                Breadcrumbs.log("session.logout src=settings")
                NativeDataClient.shared.clearNativeSession()
                SessionMigrator.state = .pending
                self?.refreshAccountSection()
            })
            present(alert, animated: true)
        } else {
            let login = LoginViewController()
            login.modalPresentationStyle = .overFullScreen
            login.onLoginSuccess = { [weak self] in
                self?.refreshAccountSection()
            }
            present(login, animated: true)
        }
    }

    @objc private func themeSwitchChanged() {
        SettingsStore.miniPlayerThemeEffectsEnabled = themeSwitch.isOn
        Breadcrumbs.log("settings.themeEffects value=\(themeSwitch.isOn)")
        NotificationCenter.default.post(name: .foliaMiniPlayerThemeChanged, object: nil)
    }

    @objc private func emphasisSwitchChanged() {
        StageEffectSettings.wordEmphasisEnabled = emphasisSwitch.isOn
        Breadcrumbs.log("settings.wordEmphasis value=\(emphasisSwitch.isOn)")
    }

    @objc private func particleFlipSwitchChanged() {
        StageEffectSettings.particleFlipEnabled = particleFlipSwitch.isOn
        Breadcrumbs.log("settings.particleFlip value=\(particleFlipSwitch.isOn)")
    }

    @objc private func slotPrevSwitchChanged() {
        MiniBarSlotSettings.showPrev = slotPrevSwitch.isOn
        Breadcrumbs.log("settings.showPrev value=\(slotPrevSwitch.isOn)")
        NotificationCenter.default.post(name: .foliaMiniBarSlotsChanged, object: nil)
    }

    @objc private func slotNextSwitchChanged() {
        MiniBarSlotSettings.showNext = slotNextSwitch.isOn
        Breadcrumbs.log("settings.showNext value=\(slotNextSwitch.isOn)")
        NotificationCenter.default.post(name: .foliaMiniBarSlotsChanged, object: nil)
    }

    @objc private func slotQueueSwitchChanged() {
        MiniBarSlotSettings.showQueue = slotQueueSwitch.isOn
        Breadcrumbs.log("settings.showQueue value=\(slotQueueSwitch.isOn)")
        NotificationCenter.default.post(name: .foliaMiniBarSlotsChanged, object: nil)
    }

    // 贴纸层（3.7 (24) 立、(27) 改管迷你台宠物、(29) 开关改绑
    // 宠物专用新键 miniPetsEnabled，不再读写旧 companionEnabled；
    // (53) 落盘改经 SettingsStore，同步写旧键，StickerSettings
    // 读者行为不变）。
    @objc private func companionSwitchChanged() {
        SettingsStore.miniPetsEnabled = companionSwitch.isOn
        Breadcrumbs.log("settings.miniPets value=\(companionSwitch.isOn)")
    }

    @objc private func loopModeChanged() {
        let index = loopModeControl.selectedSegmentIndex
        guard Self.loopModes.indices.contains(index) else { return }
        let mode = Self.loopModes[index]
        QueueManager.shared.playMode = mode
        SettingsStore.loopModeRaw = mode.rawValue
        Breadcrumbs.log("settings.loopMode value=\(mode.rawValue)")
    }

    /// 偏移写 SettingsStore（钳制后回显）：墙链经 LyricTiming
    /// .lead 即时消费（(55) 做真），面包屑记 applied=wall。
    @objc private func offsetStepperChanged() {
        let ms = Int(offsetStepper.value)
        SettingsStore.globalLyricTimelineOffsetMs = ms
        offsetValueLabel.text = Self.offsetText(ms)
        Breadcrumbs.log("settings.lyricOffsetMs value=\(ms) applied=wall")
    }

    @objc private func offsetResetTapped() {
        offsetStepper.value = 0
        offsetStepperChanged()
    }

    @objc private func settingsCatTapped() {
        guard let cat = settingsCatSticker, !settingsCatShowingAlt else { return }
        settingsCatShowingAlt = true
        cat.setSticker("cat-15", mode: .once(holdLast: true))
        cat.onFinished = { [weak self, weak cat] in
            cat?.setSticker("cat-01", mode: .loop)
            self?.settingsCatShowingAlt = false
        }
    }

    @objc private func logTapped() {
        let viewer = BridgeLogViewController()
        viewer.modalPresentationStyle = .overFullScreen
        present(viewer, animated: true)
    }
}


// MARK: - (55) 页签基础设施与新增页签

extension SettingsViewController {

    /// 页签注册：把顶层组视图记入对应页签，切换时整组显隐。
    func reg(_ view: UIView, tab: Int) {
        tabGroups[tab].append(view)
    }

    private func applyTabVisibility() {
        for (index, views) in tabGroups.enumerated() {
            views.forEach { $0.isHidden = index != selectedTab }
        }
        for (index, button) in tabButtons.enumerated() {
            let selected = index == selectedTab
            button.backgroundColor = selected ? FoliaUI.accent : FoliaUI.buttonFill
            button.setTitleColor(selected ? UIColor.white : FoliaUI.primary,
                                 for: .normal)
        }
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        selectTab(sender.tag)
    }

    private func selectTab(_ index: Int) {
        guard Self.tabTitles.indices.contains(index) else { return }
        selectedTab = index
        applyTabVisibility()
        Breadcrumbs.log("settings.tab index=\(index) name=\(Self.tabTitles[index])")
        if index == 3 {
            systemReduceMotionLabel.text =
                UIAccessibility.isReduceMotionEnabled ? "已开启" : "未开启"
        }
        if index == 9 { refreshCacheLabels() }
        if index == 10 { refreshMemoryLabel() }
    }

    private func styleSegmented(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = FoliaUI.accent
        control.setTitleTextAttributes(
            [.foregroundColor: FoliaUI.primary,
             .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor.white,
             .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
    }

    /// 分段行：标题 + 分段控件（纵向，与循环模式行同构造）。
    func makeSegmentedRow(_ title: String,
                                  _ control: UISegmentedControl,
                                  _ action: Selector) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = FoliaUI.primary
        track(label)
        styleSegmented(control)
        control.addTarget(self, action: action, for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    /// 组内整宽按钮行（与网易云账号按钮同构造）。
    func makeGroupButton(_ title: String, _ action: Selector) -> UIView {
        let wrap = UIView()
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(FoliaUI.accent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.backgroundColor = FoliaUI.buttonFill
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        if let titleLabel = button.titleLabel { track(titleLabel) }
        wrap.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            button.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -12),
            button.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            button.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
        return wrap
    }

    /// 只读「未接入」卡（(55) 补充定版形态）：纯文本行、次级
    /// 灰字、无任何可点控件/开关/箭头，与可操作行明确区分。
    /// 逐项 = 该页签未落的网页项 + 一句话原因，与交付报告
    /// 的逐签落点表口径一致。
    private func makeUnimplementedCard(_ items: [(String, String)]) -> UIView {
        let card = makeGroupCard()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let title = UILabel()
        title.text = "未接入（子系统未迁）"
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = FoliaUI.secondary
        track(title)
        stack.addArrangedSubview(title)
        for (name, reason) in items {
            let label = UILabel()
            label.text = "· \(name)——\(reason)"
            label.font = .systemFont(ofSize: 12)
            label.textColor = FoliaUI.secondary
            label.numberOfLines = 0
            track(label)
            stack.addArrangedSubview(label)
        }
        card.addArrangedSubview(stack)
        return card
    }

    /// (55) 新增页签组 + 每签未接入卡（在 buildLayout 末尾调，
    /// 未接入卡最后注册 → 恒在本签底部）。
    private func buildExtraTabs(into cardStack: UIStackView) {
        // —— 主页与歌单（速记簿把手三项；消费在速记簿把手，
        //    工作流 H 接线，键见 SettingsStore.SketchbookHandleKey）
        beginCheckGroup("主页与歌单")
        let sketchGroup = makeGroupCard()
        sketchGroup.addArrangedSubview(makeSwitchRow(
            "显示速记簿把手", sketchShowSwitch, #selector(sketchShowChanged)))
        sketchGroup.addArrangedSubview(makeHairline())
        let posRow = UIStackView()
        posRow.axis = .vertical
        posRow.spacing = 8
        posRow.isLayoutMarginsRelativeArrangement = true
        posRow.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let posHead = UIStackView()
        posHead.axis = .horizontal
        posHead.alignment = .center
        let posTitle = UILabel()
        posTitle.text = "把手高度"
        posTitle.font = .systemFont(ofSize: 15)
        posTitle.textColor = FoliaUI.primary
        track(posTitle)
        sketchPositionLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        sketchPositionLabel.textColor = FoliaUI.primary
        track(sketchPositionLabel)
        posHead.addArrangedSubview(posTitle)
        posHead.addArrangedSubview(UIView())
        posHead.addArrangedSubview(sketchPositionLabel)
        sketchPositionSlider.minimumValue = 0
        sketchPositionSlider.maximumValue = 1
        sketchPositionSlider.minimumTrackTintColor = FoliaUI.accent
        sketchPositionSlider.addTarget(
            self, action: #selector(sketchPositionChanged), for: .valueChanged)
        posRow.addArrangedSubview(posHead)
        posRow.addArrangedSubview(sketchPositionSlider)
        sketchGroup.addArrangedSubview(posRow)
        sketchGroup.addArrangedSubview(makeHairline())
        sketchGroup.addArrangedSubview(makeSegmentedRow(
            "把手样式", sketchStyleControl, #selector(sketchStyleChanged)))
        sketchGroup.addArrangedSubview(makeHairline())
        sketchGroup.addArrangedSubview(makeHintRow(
            "速记簿左缘把手：改动即时保存，把手下次出现时按新值呈现。高度 0% 在最上方、100% 贴近底部；样式为线 / 点 / 图形。"))
        cardStack.addArrangedSubview(sketchGroup)
        reg(sketchGroup, tab: 2)

        // —— 动画与性能
        beginCheckGroup("动画与性能")
        let gfxGroup = makeGroupCard()
        gfxGroup.addArrangedSubview(makeSegmentedRow(
            "歌词画布分辨率", renderScaleControl, #selector(renderScaleChanged)))
        gfxGroup.addArrangedSubview(makeHairline())
        gfxGroup.addArrangedSubview(makeInfoRow(
            title: "系统「减弱动态效果」", valueLabel: systemReduceMotionLabel))
        gfxGroup.addArrangedSubview(makeHairline())
        gfxGroup.addArrangedSubview(makeSwitchRow(
            "降低动态 · 跟随系统", reduceMotionSwitch, #selector(reduceMotionChanged)))
        gfxGroup.addArrangedSubview(makeHairline())
        gfxGroup.addArrangedSubview(makeHintRow(
            "跟随系统开启、且系统减弱动态效果打开时，设置页入场与关闭动画改为无动画直达（即时生效）。歌词画布分辨率档位即时生效于莫奈样式的歌词烘焙倍率（屏幕倍率 × 档位）。"))
        cardStack.addArrangedSubview(gfxGroup)
        reg(gfxGroup, tab: 3)

        // —— 播放控制
        beginCheckGroup("播放控制")
        let controlGroup = makeGroupCard()
        controlGroup.addArrangedSubview(makeSwitchRow(
            "无法播放自动跳过", autoSkipSwitch, #selector(autoSkipChanged)))
        controlGroup.addArrangedSubview(makeHairline())
        controlGroup.addArrangedSubview(makeSegmentedRow(
            "加入队列默认位置", queuePositionControl, #selector(queuePositionChanged)))
        controlGroup.addArrangedSubview(makeHairline())
        controlGroup.addArrangedSubview(makeHintRow(
            "自动跳过关掉后，点到确定无法播放的歌（VIP / 版权）会停住并给出提示，不再顺跳下一首。默认位置决定「加入队列」排到队尾还是插到下一首。"))
        cardStack.addArrangedSubview(controlGroup)
        reg(controlGroup, tab: 4)

        // —— 通用
        beginCheckGroup("通用")
        let generalGroup = makeGroupCard()
        generalGroup.addArrangedSubview(makeSwitchRow(
            "启动续播自动播放", autoPlaySwitch, #selector(autoPlayChanged)))
        generalGroup.addArrangedSubview(makeHairline())
        generalGroup.addArrangedSubview(makeHintRow(
            "开启后，冷启动时若有未过期的恢复队列，将自动装载并开始播放；关闭（默认）时恢复队列只留在播放台，打开舞台才装载且保持暂停。"))
        cardStack.addArrangedSubview(generalGroup)
        reg(generalGroup, tab: 6)

        // —— 快捷操作（无可操作行，仅说明 + 未接入卡）
        beginCheckGroup("快捷操作")
        let interactionNote = makeGroupCard()
        interactionNote.addArrangedSubview(makeHintRow(
            "命令面板本体已迁（点播台顶排「命令」键打开）；本页签的网页项是其上的槽位/快捷键定制层，依赖键盘场景，逐项见下方未接入清单。"))
        cardStack.addArrangedSubview(interactionNote)
        reg(interactionNote, tab: 7)

        // —— 存储与备份
        beginCheckGroup("存储与备份")
        let cacheGroup = makeGroupCard()
        cacheGroup.addArrangedSubview(makeInfoRow(
            title: "封面缓存", valueLabel: coverCacheLabel))
        cacheGroup.addArrangedSubview(makeGroupButton(
            "清除封面缓存", #selector(coverClearTapped)))
        cacheGroup.addArrangedSubview(makeHairline())
        cacheGroup.addArrangedSubview(makeInfoRow(
            title: "歌单数据缓存", valueLabel: apiCacheLabel))
        cacheGroup.addArrangedSubview(makeGroupButton(
            "清除歌单数据缓存", #selector(apiClearTapped)))
        cacheGroup.addArrangedSubview(makeHairline())
        cacheGroup.addArrangedSubview(makeInfoRow(
            title: "歌词缓存（内存）", valueLabel: lyricCacheLabel))
        cacheGroup.addArrangedSubview(makeGroupButton(
            "清除歌词缓存", #selector(lyricClearTapped)))
        cacheGroup.addArrangedSubview(makeHairline())
        cacheGroup.addArrangedSubview(makeHintRow(
            "大小为本地磁盘缓存的实际占用；清除后下次打开歌单、封面时会重新加载。歌词缓存为内存缓存，清除后下次播放重新拉取歌词。"))
        cardStack.addArrangedSubview(cacheGroup)
        reg(cacheGroup, tab: 9)
        let configGroup = makeGroupCard()
        configGroup.addArrangedSubview(makeGroupButton(
            "导出配置（配置码）", #selector(exportConfigTapped)))
        configGroup.addArrangedSubview(makeHairline())
        configGroup.addArrangedSubview(makeGroupButton(
            "导入配置", #selector(importConfigTapped)))
        configGroup.addArrangedSubview(makeHairline())
        configGroup.addArrangedSubview(makeHintRow(
            "配置码包含全部设置项，可复制保存、粘贴导入；不含登录状态与播放队列。导入后设置立即刷新。"))
        cardStack.addArrangedSubview(configGroup)
        reg(configGroup, tab: 9)

        // —— 开发者（端口 + 内存；桥日志按钮在主布局已注册）
        beginCheckGroup("开发者·内存")
        let devGroup = makeGroupCard()
        devGroup.addArrangedSubview(makeInfoRow(
            title: "本地服务端口", valueLabel: portLabel))
        devGroup.addArrangedSubview(makeHairline())
        devGroup.addArrangedSubview(makeInfoRow(
            title: "当前内存", valueLabel: memoryLabel))
        devGroup.addArrangedSubview(makeHairline())
        devGroup.addArrangedSubview(makeHintRow(
            "当前内存为进程常驻内存读数（mach_task_basic_info），打开设置或切到本页签时刷新。"))
        cardStack.addArrangedSubview(devGroup)
        reg(devGroup, tab: 10)

        // —— 帮助（发行说明 + 社区；壳版本行在主布局已注册）
        beginCheckGroup("帮助")
        let helpGroup = makeGroupCard()
        helpGroup.addArrangedSubview(makeGroupButton(
            "发行说明", #selector(releaseNotesTapped)))
        helpGroup.addArrangedSubview(makeHairline())
        helpGroup.addArrangedSubview(makeInfoRow(
            title: "社区 · QQ 群", valueLabel: qqGroupLabel))
        helpGroup.addArrangedSubview(makeGroupButton(
            "复制群号", #selector(qqCopyTapped)))
        helpGroup.addArrangedSubview(makeHairline())
        helpGroup.addArrangedSubview(makeHintRow(
            "QQ 群为网页版帮助页登记的社区群号，点「复制群号」后到 QQ 里搜索加入。"))
        cardStack.addArrangedSubview(helpGroup)
        reg(helpGroup, tab: 11)

        // —— 每签底部只读未接入卡（口径与交付报告逐签表一致）
        let unimplemented: [[(String, String)]] = [
            [("明暗模式", "界面恒深色设计，无明暗切换"),
             ("配色主题预设", "无配色主题系统"),
             ("主题乐园", "主题系统未迁"),
             ("歌曲主题自动切换 / 自动生成 / 生成来源 / 优先自定义", "无按歌主题系统"),
             ("场景与声线追踪", "场景系统未迁"),
             ("歌词动画样式工作台", "逐样式调参面板已随各样式迁入（样式选择器内点「调参」打开）；工作台本体（预览与调参一体）未迁")],
            [("播放后进入的视图", "点歌固定进舞台，无三选设置"),
             ("Lattice 暗角与海报叠色（5 项）", "Lattice 视图设置未迁"),
             ("舞台歌曲卡（显示方式 / 时长 / 位置 / 首页 / OBS）", "舞台歌曲卡本体未迁"),
             ("歌词后方视频层（URL / 不透明度 / 填充方式）", "自定义背景仅本地媒体，无 URL 与分层参数"),
             ("底部组件高度与拖动调整", "点播台高度两档写死"),
             ("隐藏底部控制条 / 字幕层 / 右侧按钮", "无对应设置面，字幕层本体未迁"),
             ("播放页顶栏模糊背景", "无此设置")],
            [("资料库界面（网格 / Bravais 墙）", "网格已落地（工具条布局钮切换）；设置层界面选择项未迁"),
             ("顶部胶囊入口显隐（总开关与 5 个页签）", "侧栏分区恒显，无显隐控制"),
             ("歌单卡片样式与网格卡片项（5 项）", "无网格视图本体"),
             ("记住主页卡片位置", "墙面位置不记忆"),
             ("墙面透光与信息条（8 项）", "墙后画面与信息条本体未迁")],
            [("静态模式", "无全局静态模式"),
             ("关闭主页动态背景", "无此开关"),
             ("播放页原生毛玻璃背景", "无此开关"),
             ("实验性动画帧率限制", "帧率写死，无设置"),
             ("歌词画布抗锯齿", "无此设置"),
             ("后台节流", "iOS 后台机制不同，无对应设置"),
             ("播放页触摸光效与密度", "触摸光效层未迁"),
             ("降低动态细分项（拼贴 / 过渡 / 展开转场 / Monet 漂移 / 设置滚动）", "对应动效本体未迁或无细分控制")],
            [("智能过渡（开关 / 模式 / 时长 / 表现 / 动画，7 项）", "引擎 B 轨未启用，无 crossfade / automix"),
             ("ReplayGain", "无增益链"),
             ("暂停 / 播放淡入淡出", "引擎未开放音量淡变入口，本包未接入"),
             ("自动转换无法播放的音频", "无转码兜底"),
             ("音频输出设备", "iOS 输出路由由系统接管"),
             ("播放时阻止休眠", "桌面语义，iOS 无对应设置"),
             ("语音输入时暂停", "无对应物")],
            [("自动使用最佳歌词", "取词链无此策略开关"),
             ("歌词匹配优先级", "只有 YRC / LRC 两级匹配，无来源优先级设置"),
             ("保留平台自带的逐字歌词", "原生恒用逐字（行为已在），无开关"),
             ("本地歌曲歌词优先级 / 本地歌词格式顺序", "无本地曲库本体"),
             ("歌词过滤（正则）", "未迁"),
             ("自动 AI 分词", "未迁")],
            [("界面语言", "文案写死简体中文，无语言切换"),
             ("启动后直接进入播放界面", "与冷启禁直达口径及入场流程冲突，未接入"),
             ("更新检查 / 自动更新 / 更新通道", "侧载分发无更新通道，更新管理器已退役"),
             ("思索教程提示 / 触屏思索按钮", "思索系统未迁")],
            [("快捷命令（固定命令槽位）", "命令面板已迁，槽位自定义未迁"),
             ("自定义快捷键", "iOS 无键盘场景，未迁"),
             ("向左滑动打开", "未迁"),
             ("海报墙 S 键打开命令窗口", "iOS 无键盘场景；命令面板由点播台命令键打开")],
            [("Navidrome 连接（开关 / 地址 / 用户名 / 密码）", "无 Navidrome 客户端"),
             ("同步服务 R2（开关 / 地址 / 令牌）", "无同步后端"),
             ("Discord 播放状态", "平台差异，未迁"),
             ("上报播放记录", "无 scrobble 上报"),
             ("播放页透明背景 / OBS 浏览器源 / OBS 保持动画", "直播场景未迁"),
             ("歌词接口", "歌词走自有代理，无接口设置"),
             ("舞台模式与舞台数据来源", "无外部舞台数据源"),
             ("PlayerCap（地址 / 播放器 / 时间轴 / 忽略清除）", "无 PlayerCap 后端")],
            [("媒体文件缓存与已缓存歌曲", "无媒体缓存体系"),
             ("分析数据 / 智能平衡数据缓存", "无对应缓存"),
             ("缓存目录 / 缓存上限", "iOS 沙盒固定，容量策略写死"),
             ("自动扫描已导入文件夹 / 文件夹监视", "无本地曲库本体"),
             ("歌词导出", "未迁")],
            [("运行日志（全量）", "只有桥日志已接入（最近 300 行），全量运行日志未迁"),
             ("写入本地文件", "未迁"),
             ("内存监控采样间隔", "内存为打开时读数，无采样设置")],
            [("思索帮助页", "思索系统未迁"),
             ("AI 帮助", "未迁"),
             ("大肥鱼陪伴", "QQ 机器人为外部系统，App 内无面板"),
             ("Discord 社区", "仅 QQ 群已接入")],
        ]
        for (tab, items) in unimplemented.enumerated() {
            let card = makeUnimplementedCard(items)
            cardStack.addArrangedSubview(card)
            reg(card, tab: tab)
        }
    }

    // MARK: (55) 新增动作

    @objc private func sketchShowChanged() {
        SettingsStore.sketchbookHandleShow = sketchShowSwitch.isOn
        Breadcrumbs.log("settings.sketchbookHandle show=\(sketchShowSwitch.isOn)")
    }

    @objc private func sketchPositionChanged() {
        let value = Double(sketchPositionSlider.value)
        SettingsStore.sketchbookHandlePosition = value
        sketchPositionLabel.text = "\(Int((value * 100).rounded()))%"
        Breadcrumbs.log("settings.sketchbookHandle position=\(String(format: "%.2f", value))")
    }

    @objc private func sketchStyleChanged() {
        let index = sketchStyleControl.selectedSegmentIndex
        guard index >= 0 else { return }
        SettingsStore.sketchbookHandleStyle = index
        Breadcrumbs.log("settings.sketchbookHandle style=\(index)")
    }

    @objc private func renderScaleChanged() {
        let index = renderScaleControl.selectedSegmentIndex
        guard Self.renderScales.indices.contains(index) else { return }
        SettingsStore.lyricRenderScale = Self.renderScales[index]
        Breadcrumbs.log("settings.lyricRenderScale value=\(Self.renderScales[index])")
    }

    @objc private func reduceMotionChanged() {
        SettingsStore.reduceMotionFollowSystem = reduceMotionSwitch.isOn
        Breadcrumbs.log("settings.reduceMotionFollowSystem value=\(reduceMotionSwitch.isOn)")
    }

    @objc private func autoSkipChanged() {
        SettingsStore.autoSkipUnplayableEnabled = autoSkipSwitch.isOn
        Breadcrumbs.log("settings.autoSkipUnplayable value=\(autoSkipSwitch.isOn)")
    }

    @objc private func queuePositionChanged() {
        let next = queuePositionControl.selectedSegmentIndex == 1
        SettingsStore.queueDefaultPosition = next ? "next" : "append"
        Breadcrumbs.log("settings.queueDefaultPosition value=\(next ? "next" : "append")")
    }

    @objc private func autoPlayChanged() {
        SettingsStore.autoPlayOnLaunch = autoPlaySwitch.isOn
        Breadcrumbs.log("settings.autoPlayOnLaunch value=\(autoPlaySwitch.isOn)")
    }

    @objc private func coverClearTapped() {
        let freed = SettingsCacheManager.clear(.cover)
        coverCacheLabel.text = SettingsCacheManager.sizeText(
            SettingsCacheManager.sizeBytes(for: .cover))
        Breadcrumbs.log("settings.cacheCover cleared freed=\(freed)")
    }

    @objc private func apiClearTapped() {
        let freed = SettingsCacheManager.clear(.api)
        apiCacheLabel.text = SettingsCacheManager.sizeText(
            SettingsCacheManager.sizeBytes(for: .api))
        Breadcrumbs.log("settings.cacheApi cleared freed=\(freed)")
    }

    /// 歌词内存缓存读数（条目数＋估算大小）。
    private func refreshLyricCacheLabel() {
        let stats = LyricRepository.shared.cacheStats
        lyricCacheLabel.text = "\(stats.count) 首 · "
            + SettingsCacheManager.sizeText(stats.bytes)
    }

    @objc private func lyricClearTapped() {
        LyricRepository.shared.clearAll()
        refreshLyricCacheLabel()
        Breadcrumbs.log("settings.cacheLyric cleared")
    }

    @objc private func exportConfigTapped() {
        let code = SettingsConfigTransfer.exportCode()
        Breadcrumbs.log("settings.config export len=\(code.count)")
        let page = SettingsTextPageViewController(
            title: "配置码（导出）", text: code)
        page.modalPresentationStyle = .overFullScreen
        present(page, animated: true)
    }

    @objc private func importConfigTapped() {
        let alert = UIAlertController(
            title: "导入配置",
            message: "粘贴配置码，导入后全部设置立即刷新。",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "配置码"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text,
                  let applied = SettingsConfigTransfer.importCode(text) else {
                let fail = UIAlertController(
                    title: "导入失败", message: "配置码无法解析，未改动任何设置。",
                    preferredStyle: .alert)
                fail.addAction(UIAlertAction(title: "好", style: .default))
                self?.present(fail, animated: true)
                return
            }
            self.refresh()
            let done = UIAlertController(
                title: "导入完成", message: "已写入 \(applied) 项设置。",
                preferredStyle: .alert)
            done.addAction(UIAlertAction(title: "好", style: .default))
            self.present(done, animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func releaseNotesTapped() {
        // (62) WC §4.12 动态化：标题与正文读 ReleaseNotes62
        // （版本自 Bundle，不再写死旧版号）。
        let page = SettingsTextPageViewController(
            title: "发行说明 · \(ReleaseNotes62.versionText)",
            text: ReleaseNotes62.bodyText)
        page.modalPresentationStyle = .overFullScreen
        present(page, animated: true)
    }

    @objc private func qqCopyTapped() {
        UIPasteboard.general.string = "1125072599"
        Breadcrumbs.log("settings.help qqCopied=1")
    }
}


/// 桥日志查看器（3.6 (3)）：全屏深色页展示桥日志尾部，支持整段复制。
/// 没有 Mac 连真机看日志的条件，诊断留痕只能靠这个页面人工带回。
final class BridgeLogViewController: UIViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = "桥日志（最近 300 行）"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        let copyButton = UIButton(type: .system)
        copyButton.setTitle("复制", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        copyButton.addTarget(self, action: #selector(copyAll), for: .touchUpInside)
        let doneButton = UIButton(type: .system)
        doneButton.setTitle("完成", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(copyButton)
        let spacer = UIView()
        spacer.widthAnchor.constraint(equalToConstant: 18).isActive = true
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(doneButton)
        view.addSubview(header)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textColor = UIColor.white.withAlphaComponent(0.85)
        textView.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        textView.isEditable = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])

        let text = FoliaBridgeLogStore.shared.recentLogText(maxLines: 300)
        textView.text = text.isEmpty ? "（暂无日志）" : text
        // 打开即滚到底，最新留痕在最下面。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let length = (self.textView.text as NSString).length
            if length > 0 {
                self.textView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
            }
        }
    }

    @objc private func copyAll() {
        UIPasteboard.general.string = textView.text
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

// MARK: - 3.7 (62) 全量迁移接线（四簇设置行构建入口，集成基座预置）
// 各簇在自己的新文件里实现 Settings62Cluster<X>.build(host:into:reg:)；
// 行工厂（makeGroupCard/makeSwitchRow 等）已去私有化供扩展文件调用；
// 控件一律用 UIAction 闭包接线，不依赖宿主存储属性。
extension SettingsViewController {
    func build62Tabs(into cardStack: UIStackView) {
        let regFn: (UIView, Int) -> Void = { [weak self] view, tab in
            self?.reg(view, tab: tab)
        }
        Settings62ClusterA.build(host: self, into: cardStack, reg: regFn)
        Settings62ClusterB.build(host: self, into: cardStack, reg: regFn)
        Settings62ClusterC.build(host: self, into: cardStack, reg: regFn)
        Settings62ClusterD.build(host: self, into: cardStack, reg: regFn)
    }
}
