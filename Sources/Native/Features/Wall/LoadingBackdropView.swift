import UIKit

/// 曲目墙加载背板（拍立得切入）：
/// 点中歌单 → 封面套拍立得像框飞到中央 → 数据到达 → 整板淡出
/// （0.3 秒）、曲目墙接住。(12) 的「放大铺满全屏」段已删
/// （Miller 指其糊）；生命周期沿用 (8) 丝滑组合：等数据
/// ≤250ms 由 VC 的 present 时机决定、胶囊 >600ms 才现
/// （VC 侧）、数据到调 dismiss() 退场。
///
/// 3.7 (24) 改规格（Miller 19:59 点名，附图）：取消照片卡的
/// 循环翻转动画——照片固定展示，只保留入场淡入 + 落位弹簧；
/// 拍立得下白边居中落「小猫跳舞」贴纸（实况抠帧捂脸猫真动效
/// 定版，cat-live APNG 2.0s 原帧循环，72pt 宽，贴纸中心压在
/// 下白边中线：照片底沿 246 与卡底 282 之间），随加载态一同
/// 淡出。旧翻面体的圈界记账（pendingDismiss/pendingClose）
/// 随旋转取消一并退役：数据到即淡出、关闭即放行。
///
/// 吉祥物预留接口（Miller 定：吉祥物后面考虑，接口留给大肥鱼）：
/// mascotContainer 是加载态形象的挂载槽（标题下方）。
final class LoadingBackdropView: UIView {

    /// 吉祥物挂载槽（预留给大肥鱼）：标题下方区域，默认空。
    let mascotContainer = UIView()
    /// 关闭回调（24 前为翻面圈界拦截后的执行口；旋转取消后
    /// requestClose 恒放行，本回调不再被触发，保留接口兼容）。
    var onPendingClose: (() -> Void)?

    private enum Phase { case idle, appearing, shown, fadingOut, finished }

    /// 远景垫色（同图重模糊 + 重压暗，只负责给画面一点颜色）。
    private let bleedImageView = UIImageView()
    /// 拍立得卡容器（24 前是透视翻面体，现为固定展示）。
    private let cardView = UIView()
    private let frontView = UIView()
    private let photoImageView = UIImageView()
    private let titleLabel = UILabel()
    /// 小猫跳舞贴纸（cat-live，落拍立得下白边）。
    private let catSticker = StickerView()

    private var phase: Phase = .idle
    private var began = false
    private var dismissed = false
    private var pendingDismiss = false

    /// 拍立得几何：照片 236 见方、白边上/左/右 10、底 36。
    private static let cardSize = CGSize(width: 256, height: 282)
    private static let photoRect = CGRect(x: 10, y: 10, width: 236, height: 236)

    init(title: String?) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .black

