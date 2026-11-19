// NowPlayingController.swift
//
// M1 播放内核：锁屏 / 控制中心（native-arch.md §5）。
// - 唯一写入点：只暴露 syncNowPlaying(elapsed:rate) 一个方法；
//   MPNowPlayingInfoCenter 完整字典原子更新（title/artist/artwork/elapsed/
//   duration/rate 同步，暂停 rate=0），同步设 playbackState。
//   写入只限离散事件（切歌/toggle/seek 完成/中断/路由），200ms 周期不写锁屏
//   （连续期由系统按 rate 外推）。
// - 封面后台线程等比缩到约 600×600 再写 MPMediaItemArtwork
//   （原图经 XPC 会被系统静默丢弃）。
// - MPRemoteCommandCenter 注册 play/pause/next/previous/changePlaybackPosition，
//   禁用 skipForward/skipBackward；队列边界禁用首尾方向（循环模式下按循环语义处理）；
//   命令 target 防重复注册（重复注册前先 removeTarget）。

import Foundation
import MediaPlayer
import UIKit

final class NowPlayingController: NSObject {

    static let shared = NowPlayingController()

    /// 队列切歌闭包，由 QueueManager 注入。
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    /// 锁屏封面最大边（约 600×600）。网页背景大图另备尺寸，不与本值混用。
    private let maxArtworkDimension: CGFloat = 600

    /// 已缩放好的封面缓存（按曲目 id），避免每次 sync 都重算。
    private var scaledArtwork: UIImage?
    private var scaledArtworkTrackId: String?
    /// 正在后台缩放的曲目 id（防重复派发）。
    private var scalingArtworkTrackId: String?
    /// nowplaying.info 面包屑去重键（曲目 id + 封面状态），状态不变不重复记。
    private var lastNowPlayingInfoLogKey: String?

    private var commandsRegistered = false

    private override init() {
        super.init()
        registerRemoteCommands()
    }

    // MARK: - 唯一写入点

