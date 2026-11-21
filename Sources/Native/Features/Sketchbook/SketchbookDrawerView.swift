import UIKit
import Combine

// SketchbookDrawerView.swift
//
// 速记簿抽屉（(53) 工作流 D、(54) 工作流 N 把手照抄网页版、
// (55) 工作流 H 补全六大块；对应 folia-major 的 ScratchpadHost /
// ScratchpadEdge / ScratchpadPanel / ScratchpadQueue）：
// 把手照 ScratchpadEdge + scratchpad.css：常驻只露左缘一条小记号
// （形态/高度/显隐由三项设置决定，见 SketchbookHandleSettings；
// 缺省形态 = (54) 的米白小条，纵向落点 (60) 第 2 条起下限
// 115pt——避让缝合工具条，见 layoutSubviews），热区 46pt 宽、高
// clamp(96, 20%屏高−76, 168)；点热区先长出完整米白标签（42pt
// 宽，0.2s），再点标签才滑出非模态抽屉，标签闲置 2.5s 自动缩回。
//
// (55) H 后抽屉内的段落（自上而下）：总览（真实统计）、暂存
// （按用户分组分段、组头可折叠；列表/表格两形态，画布形态时
// 整幅换成 SketchbookCanvasView）、队列草稿（从暂存编的独立
// 顺序，一键替换当前队列）、当前播放队列（原段，不动）、
// 历史（收进/移除按天分段）。工具栏在标题行下：形态切换
// （列表/画布/表格）＋「＋组」新建分组。
//
// 非模态做法：本视图铺满宿主，但 hitTest 只认把手（关时）与
// 抽屉（开时），其余一律返回 nil 穿透给墙；抽屉外点按关闭靠
// 挂在宿主上的旁观点击识别器（cancelsTouchesInView=false，
// 只看不拦，墙的 pan/点按照常收触摸）。开合动画用
// UISpringTimingParameters 系统弹簧（dampingRatio 0.86），
// 与全工程 iOS 原生动效口径一致。
//
// 点播漏斗（不新造队列逻辑）：暂存行/画布卡 → QueueManager
// .insertAndPlay（网页版 playNow 同语义）；队列行 → playAtIndex；
// 队列移除 → removeFromQueue；草稿替换 → setQueue（整队替换
// 并从第一首开播）。全部走 QueueManager.shared 既有 API。

final class SketchbookDrawerView: UIView {

    private let store = SketchbookStore.shared
    private let queueManager = QueueManager.shared

    private(set) var isOpen = false

    // 把手（照网页版 ScratchpadEdge）：透明热区（点按展开标签）、
    // 常驻记号（三档形态各一份视图，按设置显隐）、完整米白标签。
    private let edgeHotButton = UIButton(type: .custom)
    private let restStrip = UIView()
    private let restMark = UIView()
    private let restDot = UIView()
    private let restShapes = UIView()
    private let restShapeCircle = SketchbookRestShapeView()
    private let restShapeTriangle = SketchbookRestShapeView()
    private let restShapeChevron = SketchbookRestShapeView()
    private let expandedHandle = UIButton(type: .custom)
    private let expandedTopMark = UIView()
    private let expandedCircle = UIView()
    private let expandedTitleLabel = UILabel()
    private let expandedCountBadge = UIView()
    private let expandedCountLabel = UILabel()
    private let expandedBottomCircle = UIView()
    private(set) var isHandleExpanded = false
    /// 被外部浮层盖住（书库侧栏打开等）：照网页版 is-covered
    /// 整个藏起来，把手与抽屉都不许浮压其上。
    private(set) var isExternallyCovered = false
    private var handleIdleWorkItem: DispatchWorkItem?
    private var lastEntryCount: Int?
    private var handleSettings = SketchbookHandleSettings.read()
    private var defaultsObserver: NSObjectProtocol?

    /// 网页版配色（scratchpadLook.ts）：米白纸 / 黑墨 / 纸上红。
    private static let paperColor = UIColor(
        red: 0.957, green: 0.941, blue: 0.902, alpha: 1) // #F4F0E6
    private static let inkColor = UIColor(
        red: 0.078, green: 0.078, blue: 0.078, alpha: 1) // #141414
    private static let markColor = UIColor(
        red: 0.769, green: 0.208, blue: 0.129, alpha: 1) // #C43521
    private static let edgeWidth: CGFloat = 46
    private static let expandedHandleWidth: CGFloat = 42
    private static let expandedHandleHeight: CGFloat = 162
    private let drawerView = UIView()
    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(
        items: ["列表", "画布", "表格"])
    private let newGroupButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let canvasView = SketchbookCanvasView()

    private var cancellables = Set<AnyCancellable>()
    private var clearConfirmDeadline: Date?
    private var applyDraftDeadline: Date?
    private weak var outsideTapRecognizer: UITapGestureRecognizer?

    private static let drawerMaxWidth: CGFloat = 330

    /// 暂存的呈现形态（工具栏切换；画布时整幅换画布）。
    private enum NotesMode: Int {
        case list = 0
        case canvas = 1
        case table = 2
    }
    private var notesMode: NotesMode = .list

    /// 抽屉段落模型（refresh 时按 Store 现状重建）。
    private enum DrawerSection {
        case overview
        /// (62) 自动来源组（组头分「自动/我的分组」两段：自动
        /// 段在未分组之后、用户组之前）。
        case autoGroup(key: String)
        case group(id: String?)
        case draft
        case queue
        case historyDay(start: TimeInterval)
        /// 还没有任何历史事件时的空态段（如实说明从现在起记）。
        case historyEmpty
    }
    private var sections: [DrawerSection] = []
    private var historyDays: [(dayStart: TimeInterval,
                                events: [SketchbookStore.HistoryEvent])] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildViews()
        bindState()
        observeHandleSettings()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViews()
        bindState()
        observeHandleSettings()
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    // MARK: - 搭建

