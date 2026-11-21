import UIKit
import AVFoundation
import ImageIO

// 自定义歌词背景（3.7 (47)，Miller 定版规格）：
//  - 入口在样式选择面（StageStylePickerViewController 新增
//    「自定义背景」项），从系统相册选图片 / 动图（GIF·APNG）
//    / 视频；选入文件复制进 App 沙盒（Application Support
//    /FoliaCustomBackground），全局单槽，换新覆盖。
//  - 动图循环播放；视频循环且统一静音——不启音轨、不碰
//    AVAudioSession（音乐会话原样，歌不被压低/打断）；
//    离开舞台暂停、回舞台恢复（StageViewController 钩子）。
//  - 只占舞台最底层背景层（宿主 backdrop 三件套之上无、
//    之下即它）：生效时藏宿主封面氛围层，样式的文字渲染、
//    顶栏、点播台、宠物层全在其上不受影响；一键恢复即删
//    槽位文件、宿主氛围层回归。
//  - 尺寸上限：图片/动图 30MB、视频 200MB（沙盒为磁盘占
//    用，真正的内存约束在解码侧：静态图解码按屏幕像素上
//    限缩、动图逐帧解码且单帧按屏幕像素上限缩、视频由
//    AVPlayerLayer 按层尺寸渲染，全应用 450MB 线不动）。

enum CustomBackgroundKind: String {
    case image
    case animated
    case video
}

enum CustomBackgroundStore {
    static let maxImageBytes = 30 * 1024 * 1024
    static let maxVideoBytes = 200 * 1024 * 1024

    private static let kindKey = "folia.stage.customBgKind"
    private static let fileKey = "folia.stage.customBgFileName"

    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FoliaCustomBackground",
                                           isDirectory: true)
    }

    /// 当前槽位（元数据与文件都在才算数；文件丢失时自清
    /// 元数据，避免留一条永远 apply 失败的记录）。
    static var current: (kind: CustomBackgroundKind, url: URL)? {
        guard let kindRaw = UserDefaults.standard.string(forKey: kindKey),
              let kind = CustomBackgroundKind(rawValue: kindRaw),
              let name = UserDefaults.standard.string(forKey: fileKey)
        else { return nil }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: kindKey)
            UserDefaults.standard.removeObject(forKey: fileKey)
            return nil
        }
        return (kind, url)
    }

    /// 图片帧数（GIF/APNG 多帧判动图用）；读不到回 1。
    static func imageFrameCount(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, nil) else { return 1 }
        return max(CGImageSourceGetCount(source), 1)
    }

    enum InstallError: Error {
        case tooLarge(limit: Int)
        case copyFailed
    }

    /// 把相册临时文件装进槽位（必须在 loadFileRepresentation
    /// 回调内同步调用——临时文件在回调返回后即被系统删除）。
    /// 成功返回落盘字节数。
    @discardableResult
    static func install(sourceURL: URL, kind: CustomBackgroundKind) throws -> Int {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: sourceURL.path)
        let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let limit = kind == .video ? maxVideoBytes : maxImageBytes
        if bytes > limit { throw InstallError.tooLarge(limit: limit) }
        try fm.createDirectory(at: directory,
                               withIntermediateDirectories: true)
        // 单槽：先清旧文件再落新文件，避免两种扩展名残留叠加。
        if let old = current {
            try? fm.removeItem(at: old.url)
        }
        let ext = sourceURL.pathExtension.isEmpty
            ? (kind == .video ? "mov" : "img") : sourceURL.pathExtension
        let dest = directory.appendingPathComponent("background.\(ext)")
        do {
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            throw InstallError.copyFailed
        }
        UserDefaults.standard.set(kind.rawValue, forKey: kindKey)
        UserDefaults.standard.set(dest.lastPathComponent, forKey: fileKey)
        return bytes
    }

    /// 恢复样式背景：删槽位文件与元数据。
    static func clear() {
        if let entry = current {
            try? FileManager.default.removeItem(at: entry.url)
        }
        UserDefaults.standard.removeObject(forKey: kindKey)
        UserDefaults.standard.removeObject(forKey: fileKey)
    }

    // MARK: (62) WA 视频层独立槽（歌词后方视频层，与自定义背景槽分开）

    private static let videoKindKey = "folia.stage.videoLayerKind"
    private static let videoFileKey = "folia.stage.videoLayerFileName"

    static var videoLayerDirectory: URL {
        directory.appendingPathComponent("VideoLayer", isDirectory: true)
    }

    static var currentVideoLayer: (kind: CustomBackgroundKind, url: URL)? {
        guard let kindRaw = UserDefaults.standard.string(forKey: videoKindKey),
              let kind = CustomBackgroundKind(rawValue: kindRaw),
              let name = UserDefaults.standard.string(forKey: videoFileKey)
        else { return nil }
        let url = videoLayerDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: videoKindKey)
            UserDefaults.standard.removeObject(forKey: videoFileKey)
            return nil
        }
        return (kind, url)
    }

    /// 把已下载到本地的文件装进视频层槽（URL 路径先下载后走此通路）。
    @discardableResult
    static func installVideoLayer(sourceURL: URL, kind: CustomBackgroundKind) throws -> Int {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: sourceURL.path)
        let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let limit = kind == .video ? maxVideoBytes : maxImageBytes
        if bytes > limit { throw InstallError.tooLarge(limit: limit) }
        try fm.createDirectory(at: videoLayerDirectory,
                               withIntermediateDirectories: true)
        if let old = currentVideoLayer {
            try? fm.removeItem(at: old.url)
        }
        let ext = sourceURL.pathExtension.isEmpty
            ? (kind == .video ? "mov" : "img") : sourceURL.pathExtension
        let dest = videoLayerDirectory.appendingPathComponent("videolayer.\(ext)")
        do {
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            throw InstallError.copyFailed
        }
        UserDefaults.standard.set(kind.rawValue, forKey: videoKindKey)
        UserDefaults.standard.set(dest.lastPathComponent, forKey: videoFileKey)
        return bytes
    }

    static func clearVideoLayer() {
        if let entry = currentVideoLayer {
            try? FileManager.default.removeItem(at: entry.url)
        }
        UserDefaults.standard.removeObject(forKey: videoKindKey)
        UserDefaults.standard.removeObject(forKey: videoFileKey)
    }
}

