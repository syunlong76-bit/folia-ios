import UIKit

/// 曲目墙加载氛围底（3.7 (8) 丝滑切入组合，DS 第二十四轮对账定版）：
/// 切入第一帧用该歌单封面（主页墙刚显示过、内存缓存现成）做模糊
/// 氛围底 + 歌单名，替代「黑页 + 载入文字」；数据到达后由 VC 调
/// dismiss() 淡出，只作过渡层、不留视觉重复。
///
/// 吉祥物预留接口（Miller 2026-11-18 定：吉祥物后面考虑，接口留给
/// 大肥鱼）：mascotContainer 是加载态形象的挂载槽——将来把吉祥物
/// 视图 add 进这里即可，出现阈值/退场节奏由 VC 的加载状态机统一
/// 驱动，吉祥物本身不感知数据层。
final class LoadingBackdropView: UIView {

    /// 吉祥物挂载槽（预留给大肥鱼）：居中正方形区域，默认空。
    let mascotContainer = UIView()

    private let coverImageView = UIImageView()
    private let titleLabel = UILabel()
    private var dismissed = false

    init(title: String?) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .black

        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverImageView)

        // 模糊层：系统 GPU 模糊，不对原图做 CPU 重模糊（DS 坑单）。
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        // 压暗 + 顶部微光：暗封面糊成一团时靠它保住标题可读性。
        let dim = UIView()
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)
        let glow = UIView()
        glow.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        glow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glow)

        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
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
            coverImageView.topAnchor.constraint(equalTo: topAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            glow.topAnchor.constraint(equalTo: topAnchor),
            glow.leadingAnchor.constraint(equalTo: leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: trailingAnchor),
            glow.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.4),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -70),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            mascotContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            mascotContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40),
            mascotContainer.widthAnchor.constraint(equalToConstant: 180),
            mascotContainer.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// 填封面：先同步查内存缓存的几个候选档（主页墙用过的档），
    /// 未命中再异步取 512 档，到达时若还没退场就补上。
    func setCover(rawUrl: String?) {
        guard let rawUrl else { return }
        let loader = NativeCoverLoader.shared
        let embedded = NativeCoverLoader.wallTier(raw: rawUrl, pixelExtent: 100)
        for tier in [embedded, 1024, 512] {
            guard let urlString = loader.proxiedURLString(rawUrl, tier: tier),
                  let cached = loader.cachedImage(for: urlString) else { continue }
            coverImageView.image = cached
            return
        }
        guard let urlString = loader.proxiedURLString(rawUrl, tier: 512) else { return }
        Task { [weak self] in
            let image = await loader.image(for: urlString, tier: 512)
            guard let self, !self.dismissed, let image else { return }
            await MainActor.run {
                UIView.transition(with: self.coverImageView, duration: 0.3,
                                  options: [.transitionCrossDissolve]) {
                    self.coverImageView.image = image
                }
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
