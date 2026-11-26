import UIKit

/// port90（任务 21/24）：控制台拍立得照片墙（样片
/// pai-li-de-zhao-pian-qiang-yang-pian v2 定版形态）——控制台
/// 上方新增区：头部行（换一批＋日记本两圆钮 40）、舞台区内
/// 打印机逐张打印 10 张拍立得、打完打印机淡出消失、10 张
/// 不规则散布；点照片直接切歌播放、照片右上 ➕ 贴日记本、
/// 照片题注行小钮进日记本。
/// 推荐池数据源（原生真实来源，不用假数据）：当前队列 ∪
/// 本机播放历史（PlayHistoryStore），按 id 去重后洗牌取 10。
/// 本区是「加」在控制台上方的独立区，下方各行零改动（任务 24）。
final class PolaroidZone90View: UIView {

    var onPlay: ((FoliaTrack) -> Void)?
    var onOpenDiary: ((FoliaTrack?) -> Void)?

    private let headView = UIView()
    private let reprintButton = UIButton(type: .system)
    private let diaryButton = UIButton(type: .system)
    private let diaryBadge = UILabel()
    private let stageView = UIView()
    private let printer = PrinterView90()
    private var cards: [PolaroidCard90] = []
    private var pool: [FoliaTrack] = []
    private var printed = false
    private var printing = false