    private func buildViews() {
        backgroundColor = .clear

        // 左缘把手（照网页版）：热区透明、只承接点按；常驻记号
        // 三档（线=米白小条/点=圆点/图形=三颗记号）按设置显隐。
        edgeHotButton.backgroundColor = .clear
        edgeHotButton.accessibilityLabel = "速记簿"
        edgeHotButton.addTarget(
            self, action: #selector(edgeHotTapped), for: .touchUpInside)
        addSubview(edgeHotButton)

        restStrip.backgroundColor = Self.paperColor
        restStrip.alpha = 0.4
        restStrip.isUserInteractionEnabled = false
        addSubview(restStrip)
        restMark.backgroundColor = Self.markColor
        restMark.isUserInteractionEnabled = false
        restStrip.addSubview(restMark)

        restDot.backgroundColor = Self.markColor
        restDot.layer.cornerRadius = 7
        restDot.alpha = 0.55
        restDot.isUserInteractionEnabled = false
        restDot.isHidden = true
        addSubview(restDot)

        restShapeCircle.kind = .circle
        restShapeCircle.fillColor = Self.markColor
        restShapeTriangle.kind = .triangle
        restShapeTriangle.fillColor = Self.paperColor
        restShapeChevron.kind = .chevron
        restShapeChevron.fillColor = Self.paperColor
        restShapes.alpha = 0.45
        restShapes.isUserInteractionEnabled = false
        restShapes.isHidden = true
        restShapes.addSubview(restShapeCircle)
        restShapes.addSubview(restShapeTriangle)
        restShapes.addSubview(restShapeChevron)
        addSubview(restShapes)

        // 完整标签：米白纸、4pt 红顶边、圆形记号、竖排「速记簿」、
        // 红色计数斜块、底部线框圆（ScratchpadEdge 的 handle-body）。
        expandedHandle.backgroundColor = Self.paperColor
        expandedHandle.accessibilityLabel = "打开速记簿"
        expandedHandle.addTarget(
            self, action: #selector(expandedHandleTapped),
            for: .touchUpInside)
        expandedHandle.isHidden = true
        addSubview(expandedHandle)
        expandedTopMark.backgroundColor = Self.markColor
        expandedTopMark.isUserInteractionEnabled = false
        expandedHandle.addSubview(expandedTopMark)
        expandedCircle.backgroundColor = Self.markColor
        expandedCircle.layer.cornerRadius = 7
        expandedCircle.isUserInteractionEnabled = false
        expandedHandle.addSubview(expandedCircle)
        expandedTitleLabel.text = "速\n记\n簿"
        expandedTitleLabel.font = .systemFont(ofSize: 15, weight: .black)
        expandedTitleLabel.textColor = Self.inkColor
        expandedTitleLabel.textAlignment = .center
        expandedTitleLabel.numberOfLines = 3
        expandedTitleLabel.isUserInteractionEnabled = false
        expandedHandle.addSubview(expandedTitleLabel)
        expandedCountBadge.backgroundColor = Self.markColor
        // 构成主义斜块：整体斜 -14°，里面的字摆正（css 同口径）。
        expandedCountBadge.transform = CGAffineTransform(
            a: 1, b: 0, c: CGFloat(tan(-14 * Double.pi / 180)),
            d: 1, tx: 0, ty: 0)
        expandedCountBadge.isUserInteractionEnabled = false
        expandedCountBadge.isHidden = true
        expandedHandle.addSubview(expandedCountBadge)
        expandedCountLabel.font = .systemFont(ofSize: 12, weight: .black)
        expandedCountLabel.textColor = Self.paperColor
        expandedCountLabel.textAlignment = .center
        expandedCountLabel.transform = CGAffineTransform(
            a: 1, b: 0, c: CGFloat(tan(14 * Double.pi / 180)),
            d: 1, tx: 0, ty: 0)
        expandedCountLabel.isUserInteractionEnabled = false
        expandedCountBadge.addSubview(expandedCountLabel)
        expandedBottomCircle.backgroundColor = .clear
        expandedBottomCircle.layer.cornerRadius = 6
        expandedBottomCircle.layer.borderWidth = 2
        expandedBottomCircle.layer.borderColor = Self.inkColor.cgColor
        expandedBottomCircle.isUserInteractionEnabled = false
        expandedHandle.addSubview(expandedBottomCircle)

        // 抽屉本体：(62) §7 纸面造型——整面改米白纸色（与把手
        // paperColor 同源），深色字适配随本文件各行/组头改 ink
        // 系；开抽屉时整体轻倾斜 0.7°（见 setOpen）。
        drawerView.backgroundColor = Self.paperColor
        drawerView.isHidden = true
        addSubview(drawerView)

        titleLabel.text = "速记簿"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Self.inkColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(titleLabel)

        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 13)
        clearButton.setTitleColor(
            Self.inkColor.withAlphaComponent(0.65), for: .normal)
        clearButton.addTarget(
            self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(clearButton)

        closeButton.setImage(
            UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.tintColor = Self.inkColor.withAlphaComponent(0.8)
        closeButton.accessibilityLabel = "收起速记簿"
        closeButton.addTarget(
            self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(closeButton)

        // 工具栏：形态切换 + 新建组。
        modeControl.selectedSegmentIndex = 0
        modeControl.backgroundColor = Self.inkColor.withAlphaComponent(0.06)
        modeControl.selectedSegmentTintColor =
            Self.inkColor.withAlphaComponent(0.16)
        modeControl.setTitleTextAttributes(
            [.foregroundColor: Self.inkColor.withAlphaComponent(0.75),
             .font: UIFont.systemFont(ofSize: 12.5)], for: .normal)
        modeControl.setTitleTextAttributes(
            [.foregroundColor: Self.inkColor,
             .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold)],
            for: .selected)
        modeControl.addTarget(
            self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(modeControl)

        newGroupButton.setTitle("＋组", for: .normal)
        newGroupButton.titleLabel?.font = .systemFont(ofSize: 13)
        newGroupButton.setTitleColor(
            Self.inkColor.withAlphaComponent(0.8), for: .normal)
        newGroupButton.accessibilityLabel = "新建分组"
        newGroupButton.addTarget(
            self, action: #selector(newGroupTapped), for: .touchUpInside)
        newGroupButton.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(newGroupButton)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.sectionFooterHeight = 6
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            SketchbookRowCell.self,
            forCellReuseIdentifier: SketchbookRowCell.reuseId)
        tableView.register(
            SketchbookTableRowCell.self,
            forCellReuseIdentifier: SketchbookTableRowCell.reuseId)
        tableView.register(
            SketchbookTextCell.self,
            forCellReuseIdentifier: SketchbookTextCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(tableView)

        canvasView.isHidden = true
        canvasView.onPlayTrack = { [weak self] track in
            self?.queueManager.insertAndPlay(track)
            Breadcrumbs.log("sketchbook.play source=canvas id=\(track.id)")
        }
        canvasView.onRemoveTrack = { [weak self] trackId in
            self?.store.remove(trackId: trackId, source: "canvas")
        }
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(canvasView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: drawerView.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(
                equalTo: drawerView.leadingAnchor, constant: 16),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(
                equalTo: drawerView.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor, constant: -4),

            modeControl.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: 10),
            modeControl.leadingAnchor.constraint(
                equalTo: drawerView.leadingAnchor, constant: 16),
            modeControl.widthAnchor.constraint(equalToConstant: 168),

            newGroupButton.centerYAnchor.constraint(
                equalTo: modeControl.centerYAnchor),
            newGroupButton.leadingAnchor.constraint(
                equalTo: modeControl.trailingAnchor, constant: 10),
            newGroupButton.widthAnchor.constraint(equalToConstant: 48),

            tableView.topAnchor.constraint(
                equalTo: modeControl.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: drawerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: drawerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: drawerView.bottomAnchor),

            canvasView.topAnchor.constraint(
                equalTo: modeControl.bottomAnchor, constant: 6),
            canvasView.leadingAnchor.constraint(equalTo: drawerView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: drawerView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: drawerView.bottomAnchor),
        ])
        rebuildSections()
        updateHandleVisibility()
    }

    private func bindState() {
        store.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        store.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        store.$history
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        store.$draft
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        queueManager.$queue
            .combineLatest(queueManager.$currentIndex)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    /// 空态贴纸小图（懒建）。(62) 时作表背景居中浮在列表
    /// 上、正压「队列草稿」行；(65) B 组（Miller 17:05 截
    /// 图指令）改固定挂面板左下角：直接作 drawerView 子
    /// 视图、约束钉左下（距左 14、距安全区底 14、84×84），
    /// 不压任何文字行；显隐由 refresh 按条目数切换，显示
    /// 时列表底部补内边距让最后一行滚得过猫。横竖屏与面
    /// 板展开/收起都走同一组约束（锚点在 drawerView 上），
    /// 位置口径一致。
    private lazy var cornerCatView65: UIView = {
        let imageView = UIImageView()
        if let url = Bundle.main.url(forResource: "cat-02",
                                     withExtension: "png",
                                     subdirectory: "Stickers") {
            imageView.image = UIImage(contentsOfFile: url.path)
        }
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        drawerView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(
                equalTo: drawerView.leadingAnchor, constant: 14),
            imageView.bottomAnchor.constraint(
                equalTo: drawerView.safeAreaLayoutGuide.bottomAnchor,
                constant: -14),
            imageView.widthAnchor.constraint(equalToConstant: 84),
            imageView.heightAnchor.constraint(equalToConstant: 84),
        ])
        drawerView.bringSubviewToFront(imageView)
        return imageView
    }()

    private func refresh() {
        let count = store.entries.count
        // (65) B 组：空态猫改面板左下角固定（cornerCatView65），
        // 不再作列表背景居中压行；显示时给列表底部补 98pt
        // 内边距（猫 84 + 上下各 7），最后一行可滚到猫之上。
        cornerCatView65.isHidden = count != 0
        tableView.contentInset.bottom = count == 0 ? 98 : 0
        expandedCountBadge.isHidden = count == 0
        expandedCountLabel.text = "\(count)"
        titleLabel.text = count > 0 ? "速记簿 · \(count)" : "速记簿"
        // 新收进一批时常驻记号闪一下（网页版 addNonce → is-pulsing
        // 0.9s：亮到不透明、放大 1.5 倍再回去，Host.tsx/css）。
        if let last = lastEntryCount, count > last { pulseRestMark() }
        lastEntryCount = count
        resetClearConfirm()
        rebuildSections()
        tableView.reloadData()
        if notesMode == .canvas { canvasView.reload() }
    }

    private func rebuildSections() {
        historyDays = store.historyByDay()
        var next: [DrawerSection] = [.overview, .group(id: nil)]
        // (62) 自动来源组段（非空才出现）。
        for auto in store.autoGroups62 { next.append(.autoGroup(key: auto.key)) }
        for group in store.groups { next.append(.group(id: group.id)) }
        next.append(.draft)
        next.append(.queue)
        if historyDays.isEmpty {
            next.append(.historyEmpty)
        } else {
            for day in historyDays {
                next.append(.historyDay(start: day.dayStart))
            }
        }
        sections = next
    }

    /// 当前形态下亮着的那份常驻记号（脉冲动画用）。
    private var activeRestView: UIView {
        switch handleSettings.style {
        case .strip: return restStrip
        case .dot: return restDot
        case .shapes: return restShapes
        }
    }

    private var restBaseAlpha: CGFloat {
        switch handleSettings.style {
        case .strip: return 0.4
        case .dot: return 0.55
        case .shapes: return 0.45
        }
    }

    private func pulseRestMark() {
        guard !isOpen, !isExternallyCovered, !isHandleExpanded,
              handleSettings.show else { return }
        Breadcrumbs.log("sketchbook.handle pulse")
        let target = activeRestView
        let base = restBaseAlpha
        UIView.animateKeyframes(withDuration: 0.9, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) {
                target.alpha = 1
                target.transform = CGAffineTransform(scaleX: 1.5, y: 1)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.75) {
                target.alpha = base
                target.transform = .identity
            }
        }
    }

