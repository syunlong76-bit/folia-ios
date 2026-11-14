// AudioPlaybackProtocol.swift
//
// M1 播放内核：统一播放抽象（native-arch.md §2）。
// 状态单一化规则：isPlaying / rate 不手工置位，状态由 AVPlayer
// timeControlStatus 的 KVO 派生；togglePlayPause 只表达用户意图。
// 同步频率全工程统一 200ms；deployment target iOS 17。

import Foundation

/// 音频来源。
enum AudioSourceType: String, Codable {
    case netease
    case qq
    case kugou
    case local
}

/// 运行时组装的曲目模型。
///
/// - `id` 规则：`"ncm_<id>"` / `"qq_<id>"` / `"kg_<id>"` / `"local_<sha256前16位>"`。
/// - 在线流地址不落库、不缓存、不写死：播放时由 QueueManager 按 id 现换
///   （平台 CDN 地址有效期仅 1200 秒），因此本 struct 不含 stream URL 字段。
struct FoliaTrack: Identifiable, Codable {
    let id: String
    let sourceType: AudioSourceType
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: URL?

    init(id: String,
         sourceType: AudioSourceType,
         title: String,
         artist: String,
         album: String = "",
         duration: TimeInterval,
         artworkURL: URL? = nil) {
        self.id = id
        self.sourceType = sourceType
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
    }
}

/// 播放状态三态。waiting = 缓冲中（timeControlStatus == .waitingToPlayAtSpecifiedRate）。
enum PlaybackState {
    case playing
    case paused
    case waiting
}

/// 统一播放内核协议（在线流与本地文件同一输出面）。
protocol AudioPlaybackProtocol: AnyObject {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var playbackState: PlaybackState { get }

    /// 频谱带。阶段二 POC 通过前恒返回 []；POC 不过则删除该成员，不写成确定能力。
    var fftBands: [Float] { get }

    func play()
    func pause()
    /// 只表达用户意图；状态由 timeControlStatus KVO 收敛，不在此手工置位。
    func togglePlayPause()
    func seek(to seconds: TimeInterval)

    // MARK: - Crossfade（阶段二 POC 前只留协议签名，不实现）
    func prepareCrossfade(to track: FoliaTrack) async -> Bool
    func beginCrossfade(duration: TimeInterval)
    func cancelCrossfade()
    var isCrossfadeReady: Bool { get }
}