    /// 锁屏 / 控制中心唯一写入方法。完整字典整体赋值，不多处维护。
    /// 无当前曲目时清空锁屏信息。
    func syncNowPlaying(elapsed: TimeInterval, rate: Float) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.syncNowPlaying(elapsed: elapsed, rate: rate)
            }
            return
        }
        let engine = PlaybackEngine.shared
        let center = MPNowPlayingInfoCenter.default()
        guard let track = engine.currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .paused
            if lastNowPlayingInfoLogKey != "none" {
                lastNowPlayingInfoLogKey = "none"
                Breadcrumbs.log("nowplaying.info songId=none artwork=no source=none")
            }
            return
        }

        let duration = engine.duration
        let clampedElapsed = max(0, min(elapsed, duration > 0 ? duration : elapsed))

        // 3.7 (31) 字段审计补齐：MediaType/DefaultPlaybackRate/
        // IsLiveStream 三个标准字段此前未写，一并补上（仅标准字段）。
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clampedElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]

        // 3.7 (31)：artwork 键永不缺席——真封面缩放好用真封面；未到
        // （含正在后台缩放）先写代码生成的主题兜底图，真封面到位后
        // 下一次 sync 自动替换。此前未缩放好时整键缺席，锁屏/灵动岛
        // 只能显示系统灰方块占位。
        let artworkState: String
        if let scaled = scaledArtwork, scaledArtworkTrackId == track.id {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: scaled.size) { _ in scaled }
            artworkState = "cover"
        } else {
            if let artwork = engine.currentArtwork {
                // 封面尚未缩放：后台缩放、缩放完重推一次（届时走 cover 分支）。
                maybeDownsampleArtwork(artwork, for: track.id)
            }
            let fallback = Self.fallbackArtwork()
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: fallback.size) { _ in fallback }
            artworkState = "fallback"
        }
        let infoLogKey = "\(track.id)|\(artworkState)"
        if infoLogKey != lastNowPlayingInfoLogKey {
            lastNowPlayingInfoLogKey = infoLogKey
            Breadcrumbs.log("nowplaying.info songId=\(track.id) artwork=\(artworkState == "cover" ? "yes" : "no") source=\(artworkState)")
        }

        center.nowPlayingInfo = info
        center.playbackState = rate > 0 ? .playing : .paused
        // 3.6 (3)：每次同步顺带重申切歌命令的启用状态。队列侧的可用性更新
        // 只挂在队列变异点上，一旦错过，锁屏按钮就长期灰着没人纠正；这里
        // 按队列现状（多于 1 首即可切，与 QueueManager 口径一致）兜底重申。
        let canMove = QueueManager.shared.queue.count > 1
        let center2 = MPRemoteCommandCenter.shared()
        if center2.nextTrackCommand.isEnabled != canMove {
            center2.nextTrackCommand.isEnabled = canMove
        }
        if center2.previousTrackCommand.isEnabled != canMove {
            center2.previousTrackCommand.isEnabled = canMove
        }
    }

    // MARK: - 封面后台等比缩放

    private func maybeDownsampleArtwork(_ image: UIImage, for trackId: String) {
        guard scalingArtworkTrackId != trackId else { return }
        scalingArtworkTrackId = trackId
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scaled = Self.downsample(image: image, maxDimension: 600)
            DispatchQueue.main.async {
                guard let self else { return }
                self.scalingArtworkTrackId = nil
                guard let scaled else { return }
                // 只有仍是当前曲时才采用，避免切歌后旧封面覆盖新曲。
                guard PlaybackEngine.shared.currentTrack?.id == trackId else { return }
                self.scaledArtwork = scaled
                self.scaledArtworkTrackId = trackId
                let engine = PlaybackEngine.shared
                self.syncNowPlaying(elapsed: engine.currentTime, rate: engine.playbackState == .playing ? 1.0 : 0.0)
            }
        }
    }

    // MARK: - 兜底封面（3.7 (31)）

    private static var cachedFallbackArtwork: UIImage?

    /// 主题兜底封面：深蓝灰渐变 + 白色音符，代码生成、无外部素材，
    /// 600×600 与真封面同尺寸口径。只生成一次后缓存。
    private static func fallbackArtwork() -> UIImage {
        if let cached = cachedFallbackArtwork { return cached }
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(red: 0.16, green: 0.19, blue: 0.28, alpha: 1).cgColor,
                UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: 230, weight: .light)
            if let note = UIImage(systemName: "music.note", withConfiguration: config)?
                .withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                note.draw(at: CGPoint(x: (size.width - note.size.width) / 2,
                                      y: (size.height - note.size.height) / 2))
            }
        }
        cachedFallbackArtwork = image
        return image
    }

    /// 等比缩放：只缩小不放大，最长边约 maxDimension。
    private static func downsample(image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let ratio = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        guard ratio < 1.0 else { return image }
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - 远程命令（防重复注册）

    /// 队列边界可用性：循环模式下队内多于 1 首时双向可用；由 QueueManager 在队列变化时调用。
    func updateCommandAvailability(canGoNext: Bool, canGoPrevious: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = canGoNext
        center.previousTrackCommand.isEnabled = canGoPrevious
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // 防重复注册：重复注册前先 removeTarget（selector 式 target 可整体移除）。
        if commandsRegistered {
            removeAllCommandTargets(center)
        }

        // 显式禁用快进快退，确保锁屏显示“上一首 / 下一首”而非 ±10 秒。
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        center.playCommand.isEnabled = true
        center.playCommand.addTarget(self, action: #selector(handlePlayCommand(_:)))
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget(self, action: #selector(handlePauseCommand(_:)))
        // 耳机/锁屏的合并播放暂停键（3.6 (3) 补注册）。
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget(self, action: #selector(handleTogglePlayPauseCommand(_:)))
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget(self, action: #selector(handleNextCommand(_:)))
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget(self, action: #selector(handlePreviousCommand(_:)))
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget(self, action: #selector(handleChangePlaybackPositionCommand(_:)))

        commandsRegistered = true
    }

    private func removeAllCommandTargets(_ center: MPRemoteCommandCenter) {
        center.playCommand.removeTarget(self)
        center.pauseCommand.removeTarget(self)
        center.togglePlayPauseCommand.removeTarget(self)
        center.nextTrackCommand.removeTarget(self)
        center.previousTrackCommand.removeTarget(self)
        center.changePlaybackPositionCommand.removeTarget(self)
        center.skipForwardCommand.removeTarget(self)
        center.skipBackwardCommand.removeTarget(self)
    }

    @objc private func handlePlayCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        FoliaBridgeLogStore.shared.write(level: "info", module: "nowplaying", message: "remote play")
        PlaybackEngine.shared.play()
        return .success
    }

    @objc private func handlePauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        FoliaBridgeLogStore.shared.write(level: "info", module: "nowplaying", message: "remote pause")
        PlaybackEngine.shared.pause()
        return .success
    }

    @objc private func handleTogglePlayPauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        FoliaBridgeLogStore.shared.write(level: "info", module: "nowplaying", message: "remote toggle")
        PlaybackEngine.shared.togglePlayPause()
        return .success
    }

    @objc private func handleNextCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        // 留痕（3.6 (3)）：锁屏切歌是否送达一眼可查（壳设置页桥日志）。
        FoliaBridgeLogStore.shared.write(level: "info", module: "nowplaying", message: "remote next")
        onNextTrack?()
        return .success
    }

    @objc private func handlePreviousCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        FoliaBridgeLogStore.shared.write(level: "info", module: "nowplaying", message: "remote previous")
        onPreviousTrack?()
        return .success
    }

    @objc private func handleChangePlaybackPositionCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
            return .commandFailed
        }
        PlaybackEngine.shared.seek(to: positionEvent.positionTime)
        return .success
    }
}