    // MARK: - 把手三项设置消费

    private func observeHandleSettings() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.applyHandleSettings(source: "defaultsChanged")
        }
    }

    /// 现读三键：变了才动（UserDefaults 变更通知很密，无变化直接
    /// 返回）。布局里也调一次（source=layout），保证任何路径下
    /// 都是最新值。
    private func applyHandleSettings(source: String) {
        let next = SketchbookHandleSettings.read()
        let changed = next != handleSettings
        handleSettings = next
        if changed {
            Breadcrumbs.log(
                "sketchbook.handle settings source=\(source) show=\(next.show) pos=\(next.position) style=\(next.style.rawValue)")
            setNeedsLayout()
        }
        // 显隐每次都按现值推导（首帧布局也要生效，不能只等变化）。
        updateHandleVisibility()
    }

    // MARK: - 布局与命中穿透

    /// 热区高度（网页版 --scratchpad-edge-height:
    /// clamp(96px, 20vh - 76px, 168px)）。
    private var edgeHeight: CGFloat {
        min(168, max(96, bounds.height * 0.20 - 76))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyHandleSettings(source: "layout")
        let edgeHeight = self.edgeHeight
        // 把手高度锚点（设置 position，缺省 0 = top 72 = 旧行为）。
        // (60) 第 2 条下限：与缝合工具条干涉根治——edgeTop 缺省
        // 落点不得高于 115（工具条底边 107 + 8 间距），展开把手
        // 同用本值随之下移；用户 position 设置推得更低时照常
        // 更低，本下限只抬不降。
        let edgeTop = max(115, SketchbookHandleSettings.edgeTop(
            position: handleSettings.position,
            containerHeight: bounds.height, edgeHeight: edgeHeight))
        // 安全区避让（3.7 (54) iOS 适配自查补修）：把手三件套的
        // 横向锚点取 safeAreaInsets.left——竖屏恒 0、与网页版
        // 贴左缘口径逐点一致；横屏灵动岛转到左侧时 inset≈59，
        // 把手整体右移让开岛体，不被压住；岛在右侧时 inset=0
        // 保持贴边。抽屉本体全幅出血不避（系统面板惯例）。
        // position 在横屏同样成立：公式按当前 bounds.height 算。
        let edgeX = safeAreaInsets.left
        edgeHotButton.frame = CGRect(
            x: edgeX, y: edgeTop, width: Self.edgeWidth, height: edgeHeight)
        // 常驻记号在热区内竖直居中（css .scratchpad-edge-rest）。
        restStrip.frame = CGRect(
            x: edgeX, y: edgeTop + (edgeHeight - 56) / 2,
            width: 6, height: 56)
        restMark.frame = CGRect(x: 0, y: 0, width: 6, height: 2)
        // 圆点骑在左缘上（网页版 marginLeft -7：圆心落在缘线上）。
        restDot.frame = CGRect(
            x: edgeX - 7, y: edgeTop + (edgeHeight - 14) / 2,
            width: 14, height: 14)
        restShapes.frame = CGRect(
            x: edgeX + 4, y: edgeTop + (edgeHeight - 36) / 2,
            width: 8, height: 36)
        restShapeCircle.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
        restShapeTriangle.frame = CGRect(x: 0, y: 14, width: 8, height: 8)
        restShapeChevron.frame = CGRect(x: 0, y: 28, width: 8, height: 8)
        expandedHandle.frame = CGRect(
            x: edgeX, y: edgeTop,
            width: Self.expandedHandleWidth,
            height: Self.expandedHandleHeight)
        expandedTopMark.frame = CGRect(
            x: 0, y: 0, width: Self.expandedHandleWidth, height: 4)
        expandedCircle.frame = CGRect(x: 14, y: 14, width: 14, height: 14)
        expandedTitleLabel.frame = CGRect(x: 0, y: 38, width: 42, height: 58)
        expandedCountBadge.frame = CGRect(x: 5, y: 106, width: 32, height: 22)
        expandedCountLabel.frame = expandedCountBadge.bounds
        expandedBottomCircle.frame = CGRect(x: 15, y: 138, width: 12, height: 12)
        let width = min(Self.drawerMaxWidth, bounds.width * 0.86)
        drawerView.frame = CGRect(
            x: isOpen ? 0 : -width, y: 0, width: width, height: bounds.height)
    }

    /// 只认热区/完整标签（关时）与抽屉（开时）；其余穿透给墙，
    /// 不挡任何操作。被外部盖住时整层不接命中。把手设置
    /// show=false 时把手三件全藏（isHidden），这里自然穿透；
    /// 抽屉已开时不受 show 影响，照常可关可操作。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isExternallyCovered { return nil }
        if isOpen {
            guard drawerView.frame.contains(point) else { return nil }
            return drawerView.hitTest(
                convert(point, to: drawerView), with: event)
        }
        if isHandleExpanded, !expandedHandle.isHidden,
           expandedHandle.frame.contains(point) {
            return expandedHandle.hitTest(
                convert(point, to: expandedHandle), with: event)
        }
        guard !edgeHotButton.isHidden,
              edgeHotButton.frame.contains(point) else { return nil }
        return edgeHotButton.hitTest(
            convert(point, to: edgeHotButton), with: event)
    }

    /// 把手三件的显隐只由这一处按（开抽屉 / 被盖住 / 标签展开 /
    /// 设置 show / 设置 style）推导，不许各处散着改 isHidden 打架。
    private func updateHandleVisibility() {
        let clusterHidden = isOpen || isExternallyCovered
            || !handleSettings.show
        edgeHotButton.isHidden = clusterHidden || isHandleExpanded
        let restHidden = clusterHidden || isHandleExpanded
        restStrip.isHidden = restHidden || handleSettings.style != .strip
        restDot.isHidden = restHidden || handleSettings.style != .dot
        restShapes.isHidden = restHidden || handleSettings.style != .shapes
        expandedHandle.isHidden = clusterHidden || !isHandleExpanded
    }

    // MARK: - 把手展开/收起（网页版悬停长出标签的触屏等价）

    @objc private func edgeHotTapped() {
        expandHandle(source: "tap")
    }

    @objc private func expandedHandleTapped() {
        cancelHandleIdleTimer()
        setOpen(true, source: "handle")
    }

    /// 点热区：完整标签从常驻记号长出来（0.2s，亮度从常驻
    /// 透明度到 1，照 css .scratchpad-handle-paper 的过渡）。
    private func expandHandle(source: String) {
        guard !isOpen, !isExternallyCovered, !isHandleExpanded,
              handleSettings.show else { return }
        isHandleExpanded = true
        Breadcrumbs.log("sketchbook.handle expand source=\(source)")
        expandedHandle.alpha = restBaseAlpha
        updateHandleVisibility()
        UIView.animate(withDuration: 0.2, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.expandedHandle.alpha = 1
        }
        scheduleHandleRetract()
    }

    /// 闲置收起：网页版指针离开热区后标签缩回；触屏等价为展开
    /// 后 2.5s 无操作自动缩回（Miller 口径「不滑动的时候收起」）。
    private func scheduleHandleRetract() {
        cancelHandleIdleTimer()
        let work = DispatchWorkItem { [weak self] in
            self?.retractHandle(source: "idleTimeout")
        }
        handleIdleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func cancelHandleIdleTimer() {
        handleIdleWorkItem?.cancel()
        handleIdleWorkItem = nil
    }

    private func retractHandle(source: String) {
        guard isHandleExpanded, !isOpen else { return }
        isHandleExpanded = false
        cancelHandleIdleTimer()
        Breadcrumbs.log("sketchbook.handle retract source=\(source)")
        UIView.animate(withDuration: 0.2, delay: 0.2,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.expandedHandle.alpha = self.restBaseAlpha
        } completion: { [weak self] _ in
            guard let self, !self.isHandleExpanded else { return }
            self.expandedHandle.alpha = 1
            self.updateHandleVisibility()
        }
    }

    /// 外部浮层（书库侧栏等）盖住墙面时调用：照网页版
    /// is-covered 整个藏起来——把手不许浮压侧栏，抽屉开着也
    /// 一并藏（状态保留，盖住解除后原样回来）。HomeWall 合流
    /// 接法见 SketchbookHost 注释。
    func setExternallyCovered(_ covered: Bool) {
        guard covered != isExternallyCovered else { return }
        isExternallyCovered = covered
        Breadcrumbs.log("sketchbook.covered \(covered)")
        if covered {
            cancelHandleIdleTimer()
            isHandleExpanded = false
            expandedHandle.alpha = 1
        }
        isHidden = covered
        updateHandleVisibility()
    }

    // MARK: - 开合

    /// 挂到宿主后由 SketchbookHost 调用：旁观宿主上的点击，
    /// 点在抽屉与把手之外时收起抽屉（只看不拦，cancelsTouchesInView
    /// =false，墙照常收到这一下）。
    func observeOutsideTaps(on host: UIView) {
        let recognizer = UITapGestureRecognizer(
            target: self, action: #selector(hostTapped(_:)))
        recognizer.cancelsTouchesInView = false
        host.addGestureRecognizer(recognizer)
        outsideTapRecognizer = recognizer
    }

    @objc private func hostTapped(_ recognizer: UITapGestureRecognizer) {
        guard isOpen, !isExternallyCovered else { return }
        let point = recognizer.location(in: self)
        if drawerView.frame.contains(point)
            || edgeHotButton.frame.contains(point)
            || expandedHandle.frame.contains(point) { return }
        setOpen(false, source: "outsideTap")
    }

    @objc private func closeTapped() {
        setOpen(false, source: "closeButton")
    }

    func setOpen(_ open: Bool, source: String) {
        guard open != isOpen else { return }
        isOpen = open
        Breadcrumbs.log("sketchbook.drawer open=\(open) source=\(source)")
        let width = min(Self.drawerMaxWidth, bounds.width * 0.86)
        if open {
            // 抽屉开着时把手整个不在场（网页版 !isOpen 才渲染
            // ScratchpadEdge，Host.tsx 同口径）。
            cancelHandleIdleTimer()
            isHandleExpanded = false
            expandedHandle.alpha = 1
            updateHandleVisibility()
            drawerView.isHidden = false
            drawerView.frame = CGRect(
                x: -width, y: 0, width: width, height: bounds.height)
            refresh()
            if notesMode == .canvas { canvasView.reload() }
        }
        let animator = UIViewPropertyAnimator(
            duration: 0.55,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.86))
        animator.addAnimations { [weak self] in
            guard let self else { return }
            self.drawerView.frame = CGRect(
                x: open ? 0 : -width, y: 0,
                width: width, height: self.bounds.height)
            // (62) 纸面轻倾斜：开 0.7°、收回正（scratchpadTilt 等价）。
            self.drawerView.transform = open
                ? CGAffineTransform(rotationAngle: 0.7 * .pi / 180)
                : .identity
        }
        animator.addCompletion { [weak self] _ in
            guard let self, !self.isOpen else { return }
            self.drawerView.isHidden = true
            self.updateHandleVisibility()
        }
        animator.startAnimation()
    }

    // MARK: - 形态切换 / 新建组

    @objc private func modeChanged() {
        guard let mode = NotesMode(rawValue: modeControl.selectedSegmentIndex)
        else { return }
        notesMode = mode
        Breadcrumbs.log("sketchbook.mode \(mode)")
        let isCanvas = mode == .canvas
        canvasView.isHidden = !isCanvas
        tableView.isHidden = isCanvas
        if isCanvas {
            canvasView.reload()
        } else {
            tableView.reloadData()
        }
    }

    @objc private func newGroupTapped() {
        presentTextPrompt(
            title: "新建分组", placeholder: "分组名",
            confirmTitle: "创建") { [weak self] name in
            self?.store.createGroup(name: name ?? "")
        }
    }

    // MARK: - 清空（两下确认，照网页版 3 秒口径）

    private func resetClearConfirm() {
        clearConfirmDeadline = nil
        clearButton.setTitle("清空", for: .normal)
        clearButton.setTitleColor(
            Self.inkColor.withAlphaComponent(0.65), for: .normal)
    }

    @objc private func clearTapped() {
        if let deadline = clearConfirmDeadline, deadline > Date() {
            store.clear(source: "drawer")
            return
        }
        clearConfirmDeadline = Date().addingTimeInterval(3)
        clearButton.setTitle("确认清空？", for: .normal)
        clearButton.setTitleColor(
            UIColor(red: 1, green: 0.42, blue: 0.42, alpha: 1), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self,
                  let deadline = self.clearConfirmDeadline,
                  deadline <= Date() else { return }
            self.resetClearConfirm()
        }
    }

    // MARK: - 草稿替换当前队列（两下确认）

    private func applyDraftTapped() {
        guard !store.draft.isEmpty else { return }
        if let deadline = applyDraftDeadline, deadline > Date() {
            applyDraftDeadline = nil
            let tracks = store.draft
            queueManager.setQueue(
                tracks, startingAt: 0, source: "sketchbook-draft")
            Breadcrumbs.log("sketchbook.draft apply n=\(tracks.count)")
            tableView.reloadData()
            return
        }
        applyDraftDeadline = Date().addingTimeInterval(3)
        tableView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self,
                  let deadline = self.applyDraftDeadline,
                  deadline <= Date() else { return }
            self.applyDraftDeadline = nil
            self.tableView.reloadData()
        }
    }

    // MARK: - 弹窗（分组相关）

    private func topPresenter() -> UIViewController? {
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    private func presentTextPrompt(
        title: String, placeholder: String, confirmTitle: String,
        onConfirm: @escaping (String?) -> Void
    ) {
        guard let presenter = topPresenter() else { return }
        let alert = UIAlertController(
            title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = placeholder
        }
        alert.addAction(UIAlertAction(
            title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(
            title: confirmTitle, style: .default) { _ in
            onConfirm(alert.textFields?.first?.text)
        })
        presenter.present(alert, animated: true)
    }

    /// 条目「移到分组」选单：未分组 + 每个用户组。
    private func presentGroupPicker(for entry: SketchbookStore.Entry) {
        guard let presenter = topPresenter() else { return }
        let alert = UIAlertController(
            title: "移到分组", message: entry.track.title,
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(
            title: "未分组", style: .default) { [weak self] _ in
            self?.store.assign(
                trackId: entry.track.id, toGroup: nil, source: "drawer")
        })
        for group in store.groups {
            alert.addAction(UIAlertAction(
                title: group.name, style: .default) { [weak self] _ in
                self?.store.assign(
                    trackId: entry.track.id, toGroup: group.id,
                    source: "drawer")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = drawerView
            popover.sourceRect = drawerView.bounds
        }
        presenter.present(alert, animated: true)
    }

    private func confirmDeleteGroup(_ group: SketchbookStore.Group) {
        guard let presenter = topPresenter() else { return }
        let alert = UIAlertController(
            title: "删除分组「\(group.name)」？",
            message: "组里的歌回到未分组，不会删歌。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(
            title: "删除", style: .destructive) { [weak self] _ in
            self?.store.deleteGroup(id: group.id, source: "drawer")
        })
        presenter.present(alert, animated: true)
    }
}

// MARK: - 段落与行

extension SketchbookDrawerView: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        switch sections[section] {
        case .overview:
            return 1
        case .group(let groupId):
            if let groupId, store.group(id: groupId)?.collapsed == true {
                return 0
            }
            let count = store.entries(inGroup: groupId).count
            // 表格形态多一行列头。
            return notesMode == .table && count > 0 ? count + 1 : count
        case .autoGroup(let key):
            return store.entries(inAutoGroup: key).count
        case .draft:
            return store.draft.count
        case .queue:
            return queueManager.queue.count
        case .historyDay(let start):
            return historyDays.first { $0.dayStart == start }?.events.count ?? 0
        case .historyEmpty:
            return 1
        }
    }

    func tableView(
        _ tableView: UITableView, titleForHeaderInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .queue:
            return queueManager.queue.isEmpty
                ? "当前队列（空）" : "当前队列 · \(queueManager.queue.count)"
        case .historyDay(let start):
            return "历史 · \(Self.historyDayTitle(start: start))"
        case .historyEmpty:
            return "历史"
        default:
            return nil
        }
    }

    func tableView(
        _ tableView: UITableView, viewForHeaderInSection section: Int
    ) -> UIView? {
        switch sections[section] {
        case .overview:
            return SketchbookSectionHeaderView(
                title: "总览", detail: nil, buttons: [])
        case .group(let groupId):
            let name = groupId == nil
                ? "未分组"
                : (store.group(id: groupId ?? "")?.name ?? "分组")
            let collapsed = groupId.flatMap {
                store.group(id: $0)?.collapsed
            } ?? false
            let count = store.entries(inGroup: groupId).count
            // 未分组段没有折叠状态（网页版组头折叠只对成组段），
            // 只给用户组折叠钮；未分组段给新建组钮。
            var buttons: [SketchbookSectionHeaderView.Button] = []
            if let groupId {
                buttons.append(.init(
                    title: collapsed ? "展开" : "折叠",
                    accessibilityLabel: collapsed ? "展开分组" : "折叠分组",
                    action: { [weak self] in
                        self?.store.setGroupCollapsed(
                            id: groupId, collapsed: !collapsed)
                    }))
            }
            if groupId == nil {
                buttons.append(.init(
                    title: "＋组", accessibilityLabel: "新建分组",
                    action: { [weak self] in self?.newGroupTapped() }))
            } else if let groupId {
                buttons.append(.init(
                    title: "删组", accessibilityLabel: "删除分组",
                    action: { [weak self] in
                        guard let self,
                              let group = self.store.group(id: groupId)
                        else { return }
                        self.confirmDeleteGroup(group)
                    }))
            }
            return SketchbookSectionHeaderView(
                title: groupId == nil
                    ? name : "\(collapsed ? "▸" : "▾") \(name)",
                detail: "\(count) 首", buttons: buttons)
        case .autoGroup(let key):
            return SketchbookSectionHeaderView(
                title: "自动 · \(SketchbookStore.autoGroupName(forKey: key))",
                detail: "\(store.entries(inAutoGroup: key).count) 首",
                buttons: [])
        case .draft:
            let armed = applyDraftDeadline.map { $0 > Date() } ?? false
            var buttons: [SketchbookSectionHeaderView.Button] = []
            if !store.draft.isEmpty {
                buttons.append(.init(
                    title: armed ? "确认替换？" : "替换当前队列",
                    accessibilityLabel: "按草稿替换当前队列",
                    action: { [weak self] in self?.applyDraftTapped() }))
                buttons.append(.init(
                    title: "清空", accessibilityLabel: "清空草稿",
                    action: { [weak self] in
                        self?.store.clearDraft(source: "drawer")
                    }))
            }
            return SketchbookSectionHeaderView(
                title: "队列草稿",
                detail: store.draft.isEmpty
                    ? "空（在暂存行左滑「入草稿」）"
                    : "\(store.draft.count) 首",
                buttons: buttons)
        default:
            return nil
        }
    }

    func tableView(
        _ tableView: UITableView, heightForHeaderInSection section: Int
    ) -> CGFloat {
        switch sections[section] {
        case .overview, .group, .draft, .autoGroup: return 34
        default: return 28
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .overview:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookTextCell.reuseId,
                for: indexPath) as! SketchbookTextCell
            cell.configure(text: overviewText())
            return cell
        case .group(let groupId):
            let groupEntries = store.entries(inGroup: groupId)
            if notesMode == .table {
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SketchbookTableRowCell.reuseId,
                    for: indexPath) as! SketchbookTableRowCell
                if indexPath.row == 0 {
                    cell.configureHeader()
                } else {
                    cell.configure(track: groupEntries[indexPath.row - 1].track)
                }
                return cell
            }
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookRowCell.reuseId,
                for: indexPath) as! SketchbookRowCell
            let entry = groupEntries[indexPath.row]
            cell.configure(
                track: entry.track, isCurrent: false, removeLocked: false)
            cell.onRemove = { [weak self] in
                self?.store.remove(trackId: entry.track.id, source: "drawer")
            }
            return cell
        case .autoGroup(let key):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookRowCell.reuseId,
                for: indexPath) as! SketchbookRowCell
            let entry = store.entries(inAutoGroup: key)[indexPath.row]
            cell.configure(
                track: entry.track, isCurrent: false, removeLocked: false)
            cell.onRemove = { [weak self] in
                self?.store.remove(trackId: entry.track.id, source: "drawer")
            }
            return cell
        case .draft:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookRowCell.reuseId,
                for: indexPath) as! SketchbookRowCell
            let track = store.draft[indexPath.row]
            cell.configure(track: track, isCurrent: false, removeLocked: false)
            cell.onRemove = { [weak self] in
                self?.store.removeFromDraft(trackId: track.id, source: "drawer")
            }
            return cell
        case .queue:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookRowCell.reuseId,
                for: indexPath) as! SketchbookRowCell
            let track = queueManager.queue[indexPath.row]
            let isCurrent = indexPath.row
                == queueManager.currentIndex % max(queueManager.queue.count, 1)
                && !queueManager.queue.isEmpty
            // 正在播的那首锁定不可移除（照网页版 ScratchpadQueue）。
            cell.configure(track: track, isCurrent: isCurrent, removeLocked: isCurrent)
            cell.onRemove = { [weak self] in
                guard let self,
                      let at = self.queueManager.queue.firstIndex(
                        where: { $0.id == track.id }) else { return }
                self.queueManager.removeFromQueue(at: at)
                Breadcrumbs.log("sketchbook.queueRemove at=\(at)")
            }
            return cell
        case .historyDay(let start):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookTextCell.reuseId,
                for: indexPath) as! SketchbookTextCell
            let events = historyDays.first { $0.dayStart == start }?.events ?? []
            let event = events[indexPath.row]
            cell.configure(text: Self.historyEventText(event))
            return cell
        case .historyEmpty:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SketchbookTextCell.reuseId,
                for: indexPath) as! SketchbookTextCell
            cell.configure(text: "暂无历史（收进与移除从现在起记录）")
            return cell
        }
    }

    func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .group(let groupId):
            let groupEntries = store.entries(inGroup: groupId)
            let row = notesMode == .table ? indexPath.row - 1 : indexPath.row
            guard groupEntries.indices.contains(row) else { return }
            let track = groupEntries[row].track
            // 网页版单条「播放」语义：插进当前队列并播放，不换队列。
            queueManager.insertAndPlay(track)
            Breadcrumbs.log("sketchbook.play source=notes id=\(track.id)")
        case .autoGroup(let key):
            let autoEntries = store.entries(inAutoGroup: key)
            guard autoEntries.indices.contains(indexPath.row) else { return }
            let track = autoEntries[indexPath.row].track
            queueManager.insertAndPlay(track)
            Breadcrumbs.log("sketchbook.play source=autogroup id=\(track.id)")
        case .draft:
            let track = store.draft[indexPath.row]
            queueManager.insertAndPlay(track)
            Breadcrumbs.log("sketchbook.play source=draft id=\(track.id)")
        case .queue:
            queueManager.playAtIndex(indexPath.row)
            Breadcrumbs.log("sketchbook.play source=queue at=\(indexPath.row)")
        default:
            break
        }
    }

    func tableView(
        _ tableView: UITableView, heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        switch sections[indexPath.section] {
        case .overview: return 64
        case .group:
            if notesMode == .table {
                return indexPath.row == 0 ? 26 : 44
            }
            return 60
        case .historyDay, .historyEmpty: return 30
        default: return 60
        }
    }

    /// 左滑行操作：暂存行（移除/入草稿/移到分组）、草稿行
    /// （上移/下移/移除）。其余段无行操作。
    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        switch sections[indexPath.section] {
        case .group(let groupId):
            if notesMode == .table, indexPath.row == 0 { return nil }
            let groupEntries = store.entries(inGroup: groupId)
            let row = notesMode == .table ? indexPath.row - 1 : indexPath.row
            guard groupEntries.indices.contains(row) else { return nil }
            let entry = groupEntries[row]
            let remove = UIContextualAction(
                style: .destructive, title: "移除") { [weak self] _, _, done in
                self?.store.remove(trackId: entry.track.id, source: "drawer")
                done(true)
            }
            let toDraft = UIContextualAction(
                style: .normal, title: "入草稿") { [weak self] _, _, done in
                self?.store.addToDraft(entry.track, source: "drawer")
                done(true)
            }
            toDraft.backgroundColor = UIColor(
                red: 0.25, green: 0.45, blue: 0.85, alpha: 1)
            let move = UIContextualAction(
                style: .normal, title: "分组") { [weak self] _, _, done in
                self?.presentGroupPicker(for: entry)
                done(true)
            }
            move.backgroundColor = UIColor(
                red: 0.35, green: 0.35, blue: 0.4, alpha: 1)
            return UISwipeActionsConfiguration(actions: [remove, move, toDraft])
        case .draft:
            let row = indexPath.row
            guard store.draft.indices.contains(row) else { return nil }
            let track = store.draft[row]
            let remove = UIContextualAction(
                style: .destructive, title: "移除") { [weak self] _, _, done in
                self?.store.removeFromDraft(trackId: track.id, source: "drawer")
                done(true)
            }
            let up = UIContextualAction(
                style: .normal, title: "上移") { [weak self] _, _, done in
                self?.store.moveDraftItem(from: row, to: row - 1)
                done(true)
            }
            let down = UIContextualAction(
                style: .normal, title: "下移") { [weak self] _, _, done in
                self?.store.moveDraftItem(from: row, to: row + 1)
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [remove, down, up])
        default:
            return nil
        }
    }

    // MARK: - 总览 / 历史文案（全部从 Store 现有数据现算）

    /// (62) 时段问候（早/午/晚/深夜四池）。
    static func greeting62() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好，先把想听的收好。"
        case 11..<14: return "中午好，午休挑几首放着。"
        case 14..<19: return "下午好，顺手收几首喜欢的。"
        case 19..<24: return "晚上好，夜里听的先收进来。"
        default: return "夜深了，收完早点休息。"
        }
    }

    private func overviewText() -> String {
        let groupCount = store.groups.count
        let historyCount = store.history.count
        if store.entries.isEmpty {
            // 空态文案（贴纸小图在面板左下角，见 cornerCatView65）。
            return "\(Self.greeting62())\n这里还空着——在搜索、歌单、队列里点速记簿钮，歌就会收进这张纸。"
        }
        return "\(Self.greeting62())\n"
            + "暂存 \(store.entries.count) 首 · 分组 \(groupCount) 个"
            + " · 未分组 \(store.entries(inGroup: nil).count) 首\n"
            + "今日新增 \(store.addedTodayCount) 首"
            + " · 历史 \(historyCount) 条\n"
            + "队列草稿 \(store.draft.count) 首"
            + " · 当前队列 \(queueManager.queue.count) 首"
    }

    private static func historyDayTitle(start: TimeInterval) -> String {
        let calendar = Calendar.current
        let day = Date(timeIntervalSince1970: start)
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day)
    }

    private static func historyEventText(
        _ event: SketchbookStore.HistoryEvent
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(
            from: Date(timeIntervalSince1970: event.at))
        let action: String
        switch event.action {
        case "add": action = "收进"
        case "remove": action = "移除"
        case "clear": action = "清空"
        default: action = event.action
        }
        let song = event.artist.isEmpty
            ? event.title : "\(event.title) · \(event.artist)"
        return "\(time)  \(action)  \(song)"
    }
}

