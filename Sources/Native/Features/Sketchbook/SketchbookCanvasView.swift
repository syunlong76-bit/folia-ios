import UIKit

// SketchbookCanvasView.swift
//
// 速记簿画布形态（(55) 工作流 H；对应 folia-major 的
// ScratchpadCanvas.tsx + canvasLayout.ts）：暂存歌曲按组摆成卡片
// 网格，卡片 136×176、间隙 12（canvasLayout 的 DEFAULT_SPACING /
// CARD_WIDTH / CARD_HEIGHT），列数按可用宽现算（columnsFor）。
// 拖拽：卡片跟手走（抬起放大一点点），松手按卡片中心最近的格子
// 吸附（dropIndexAt 的换算），组内换序后落点写回 Store 持久化；
// 没拖过的卡按组内序号摆槽位（slotPosition）。点卡点播走抽屉的
// 既有点播通路（回调出去，仍是 insertAndPlay）。
//
// 手势分工：卡片自己的 UIPanGestureRecognizer 只在按住卡片时
// 接管，开拖即关掉画布的滚动（isScrollEnabled=false），松手
// 恢复——拖卡与滚画布不打架；点卡是卡片上的 UITapGestureRecognizer，
// 与拖拽以移动距离自然区分（拖动开始后 tap 不触发）。

final class SketchbookCanvasView: UIScrollView {

    var onPlayTrack: ((FoliaTrack) -> Void)?
    var onRemoveTrack: ((String) -> Void)?

    private let store = SketchbookStore.shared
    private let contentView = UIView()

    private static let cardWidth: CGFloat = 136
    private static let cardHeight: CGFloat = 176
    private static let gap: CGFloat = 12
    private static let edge: CGFloat = 12
    private static let headerHeight: CGFloat = 26
    private static let blockGap: CGFloat = 18

    private struct Block {
        var groupId: String?
        var title: String
        var gridOrigin: CGPoint
        var entries: [SketchbookStore.Entry]
    }

    private var blocks: [Block] = []
    private var cardViews: [String: SketchbookCanvasCardView] = [:]
    private let emptyLabel = UILabel()