        bleedImageView.contentMode = .scaleAspectFill
        bleedImageView.clipsToBounds = true
        bleedImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bleedImageView)
        // 模糊层：系统 GPU 模糊，不对原图做 CPU 重模糊（DS 坑单）。
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        let dim = UIView()
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)
        NSLayoutConstraint.activate([
            bleedImageView.topAnchor.constraint(equalTo: topAnchor),
            bleedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bleedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bleedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // 拍立得：白框卡 + 照片，固定展示（无翻面体）。
        cardView.alpha = 0
        addSubview(cardView)
        cardView.addSubview(frontView)

        frontView.backgroundColor = .white
        frontView.layer.cornerRadius = 8
        frontView.layer.shadowColor = UIColor.black.cgColor
        frontView.layer.shadowOpacity = 0.55
        frontView.layer.shadowRadius = 24
        frontView.layer.shadowOffset = CGSize(width: 0, height: 10)
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        photoImageView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        photoImageView.frame = Self.photoRect
        frontView.addSubview(photoImageView)

        // 小猫跳舞贴纸：72pt 宽（cat-live 原生 270×250），居中
        // 压在下白边上（中心 = 白边中线 y=264），随卡一同入场。
        catSticker.setSticker("cat-live", mode: .loop)
        frontView.addSubview(catSticker)

        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.9
        titleLabel.layer.shadowRadius = 6
        titleLabel.layer.shadowOffset = .zero
        addSubview(titleLabel)

        addSubview(mascotContainer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let card = Self.cardSize
        cardView.frame = CGRect(
            x: (bounds.width - card.width) / 2,
            y: (bounds.height - card.height) / 2 - 56,
            width: card.width, height: card.height)
        frontView.frame = cardView.bounds
        // 阴影走显式 path，避免每帧按 bounds 重算。
        frontView.layer.shadowPath = UIBezierPath(
            roundedRect: frontView.bounds, cornerRadius: 8).cgPath
        // 贴纸：宽 72、高按素材比例 250/270 ≈ 66.7；水平居中，
        // 垂直中心落在下白边中线（照片底 246 与卡底 282 的中点）。
        let stickerWidth: CGFloat = 72
        let stickerHeight = stickerWidth * 250 / 270
        catSticker.frame = CGRect(
            x: (card.width - stickerWidth) / 2,
            y: 264 - stickerHeight / 2,
            width: stickerWidth, height: stickerHeight)
        titleLabel.frame = CGRect(
            x: 32, y: cardView.frame.maxY + 22,
            width: bounds.width - 64, height: 44)
        mascotContainer.frame = CGRect(
            x: (bounds.width - 150) / 2, y: titleLabel.frame.maxY + 14,
            width: 150, height: 150)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { begin() }
    }

    // MARK: - 状态机

    /// 上屏即开场（预加载期在屏外创建，上屏前 dismiss 已调用则
    /// 永不开场——快路径下背板根本不露面）。入场 = 淡入 +
    /// 落位弹簧（缩放 0.92→1、下移回正），照片本体之后零位移。
    private func begin() {
        guard !began, !dismissed, phase == .idle else { return }
        began = true
        phase = .appearing
        cardView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            .translatedBy(x: 0, y: 14)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0.35,
                       options: [.curveEaseOut]) {
            self.cardView.alpha = 1
            self.cardView.transform = .identity
        } completion: { _ in
            guard self.phase == .appearing else { return }
            if self.pendingDismiss {
                // 数据在入场期就到：快路径，落位后直接退场。
                self.fadeOutNow()
                return
            }
            self.phase = .shown
        }
    }

    /// 数据到达后退场：idle 立即淡出、appearing 期记账等落位
    /// 完成、shown 立即淡出（全程与淡出不重叠的只有入场弹簧）。
    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        switch phase {
        case .idle, .shown:
            fadeOutNow()
        case .appearing:
            pendingDismiss = true
        case .fadingOut, .finished:
            break
        }
    }

    /// 关闭请求：旋转取消后无圈界可等，恒放行（VC 随即收墙）。
    func requestClose() -> Bool {
        return true
    }

    private func fadeOutNow() {
        phase = .fadingOut
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in
            self.phase = .finished
            self.removeFromSuperview()
        }
    }

    // MARK: - 封面

    /// 填封面：大档（1024 优先）→ 已缓存档 → 异步取 1024 一张两用
    /// （照片面 / 垫色）。来源都是内存缓存优先（主页墙刚显示过
    /// 这批封面），零额外等待是常态。
    func setCover(rawUrl: String?) {
        guard let rawUrl else { return }
        let loader = NativeCoverLoader.shared
        let embedded = NativeCoverLoader.wallTier(raw: rawUrl, pixelExtent: 100)
        var cardImage: UIImage?
        for tier in [1024, embedded, 512] {
            guard let urlString = loader.proxiedURLString(rawUrl, tier: tier),
                  let cached = loader.cachedImage(for: urlString) else { continue }
            cardImage = cached
            break
        }
        if let cardImage {
            applyCover(cardImage)
            return
        }
        guard let urlString = loader.proxiedURLString(rawUrl, tier: 1024) else { return }
        Task { [weak self] in
            let image = await loader.image(for: urlString, tier: 1024)
            guard let self, !self.dismissed, let image else { return }
            await MainActor.run { self.applyCover(image) }
        }
    }

    private func applyCover(_ image: UIImage) {
        photoImageView.image = image
        bleedImageView.image = image
    }
}