    /// 舞台区高度（头部行之外）：竖屏 232/横屏 150 由宿主约束
    /// 给定总高，本视图内部按 head 40 + 其余为舞台排布。
    private static let headHeight: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        NotificationCenter.default.addObserver(
            self, selector: #selector(diaryChanged90),
            name: .foliaDiary90Changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        headView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headView)
        stageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stageView)

        for (button, symbol) in [(reprintButton, "arrow.counterclockwise"),
                                 (diaryButton, "book")] {
            button.setImage(UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
                for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.09)
            button.layer.cornerRadius = 20
            button.translatesAutoresizingMaskIntoConstraints = false
            headView.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 40),
                button.heightAnchor.constraint(equalToConstant: 40),
                button.centerYAnchor.constraint(equalTo: headView.centerYAnchor),
            ])
        }
        reprintButton.accessibilityLabel = "换一批重新打印"
        diaryButton.accessibilityLabel = "打开日记本"
        reprintButton.addTarget(self, action: #selector(reprintTapped), for: .touchUpInside)
        diaryButton.addTarget(self, action: #selector(diaryTapped), for: .touchUpInside)

        diaryBadge.font = .systemFont(ofSize: 10.5, weight: .bold)
        diaryBadge.textColor = UIColor(red: 0.16, green: 0.13, blue: 0.05, alpha: 1)
        diaryBadge.backgroundColor = UIColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)
        diaryBadge.textAlignment = .center
        diaryBadge.layer.cornerRadius = 8.5
        diaryBadge.clipsToBounds = true
        diaryBadge.translatesAutoresizingMaskIntoConstraints = false
        headView.addSubview(diaryBadge)

        // 打印机帧由本视图 layoutSubviews 直接管理（打印动画需
        // 逐帧控制），不挂 Auto Layout 约束。
        stageView.addSubview(printer)

        NSLayoutConstraint.activate([
            headView.topAnchor.constraint(equalTo: topAnchor),
            headView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headView.heightAnchor.constraint(equalToConstant: Self.headHeight),
            diaryButton.trailingAnchor.constraint(equalTo: headView.trailingAnchor),
            reprintButton.trailingAnchor.constraint(equalTo: diaryButton.leadingAnchor, constant: -8),
            diaryBadge.topAnchor.constraint(equalTo: diaryButton.topAnchor, constant: -4),
            diaryBadge.trailingAnchor.constraint(equalTo: diaryButton.trailingAnchor, constant: 4),
            diaryBadge.heightAnchor.constraint(equalToConstant: 17),
            diaryBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 17),
            stageView.topAnchor.constraint(equalTo: headView.bottomAnchor, constant: 2),
            stageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refreshBadge()
    }

    // MARK: 推荐池与打印

    /// 控制台呈现后调用：备池并（首次）打印。
    func beginIfNeeded() {
        if pool.isEmpty { reloadPool() }
        if !printed { startPrinting() }
    }

    private func reloadPool() {
        var seen = Set<String>()
        var merged: [FoliaTrack] = []
        for track in QueueManager.shared.queue + PlayHistoryStore.shared.records.map({ $0.track }) {
            if seen.insert(track.id).inserted { merged.append(track) }
        }
        merged.shuffle()
        pool = Array(merged.prefix(10))
        for card in cards { card.removeFromSuperview() }
        cards = pool.map { track in
            let card = PolaroidCard90()
            card.configure(track: track)
            card.onTap = { [weak self] t in self?.onPlay?(t) }
            card.onBook = { [weak self] t in self?.onOpenDiary?(t) }
            stageView.addSubview(card)
            return card
        }
        printed = false
        setNeedsLayout()
    }

    @objc private func reprintTapped() {
        guard !printing else { return }
        reloadPool()
        startPrinting()
        Breadcrumbs.log("port90 polaroid reprint n=\(pool.count)")
    }

    @objc private func diaryTapped() { onOpenDiary?(nil) }

    @objc private func diaryChanged90() {
        refreshBadge()
        for card in cards { card.refreshAddState() }
    }

    private func refreshBadge() {
        let count = DiaryStore90.songs.count
        diaryBadge.text = "\(count)"
        diaryBadge.isHidden = count == 0
    }

    /// 散布槽位（中心点占舞台宽/高的比例＋旋转角），照样片
    /// 不规则排布：上下两排错位、角度 −7°…+8°。
    private static let slots: [(x: CGFloat, y: CGFloat, rot: CGFloat)] = [
        (0.11, 0.27, -6), (0.30, 0.24, 4), (0.50, 0.28, -3), (0.70, 0.24, 6), (0.89, 0.27, -5),
        (0.16, 0.73, 5), (0.35, 0.76, -4), (0.55, 0.72, 7), (0.74, 0.76, -6), (0.90, 0.72, 3),
    ]

    /// 槽位帧单一计算口（布局与打印动画共用，避免两处账不一）。
    private func frameForSlot(_ index: Int, stage: CGRect) -> CGRect {
        let slot = Self.slots[index % Self.slots.count]
        let polaW = min(stage.width * 0.27, stage.height * 0.46)
        let polaH = polaW * 1.27
        return CGRect(x: slot.x * stage.width - polaW / 2,
                      y: slot.y * stage.height - polaH / 2,
                      width: polaW, height: polaH)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let stage = stageView.bounds
        guard stage.width > 0, stage.height > 0 else { return }
        printer.frame = CGRect(x: (stage.width - min(224, stage.width * 0.58)) / 2, y: 0,
                               width: min(224, stage.width * 0.58),
                               height: min(224, stage.width * 0.58) * 0.55)
        // 打印动画进行中不碰卡帧（动画自有帧序列，布局回写会打断）。
        guard !printing else { return }
        for (index, card) in cards.enumerated() {
            card.frame = frameForSlot(index, stage: stage)
            if printed {
                let slot = Self.slots[index % Self.slots.count]
                card.transform = CGAffineTransform(rotationAngle: slot.rot * .pi / 180)
            }
        }
    }

    /// 逐张打印：每张从打印机出纸口滑出、弹簧落到槽位；
    /// 全部打完后打印机淡出上移消失（样片同序）。
    private func startPrinting() {
        guard !cards.isEmpty, bounds.width > 0 else { return }
        printing = true
        printed = false
        printer.alpha = 1
        printer.isHidden = false
        printer.setLED(on: true)
        let stage = stageView.bounds
        let startFrame = CGRect(x: stage.width / 2 - 30, y: printer.frame.maxY - 26,
                                width: 60, height: 76)
        for (index, card) in cards.enumerated() {
            let target = frameForSlot(index, stage: stage)
            let slot = Self.slots[index % Self.slots.count]
            card.frame = startFrame
            card.transform = .identity
            card.alpha = 0
            stageView.bringSubviewToFront(card)
            UIView.animate(withDuration: 0.55, delay: 0.15 + Double(index) * 0.42,
                           usingSpringWithDamping: 0.72, initialSpringVelocity: 0.4,
                           options: [.allowUserInteraction]) {
                card.alpha = 1
                card.frame = target
                card.transform = CGAffineTransform(rotationAngle: slot.rot * .pi / 180)
            }
        }
        let total = 0.15 + Double(cards.count) * 0.42 + 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self else { return }
            self.printer.setLED(on: false)
            UIView.animate(withDuration: 0.5, animations: {
                self.printer.alpha = 0
                self.printer.transform = CGAffineTransform(translationX: 0, y: -14)
                    .scaledBy(x: 0.9, y: 0.9)
            }, completion: { _ in
                self.printer.isHidden = true
                self.printer.transform = .identity
                self.printing = false
                self.printed = true
            })
        }
        Breadcrumbs.log("port90 polaroid print n=\(cards.count)")
    }
}