    private var dragCard: SketchbookCanvasCardView?
    private var dragStartCenter: CGPoint = .zero
    private var dragGroupId: String?? = nil
    private var dragGridOrigin: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        alwaysBounceVertical = true
        addSubview(contentView)
        emptyLabel.text = "暂存是空的"
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        contentView.addSubview(emptyLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private var columns: Int {
        let width = bounds.width - Self.edge * 2
        return max(1, Int((width + Self.gap) / (Self.cardWidth + Self.gap)))
    }

    // MARK: - 摆卡

    func reload() {
        // 还没布局（宽 0）时摆不了：等 layoutSubviews 里宽度到位
        // 后会自己再摆一次。
        guard bounds.width > 0 else { return }
        for card in cardViews.values { card.removeFromSuperview() }
        cardViews = [:]
        for view in transientViews { view.removeFromSuperview() }
        transientViews = []
        blocks = []

        let orderedGroupIds: [String?] =
            [nil] + store.groups.map { Optional($0.id) }
        var y = Self.edge
        let columns = self.columns
        for groupId in orderedGroupIds {
            let groupEntries = store.entries(inGroup: groupId)
            if groupEntries.isEmpty { continue }
            let title = groupId == nil
                ? "未分组" : (store.group(id: groupId ?? "")?.name ?? "分组")
            let header = UILabel()
            header.text = "\(title) · \(groupEntries.count)"
            header.font = .systemFont(ofSize: 12.5, weight: .semibold)
            header.textColor = UIColor.white.withAlphaComponent(0.55)
            header.frame = CGRect(
                x: Self.edge, y: y, width: bounds.width - Self.edge * 2,
                height: Self.headerHeight)
            contentView.addSubview(header)
            // 每次 reload 重建的组头要跟着清掉：借 cardViews 之外
            // 单独记一份，下次 reload 一并移除。
            transientViews.append(header)

            let gridOrigin = CGPoint(
                x: Self.edge, y: y + Self.headerHeight + 4)
            blocks.append(Block(
                groupId: groupId, title: title,
                gridOrigin: gridOrigin, entries: groupEntries))
            for (index, entry) in groupEntries.enumerated() {
                let slot = slotOrigin(index: index, columns: columns)
                let origin = CGPoint(
                    x: gridOrigin.x + (entry.canvasX.map { CGFloat($0) } ?? slot.x),
                    y: gridOrigin.y + (entry.canvasY.map { CGFloat($0) } ?? slot.y))
                let card = SketchbookCanvasCardView()
                card.frame = CGRect(
                    x: origin.x, y: origin.y,
                    width: Self.cardWidth, height: Self.cardHeight)
                card.configure(entry: entry)
                card.onTap = { [weak self] in
                    self?.onPlayTrack?(entry.track)
                }
                card.onRemove = { [weak self] in
                    self?.onRemoveTrack?(entry.track.id)
                }
                card.onShapeCycle = { [weak self] in
                    guard let self else { return }
                    let order = ["rect", "round", "tape"]
                    let current = entry.shape ?? "rect"
                    let next = order[((order.firstIndex(of: current) ?? 0) + 1) % order.count]
                    self.store.setShape(trackId: entry.track.id, shape: next)
                    self.reload()
                }
                let pan = UIPanGestureRecognizer(
                    target: self, action: #selector(cardPanned(_:)))
                card.addGestureRecognizer(pan)
                contentView.addSubview(card)
                cardViews[entry.track.id] = card
            }
            let rows = Int(ceil(
                Double(groupEntries.count) / Double(columns)))
            var gridHeight = rows > 0
                ? CGFloat(rows) * Self.cardHeight
                    + CGFloat(rows - 1) * Self.gap : 0
            // (62) 自由坐标：已摆卡片的落点可超出网格高，块高
            // 取两者大者防后续组压住自由摆放的卡片。
            for entry in groupEntries {
                if let cy = entry.canvasY {
                    gridHeight = max(gridHeight, CGFloat(cy) + Self.cardHeight)
                }
            }
            y = gridOrigin.y + gridHeight + Self.blockGap
        }

        emptyLabel.isHidden = !store.entries.isEmpty
        emptyLabel.frame = CGRect(
            x: Self.edge, y: 60, width: bounds.width - Self.edge * 2,
            height: 24)
        let contentHeight = max(y, bounds.height + 1)
        contentView.frame = CGRect(
            x: 0, y: 0, width: bounds.width, height: contentHeight)
        contentSize = CGSize(width: bounds.width, height: contentHeight)
    }

    private var transientViews: [UIView] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        // 宽度变了（旋转）列数会变：清掉旧组头后整幅重摆。
        if abs(contentView.frame.width - bounds.width) > 0.5, bounds.width > 0 {
            for view in transientViews { view.removeFromSuperview() }
            transientViews = []
            reload()
        }
    }

    /// 第 index 个槽位的左上角（相对组网格原点，slotPosition）。
    private func slotOrigin(index: Int, columns: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(index % columns) * (Self.cardWidth + Self.gap),
            y: CGFloat(index / columns) * (Self.cardHeight + Self.gap))
    }

    // MARK: - 拖拽（(62) 起自由坐标，旧 dropIndexAt 吸附退役）

    @objc private func cardPanned(_ gesture: UIPanGestureRecognizer) {
        guard let card = gesture.view as? SketchbookCanvasCardView,
              let trackId = card.trackId else { return }
        switch gesture.state {
        case .began:
            guard let block = blocks.first(where: {
                $0.entries.contains { $0.track.id == trackId }
            }) else { return }
            dragCard = card
            dragGroupId = block.groupId
            dragGridOrigin = block.gridOrigin
            dragStartCenter = card.center
            isScrollEnabled = false
            contentView.bringSubviewToFront(card)
            UIView.animate(withDuration: 0.18) {
                card.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                card.layer.shadowOpacity = 0.35
            }
        case .changed:
            guard dragCard === card else { return }
            let translation = gesture.translation(in: contentView)
            card.center = CGPoint(
                x: dragStartCenter.x + translation.x,
                y: dragStartCenter.y + translation.y)
        case .ended, .cancelled:
            guard dragCard === card else { return }
            defer {
                dragCard = nil
                isScrollEnabled = true
            }
            guard let groupId = dragGroupId else { return }
            // (62) 自由坐标落盘：脱离网格槽位——落点即卡片左
            // 上角相对组原点的原始坐标（钳 ≥0），不再吸附、
            // 不再改组内序（moveWithinGroup 退役于画布拖拽）。
            let topLeft = CGPoint(
                x: max(0, card.frame.minX - dragGridOrigin.x),
                y: max(0, card.frame.minY - dragGridOrigin.y))
            store.setCanvasPosition(
                trackId: trackId, x: Double(topLeft.x), y: Double(topLeft.y))
            Breadcrumbs.log(
                "sketchbook.canvas drop62 id=\(trackId) group=\(groupId ?? "none") x=\(Int(topLeft.x)) y=\(Int(topLeft.y))")
            UIView.animate(withDuration: 0.22) {
                card.transform = .identity
                card.layer.shadowOpacity = 0
            }
            reload()
        default:
            break
        }
    }
}

