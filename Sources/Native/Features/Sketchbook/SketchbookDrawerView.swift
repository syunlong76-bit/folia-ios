import UIKit
import Combine

// SketchbookDrawerView.swift
//
// 速记簿抽屉（(53) 工作流 D；对应 folia-major 的 ScratchpadHost /
// ScratchpadEdge / ScratchpadPanel / ScratchpadQueue）：
// 左缘小把手（离散小视图，非常驻全缘手势）点开，从左滑出非模态
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

    private let handleButton = UIButton(type: .custom)
    private let handleCountLabel = UILabel()
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

        // 左缘把手：小命中区（28×88），半透明深色竖条 + 图标 + 计数。
        handleButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        handleButton.layer.cornerRadius = 8
        handleButton.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        handleButton.setImage(
            UIImage(systemName: "note.text"), for: .normal)
        handleButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        handleButton.accessibilityLabel = "速记簿"
        handleButton.addTarget(
            self, action: #selector(handleTapped), for: .touchUpInside)
        addSubview(handleButton)

        handleCountLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        handleCountLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        handleCountLabel.textAlignment = .center
        handleCountLabel.isUserInteractionEnabled = false
        handleButton.addSubview(handleCountLabel)

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
        handleCountLabel.text = count > 0 ? "\(count)" : ""
        titleLabel.text = count > 0 ? "速记簿 · \(count)" : "速记簿"
        resetClearConfirm()
        tableView.reloadData()
    }

    // MARK: - 布局与命中穿透

    override func layoutSubviews() {
        super.layoutSubviews()
        let handleHeight: CGFloat = 88
        handleButton.frame = CGRect(
            x: 0, y: bounds.height * 0.36,
            width: 28, height: handleHeight)
        handleCountLabel.frame = CGRect(
            x: 0, y: handleHeight - 24, width: 28, height: 16)
        let width = min(Self.drawerMaxWidth, bounds.width * 0.86)
        drawerView.frame = CGRect(
            x: isOpen ? 0 : -width, y: 0, width: width, height: bounds.height)
    }

    /// 只认把手（关时）与抽屉（开时）；其余穿透给墙，不挡任何操作。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isOpen {
            guard drawerView.frame.contains(point) else { return nil }
            return drawerView.hitTest(
                convert(point, to: drawerView), with: event)
        }
        guard !handleButton.isHidden,
              handleButton.frame.contains(point) else { return nil }
        return handleButton.hitTest(
            convert(point, to: handleButton), with: event)
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
        guard isOpen else { return }
        let point = recognizer.location(in: self)
        if drawerView.frame.contains(point)
            || handleButton.frame.contains(point) { return }
        setOpen(false, source: "outsideTap")
    }

    @objc private func handleTapped() {
        setOpen(true, source: "handle")
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
            drawerView.isHidden = false
            handleButton.isHidden = true
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
            self.handleButton.isHidden = false
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
