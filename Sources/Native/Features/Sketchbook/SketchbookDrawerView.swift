import UIKit
import Combine

// SketchbookDrawerView.swift
//
// 速记簿抽屉（(53) 工作流 D、(54) 工作流 N 把手照抄网页版；
// 对应 folia-major 的 ScratchpadHost / ScratchpadEdge /
// ScratchpadPanel / ScratchpadQueue）：
// 把手照 ScratchpadEdge + scratchpad.css：常驻只露左缘顶部
// （top 72pt）一条 6×56pt 米白小条（strip 样式，opacity 0.4，
// 顶端 2pt 点缀红），热区 46pt 宽、高 clamp(96, 20%屏高−76, 168)；点热区先长出完整
// 米白标签（42pt 宽，0.2s），再点标签才滑出非模态抽屉，标签
// 闲置 2.5s 自动缩回小条（网页版是悬停驱动 + 0.2s 收回延迟，
// 触屏以点按展开 + 闲置计时等价代之，见工作流 N 报告对照表）。
// 抽屉——上半「暂存」列表（封面/歌名/艺人/移除，点行点播），
// 下半「展开队列」区（当前播放队列，点行跳播、行尾可移除，
// 正在播的那首照网页版锁定不可移除），底部清空（两下确认，
// 照网页版 CLEAR_CONFIRM 口径）。
//
// 非模态做法：本视图铺满宿主，但 hitTest 只认把手（关时）与
// 抽屉（开时），其余一律返回 nil 穿透给墙；抽屉外点按关闭靠
// 挂在宿主上的旁观点击识别器（cancelsTouchesInView=false，
// 只看不拦，墙的 pan/点按照常收触摸）。开合动画用
// UISpringTimingParameters 系统弹簧（dampingRatio 0.86），
// 与全工程 iOS 原生动效口径一致。
//
// 点播漏斗（不新造队列逻辑）：暂存行 → QueueManager.insertAndPlay
// （网页版 playNow 同语义：已在队列跳过去播、不在则插到当前曲
// 之后，不换队列）；队列行 → playAtIndex；队列移除 →
// removeFromQueue。全部走 QueueManager.shared 既有 API。

final class SketchbookDrawerView: UIView {

    private let store = SketchbookStore.shared
    private let queueManager = QueueManager.shared

    private(set) var isOpen = false

    // 把手三件（照网页版 ScratchpadEdge）：透明热区（点按展开
    // 标签）、常驻小条（rest）、完整米白标签（expanded）。
    private let edgeHotButton = UIButton(type: .custom)
    private let restStrip = UIView()
    private let restMark = UIView()
    private let expandedHandle = UIButton(type: .custom)
    private let expandedTopMark = UIView()
    private let expandedCircle = UIView()
    private let expandedTitleLabel = UILabel()
    private let expandedCountBadge = UIView()
    private let expandedCountLabel = UILabel()
    private let expandedBottomCircle = UIView()
    private(set) var isHandleExpanded = false
    /// 被外部浮层盖住（书库侧栏打开等）：照网页版 is-covered
    /// 整个藏起来（ScratchpadHost.tsx 的 isCovered / css 的
    /// .is-covered{display:none}），把手与抽屉都不许浮压其上。
    private(set) var isExternallyCovered = false
    private var handleIdleWorkItem: DispatchWorkItem?
    private var lastEntryCount: Int?

    /// 网页版配色（scratchpadLook.ts）：米白纸 / 黑墨 / 纸上红。
    private static let paperColor = UIColor(
        red: 0.957, green: 0.941, blue: 0.902, alpha: 1) // #F4F0E6
    private static let inkColor = UIColor(
        red: 0.078, green: 0.078, blue: 0.078, alpha: 1) // #141414
    private static let markColor = UIColor(
        red: 0.769, green: 0.208, blue: 0.129, alpha: 1) // #C43521
    /// 把手在左缘的起始高度（网页版 fixed top 72px，默认
    /// handlePosition=0；scratchpad.css .scratchpad-edge）。
    private static let edgeTop: CGFloat = 72
    private static let edgeWidth: CGFloat = 46
    private static let expandedHandleWidth: CGFloat = 42
    private static let expandedHandleHeight: CGFloat = 162
    private let drawerView = UIView()
    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private var cancellables = Set<AnyCancellable>()
    private var clearConfirmDeadline: Date?
    private weak var outsideTapRecognizer: UITapGestureRecognizer?

