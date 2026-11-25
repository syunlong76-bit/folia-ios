import UIKit

/// (87) 队列封面模块（样片定版 2026-11-25 15:07）：控制台
/// 顶部横滑封面条与歌曲列表页封面阵列的共用件——封面瓷
/// 砖（序号角标＋在播金环＋律动标记）与网格单元（封面＋
/// 歌名/歌手小字）。点封面直接切歌由宿主接 target。
/// 封面取图走 NativeCoverLoader 既有链（缓存优先、异步
/// 回填带 id 防串图），不另开裸下载。

/// 在播律动标记：三根金色小条错相缩放（样片 .ceq）。
final class EqBars87View: UIView {
    private var bars: [UIView] = []
    private var animating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for _ in 0..<3 {
            let bar = UIView()
            bar.backgroundColor = UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 1)
            bar.layer.cornerRadius = 1.3
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            bars.append(bar)
        }
        NSLayoutConstraint.activate([
            bars[0].leadingAnchor.constraint(equalTo: leadingAnchor),
            bars[1].leadingAnchor.constraint(equalTo: bars[0].trailingAnchor, constant: 2),
            bars[2].leadingAnchor.constraint(equalTo: bars[1].trailingAnchor, constant: 2),
            bars[2].trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for bar in bars {
            bar.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            bar.widthAnchor.constraint(equalToConstant: 2.6).isActive = true
            bar.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setAnimating(_ on: Bool) {
        guard on != animating else { return }
        animating = on
        isHidden = !on
        for (index, bar) in bars.enumerated() {
            bar.layer.removeAllAnimations()
            guard on else { continue }
            let anim = CABasicAnimation(keyPath: "bounds.size.height")
            // 以层高为基准上下律动：用 transform.scale.y 等价实现，
            // 锚点钉底边、只长高缩短。
            bar.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            let scale = CAKeyframeAnimation(keyPath: "transform.scale.y")
            scale.values = [0.45, 1.0, 0.6, 0.9, 0.45]
            scale.keyTimes = [0, 0.3, 0.55, 0.8, 1]
            scale.duration = 0.9 + Double(index) * 0.17
            scale.repeatCount = .infinity
            scale.calculationMode = .paced
            bar.layer.add(scale, forKey: "eq87")
            _ = anim
        }
    }
}

/// 封面瓷砖（条带用）：74pt 方封面＋左上序号角标＋右下
/// 律动标记；在播态全亮＋放大 1.07＋金环，非在播 0.72 透
/// 明（样片 .cov/.cov.cur）。
final class CoverTile87: UIControl {
    let coverView = UIImageView()
    private let indexLabel = UILabel()
    private let eq = EqBars87View()
    private var coverTask: Task<Void, Never>?
    private(set) var trackId: String?

    var isCurrent = false {
        didSet { applyCurrent() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 13
        coverView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverView)

        indexLabel.font = .systemFont(ofSize: 9, weight: .bold)
        indexLabel.textColor = .white
        indexLabel.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        indexLabel.layer.cornerRadius = 4
        indexLabel.clipsToBounds = true
        indexLabel.textAlignment = .center
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indexLabel)

        eq.translatesAutoresizingMaskIntoConstraints = false
        eq.isHidden = true
        addSubview(eq)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverView.topAnchor.constraint(equalTo: topAnchor),
            coverView.bottomAnchor.constraint(equalTo: bottomAnchor),
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            indexLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            indexLabel.heightAnchor.constraint(equalToConstant: 14),
            indexLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            eq.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            eq.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            eq.widthAnchor.constraint(equalToConstant: 12),
            eq.heightAnchor.constraint(equalToConstant: 11),
        ])
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(track: FoliaTrack, index: Int, isCurrent: Bool, isPlaying: Bool) {
        trackId = track.id
        indexLabel.text = "\(index + 1)"
        self.isCurrent = isCurrent
        eq.setAnimating(isCurrent && isPlaying)
        loadCover(track: track)
    }

    private func applyCurrent() {
        alpha = isCurrent ? 1 : 0.72
        coverView.layer.borderWidth = isCurrent ? 2 : 0
        coverView.layer.borderColor = UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 0.9).cgColor
        transform = isCurrent ? CGAffineTransform(scaleX: 1.07, y: 1.07) : .identity
    }

    func loadCover(track: FoliaTrack) {
        coverTask?.cancel()
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

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.94, y: 0.94)
                    : (self.isCurrent ? CGAffineTransform(scaleX: 1.07, y: 1.07) : .identity)
            }
        }
    }
}

/// 网格单元（列表页/控制台队列视图）：封面（金环在播）＋
/// 歌名 12pt＋歌手 10.5pt（样片 .gcell）。
final class CoverGridCell87: UICollectionViewCell {
    static let reuseId = "CoverGridCell87"
    private let tile = CoverTile87()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private(set) var trackId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        tile.isUserInteractionEnabled = false
        tile.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tile)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        artistLabel.font = .systemFont(ofSize: 10.5)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artistLabel)
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tile.topAnchor.constraint(equalTo: contentView.topAnchor),
            tile.heightAnchor.constraint(equalTo: tile.widthAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: tile.bottomAnchor, constant: 6),
            artistLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(track: FoliaTrack, index: Int, isCurrent: Bool, isPlaying: Bool) {
        trackId = track.id
        titleLabel.text = track.title
        artistLabel.text = track.artist
        titleLabel.textColor = isCurrent
            ? UIColor(red: 1, green: 0.83, blue: 0.47, alpha: 1) : .white
        tile.configure(track: track, index: index, isCurrent: isCurrent, isPlaying: isPlaying)
        // 网格内不放大（样片 .gcell.cur 只加金环、不缩放）。
        tile.transform = .identity
        tile.alpha = isCurrent ? 1 : 0.85
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        trackId = nil
    }
}
