import UIKit

/// (102) 第 1 项：歌单页海报视图（样板 v4 #view-poster
/// 定版移植）＋ v4 定版数值单源（PlaylistLayout102）。
///
/// 样板定版：整页海报左右滑选歌（横向分页、snap 吸附、
/// 系统分页手感）、每首一整页——同图重模糊垫底＋方形
/// 原比例大图＋海报式题注（歌名 28/700、歌手 15.5 透
/// 白）；滑定后胶囊台同步到该首（宿主回调 onSettle）；
/// 点海报即播（onTapPlay）。此视图下缝收起让位、胶囊
/// 台常驻（宿主侧装配：海报层在台之下、缝只剩头像）。
///
/// 大图口径（任务书定）：原生侧取大图参数单独缓存——
/// 网易云 ?param= 改 1000y1000、QQ R300x300→R1000x1000、
/// 酷狗 stdmusic 尺寸段改 1000；加载走 NativeCoverLoader
/// （按 URL 独立缓存键、与缩略档天然分开），缩略图不放
/// 大用。样板大图为 1440 宽，平台原图上限各异，取
/// 1000 档为画质/流量折中（数值待真机验）。
enum PlaylistLayout102 {

    /// 书库页宽缝（样板 .lib-seam）：竖屏 248 / 横屏 272、
    /// 缝内间距 40、底部细线齿轮。原生落点待定（见 (102)
    /// 交付报告分叉项），先立单源。
    static let librarySeamPortrait: CGFloat = 248
    static let librarySeamLandscape: CGFloat = 272
    static let librarySeamGap: CGFloat = 40

    /// 海报视图（样板 .poster 定版）。
    static let posterArtMaxSide: CGFloat = 460
    static let posterArtHeightFraction: CGFloat = 0.56
    static let posterArtLandscapeMaxSide: CGFloat = 340
    static let posterTitleFont: CGFloat = 28
    static let posterArtistFont: CGFloat = 15.5
    static let posterCaptionGap: CGFloat = 24
    static let posterSidePadding: CGFloat = 28

    /// 歌单页头部（样板 v4）：缝收起＝左上角圆形头像
    /// （直径 36）、右上角搜索钮（36）。
    static let headerButtonSide: CGFloat = 36
    static let headerInset: CGFloat = 12

    /// 大图档（像素宽）。
    static let posterImageTier = 1440

    /// 平台封面大图地址改写（任务书口径）。非平台地址
    /// 原样返回（走加载器档位体系）。
    static func largeCoverURLString(_ raw: String) -> String {
        var s = raw
        // QQ 音乐：地址内 R300x300 尺寸段 → R1000x1000。
        if s.contains("qq.com") || s.contains("qpic.cn") {
            s = s.replacingOccurrences(
                of: #"R\d+x\d+"#, with: "R1000x1000",
                options: .regularExpression)
            return s
        }
        // 酷狗：stdmusic/<尺寸>/ 段 → 1000。
        if s.contains("kugou.com") {
            s = s.replacingOccurrences(
                of: #"stdmusic/\d+"#, with: "stdmusic/1000",
                options: .regularExpression)
            return s
        }
        // 网易云：?param=<w>x<h> / <w>y<h> → 1000y1000；
        // 无 param 时补上。
        if s.contains("music.126.net") || s.contains("126.net") {
            if s.contains("param=") {
                s = s.replacingOccurrences(
                    of: #"param=[0-9]+[xy][0-9]+"#, with: "param=1000y1000",
                    options: .regularExpression)
            } else {
                s += (s.contains("?") ? "&" : "?") + "param=1000y1000"
            }
            return s
        }
        return s
    }
}

