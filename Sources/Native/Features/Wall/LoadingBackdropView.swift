import UIKit

/// 曲目墙加载背板（3.7 (12) 拍立得切入，Miller 2026-11-18 03:49
/// 拍板定版、DS27 状态机）：点中歌单 → 封面套拍立得像框飞到中央
/// 翻一整圈 → 放大时框淡去、画面铺满全屏 → 全屏封面停留期即加载
/// 等待 → 数据到达封面直接淡出、曲目墙接住。没有第二次翻面。
/// 生命周期沿用 (8) 丝滑组合：等数据 ≤250ms 由 VC 的 present 时
/// 机决定、胶囊 >600ms 才现（VC 侧）、数据到调 dismiss() 退场。
///
/// 状态机（DS27）：idle → flyIn → flip → fullHold → fadingOut。
/// 数据在 flyIn 期到 = 快路径（跳过翻面直接退场）；在 flip 期到
/// 不截断动画，记 pendingDismiss、fullHold 落定即退场。关闭在
/// flyIn/flip 期被拦截记 pendingClose，fullHold 后由 VC 执行
/// （关闭与数据同时到达时关闭优先）。
///
/// 吉祥物预留接口（Miller 定：吉祥物后面考虑，接口留给大肥鱼）：
/// mascotContainer 是加载态形象的挂载槽（标题下方）。
final class LoadingBackdropView: UIView {

    /// 吉祥物挂载槽（预留给大肥鱼）：标题下方区域，默认空。
    let mascotContainer = UIView()
    /// 关闭被拦截后、到达 fullHold 时回调（VC 据此执行关闭）。
    var onPendingClose: (() -> Void)?

    private enum Phase { case idle, flyIn, flip, fullHold, fadingOut, finished }

    /// 远景垫色（同图重模糊 + 重压暗，只负责给画面一点颜色）。
    private let bleedImageView = UIImageView()
    /// 透视容器（m34 挂在它的 sublayerTransform 上）。
    private let perspectiveContainer = UIView()
    /// 翻面体：正反两面都是它的子视图。
    private let flipView = UIView()
    private let frontView = UIView()
    private let photoImageView = UIImageView()
    private let backView = UIView()
    /// 铺满全屏的封面（展开阶段从照片位置长到全屏，停留期即它）。
    private let fullImageView = UIImageView()
    private let titleLabel = UILabel()

    private var phase: Phase = .idle
    private var flipDelegate: AnimationDelegate?
    private var began = false
    private var dismissed = false
    private var pendingDismiss = false
    private var pendingClose = false

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

        // 全屏封面（展开后才现身，先藏好）。
        fullImageView.contentMode = .scaleAspectFill
        fullImageView.clipsToBounds = true
        fullImageView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        fullImageView.alpha = 0
        addSubview(fullImageView)

        // 拍立得：透视容器 → 翻面体 → 正（白框+照片）/背（相纸素背）。
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 1400
        perspectiveContainer.layer.sublayerTransform = perspective
        perspectiveContainer.alpha = 0
        addSubview(perspectiveContainer)
        perspectiveContainer.addSubview(flipView)

        frontView.backgroundColor = .white
        frontView.layer.cornerRadius = 8
        frontView.layer.shadowColor = UIColor.black.cgColor
        frontView.layer.shadowOpacity = 0.55
        frontView.layer.shadowRadius = 24
        frontView.layer.shadowOffset = CGSize(width: 0, height: 10)
        frontView.layer.isDoubleSided = false
        flipView.addSubview(frontView)

        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        photoImageView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        photoImageView.frame = Self.photoRect
        frontView.addSubview(photoImageView)

        backView.backgroundColor = UIColor(white: 0.93, alpha: 1)
        backView.layer.cornerRadius = 8
        backView.layer.isDoubleSided = false
        backView.layer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
        flipView.addSubview(backView)

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
        perspectiveContainer.frame = CGRect(
            x: (bounds.width - card.width) / 2,
            y: (bounds.height - card.height) / 2 - 56,
            width: card.width, height: card.height)
        flipView.frame = perspectiveContainer.bounds
        frontView.frame = flipView.bounds
        backView.frame = flipView.bounds
        // 阴影走显式 path，避免每帧按 bounds 重算。
        frontView.layer.shadowPath = UIBezierPath(
            roundedRect: frontView.bounds, cornerRadius: 8).cgPath
        titleLabel.frame = CGRect(
            x: 32, y: perspectiveContainer.frame.maxY + 22,
            width: bounds.width - 64, height: 44)
        mascotContainer.frame = CGRect(
            x: (bounds.width - 150) / 2, y: titleLabel.frame.maxY + 14,
            width: 150, height: 150)
        if phase == .fullHold || phase == .fadingOut {
            fullImageView.frame = bounds
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { begin() }
    }

