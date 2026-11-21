import UIKit
import Combine

// 3.7 (62) WD 簇：舞台背景体系（§6 背景 7 项）。
//
// 契约符号（WA 在 StageViewController 调用）：
//   StageBackdrop62.attach(to: container)
// attach 把背景层插到 container 最底层（渲染器层之下、宿主自带
// backdrop 三件套由 WA 决定让位），内部自订阅切歌/封面/进度，
// WA 不再逐帧驱动。模式存 SettingsStore.backdropMode62，选择入口
// 在样式选择器背景段（StageStylePickerViewController）。
//
// 模式：
//  - none：隐藏（样式自带背景当家）
//  - common：流体光晕（双色大团模糊圆缓慢漂移）+ 几何漂浮（环/方
//    低透明形缓慢旋转平移）——网页 common 的近似补齐
//  - latentCover / latentLyric / latentSpectrum：隐现三子型，
//    分别为封面 / 当前歌词行大字 / 频谱条，统一低透明（0.16–0.22）
//  - monet：莫奈 wash 从 monet 样式拆出的独立背景模式——以调色板
//    三色做多层径向 wash 渐变（近似 MonetStageRenderer 的 wash
//    观感，非逐像素烘焙；逐像素管线仍属 monet 样式本体）
//  - nomand：漫游纸感（米纸底色 + 程序点纹 + 轻暗角）
//  - sora：星空（星点层 + 缓漂 + 偶发亮星）
//  - url：远程图（D13 口径定版：URLSession 下载 → 本地缓存
//    Caches/folia-backdrop62 → 作背景图层；禁 WebView）
// 自定义背景（(47) 单槽）优先：CustomBackgroundStore 有槽位时
// 本层整体隐藏并在面包屑标注让位，二者互斥关系在选择器明示。

enum StageBackdrop62 {
    static func attach(to container: UIView) {
        StageBackdropHost62.shared.attach(to: container)
        RandomStylePerSong62.shared.startIfNeeded()
    }

    /// 选择器改模式后调用：广播刷新（宿主已订阅同一通知）。
    static func modeDidChange() {
        NotificationCenter.default.post(name: .foliaBackdropMode62Changed, object: nil)
    }
}

private final class StageBackdropHost62 {

    static let shared = StageBackdropHost62()

    private weak var container: UIView?
    private let root = UIView()
    private var contentLayer = UIView()
    private var cancellables = Set<AnyCancellable>()
    private var currentMode = ""
    private var currentTrackId: String?
    private var lyricLines: [LyricLineData] = []
    private var lyricLabel: UILabel?
    private var urlTask: Task<Void, Never>?

    private init() {
        root.isUserInteractionEnabled = false
        contentLayer.isUserInteractionEnabled = false
    }

    func attach(to container: UIView) {
        if self.container === container, root.superview === container { refresh() ; return }
        self.container = container
        root.removeFromSuperview()
        root.frame = container.bounds
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.insertSubview(root, at: 0)
        contentLayer.frame = root.bounds
        contentLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(contentLayer)
        bind()
        refresh()
        Breadcrumbs.log("stage62.backdrop attach mode=\(SettingsStore.backdropMode62)")
    }

