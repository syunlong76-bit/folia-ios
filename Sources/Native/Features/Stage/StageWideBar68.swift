import UIKit

/// 舞台全宽控制条出样（3.7 (68) B 组，Miller 点名「出一版对比
/// 用」）：舞台点屏唤出一条全宽控制条——进度＋播放控制一行
/// 全宽（形态参考社区版录屏核验 §七），闲置 5 秒自隐（与本
/// App 顶栏/迷你台的 5 秒 chrome 纪律同值）。
///
/// 出样纪律（DS 对账 Q1·P8 约束＋任务书口径）：
/// - 设置开关 `SettingsStore.wideBar68Enabled` 缺省关；关时
///   本条不装配识别器、不响应，舞台行为与现行逐项一致。
/// - 与现行点播台/顶栏**并存可比**：不迁移、不废弃任何现行
///   控制；唤出时全宽条浮压在底部、盖住点播台所在带，自隐
///   后点播台原样露出。
/// - 可整体摘除：本体只住本文件；外部钩子仅 StageVC 的装配/
///   同步/进度喂入三处、SettingsStore62A 一键、设置面一行。
/// - 命令落点与舞台既有控制完全同路（VC 闭包注入：toggle →
///   PlaybackEngine、prev/next → QueueManager、seek →
///   StageVC.performSeek），本条不自建第二套播放逻辑。
/// - 动效守 iOS 口径：入场系统弹簧（0.5s/damping 0.85，与
///   迷你台形态弹簧同值）、退场自然减速淡出；Reduce Motion
///   时降级为纯 alpha。
final class StageWideBar68: UIView {

    /// 内容行高（不含底部安全区填充，帧高由宿主按安全区补）。
    static let contentHeight: CGFloat = 64
    /// 闲置自隐秒数（顶栏自动隐藏同值）。
    static let idleSeconds: TimeInterval = 5

    var onTogglePlay: (() -> Void)?
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    /// 松手落点 seek（fraction 0...1），宿主换算成秒走既有通路。
    var onSeek: ((Double) -> Void)?

    private(set) var isBarVisible = false

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let topHairline = UIView()
    private let prevButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let elapsedLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = UISlider()

    private var hideWorkItem: DispatchWorkItem?
    private var isSeeking = false
    private var duration: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        isHidden = true
        alpha = 0

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        topHairline.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        topHairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topHairline)

        let sideConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        prevButton.setImage(UIImage(systemName: "backward.end.fill",
                                    withConfiguration: sideConfig), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill",
                                    withConfiguration: sideConfig), for: .normal)
        prevButton.tintColor = .white
        nextButton.tintColor = .white
        prevButton.accessibilityLabel = "上一首"
        nextButton.accessibilityLabel = "下一首"
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        playButton.tintColor = .white
        playButton.accessibilityLabel = "播放/暂停"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        setPlayIcon(playing: false)

        for label in [elapsedLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = UIColor.white.withAlphaComponent(0.75)
            label.text = "0:00"
        }
        elapsedLabel.textAlignment = .right
        durationLabel.textAlignment = .left

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        slider.accessibilityLabel = "播放进度"
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderReleased),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let row = UIStackView(arrangedSubviews: [
            prevButton, playButton, nextButton,
            elapsedLabel, slider, durationLabel,
        ])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topHairline.topAnchor.constraint(equalTo: topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 0.5),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            prevButton.widthAnchor.constraint(equalToConstant: 40),
            prevButton.heightAnchor.constraint(equalToConstant: 44),
            playButton.widthAnchor.constraint(equalToConstant: 46),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 44),
            elapsedLabel.widthAnchor.constraint(equalToConstant: 38),
            durationLabel.widthAnchor.constraint(equalToConstant: 38),
        ])
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func setPlayIcon(playing: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        playButton.setImage(
            UIImage(systemName: playing ? "pause.fill" : "play.fill",
                    withConfiguration: config), for: .normal)
    }

    // MARK: - 状态喂入（宿主逐帧/切歌时调）

    /// fraction 为宿主进度驱动的同源值；拖动中不覆写滑杆，
    /// 只更新时长与播放图标（拖动预览由 sliderChanged 就地算）。
    func update(fraction: Double, playing: Bool, duration: TimeInterval) {
        self.duration = duration
        setPlayIcon(playing: playing)
        durationLabel.text = Self.timeText(duration)
        if !isSeeking {
            let clamped = Float(min(max(fraction, 0), 1))
            slider.value = clamped
            elapsedLabel.text = Self.timeText(Double(clamped) * duration)
        }
    }

    // MARK: - 显隐

    func show() {
        poke()
        guard !isBarVisible else { return }
        isBarVisible = true
        isHidden = false
        Breadcrumbs.log("widebar.show")
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        transform = reduceMotion ? .identity
            : CGAffineTransform(translationX: 0, y: bounds.height)
        UIView.animate(withDuration: reduceMotion ? 0.2 : 0.5, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1,
                       options: [.beginFromCurrentState]) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard isBarVisible else { return }
        isBarVisible = false
        Breadcrumbs.log("widebar.hide")
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
            if !reduceMotion {
                self.transform = CGAffineTransform(
                    translationX: 0, y: self.bounds.height)
            }
        } completion: { _ in
            if !self.isBarVisible {
                self.isHidden = true
                self.transform = .identity
            }
        }
    }

    /// 立即收起（离台/开关关闭）：无动画、不留状态。
    func hideNow() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isBarVisible = false
        isSeeking = false
        isHidden = true
        alpha = 0
        transform = .identity
    }

    /// 有交互即续命：重排闲置自隐计时。
    func poke() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.idleSeconds, execute: work)
    }

    // MARK: - 动作

    @objc private func playTapped() {
        poke()
        onTogglePlay?()
    }

    @objc private func prevTapped() {
        poke()
        onPrev?()
    }

    @objc private func nextTapped() {
        poke()
        onNext?()
    }

    @objc private func sliderChanged() {
        isSeeking = true
        poke()
        elapsedLabel.text = Self.timeText(Double(slider.value) * duration)
    }

    @objc private func sliderReleased() {
        guard isSeeking else { return }
        isSeeking = false
        poke()
        onSeek?(Double(slider.value))
    }

    private static func timeText(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t.rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