// MARK: - 动图帧进播放（GIF/APNG，ImageIO 逐帧）

/// 逐帧解码播放：任一时刻只持当前帧 + 预解下一帧，单帧按
/// 屏幕像素上限缩（kCGImageSourceThumbnailMaxPixelSize），
/// 避免整包解码把大 GIF 撑爆内存（UIImage.animatedImage 的
/// 全帧解码路线不用）。循环播放，时长取帧自带 delay（GIF/
/// APNG 字典），缺失时 0.1s，下限 0.03s。
final class AnimatedImagePlayerView: UIView {

    private let imageView = UIImageView()
    private var source: CGImageSource?
    private var frameCount = 0
    private var durations: [TimeInterval] = []
    private var displayLink: CADisplayLink?
    private var currentIndex = 0
    private var frameDeadline: CFTimeInterval = 0
    private var nextFrame: UIImage?
    private var nextIndex = -1
    private var decoding = false
    private var useThumbnail = false
    private let decodeQueue = DispatchQueue(
        label: "folia.custombg.animdecode", qos: .userInitiated)

    /// (62) 填充方式转发到内部 imageView。
    var imageContentMode: UIView.ContentMode = .scaleAspectFill {
        didSet { imageView.contentMode = imageContentMode }
    }

    init(url: URL) {
        super.init(frame: .zero)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        load(url: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    private func load(url: URL) {
        decodeQueue.async { [weak self] in
            guard let self,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            else { return }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { return }
            var durations: [TimeInterval] = []
            var firstSize = CGSize.zero
            for i in 0..<count {
                let props = CGImageSourceCopyPropertiesAtIndex(
                    source, i, nil) as? [CFString: Any]
                if i == 0, let props {
                    let w = props[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
                    let h = props[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
                    firstSize = CGSize(width: w, height: h)
                }
                durations.append(Self.frameDuration(props))
            }
            // 首帧像素任一边超过屏幕像素长边 → 全程走缩略解码。
            let screenMax = max(UIScreen.main.bounds.width,
                                UIScreen.main.bounds.height)
                * UIScreen.main.scale
            let thumbnail = max(firstSize.width, firstSize.height) > screenMax
            DispatchQueue.main.async {
                self.source = source
                self.frameCount = count
                self.durations = durations
                self.useThumbnail = thumbnail
                self.showFrame(0)
                self.prefetchNext()
            }
        }
    }

    private static func frameDuration(_ props: [CFString: Any]?) -> TimeInterval {
        guard let props else { return 0.1 }
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let v = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, v > 0 {
                return max(v, 0.03)
            }
            if let v = gif[kCGImagePropertyGIFDelayTime] as? Double, v > 0 {
                return max(v, 0.03)
            }
        }
        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let v = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double, v > 0 {
                return max(v, 0.03)
            }
            if let v = png[kCGImagePropertyAPNGDelayTime] as? Double, v > 0 {
                return max(v, 0.03)
            }
        }
        return 0.1
    }

    private func decodeFrame(_ index: Int) -> UIImage? {
        guard let source, frameCount > 0 else { return nil }
        if useThumbnail {
            let screenMax = max(UIScreen.main.bounds.width,
                                UIScreen.main.bounds.height)
                * UIScreen.main.scale
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(screenMax),
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(
                source, index, options as CFDictionary) {
                return UIImage(cgImage: cg)
            }
        }
        guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    private func showFrame(_ index: Int) {
        currentIndex = index
        if nextIndex == index, let ready = nextFrame {
            imageView.image = ready
            nextFrame = nil
            nextIndex = -1
        } else if let image = decodeFrame(index) {
            imageView.image = image
        }
        frameDeadline = CACurrentMediaTime()
            + (durations.indices.contains(index) ? durations[index] : 0.1)
    }

    private func prefetchNext() {
        guard frameCount > 1, !decoding else { return }
        let target = (currentIndex + 1) % frameCount
        decoding = true
        decodeQueue.async { [weak self] in
            let image = self?.decodeFrame(target)
            DispatchQueue.main.async {
                guard let self else { return }
                self.decoding = false
                self.nextFrame = image
                self.nextIndex = target
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard frameCount > 1 else { return }
        if CACurrentMediaTime() >= frameDeadline {
            showFrame((currentIndex + 1) % frameCount)
            prefetchNext()
        }
    }

    func play() {
        guard displayLink == nil else { return }
        frameDeadline = CACurrentMediaTime()
            + (durations.indices.contains(currentIndex)
               ? durations[currentIndex] : 0.1)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func pause() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { displayLink?.invalidate() }
}

// MARK: - 视频背景（统一静音循环）

/// AVQueuePlayer + AVPlayerLooper 无限循环；isMuted = true
/// 且全程不碰 AVAudioSession——不启音轨、不改类别，音乐
/// 会话与音量原样。preventDisplaySleep 关掉，不抢系统行为。
final class CustomBackgroundVideoView: UIView {

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    init(url: URL) {
        super.init(frame: .zero)
        clipsToBounds = true
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        looper = AVPlayerLooper(player: player,
                                 templateItem: AVPlayerItem(url: url))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    /// (62) 填充方式：fill = resizeAspectFill / fit = resizeAspect。
    func setFillMode(fill: Bool) {
        playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    func play() { player.play() }

    func pause() { player.pause() }

    deinit {
        player.pause()
        looper?.disableLooping()
    }
}

// MARK: - 背景宿主视图

/// 舞台最底层背景宿主：按槽位类型装配静态图 / 动图 / 视频
/// 三选一子视图，play/pause 透传。静态图解码按屏幕像素长
/// 边为上限（ImageIO 缩略解码，不整图入内存）。
final class CustomBackgroundView: UIView {

    private var staticView: UIImageView?
    private var animatedView: AnimatedImagePlayerView?
    private var videoView: CustomBackgroundVideoView?
    private var appliedKey: String?
    private(set) var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// (62) 视频层渲染参数：不透明度与填充方式（fill/fit）真消费点。
    func applyLayerRendering(opacity: Double, fill: Bool) {
        alpha = CGFloat(opacity)
        let mode: UIView.ContentMode = fill ? .scaleAspectFill : .scaleAspectFit
        staticView?.contentMode = mode
        animatedView?.imageContentMode = mode
        videoView?.setFillMode(fill: fill)
    }

    func apply(kind: CustomBackgroundKind, url: URL) {
        let key = "\(kind.rawValue)|\(url.path)"
        if key == appliedKey { return }
        clearContent()
        appliedKey = key
        isActive = true
        // (62) 填充方式来自视频层设置（fill 默认）；apply 后由宿主
        // refreshCustomBackground 再调 applyLayerRendering 对齐当次值。
        let fillMode = SettingsStore.videoLayerFillMode == 0
        switch kind {
        case .image:
            let imageView = UIImageView()
            imageView.contentMode = fillMode ? .scaleAspectFill : .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.frame = bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(imageView)
            staticView = imageView
            let screenMax = max(UIScreen.main.bounds.width,
                                UIScreen.main.bounds.height)
                * UIScreen.main.scale
            DispatchQueue.global(qos: .userInitiated).async {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(screenMax),
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ]
                guard let source = CGImageSourceCreateWithURL(
                    url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(
                        source, 0, options as CFDictionary)
                else { return }
                let image = UIImage(cgImage: cg)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.appliedKey == key else { return }
                    self.staticView?.image = image
                }
            }
        case .animated:
            let player = AnimatedImagePlayerView(url: url)
            player.imageContentMode = fillMode ? .scaleAspectFill : .scaleAspectFit
            player.frame = bounds
            player.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(player)
            animatedView = player
        case .video:
            let video = CustomBackgroundVideoView(url: url)
            video.setFillMode(fill: fillMode)
            video.frame = bounds
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(video)
            videoView = video
        }
    }

    func clearContent() {
        appliedKey = nil
        isActive = false
        animatedView?.pause()
        videoView?.pause()
        staticView?.removeFromSuperview()
        animatedView?.removeFromSuperview()
        videoView?.removeFromSuperview()
        staticView = nil
        animatedView = nil
        videoView = nil
    }

    func play() {
        animatedView?.play()
        videoView?.play()
    }

    func pause() {
        animatedView?.pause()
        videoView?.pause()
    }
}

/// (62) 视频层 URL 安装：远程图片/GIF/视频 URL 先下载到本地缓存
/// （Caches/FoliaVideoLayerURL），再走 CustomBackgroundStore
/// .installVideoLayer 落槽播放——原生等价实现，禁 WebView。
/// 完成后发 foliaSettings62AChanged（key=videoLayerURL），在场
/// 舞台经 refreshCustomBackground 即时换层。
enum VideoLayerURLInstaller62 {

    static func install(from urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme == "https" || url.scheme == "http" else {
            Breadcrumbs.log("videolayer62.url fail=bad-url")
            return
        }
        Breadcrumbs.log("videolayer62.url download begin")
        let task = URLSession.shared.downloadTask(with: url) { temp, _, error in
            guard let temp, error == nil else {
                Breadcrumbs.log("videolayer62.url fail=download")
                return
            }
            let ext = url.pathExtension.lowercased()
            let kind: CustomBackgroundKind
            if ["mp4", "mov", "m4v"].contains(ext) {
                kind = .video
            } else if ext == "gif" || ext == "apng" {
                kind = .animated
            } else {
                kind = .image
            }
            // downloadTask 的临时文件在回调返回后即删：先挪进缓存目录再装槽。
            let cacheDir = FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FoliaVideoLayerURL", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: cacheDir, withIntermediateDirectories: true)
            let staged = cacheDir.appendingPathComponent(
                "download.\(ext.isEmpty ? "bin" : ext)")
            try? FileManager.default.removeItem(at: staged)
            do {
                try FileManager.default.copyItem(at: temp, to: staged)
                let bytes = try CustomBackgroundStore.installVideoLayer(
                    sourceURL: staged, kind: kind)
                SettingsStore.videoLayerURL = trimmed
                SettingsStore.videoLayerEnabled = true
                Breadcrumbs.log("videolayer62.url ok kind=\(kind.rawValue) bytes=\(bytes)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .foliaSettings62AChanged, object: nil,
                        userInfo: ["key": SettingsStore.Key62A.videoLayerURL])
                }
            } catch {
                Breadcrumbs.log("videolayer62.url fail=install")
            }
        }
        task.resume()
    }
}