    // MARK: - 状态机

    /// 上屏即开场（预加载期在屏外创建，上屏前 dismiss 已调用则
    /// 永不开场——快路径下背板根本不露面）。
    private func begin() {
        guard !began, !dismissed, phase == .idle else { return }
        began = true
        phase = .flyIn
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.perspectiveContainer.alpha = 1
        } completion: { _ in
            guard self.phase == .flyIn else { return }
            if self.pendingDismiss {
                // 数据在 flyIn 期就到：快路径，跳过翻面直接退场。
                self.fadeOutNow()
                return
            }
            self.startFlip()
        }
    }

    private func startFlip() {
        phase = .flip
        func keyframe(_ angle: CGFloat, _ scale: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeRotation(angle, 0, 1, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            return t
        }
        let flip = CAKeyframeAnimation(keyPath: "transform")
        flip.values = [
            NSValue(caTransform3D: keyframe(0, 0.8)),
            NSValue(caTransform3D: keyframe(.pi, 0.9)),
            NSValue(caTransform3D: keyframe(2 * .pi, 1.0))
        ]
        flip.keyTimes = [0, 0.5, 1]
        flip.duration = 1.0
        flip.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        // CAAnimation 不强持 delegate，须由视图自己留住它到回调落地。
        let delegate = AnimationDelegate { [weak self] in self?.flipFinished() }
        flipDelegate = delegate
        flip.delegate = delegate
        flipView.layer.add(flip, forKey: "foliaPolaroidFlip")
        flipView.layer.transform = keyframe(2 * .pi, 1.0)
    }

    private func flipFinished() {
        flipDelegate = nil
        guard phase == .flip else { return }
        // 展开：全屏封面从照片的当前位置长到全屏，像框同时淡去。
        let start = photoImageView.convert(photoImageView.bounds, to: self)
        fullImageView.frame = start
        fullImageView.alpha = 1
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseOut]) {
            self.fullImageView.frame = self.bounds
            self.perspectiveContainer.alpha = 0
            self.titleLabel.alpha = 0
            self.mascotContainer.alpha = 0
        } completion: { _ in
            self.phase = .fullHold
            self.perspectiveContainer.isHidden = true
            // 停留期给全屏封面一点极慢的呼吸，别死贴着。
            let drift = CABasicAnimation(keyPath: "transform.scale")
            drift.fromValue = 1.0
            drift.toValue = 1.04
            drift.duration = 6
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.fullImageView.layer.add(drift, forKey: "foliaCoverDrift")
            if self.pendingClose {
                self.onPendingClose?()
            } else if self.pendingDismiss {
                self.fadeOutNow()
            }
        }
    }

    /// 数据到达后退场：flyIn 期走快路径、flip 期记账等落定、
    /// fullHold 立即淡出（DS27 状态机）。
    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        switch phase {
        case .idle, .fullHold:
            fadeOutNow()
        case .flyIn, .flip:
            pendingDismiss = true
        case .fadingOut, .finished:
            break
        }
    }

    /// 关闭请求：flyIn/flip 期拦截并记账（返回 false），其余放行。
    func requestClose() -> Bool {
        switch phase {
        case .flyIn, .flip:
            pendingClose = true
            return false
        default:
            return true
        }
    }

    private func fadeOutNow() {
        phase = .fadingOut
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in
            self.phase = .finished
            self.removeFromSuperview()
        }
    }

    // MARK: - 封面

    /// 填封面：大档（1024 优先）→ 已缓存档 → 异步取 1024 一张三用
    /// （照片面 / 全屏面 / 垫色）。来源都是内存缓存优先（主页墙刚
    /// 显示过这批封面），零额外等待是常态。
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
        if phase == .fullHold || phase == .fadingOut {
            UIView.transition(with: fullImageView, duration: 0.3,
                              options: [.transitionCrossDissolve]) {
                self.fullImageView.image = image
            }
        } else {
            fullImageView.image = image
        }
    }
}

/// CAAnimation 完成回调的最小承接（动画本身留在 layer 上，
/// 落位靠 flipView.layer.transform 的预设终值，不依赖回调改状态）。
private final class AnimationDelegate: NSObject, CAAnimationDelegate {
    private let onStop: () -> Void
    init(onStop: @escaping () -> Void) { self.onStop = onStop }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag { onStop() }
    }
}
