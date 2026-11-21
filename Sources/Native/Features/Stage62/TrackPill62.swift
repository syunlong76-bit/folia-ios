import UIKit

/// 舞台歌曲卡（(62) §4.2 track pill 本体）：封面＋歌名/歌手小卡。
/// 显隐由 SettingsStore62A 三项管辖：显示方式（切歌时显/常显/关）、
/// 显示时长（切歌时显模式的自动收起秒数）、位置（四角）。
/// 首页同款小卡由 HomeWall 在 trackPillShowOnHome 开时复用本类。
final class TrackPill62: UIView {

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var hideWorkItem: DispatchWorkItem?
    private var coverTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 12
        clipsToBounds = true
        isUserInteractionEnabled = false
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        artistLabel.font = .systemFont(ofSize: 11)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(coverView)
        addSubview(titleLabel)
        addSubview(artistLabel)
        alpha = 0
        isHidden = true
        // (62) INT-9：舞台数据来源覆写——WB 的 StageDataSource62
        // 轮询外部端点后经 .foliaExternalStageData 广播，舞台
        // 模式（stageModeEnabled）开启时本卡信息以外部数据为
        // 准（标题/歌手覆写、显隐跟随显示方式）；关闭时通知
        // 忽略、本卡仍由 noteTrackChanged 本地驱动。
        NotificationCenter.default.addObserver(
            forName: .foliaExternalStageData, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, SettingsStore.stageModeEnabled else { return }
            let title = note.userInfo?["title"] as? String ?? ""
            let artist = note.userInfo?["artist"] as? String ?? ""
            if !title.isEmpty { self.titleLabel.text = title }
            if !artist.isEmpty { self.artistLabel.text = artist }
            guard SettingsStore.trackPillDisplayMode != 2 else { return }
            self.hideWorkItem?.cancel()
            self.fadeIn()
            if SettingsStore.trackPillDisplayMode == 0 {
                let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
                self.hideWorkItem = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + SettingsStore.trackPillDurationSeconds,
                    execute: work)
            }
            Breadcrumbs.log("trackpill62.external override=1")
        }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        coverView.frame = CGRect(x: 8, y: 8, width: 36, height: 36)
        titleLabel.frame = CGRect(x: 52, y: 9, width: bounds.width - 60, height: 17)
        artistLabel.frame = CGRect(x: 52, y: 27, width: bounds.width - 60, height: 14)
    }

    /// 固定尺寸口径：宽 210、高 52（宿主按位置锚点摆位）。
    static let pillSize = CGSize(width: 210, height: 52)

    /// 按当前设置摆到宿主四角之一（inset 含安全区近似 12pt）。
    func place(in host: UIView) {
        let size = Self.pillSize
        let b = host.bounds
        let m: CGFloat = 12
        let top = host.safeAreaInsets.top + 52 // 避顶栏一行
        let origin: CGPoint
        switch SettingsStore.trackPillPosition {
        case 1: origin = CGPoint(x: b.width - size.width - m, y: top)
        case 2: origin = CGPoint(x: m, y: b.height - size.height - 96)
        case 3: origin = CGPoint(x: b.width - size.width - m, y: b.height - size.height - 96)
        default: origin = CGPoint(x: m, y: top)
        }
        frame = CGRect(origin: origin, size: size)
    }

    /// 切歌/开台时调用：按显示方式决定出没。
    func noteTrackChanged(track: FoliaTrack?) {
        hideWorkItem?.cancel()
        coverTask?.cancel()
        guard let track, SettingsStore.trackPillDisplayMode != 2 else {
            fadeOut()
            return
        }
        titleLabel.text = track.title
        artistLabel.text = track.artist
        coverView.image = nil
        if let raw = track.artworkURL?.absoluteString {
            let loader = NativeCoverLoader.shared
            if let urlString = loader.proxiedURLString(raw, tier: 300) {
                coverTask = Task { [weak self] in
                    let image = await loader.image(for: urlString, tier: 300)
                    await MainActor.run { self?.coverView.image = image }
                }
            }
        }
        fadeIn()
        if SettingsStore.trackPillDisplayMode == 0 {
            let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + SettingsStore.trackPillDurationSeconds, execute: work)
        }
        Breadcrumbs.log("trackpill62.show mode=\(SettingsStore.trackPillDisplayMode)"
            + " pos=\(SettingsStore.trackPillPosition)")
    }

    func fadeIn() {
        isHidden = false
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) { self.alpha = 1 }
    }
    func fadeOut() {
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.beginFromCurrentState],
                       animations: { self.alpha = 0 },
                       completion: { _ in if self.alpha == 0 { self.isHidden = true } })
    }
}

/// 播放后进入的视图（(62) §4.2）：三段设置的路由帮助，供 HomeWall
/// 点歌路由与他簇调用。返回值语义：
/// - .stage： present StageViewController（默认，现行为）
/// - .detail：播放详情——原生无独立详情 VC，等价落点为舞台开台后
///   立即打开播放面板（PlaybackPanelViewController），调用方在
///   stage presented 后调 openPanelOnPresentedStage(from:)。
/// - .stay：留在当前页（只起播不开台），调用方跳过 present。
enum PlaybackEntry62 {
    enum Entry { case stage, detail, stay }

    static var current: Entry {
        switch SettingsStore.playbackEntryView {
        case 1: return .detail
        case 2: return .stay
        default: return .stage
        }
    }

    /// detail 模式的第二步：在已呈现的舞台上打开播放面板。
    static func openPanelOnPresentedStage(from host: UIViewController) {
        var top = host
        while let presented = top.presentedViewController { top = presented }
        guard top is StageViewController else {
            Breadcrumbs.log("entry62.detail skip=no-stage-on-top")
            return
        }
        PlaybackPanelViewController.present(from: top, initialTab: .cover)
        Breadcrumbs.log("entry62.detail panel=open")
    }
}