/// 海报视图切换字形（24 画布细线：方框＋日头＋山脊，
/// 与 SeamGlyph93 同语言），供宿主视图胶囊第四格用。
enum PosterGlyph102 {
    static func image(pointSize: CGFloat = 16) -> UIImage? {
        let scale = pointSize / 24
        let size = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setStroke()
            UIColor.white.setFill()
            let box = UIBezierPath(roundedRect: CGRect(
                x: 4.5 * scale, y: 4.5 * scale,
                width: 15 * scale, height: 15 * scale),
                cornerRadius: 2.5 * scale)
            box.lineWidth = 1.5 * scale
            box.stroke()
            UIBezierPath(ovalIn: CGRect(
                x: 8 * scale, y: 8 * scale,
                width: 3.4 * scale, height: 3.4 * scale)).fill()
            let ridge = UIBezierPath()
            ridge.move(to: CGPoint(x: 5.5 * scale, y: 17.5 * scale))
            ridge.addLine(to: CGPoint(x: 10.5 * scale, y: 12.8 * scale))
            ridge.addLine(to: CGPoint(x: 14 * scale, y: 15.6 * scale))
            ridge.addLine(to: CGPoint(x: 16 * scale, y: 13.8 * scale))
            ridge.addLine(to: CGPoint(x: 18.5 * scale, y: 17.5 * scale))
            ridge.lineWidth = 1.5 * scale
            ridge.lineJoinStyle = .round
            ridge.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// 海报分页视图：横向分页滚动、每页一首。宿主只喂数据
/// 与回调，本视图不管播放与台面。
final class PosterView102: UIView, UIScrollViewDelegate {

    struct Item {
        let title: String
        let artist: String
        let picUrl: String?
    }

    /// 滑定（分页落定且页码变化）→ 宿主同步胶囊台。
    var onSettle: ((Int) -> Void)?
    /// 点按当前海报 → 宿主播放该首。
    var onTapPlay: ((Int) -> Void)?

    private let scroll = UIScrollView()
    private var pages: [PosterPage102] = []
    private var items: [Item] = []
    private(set) var currentIndex = 0
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.047, alpha: 1)
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = self
        scroll.contentInsetAdjustmentBehavior = .never
        addSubview(scroll)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap102))
        scroll.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    @objc private func handleTap102() {
        guard !items.isEmpty else { return }
        onTapPlay?(currentIndex)
    }

    func setItems(_ newItems: [Item]) {
        items = newItems
        currentIndex = min(currentIndex, max(0, items.count - 1))
        rebuildPages()
    }

    func scrollTo(index: Int, animated: Bool) {
        guard index >= 0, index < items.count, bounds.width > 0 else { return }
        currentIndex = index
        scroll.setContentOffset(
            CGPoint(x: CGFloat(index) * bounds.width, y: 0), animated: animated)
    }

    private func rebuildPages() {
        for page in pages { page.removeFromSuperview() }
        pages = items.map { item in
            let page = PosterPage102()
            page.configure(item: item)
            scroll.addSubview(page)
            return page
        }
        layoutPages()
    }

    private func layoutPages() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        scroll.frame = bounds
        scroll.contentSize = CGSize(width: w * CGFloat(max(items.count, 1)), height: h)
        for (i, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
            page.layoutInBounds()
        }
        scroll.contentOffset = CGPoint(x: CGFloat(currentIndex) * w, y: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            layoutPages()
        }
    }

    // MARK: UIScrollViewDelegate（分页落定＝系统减速收口）

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                  willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    private func settle() {
        guard bounds.width > 0, !items.isEmpty else { return }
        let idx = Int((scroll.contentOffset.x / bounds.width).rounded())
        let clamped = min(max(idx, 0), items.count - 1)
        if clamped != currentIndex {
            currentIndex = clamped
            onSettle?(clamped)
        }
    }
}

/// 单页海报：模糊垫底＋方形大图＋题注（样板 .poster）。
private final class PosterPage102: UIView {

    private let bgView = UIImageView()
    private let shade = UIView()
    private let artView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        bgView.contentMode = .scaleAspectFill
        bgView.clipsToBounds = true
        addSubview(bgView)
        // 同图重模糊：以视觉效果层压在垫底图上（样板
        // filter: blur(60px) 的等效近似，另加暗罩保题注
        // 可读）。
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(shade)
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        artView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        addSubview(artView)
        titleLabel.font = .systemFont(ofSize: PlaylistLayout102.posterTitleFont,
                                      weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.shadowColor = UIColor.black.withAlphaComponent(0.5)
        titleLabel.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(titleLabel)
        artistLabel.font = .systemFont(ofSize: PlaylistLayout102.posterArtistFont)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        artistLabel.numberOfLines = 1
        addSubview(artistLabel)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(item: PosterView102.Item) {
        titleLabel.text = item.title
        artistLabel.text = item.artist
        loadTask?.cancel()
        bgView.image = nil
        artView.image = nil
        guard let raw = item.picUrl else { return }
        let big = PlaylistLayout102.largeCoverURLString(raw)
        loadTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(
                for: big, tier: PlaylistLayout102.posterImageTier)
            guard let self, !Task.isCancelled, let image else { return }
            self.bgView.image = image
            self.artView.image = image
        }
    }

    /// 样板构图：竖屏纵列（大图在上、题注同宽在下）；
    /// 横屏横列（大图在左、题注在右）。
    func layoutInBounds() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        bgView.frame = bounds
        shade.frame = bounds
        if h >= w {
            let side = min(w - PlaylistLayout102.posterSidePadding * 2,
                           PlaylistLayout102.posterArtMaxSide,
                           h * PlaylistLayout102.posterArtHeightFraction)
            let artY = safeAreaInsets.top + 64
            artView.frame = CGRect(x: (w - side) / 2, y: artY,
                                   width: side, height: side)
            let capY = artY + side + PlaylistLayout102.posterCaptionGap
            titleLabel.frame = CGRect(
                x: (w - side) / 2, y: capY, width: side, height: 70)
            artistLabel.frame = CGRect(
                x: (w - side) / 2, y: capY + 64, width: side, height: 22)
        } else {
            let side = min(h - 150, PlaylistLayout102.posterArtLandscapeMaxSide)
            let artY = (h - side) / 2 - 10
            artView.frame = CGRect(
                x: PlaylistLayout102.posterSidePadding, y: artY,
                width: side, height: side)
            let capX = PlaylistLayout102.posterSidePadding + side + 28
            titleLabel.frame = CGRect(
                x: capX, y: artY + side / 2 - 50,
                width: min(320, w - capX - 20), height: 70)
            artistLabel.frame = CGRect(
                x: capX, y: artY + side / 2 + 14,
                width: min(320, w - capX - 20), height: 22)
        }
    }
}