    private func bind() {
        guard cancellables.isEmpty else { return }
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if track?.id != self.currentTrackId {
                    self.currentTrackId = track?.id
                    self.lyricLines = []
                    if let track { self.loadLyrics(for: track) }
                    self.refresh()
                }
            }
            .store(in: &cancellables)
        PlaybackEngine.shared.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        PlaybackEngine.shared.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.updateLyricLine(at: time) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .foliaBackdropMode62Changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func loadLyrics(for track: FoliaTrack) {
        let trackId = track.id
        Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: trackId)
            await MainActor.run {
                guard let self, self.currentTrackId == trackId else { return }
                self.lyricLines = entry.lines
            }
        }
    }

    // MARK: - 模式构建

    private func refresh() {
        guard container != nil else { return }
        let customActive = CustomBackgroundStore.current != nil
        let mode = SettingsStore.backdropMode62
        if customActive {
            root.isHidden = true
            if currentMode != "custom" {
                currentMode = "custom"
                Breadcrumbs.log("stage62.backdrop yield custom=1")
            }
            return
        }
        root.isHidden = (mode == "none")
        guard mode != currentMode || mode == "latentCover" || mode == "monet" else {
            if mode == "none" { currentMode = mode }
            return
        }
        currentMode = mode
        rebuild(mode: mode)
        if mode != "none" {
            Breadcrumbs.log("stage62.backdrop apply mode=\(mode)")
        }
    }

    private func rebuild(mode: String) {
        urlTask?.cancel()
        lyricLabel = nil
        for sub in contentLayer.subviews { sub.removeFromSuperview() }
        contentLayer.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let palette = currentPalette()
        switch mode {
        case "common": buildCommon(palette: palette)
        case "latentCover": buildLatentCover()
        case "latentLyric": buildLatentLyric(palette: palette)
        case "latentSpectrum": buildLatentSpectrum(palette: palette)
        case "monet": buildMonet(palette: palette)
        case "nomand": buildNomand()
        case "sora": buildSora()
        case "url": buildURL()
        default: break
        }
    }

    private func currentPalette() -> PaletteTokens {
        if let image = PlaybackEngine.shared.currentArtwork {
            return StagePalette.tokens(from: image)
        }
        return .neutralDark
    }

    private func fill(_ view: UIView) {
        view.frame = contentLayer.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentLayer.addSubview(view)
    }

    private func drift(_ view: UIView, dx: CGFloat, dy: CGFloat, duration: TimeInterval) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.repeat, .autoreverse, .curveEaseInOut]) {
            view.transform = CGAffineTransform(translationX: dx, y: dy)
        }
    }

    // MARK: common：流体光晕 + 几何漂浮

    private func buildCommon(palette: PaletteTokens) {
        let base = UIView(); base.backgroundColor = palette.background; fill(base)
        for (color, frame, dx, dy, dur) in [
            (palette.accent, CGRect(x: -80, y: -60, width: 320, height: 320), 36.0, 22.0, 9.0),
            (palette.primary, CGRect(x: 140, y: 260, width: 280, height: 280), -28.0, -30.0, 11.0),
        ] as [(UIColor, CGRect, CGFloat, CGFloat, TimeInterval)] {
            let blob = UIView(frame: frame)
            blob.backgroundColor = color.withAlphaComponent(0.30)
            blob.layer.cornerRadius = frame.width / 2
            blob.layer.shadowColor = color.cgColor
            blob.layer.shadowRadius = 60
            blob.layer.shadowOpacity = 0.8
            blob.layer.shadowOffset = .zero
            contentLayer.addSubview(blob)
            drift(blob, dx: dx, dy: dy, duration: dur)
        }
        for index in 0..<5 {
            let size = CGFloat(26 + index * 9)
            let shape = UIView(frame: CGRect(
                x: CGFloat(30 + index * 64), y: CGFloat(90 + (index % 3) * 130),
                width: size, height: size))
            shape.layer.borderWidth = 1.5
            shape.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
            if index % 2 == 0 { shape.layer.cornerRadius = size / 2 }
            contentLayer.addSubview(shape)
            drift(shape, dx: index % 2 == 0 ? 14 : -12, dy: -18, duration: 8 + Double(index))
        }
    }

    // MARK: latent 三子型

    private func buildLatentCover() {
        let base = UIView(); base.backgroundColor = .black; fill(base)
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = 0.20
        imageView.image = PlaybackEngine.shared.currentArtwork
        fill(imageView)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.alpha = 0.45
        fill(blur)
    }

    private func buildLatentLyric(palette: PaletteTokens) {
        let base = UIView(); base.backgroundColor = palette.background; fill(base)
        let label = UILabel()
        label.font = .systemFont(ofSize: 44, weight: .bold)
        label.textColor = palette.text.withAlphaComponent(0.17)
        label.textAlignment = .center
        label.numberOfLines = 3
        label.frame = contentLayer.bounds.insetBy(dx: 24, dy: 0)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.center = CGPoint(x: contentLayer.bounds.midX, y: contentLayer.bounds.midY)
        contentLayer.addSubview(label)
        lyricLabel = label
        updateLyricLine(at: PlaybackEngine.shared.currentTime)
    }

    private func buildLatentSpectrum(palette: PaletteTokens) {
        let base = UIView(); base.backgroundColor = palette.background; fill(base)
        let bars = UIView()
        fill(bars)
        let count = 28
        let width = max(contentLayer.bounds.width, 320)
        let barWidth = width / CGFloat(count) * 0.55
        for index in 0..<count {
            let bar = UIView()
            let x = (width / CGFloat(count)) * CGFloat(index) + barWidth * 0.4
            bar.frame = CGRect(x: x, y: contentLayer.bounds.height - 130,
                               width: barWidth, height: 60)
            bar.backgroundColor = palette.accent.withAlphaComponent(0.20)
            bar.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            bar.frame.origin.y = contentLayer.bounds.height - 70
            bars.addSubview(bar)
            if !UIAccessibility.isReduceMotionEnabled {
                let anim = CABasicAnimation(keyPath: "transform.scale.y")
                anim.fromValue = 0.35 + Double(index % 5) * 0.12
                anim.toValue = 1.25 - Double(index % 4) * 0.16
                anim.duration = 0.55 + Double(index % 7) * 0.09
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.layer.add(anim, forKey: "spectrum62")
            }
        }
    }

    private func updateLyricLine(at time: TimeInterval) {
        guard currentMode == "latentLyric", let label = lyricLabel else { return }
        var current: String?
        for line in lyricLines where line.time <= time { current = line.text }
        if label.text != current { label.text = current }
    }

    // MARK: monet 背景模式（wash 近似）

    private func buildMonet(palette: PaletteTokens) {
        let base = UIView(); base.backgroundColor = palette.background; fill(base)
        let wash = CAGradientLayer()
        wash.type = .radial
        wash.colors = [
            palette.accent.withAlphaComponent(0.5).cgColor,
            palette.primary.withAlphaComponent(0.28).cgColor,
            palette.background.cgColor,
        ]
        wash.locations = [0, 0.55, 1]
        wash.startPoint = CGPoint(x: 0.5, y: 0.42)
        wash.endPoint = CGPoint(x: 1, y: 1)
        wash.frame = contentLayer.bounds
        contentLayer.layer.addSublayer(wash)
        if let image = PlaybackEngine.shared.currentArtwork {
            let cover = UIImageView(image: image)
            cover.contentMode = .scaleAspectFill
            cover.clipsToBounds = true
            cover.alpha = 0.22
            fill(cover)
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            blur.alpha = 0.5
            fill(blur)
        }
    }

    // MARK: nomand 纸感

    private func buildNomand() {
        let base = UIView()
        base.backgroundColor = UIColor(red: 0.93, green: 0.90, blue: 0.83, alpha: 1)
        fill(base)
        // 程序点纹（纸纹近似）：确定性伪随机小点两层。
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func nextRand() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return CGFloat(seed % 1000) / 1000
        }
        let dots = CAShapeLayer()
        let path = UIBezierPath()
        let w = max(contentLayer.bounds.width, 320), h = max(contentLayer.bounds.height, 480)
        for _ in 0..<420 {
            let rect = CGRect(x: nextRand() * w, y: nextRand() * h, width: 1.4, height: 1.4)
            path.append(UIBezierPath(ovalIn: rect))
        }
        dots.path = path.cgPath
        dots.fillColor = UIColor(red: 0.45, green: 0.38, blue: 0.28, alpha: 0.20).cgColor
        dots.frame = contentLayer.bounds
        contentLayer.layer.addSublayer(dots)
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.18).cgColor]
        vignette.locations = [0.62, 1]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1, y: 1)
        vignette.frame = contentLayer.bounds
        contentLayer.layer.addSublayer(vignette)
    }

    // MARK: sora 星空

    private func buildSora() {
        let base = UIView()
        base.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)
        fill(base)
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func nextRand() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return CGFloat(seed % 1000) / 1000
        }
        let w = max(contentLayer.bounds.width, 320), h = max(contentLayer.bounds.height, 480)
        for index in 0..<90 {
            let size = 1 + nextRand() * 2.2
            let star = UIView(frame: CGRect(x: nextRand() * w, y: nextRand() * h,
                                            width: size, height: size))
            star.backgroundColor = .white
            star.layer.cornerRadius = size / 2
            star.alpha = 0.25 + nextRand() * 0.6
            contentLayer.addSubview(star)
            if !UIAccessibility.isReduceMotionEnabled, index % 3 == 0 {
                let twinkle = CABasicAnimation(keyPath: "opacity")
                twinkle.fromValue = star.alpha * 0.4
                twinkle.toValue = star.alpha
                twinkle.duration = 1.4 + Double(index % 5) * 0.35
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                star.layer.add(twinkle, forKey: "twinkle62")
            }
        }
        drift(contentLayer, dx: 0, dy: 6, duration: 14)
    }

    // MARK: url 嵌入（下载缓存，禁 WebView）

    private func buildURL() {
        let base = UIView(); base.backgroundColor = .black; fill(base)
        let raw = SettingsStore.backdropRemoteURL62
        guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else {
            Breadcrumbs.log("stage62.backdrop url invalid")
            return
        }
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-backdrop62", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let fileName = "bg-\(abs(raw.hashValue)).img"
        let fileURL = cacheDir.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            showURLImage(image)
            Breadcrumbs.log("stage62.backdrop url cacheHit=1")
            return
        }
        urlTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    Breadcrumbs.log("stage62.backdrop url decodeFail=1")
                    return
                }
                try? data.write(to: fileURL, options: .atomic)
                await MainActor.run {
                    guard let self, self.currentMode == "url" else { return }
                    self.showURLImage(image)
                    Breadcrumbs.log("stage62.backdrop url downloaded bytes=\(data.count)")
                }
            } catch {
                Breadcrumbs.log("stage62.backdrop url downloadFail=1")
            }
        }
    }

    private func showURLImage(_ image: UIImage) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        fill(imageView)
    }
}
