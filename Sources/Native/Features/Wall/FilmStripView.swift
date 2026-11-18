import UIKit
import ImageIO

/// 主页入场「电影长卷」（3.7 (12)，Miller 2026-11-18 03:58 定版、
/// 04:5x 高清版阵容，DS27 B 纪律）：主页墙数据在途时，五条电影
/// 剧照横带按左→右→左交替滑入铺满全屏、各自 Ken Burns 缓推；
/// 加载慢则在 5.6s/6.3s 换入两条新带；数据到达整卷淡出进主页墙。
/// 数据已缓存（play 前 finish）则整段不播。
///
/// 素材：海蒂和爷爷 / 情书 / 小森林 / 梦 四部剧照 7 张（包内
/// Resources/FilmStrip，已预降采样至 2048 边）。运行时按带尺寸
/// 再解码到 ≤1200px：同时持有 ≤2 张待换带图，解码内存 ≤30MB；
/// 内存警告或解码失败即整段跳过（回落黑底 + 状态胶囊）。
final class FilmStripView: UIView {

    /// 初始五带（上→下）与慢加载换带（带索引， 换入图， 时刻秒）。
    private static let initialBands = [
        "heidi-fence", "love-b", "forest-2", "dreams-2", "forest-1"
    ]
    private static let swaps: [(band: Int, name: String, at: TimeInterval)] = [
        (0, "dreams-4", 5.6), (2, "dreams-8", 6.3)
    ]
    /// 解码上限（px）：带宽约 1170px（390pt@3x），1200 够满幅。
    private static let decodeMaxPixel = 1200

    private var bandClips: [UIView] = []
    private var bandSlides: [UIView] = []
    private var bandImages: [UIImageView] = []
    private var pending: [DispatchWorkItem] = []
    private var playing = false
    private var finished = false
    private var memoryObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in
            // 内存兜底（DS27）：警告即整段跳过，不与墙争内存。
            self?.finish("memory-warning")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
    }

    // MARK: - 播放

    /// 上屏且数据仍在途时调用；已 finish（数据先到）则永不播。
    func play() {
        guard !playing, !finished, bandClips.isEmpty else { return }
        playing = true
        buildBands()
        let width = bounds.width
        for (i, slide) in bandSlides.enumerated() {
            // 交替方向滑入：偶数带自左、奇数带自右（定版编排）。
            slide.transform = CGAffineTransform(
                translationX: i % 2 == 0 ? -width : width, y: 0)
            UIView.animate(withDuration: 1.4, delay: Double(i) * 0.15,
                           options: [.curveEaseOut]) {
                slide.transform = .identity
            } completion: { _ in
                self.startKenBurns(band: i)
            }
        }
        for swap in Self.swaps {
            let item = DispatchWorkItem { [weak self] in
                self?.performSwap(band: swap.band, name: swap.name)
            }
            pending.append(item)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + swap.at, execute: item)
        }
    }

    /// 重进主页墙的静态氛围底（3.7 (13.2)）：长卷每启动只播一次，
    /// 重进的新实例数据在途时不再纯黑——铺五带静止剧照压暗垫底，
    /// 不滑入、不 Ken Burns、不换带；加载落定仍走 finish 淡出。
    func showStillBackdrop() {
        guard !playing, !finished, bandClips.isEmpty,
              bounds.width > 0, bounds.height > 0 else { return }
        buildBands()
        let dim = UIView(frame: bounds)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(dim)
        Breadcrumbs.log("film still backdrop shown")
    }

    /// 数据到达（或失败/未登录/内存警告）：整卷淡出并自拆。
    /// reason 必记面包屑（3.7 (13.1)，DS32）：黑屏归因要能区分
    /// 加载落定、重进跳过与内存警告三条 finish 路径。
    func finish(_ reason: String = "load-resolved") {
        guard !finished else { return }
        finished = true
        Breadcrumbs.log("film finish reason=\(reason)")
        pending.forEach { $0.cancel() }
        pending.removeAll()
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
            self.memoryObserver = nil
        }
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    // MARK: - 内部

    private func buildBands() {
        let bandHeight = bounds.height / CGFloat(Self.initialBands.count)
        for (i, name) in Self.initialBands.enumerated() {
            let clip = UIView(frame: CGRect(
                x: 0, y: CGFloat(i) * bandHeight,
                width: bounds.width, height: bandHeight))
            clip.clipsToBounds = true
            clip.backgroundColor = UIColor(white: 0.08, alpha: 1)
            let slide = UIView(frame: clip.bounds)
            let imageView = UIImageView(frame: clip.bounds)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            slide.addSubview(imageView)
            clip.addSubview(slide)
            addSubview(clip)
            bandClips.append(clip)
            bandSlides.append(slide)
            bandImages.append(imageView)
            if let image = Self.decode(name: name) {
                imageView.image = image
            } else {
                // 单带解码失败不整段跳：留深灰带（其余带照常）。
                imageView.image = nil
            }
        }
    }

    private func startKenBurns(band: Int) {
        guard !finished, band < bandImages.count else { return }
        let layer = bandImages[band].layer
        guard layer.animation(forKey: "foliaKenBurns") == nil else { return }
        let kb = CABasicAnimation(keyPath: "transform.scale")
        kb.fromValue = 1.0
        kb.toValue = 1.06
        kb.duration = 7
        kb.autoreverses = true
        kb.repeatCount = .infinity
        kb.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(kb, forKey: "foliaKenBurns")
    }

    private func performSwap(band: Int, name: String) {
        guard !finished, band < bandImages.count,
              let image = Self.decode(name: name) else { return }
        UIView.transition(with: bandImages[band], duration: 0.8,
                          options: [.transitionCrossDissolve]) {
            self.bandImages[band].image = image
        }
    }

    /// ImageIO 缩略图解码：只解到带尺寸量级，不整图进内存。
    private static func decode(name: String) -> UIImage? {
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "jpg",
            subdirectory: "FilmStrip"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeMaxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
