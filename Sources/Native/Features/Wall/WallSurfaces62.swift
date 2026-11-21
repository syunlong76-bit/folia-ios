import Combine
import UIKit

// (62) WD §1 墙面余项：墙缝信息条 StripSurface62 与墙后层
// WallBackdrop62。参数消费 WA 的 SettingsStore62A 访问器
// （跨簇契约名）：stripDirection / stripAlwaysTransparent /
// stripStyle / wallTransparency / wallWindowsPerPane /
// stackEdgesEnabled / backdropLyricsEnabled / backdropBlurAmount。
// 墙几何本体（BravaisFinite 等）一字不动：wallWindowsPerPane 与
// stackEdgesEnabled 只作只读参数在本层做视觉提示（窗格分隔线 /
// 叠页边线），不回写任何布局算法（消费深度见交付报告）。

// MARK: - 墙缝信息条

/// 墙缝处信息条：当前歌 / 播放时间 / 队列数。自订阅播放引擎
/// 与队列，不需宿主逐帧驱动。挂载于 HomeWall 工具条下方。
final class StripSurface62: UIView {

    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let queueLabel = UILabel()
    private let backgroundView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var cancellables = Set<AnyCancellable>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 13
        layer.masksToBounds = true

        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        queueLabel.font = .systemFont(ofSize: 11)
        queueLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        let stack = UIStackView(arrangedSubviews: [titleLabel, timeLabel, queueLabel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        applyStyle()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 样式消费（WA strip* 访问器）：stripStyle =
    /// glass（毛玻璃，缺省）/ solid（实色）/ clear（全透）；
    /// stripAlwaysTransparent 恒全透（压过 style）。
    private func applyStyle() {
        if SettingsStore.stripAlwaysTransparent || SettingsStore.stripStyle == 2 { // (62) 集成修正：WA 键为 Int 码（0 毛玻璃/1 实色/2 全透），WD 原按字符串码消费
            backgroundView.isHidden = true
            backgroundColor = .clear
        } else if SettingsStore.stripStyle == 1 {
            backgroundView.isHidden = true
            backgroundColor = UIColor(white: 0.08, alpha: 0.92)
        } else {
            backgroundView.isHidden = false
            backgroundColor = .clear
        }
    }

    private func bind() {
        let engine = PlaybackEngine.shared
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.titleLabel.text = track.map {
                    "\($0.title) · \($0.artist)"
                } ?? "未在播放"
            }
            .store(in: &cancellables)
        engine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTime() }
            .store(in: &cancellables)
        engine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTime() }
            .store(in: &cancellables)
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                self?.queueLabel.text = "队列 \(queue.count)"
            }
            .store(in: &cancellables)
        refreshTime()
    }

    private func refreshTime() {
        let engine = PlaybackEngine.shared
        timeLabel.text = "\(Self.format(engine.currentTime)) / \(Self.format(engine.duration))"
    }

    private static func format(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 墙后层

/// 墙后画面：插在墙画布之下（宿主把画布底色改透后可见）。
///  - 透光：当前封面大图以 wallTransparency 不透明度铺底；
///  - 模糊：UIVisualEffectView 叠层 alpha = backdropBlurAmount
///    （系统毛玻璃强度近似的标准手法）；
///  - 墙后歌词：backdropLyricsEnabled 时当前歌词行大字居中
///    低透明显示（歌词经 LyricRepository 既有通路）；
///  - 窗格/叠页边：wallWindowsPerPane 条竖向分隔线 +
///    stackEdgesEnabled 时四周叠页边线（只读参数的视觉提示，
///    不改墙布局几何）。
final class WallBackdrop62: UIView {

    private let coverView = UIImageView()
    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemMaterialDark))
    private let lyricLabel = UILabel()
    private let gridLayer = CAShapeLayer()
    private let edgeLayer = CAShapeLayer()
    private var cancellables = Set<AnyCancellable>()
    private var lyricTask: Task<Void, Never>?
    private var lyricKey = ""
    private var lines: [LyricLineData] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        addSubview(coverView)
        addSubview(blurView)
        lyricLabel.font = .systemFont(ofSize: 44, weight: .bold)
        lyricLabel.textColor = UIColor.white.withAlphaComponent(0.16)
        lyricLabel.textAlignment = .center
        lyricLabel.numberOfLines = 2
        addSubview(lyricLabel)
        layer.addSublayer(gridLayer)
        layer.addSublayer(edgeLayer)
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.05).cgColor
        gridLayer.lineWidth = 1
        edgeLayer.strokeColor = UIColor.white.withAlphaComponent(0.13).cgColor
        edgeLayer.lineWidth = 1
        edgeLayer.fillColor = nil

        applyParameters()
        bind()
        Breadcrumbs.log(
            "wall62.backdrop attach transparency=\(SettingsStore.wallTransparency) windows=\(SettingsStore.wallWindowsPerPane) edges=\(SettingsStore.stackEdgesEnabled ? 1 : 0) lyrics=\(SettingsStore.backdropLyricsEnabled ? 1 : 0) blur=\(SettingsStore.backdropBlurAmount)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        coverView.frame = bounds
        blurView.frame = bounds
        lyricLabel.frame = bounds.insetBy(dx: 32, dy: 0)
        drawGrid()
    }

    private func applyParameters() {
        coverView.alpha = CGFloat(SettingsStore.wallTransparency)
        blurView.alpha = CGFloat(SettingsStore.backdropBlurAmount)
        lyricLabel.isHidden = !SettingsStore.backdropLyricsEnabled
        edgeLayer.isHidden = !SettingsStore.stackEdgesEnabled
        drawGrid()
    }

    private func drawGrid() {
        let panes = max(SettingsStore.wallWindowsPerPane, 1)
        let path = UIBezierPath()
        if panes > 1 {
            for i in 1..<panes {
                let x = bounds.width * CGFloat(i) / CGFloat(panes)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: bounds.height))
            }
        }
        gridLayer.path = path.cgPath
        gridLayer.frame = bounds
        let edge = UIBezierPath()
        for offset in [CGFloat(5), CGFloat(10)] {
            edge.append(UIBezierPath(rect: bounds.insetBy(dx: offset, dy: offset)))
        }
        edgeLayer.path = edge.cgPath
        edgeLayer.frame = bounds
    }

    private func bind() {
        let engine = PlaybackEngine.shared
        engine.$currentArtwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in self?.coverView.image = image }
            .store(in: &cancellables)
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in self?.loadLyrics(for: track) }
            .store(in: &cancellables)
        engine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.updateLyric(at: time) }
            .store(in: &cancellables)
    }

    private func loadLyrics(for track: FoliaTrack?) {
        lyricTask?.cancel()
        lines = []
        lyricKey = track?.id ?? ""
        guard SettingsStore.backdropLyricsEnabled, let track else {
            lyricLabel.text = nil
            return
        }
        lyricTask = Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: track.id)
            await MainActor.run {
                guard let self, self.lyricKey == track.id else { return }
                self.lines = entry.lines
                self.updateLyric(at: PlaybackEngine.shared.currentTime)
            }
        }
    }

    private func updateLyric(at time: TimeInterval) {
        guard SettingsStore.backdropLyricsEnabled, !lines.isEmpty else { return }
        var current: String?
        for line in lines {
            if line.time <= time { current = line.text } else { break }
        }
        if lyricLabel.text != current { lyricLabel.text = current }
    }
}
