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

final class NowPlayingController {

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

    private var commandsRegistered = false

    private init() {
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
            return
        }

        let duration = engine.duration
        let clampedElapsed = max(0, min(elapsed, duration > 0 ? duration : elapsed))

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clampedElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]

        if let scaled = scaledArtwork, scaledArtworkTrackId == track.id {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: scaled.size) { _ in scaled }
        } else if let artwork = engine.currentArtwork {
            // 封面尚未缩放：先写无封面字典，再后台缩放、缩放完重推一次。
            maybeDownsampleArtwork(artwork, for: track.id)
        }

        center.nowPlayingInfo = info
        center.playbackState = rate > 0 ? .playing : .paused
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
        center.nextTrackCommand.removeTarget(self)
        center.previousTrackCommand.removeTarget(self)
        center.changePlaybackPositionCommand.removeTarget(self)
        center.skipForwardCommand.removeTarget(self)
        center.skipBackwardCommand.removeTarget(self)
    }

    @objc private func handlePlayCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        PlaybackEngine.shared.play()
        return .success
    }

    @objc private func handlePauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        PlaybackEngine.shared.pause()
        return .success
    }

    @objc private func handleNextCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        onNextTrack?()
        return .success
    }

    @objc private func handlePreviousCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
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