    private static let drawerMaxWidth: CGFloat = 330

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildViews()
        bindState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViews()
        bindState()
    }

    // MARK: - 搭建

    private func buildViews() {
        backgroundColor = .clear

        // 左缘把手（照网页版）：热区透明、只承接点按；常驻
        // 视觉只有 6×56 米白小条（opacity 0.4、顶端 2pt 红）。
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

        // 抽屉本体。
        drawerView.backgroundColor = UIColor(
            red: 0.09, green: 0.09, blue: 0.11, alpha: 0.97)
        drawerView.isHidden = true
        addSubview(drawerView)

        titleLabel.text = "速记簿"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(titleLabel)

        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 13)
        clearButton.setTitleColor(
            UIColor.white.withAlphaComponent(0.65), for: .normal)
        clearButton.addTarget(
            self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(clearButton)

        closeButton.setImage(
            UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        closeButton.accessibilityLabel = "收起速记簿"
        closeButton.addTarget(
            self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(closeButton)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            SketchbookRowCell.self,
            forCellReuseIdentifier: SketchbookRowCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        drawerView.addSubview(tableView)

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

            tableView.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: drawerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: drawerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: drawerView.bottomAnchor),
        ])
    }

    private func bindState() {
        store.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        queueManager.$queue
            .combineLatest(queueManager.$currentIndex)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let count = store.entries.count
        expandedCountBadge.isHidden = count == 0
        expandedCountLabel.text = "\(count)"
        titleLabel.text = count > 0 ? "速记簿 · \(count)" : "速记簿"
        // 新收进一批时常驻小条闪一下（网页版 addNonce → is-pulsing
        // 0.9s：亮到不透明、放大 1.5 倍再回去，Host.tsx/css）。
        if let last = lastEntryCount, count > last { pulseRestStrip() }
        lastEntryCount = count
        resetClearConfirm()
        tableView.reloadData()
    }

    private func pulseRestStrip() {
        guard !isOpen, !isExternallyCovered, !isHandleExpanded else { return }
        Breadcrumbs.log("sketchbook.handle pulse")
        UIView.animateKeyframes(withDuration: 0.9, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) {
                self.restStrip.alpha = 1
                self.restStrip.transform = CGAffineTransform(scaleX: 1.5, y: 1)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.75) {
                self.restStrip.alpha = 0.4
                self.restStrip.transform = .identity
            }
        }
    }

    // MARK: - 布局与命中穿透

    /// 热区高度（网页版 --scratchpad-edge-height:
    /// clamp(96px, 20vh - 76px, 168px)）。
    private var edgeHeight: CGFloat {
        min(168, max(96, bounds.height * 0.20 - 76))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let edgeHeight = self.edgeHeight
        edgeHotButton.frame = CGRect(
            x: 0, y: Self.edgeTop, width: Self.edgeWidth, height: edgeHeight)
        // 常驻小条在热区内竖直居中（css .scratchpad-edge-rest）。
        restStrip.frame = CGRect(
            x: 0, y: Self.edgeTop + (edgeHeight - 56) / 2,
            width: 6, height: 56)
        restMark.frame = CGRect(x: 0, y: 0, width: 6, height: 2)
        expandedHandle.frame = CGRect(
            x: 0, y: Self.edgeTop,
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
    /// 不挡任何操作。被外部盖住时整层不接命中。
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

    /// 把手三件的显隐只由这一处按（开抽屉 / 被盖住 / 标签展开）
    /// 三个状态推导，不许各处散着改 isHidden 打架。
    private func updateHandleVisibility() {
        let clusterHidden = isOpen || isExternallyCovered
        edgeHotButton.isHidden = clusterHidden || isHandleExpanded
        restStrip.isHidden = clusterHidden || isHandleExpanded
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

    /// 点热区：完整标签从小条长出来（0.2s，亮度从常驻 0.4 到 1，
    /// 照 css .scratchpad-handle-paper 的 clip/opacity 过渡）。
    private func expandHandle(source: String) {
        guard !isOpen, !isExternallyCovered, !isHandleExpanded else { return }
        isHandleExpanded = true
        Breadcrumbs.log("sketchbook.handle expand source=\(source)")
        expandedHandle.alpha = 0.4
        updateHandleVisibility()
        UIView.animate(withDuration: 0.2, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.expandedHandle.alpha = 1
        }
        scheduleHandleRetract()
    }

    /// 闲置收起：网页版指针离开热区后标签缩回小条（收回延迟
    /// 0.2s）；触屏没有悬停离开，等价为展开后 2.5s 无操作自动
    /// 缩回（Miller 口径「不滑动的时候它就收起来」）。
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
            self.expandedHandle.alpha = 0.4
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
            tableView.reloadData()
        }
        let animator = UIViewPropertyAnimator(
            duration: 0.55,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.86))
        animator.addAnimations { [weak self] in
            guard let self else { return }
            self.drawerView.frame = CGRect(
                x: open ? 0 : -width, y: 0,
                width: width, height: self.bounds.height)
        }
        animator.addCompletion { [weak self] _ in
            guard let self, !self.isOpen else { return }
            self.drawerView.isHidden = true
            self.updateHandleVisibility()
        }
        animator.startAnimation()
    }

    // MARK: - 清空（两下确认，照网页版 3 秒口径）

    private func resetClearConfirm() {
        clearConfirmDeadline = nil
        clearButton.setTitle("清空", for: .normal)
        clearButton.setTitleColor(
            UIColor.white.withAlphaComponent(0.65), for: .normal)
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
}

// MARK: - 列表（0 暂存 / 1 当前队列）

extension SketchbookDrawerView: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        section == 0 ? store.entries.count : queueManager.queue.count
    }

    func tableView(
        _ tableView: UITableView, titleForHeaderInSection section: Int
    ) -> String? {
        if section == 0 {
            return store.entries.isEmpty
                ? "暂存（空）" : "暂存 · \(store.entries.count)"
        }
        return queueManager.queue.isEmpty
            ? "当前队列（空）" : "当前队列 · \(queueManager.queue.count)"
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SketchbookRowCell.reuseId,
            for: indexPath) as! SketchbookRowCell
        if indexPath.section == 0 {
            let entry = store.entries[indexPath.row]
            cell.configure(
                track: entry.track, isCurrent: false, removeLocked: false)
            cell.onRemove = { [weak self] in
                self?.store.remove(trackId: entry.track.id, source: "drawer")
            }
        } else {
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
        }
        return cell
    }

    func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let track = store.entries[indexPath.row].track
            // 网页版单条「播放」语义：插进当前队列并播放，不换队列。
            queueManager.insertAndPlay(track)
            Breadcrumbs.log("sketchbook.play source=notes id=\(track.id)")
        } else {
            queueManager.playAtIndex(indexPath.row)
            Breadcrumbs.log("sketchbook.play source=queue at=\(indexPath.row)")
        }
    }

    func tableView(
        _ tableView: UITableView, heightForRowAt indexPath: IndexPath
    ) -> CGFloat { 60 }
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
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = .systemFont(ofSize: 14.5, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.5)
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