// MARK: - 卡片（封面 / 歌名 / 歌手 / 移除）

final class SketchbookCanvasCardView: UIView {

    private(set) var trackId: String?
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?
    /// (62) 长按循环切换便签形状（rect→round→tape）。
    var onShapeCycle: (() -> Void)?

    /// (62) 胶带角的胶带条（tape 形状时显）。
    private let tapeView = UIView()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private var coverTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.07)
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowOpacity = 0

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 6
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverView.isUserInteractionEnabled = false
        addSubview(coverView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 11.5)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.isUserInteractionEnabled = false
        addSubview(artistLabel)

        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = UIColor.white.withAlphaComponent(0.75)
        removeButton.accessibilityLabel = "移除"
        removeButton.addTarget(
            self, action: #selector(removeTapped), for: .touchUpInside)
        addSubview(removeButton)

        let tap = UITapGestureRecognizer(
            target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(shapeLongPressed(_:)))
        longPress.minimumPressDuration = 0.6
        addGestureRecognizer(longPress)
        tapeView.backgroundColor = UIColor(red: 0.98, green: 0.93,
                                           blue: 0.72, alpha: 0.85)
        tapeView.isHidden = true
        tapeView.isUserInteractionEnabled = false
        addSubview(tapeView)
    }

    @objc private func shapeLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onShapeCycle?()
    }

    /// (62) 形状应用：rect 矩形（圆角 8）/ round 圆角（18）/
    /// tape 胶带角（顶部胶带条）。
    func applyShape62(_ shape: String?) {
        switch shape {
        case "round":
            layer.cornerRadius = 18
            tapeView.isHidden = true
        case "tape":
            layer.cornerRadius = 8
            tapeView.isHidden = false
        default:
            layer.cornerRadius = 8
            tapeView.isHidden = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        tapeView.frame = CGRect(x: bounds.width / 2 - 26, y: -5,
                                width: 52, height: 14)
        tapeView.transform = CGAffineTransform(rotationAngle: -0.06)
        coverView.frame = CGRect(x: 6, y: 6, width: bounds.width - 12, height: 104)
        titleLabel.frame = CGRect(
            x: 8, y: 116, width: bounds.width - 16, height: 34)
        artistLabel.frame = CGRect(
            x: 8, y: 152, width: bounds.width - 16, height: 16)
        removeButton.frame = CGRect(
            x: bounds.width - 30, y: 2, width: 28, height: 28)
    }

    @objc private func tapped() { onTap?() }
    @objc private func removeTapped() { onRemove?() }

    func configure(entry: SketchbookStore.Entry) {
        trackId = entry.track.id
        applyShape62(entry.shape)
        titleLabel.text = entry.track.title
        artistLabel.text = entry.track.artist
        coverTask?.cancel()
        coverView.image = nil
        guard let raw = entry.track.artworkURL?.absoluteString else { return }
        let loader = NativeCoverLoader.shared
        if let cached = loader.cachedImage(for: raw)
            ?? loader.cachedImageAnyTier(raw: raw, excludingTier: -1) {
            coverView.image = cached
            return
        }
        let id = entry.track.id
        coverTask = Task { [weak self] in
            let image = await loader.image(for: raw, tier: 256)
            guard let self, self.trackId == id, let image else { return }
            self.coverView.image = image
        }
    }
}