/// 打印机造型（样片 SVG 的原生等价）：奶油色机身＋顶部纸槽
/// ＋镜头圆＋LED＋底部出纸口。用图层拼，不引图片资源。
final class PrinterView90: UIView {

    private let led = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let body = UIView()
        body.backgroundColor = UIColor(red: 0.93, green: 0.89, blue: 0.80, alpha: 1)
        body.layer.cornerRadius = 16
        body.layer.shadowColor = UIColor.black.cgColor
        body.layer.shadowOpacity = 0.45
        body.layer.shadowRadius = 12
        body.layer.shadowOffset = CGSize(width: 0, height: 8)
        addSubview(body)
        let paper = UIView()
        paper.backgroundColor = UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1)
        paper.layer.cornerRadius = 3
        addSubview(paper)
        let lens = UIView()
        lens.backgroundColor = UIColor(red: 0.23, green: 0.25, blue: 0.29, alpha: 1)
        lens.layer.cornerRadius = 11.5
        addSubview(lens)
        let lensCore = UIView()
        lensCore.backgroundColor = UIColor(red: 0.47, green: 0.51, blue: 0.56, alpha: 1)
        lensCore.layer.cornerRadius = 5
        addSubview(lensCore)
        led.backgroundColor = UIColor(red: 0.54, green: 0.52, blue: 0.47, alpha: 1)
        led.layer.cornerRadius = 4
        addSubview(led)
        let slot = UIView()
        slot.backgroundColor = UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)
        slot.layer.cornerRadius = 6
        addSubview(slot)
        // 子件帧按 224×123 基准记录，layoutSubviews 等比重算。
        baseFrames = [
            (body, CGRect(x: 20, y: 30, width: 184, height: 84)),
            (paper, CGRect(x: 63, y: 8, width: 98, height: 24)),
            (lens, CGRect(x: 42, y: 48, width: 23, height: 23)),
            (lensCore, CGRect(x: 48, y: 54, width: 11, height: 11)),
            (led, CGRect(x: 183, y: 53, width: 8, height: 8)),
            (slot, CGRect(x: 40, y: 94, width: 144, height: 13)),
        ]
        for (view, base) in baseFrames { view.frame = base }
    }

    private var baseFrames: [(UIView, CGRect)] = []

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = bounds.width / 224
        guard scale > 0 else { return }
        for (view, base) in baseFrames {
            view.frame = CGRect(x: base.minX * scale, y: base.minY * scale,
                                width: base.width * scale, height: base.height * scale)
        }
    }

    func setLED(on: Bool) {
        led.backgroundColor = on
            ? UIColor(red: 1, green: 0.72, blue: 0.30, alpha: 1)
            : UIColor(red: 0.54, green: 0.52, blue: 0.47, alpha: 1)
        led.layer.removeAllAnimations()
        if on {
            let blink = CABasicAnimation(keyPath: "opacity")
            blink.fromValue = 1
            blink.toValue = 0.25
            blink.duration = 0.45
            blink.autoreverses = true
            blink.repeatCount = .infinity
            led.layer.add(blink, forKey: "blink90")
        }
    }
}

