import UIKit

/// 曲目墙加载氛围底（3.7 (8) 丝滑切入组合，DS 第二十四轮对账定版；
/// 3.7 (9) 按 Miller 验收建议改版）：加载视觉的主角是歌单封面
/// 本人——居中一张清晰的封面卡做呼吸缩放动画，远景只留压暗的
/// 模糊同图垫色，标题在卡下。数据到达后由 VC 调 dismiss() 淡出。
///
/// 吉祥物预留接口（Miller 2026-11-18 定：吉祥物后面考虑，接口留给
/// 大肥鱼）：mascotContainer 是加载态形象的挂载槽（标题下方）——
/// 将来把吉祥物视图 add 进这里即可，出现阈值/退场节奏由 VC 的
/// 加载状态机统一驱动，吉祥物本身不感知数据层。
final class LoadingBackdropView: UIView {

    /// 吉祥物挂载槽（预留给大肥鱼）：标题下方区域，默认空。
    let mascotContainer = UIView()

    /// 远景垫色（同图重模糊 + 重压暗，只负责给画面一点颜色）。
    private let bleedImageView = UIImageView()
    /// 主角：清晰封面卡（呼吸动画挂在它身上）。
    private let cardImageView = UIImageView()
    private let titleLabel = UILabel()
    private var dismissed = false

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

        // 封面卡：圆角 + 阴影，呼吸缩放就是加载动画本体。
        cardImageView.contentMode = .scaleAspectFill
        cardImageView.clipsToBounds = true
        cardImageView.layer.cornerRadius = 16
        cardImageView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        cardImageView.translatesAutoresizingMaskIntoConstraints = false
        let cardShadow = UIView()
        cardShadow.layer.shadowColor = UIColor.black.cgColor
        cardShadow.layer.shadowOpacity = 0.55
        cardShadow.layer.shadowRadius = 24
        cardShadow.layer.shadowOffset = CGSize(width: 0, height: 10)
        cardShadow.translatesAutoresizingMaskIntoConstraints = false
        cardShadow.addSubview(cardImageView)
        addSubview(cardShadow)

        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.9
        titleLabel.layer.shadowRadius = 6
        titleLabel.layer.shadowOffset = .zero
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        mascotContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mascotContainer)

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
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardShadow.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardShadow.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -56),
            cardShadow.widthAnchor.constraint(equalToConstant: 236),
            cardShadow.heightAnchor.constraint(equalToConstant: 236),
            cardImageView.topAnchor.constraint(equalTo: cardShadow.topAnchor),
            cardImageView.bottomAnchor.constraint(equalTo: cardShadow.bottomAnchor),
            cardImageView.leadingAnchor.constraint(equalTo: cardShadow.leadingAnchor),
            cardImageView.trailingAnchor.constraint(equalTo: cardShadow.trailingAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: cardShadow.bottomAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            mascotContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            mascotContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            mascotContainer.widthAnchor.constraint(equalToConstant: 150),
            mascotContainer.heightAnchor.constraint(equalToConstant: 150)
        ])
        cardShadow.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: 236, height: 236), cornerRadius: 16).cgPath

        // 呼吸：1.0 ↔ 1.045、1.5 秒往返，封面卡活过来而不是死贴图。
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1.0
        breath.toValue = 1.045
        breath.duration = 1.5
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cardShadow.layer.add(breath, forKey: "foliaCoverBreath")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// 填封面：卡用大档（1024 优先），垫色用任意已缓存档；都未命中
    /// 再异步取 1024 档一张两用。来源都是内存缓存优先（主页墙刚
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
            cardImageView.image = cardImage
            bleedImageView.image = cardImage
            return
        }
        guard let urlString = loader.proxiedURLString(rawUrl, tier: 1024) else { return }
        Task { [weak self] in
            let image = await loader.image(for: urlString, tier: 1024)
            guard let self, !self.dismissed, let image else { return }
            await MainActor.run {
                UIView.transition(with: self.cardImageView, duration: 0.3,
                                  options: [.transitionCrossDissolve]) {
                    self.cardImageView.image = image
                }
                self.bleedImageView.image = image
            }
        }
    }

    /// 数据到达后退场：0.35 秒淡出并移出层级（不留常驻层）。
    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