// MARK: - 段头（组头 / 总览 / 草稿头共用）

/// 照网页版 ScratchpadGroupHeader 的语义：名字 + 条数 + 右侧
/// 一排小按钮（按钮由调用方给）。点整条头不触发按钮时无动作，
/// 折叠走「折叠/展开」按钮（触屏没有悬停，显式按钮更稳）。
final class SketchbookSectionHeaderView: UIView {

    struct Button {
        var title: String
        var accessibilityLabel: String
        var action: () -> Void
    }

    private var actions: [() -> Void] = []

    init(title: String, detail: String?, buttons: [Button]) {
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: 34))
        backgroundColor = UIColor(red: 0.078, green: 0.078, blue: 0.078,
                                  alpha: 0.05)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078,
                                       alpha: 0.9)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        var constraints = [
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        var trailing = trailingAnchor
        // 按钮从右往左排。
        for button in buttons.reversed() {
            let uiButton = UIButton(type: .system)
            uiButton.setTitle(button.title, for: .normal)
            uiButton.titleLabel?.font = .systemFont(ofSize: 12)
            uiButton.setTitleColor(
                UIColor(red: 0.078, green: 0.078, blue: 0.078,
                        alpha: 0.75), for: .normal)
            uiButton.accessibilityLabel = button.accessibilityLabel
            let index = actions.count
            actions.append(button.action)
            uiButton.tag = index
            uiButton.addTarget(
                self, action: #selector(buttonTapped(_:)),
                for: .touchUpInside)
            uiButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(uiButton)
            constraints += [
                uiButton.trailingAnchor.constraint(
                    equalTo: trailing, constant: -10),
                uiButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            trailing = uiButton.leadingAnchor
        }
        if let detail {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .systemFont(ofSize: 11.5)
            detailLabel.textColor = UIColor(red: 0.078, green: 0.078,
                                            blue: 0.078, alpha: 0.5)
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(detailLabel)
            constraints += [
                detailLabel.leadingAnchor.constraint(
                    equalTo: titleLabel.trailingAnchor, constant: 8),
                detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                detailLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailing, constant: -8),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    @objc private func buttonTapped(_ sender: UIButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

// MARK: - 纯文本行（总览 / 历史共用）

final class SketchbookTextCell: UITableViewCell {

    static let reuseId = "SketchbookTextCell"

    private let bodyLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        bodyLabel.font = .systemFont(ofSize: 12.5)
        bodyLabel.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078,
                                      alpha: 0.8)
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyLabel)
        NSLayoutConstraint.activate([
            bodyLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -14),
            bodyLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: 5),
            bodyLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(text: String) {
        bodyLabel.text = text
    }
}

// MARK: - 表格行（歌名 / 歌手 / 专辑 / 时长 多列）

/// 歌曲表格形态的一行（对应网页版 ScratchpadSongTable 的多列
/// 口径）：歌名弹性宽、歌手/专辑定宽截断、时长右对齐定宽。
/// 字段全部来自 FoliaTrack 实有数据；时长为 0（未知）时画「—」，
/// 不造数。
final class SketchbookTableRowCell: UITableViewCell {

    static let reuseId = "SketchbookTableRowCell"

    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let albumLabel = UILabel()
    private let durationLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        for label in [titleLabel, artistLabel, albumLabel, durationLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.8)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.95)
        durationLabel.textAlignment = .right
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 104),

            artistLabel.leadingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor, constant: 6),
            artistLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artistLabel.widthAnchor.constraint(equalToConstant: 62),

            albumLabel.leadingAnchor.constraint(
                equalTo: artistLabel.trailingAnchor, constant: 6),
            albumLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            durationLabel.leadingAnchor.constraint(
                equalTo: albumLabel.trailingAnchor, constant: 6),
            durationLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -12),
            durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configureHeader() {
        titleLabel.text = "歌名"
        artistLabel.text = "歌手"
        albumLabel.text = "专辑"
        durationLabel.text = "时长"
        for label in [titleLabel, artistLabel, albumLabel, durationLabel] {
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.5)
        }
    }

    func configure(track: FoliaTrack) {
        titleLabel.text = track.title
        artistLabel.text = track.artist
        albumLabel.text = track.album
        durationLabel.text = Self.durationText(track.duration)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.95)
        for label in [artistLabel, albumLabel, durationLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.8)
        }
    }

    static func durationText(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "—" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 行（封面 / 歌名 / 艺人 / 移除）

final class SketchbookRowCell: UITableViewCell {

    static let reuseId = "SketchbookRowCell"

    var onRemove: (() -> Void)?

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let stateIcon = UIImageView()
    private let removeButton = UIButton(type: .system)
    private var coverTask: Task<Void, Never>?
    private var trackId: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 4
        coverView.backgroundColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.07)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = .systemFont(ofSize: 14.5, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.95)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 0.55)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artistLabel)

        stateIcon.image = UIImage(systemName: "speaker.wave.2.fill")
        stateIcon.tintColor = UIColor.white.withAlphaComponent(0.9)
        stateIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stateIcon)

        removeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        removeButton.tintColor = UIColor.white.withAlphaComponent(0.55)
        removeButton.accessibilityLabel = "移除"
        removeButton.addTarget(
            self, action: #selector(removeTapped), for: .touchUpInside)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(removeButton)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 14),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 44),
            coverView.heightAnchor.constraint(equalToConstant: 44),

            stateIcon.leadingAnchor.constraint(
                equalTo: coverView.trailingAnchor, constant: 10),
            stateIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stateIcon.widthAnchor.constraint(equalToConstant: 16),
            stateIcon.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(
                equalTo: stateIcon.trailingAnchor, constant: 6),
            titleLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(
                equalTo: removeButton.leadingAnchor, constant: -6),

            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: 3),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            removeButton.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 32),
            removeButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverTask?.cancel()
        coverTask = nil
        trackId = nil
        coverView.image = nil
        onRemove = nil
    }

    @objc private func removeTapped() { onRemove?() }

    func configure(track: FoliaTrack, isCurrent: Bool, removeLocked: Bool) {
        trackId = track.id
        titleLabel.text = track.title
        artistLabel.text = track.artist
        titleLabel.font = .systemFont(
            ofSize: 14.5, weight: isCurrent ? .semibold : .medium)
        stateIcon.isHidden = !isCurrent
        removeButton.isHidden = removeLocked

        // 封面照 QueuePanel 行的取图口径：先内存缓存，未命中异步按档取。
        coverView.image = nil
        guard let raw = track.artworkURL?.absoluteString else { return }
        let loader = NativeCoverLoader.shared
        if let cached = loader.cachedImage(for: raw)
            ?? loader.cachedImageAnyTier(raw: raw, excludingTier: -1) {
            coverView.image = cached
            return
        }
        let id = track.id
        coverTask = Task { [weak self] in
            let image = await loader.image(for: raw, tier: 256)
            guard let self, self.trackId == id, let image else { return }
            self.coverView.image = image
        }
    }
}