/// 单张拍立得（样片 .pola 等价）：白框、方封面、题注（歌名＋
/// 歌手）、封面右上 ➕、题注行右端日记本小钮。
final class PolaroidCard90: UIControl {

    var onTap: ((FoliaTrack) -> Void)?
    var onBook: ((FoliaTrack) -> Void)?

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let addButton = DiaryAddButton90.make()
    private let bookButton = UIButton(type: .system)
    private var coverTask: Task<Void, Never>?
    private(set) var track: FoliaTrack?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 11
        layer.shadowOffset = CGSize(width: 0, height: 6)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 2
        imageView.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1)
        addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = UIColor(red: 0.20, green: 0.19, blue: 0.16, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        artistLabel.font = .systemFont(ofSize: 8.5)
        artistLabel.textColor = UIColor(red: 0.60, green: 0.57, blue: 0.49, alpha: 1)
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)

        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addSubview(addButton)

        bookButton.setImage(UIImage(systemName: "pencil",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)),
            for: .normal)
        bookButton.tintColor = UIColor(red: 0.64, green: 0.61, blue: 0.55, alpha: 1)
        bookButton.addTarget(self, action: #selector(bookTapped), for: .touchUpInside)
        bookButton.accessibilityLabel = "为这首歌打开日记本"
        addSubview(bookButton)

        addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad = bounds.width * 0.075
        let imgSide = bounds.width - pad * 2
        imageView.frame = CGRect(x: pad, y: pad, width: imgSide, height: imgSide)
        addButton.frame = CGRect(x: imageView.frame.maxX - 29, y: imageView.frame.minY + 5,
                                 width: 24, height: 24)
        let capY = imageView.frame.maxY + 4
        bookButton.frame = CGRect(x: bounds.width - pad - 20, y: capY - 2, width: 20, height: 20)
        titleLabel.frame = CGRect(x: pad, y: capY, width: bounds.width - pad * 2 - 20, height: 14)
        artistLabel.frame = CGRect(x: pad, y: capY + 14, width: bounds.width - pad * 2, height: 11)
    }

    func configure(track: FoliaTrack) {
        self.track = track
        titleLabel.text = track.title
        artistLabel.text = track.artist
        refreshAddState()
        coverTask?.cancel()
        imageView.image = nil
        guard let raw = track.artworkURL?.absoluteString else { return }
        let loader = NativeCoverLoader.shared
        let proxy = loader.proxiedURLString(raw, tier: 256)
        if let key = proxy, let cached = loader.cachedImage(for: key) {
            imageView.image = cached
            return
        }
        if let cached = loader.cachedImageAnyTier(raw: raw, excludingTier: 256) {
            imageView.image = cached
            return
        }
        let id = track.id
        coverTask = Task { [weak self] in
            let image = await loader.image(for: proxy ?? raw, tier: 256)
            guard let self, self.track?.id == id, let image else { return }
            self.imageView.image = image
        }
    }

    func refreshAddState() {
        DiaryAddButton90.refresh(addButton, songId: track?.id)
    }

    @objc private func cardTapped() {
        if let track { onTap?(track) }
    }

    @objc private func addTapped() {
        guard let track else { return }
        DiaryStore90.toggle(DiarySong90(track: track))
        refreshAddState()
    }

    @objc private func bookTapped() {
        if let track { onBook?(track) }
    }
}
