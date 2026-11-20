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
                let pan = UIPanGestureRecognizer(
                    target: self, action: #selector(cardPanned(_:)))
                card.addGestureRecognizer(pan)
                contentView.addSubview(card)
                cardViews[entry.track.id] = card
            }
            let rows = Int(ceil(
                Double(groupEntries.count) / Double(columns)))
            let gridHeight = rows > 0
                ? CGFloat(rows) * Self.cardHeight
                    + CGFloat(rows - 1) * Self.gap : 0
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

    // MARK: - 拖拽（dropIndexAt 吸附）

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
            let groupEntries = store.entries(inGroup: groupId)
            // 落点换算（dropIndexAt）：卡片左上角相对网格原点，
            // 取最近格子，夹进 [0, 挪走后剩余张数]。
            let topLeft = CGPoint(
                x: card.frame.minX - dragGridOrigin.x,
                y: card.frame.minY - dragGridOrigin.y)
            let columns = self.columns
            let column = min(
                columns - 1,
                max(0, Int(round(topLeft.x / (Self.cardWidth + Self.gap)))))
            let row = max(
                0, Int(round(topLeft.y / (Self.cardHeight + Self.gap))))
            let target = min(
                max(0, groupEntries.count - 1), row * columns + column)
            store.moveWithinGroup(
                trackId: trackId, groupId: groupId, targetIndex: target)
            // 最终槽位落点落盘（组内序号可能没变也要记：第一次摆）。
            let finalIndex = store.entries(inGroup: groupId)
                .firstIndex { $0.track.id == trackId } ?? target
            let slot = slotOrigin(index: finalIndex, columns: columns)
            store.setCanvasPosition(
                trackId: trackId, x: Double(slot.x), y: Double(slot.y))
            Breadcrumbs.log(
                "sketchbook.canvas drop id=\(trackId) group=\(groupId ?? "none") at=\(finalIndex)")
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
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
