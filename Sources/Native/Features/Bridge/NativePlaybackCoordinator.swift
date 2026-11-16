// NativePlaybackCoordinator.swift
//
// 3.2 原生接管（M3 第一刀）：浏览表面的桥点歌指令改道原生播放内核。
//
// 背景：3.1 及以前，浏览表面点歌经 /__bridge/cmd 发到网页播放表面执行
//（网页音频出声），iOS 给网页音频的锁屏界面只有 ±10 秒快进快退，
// 没有上一首/下一首；原生 NowPlayingController 注册的切歌命令只对
// 原生引擎生效，管不到网页播放。
//
// 本协调器做的事：
// 1. 在 BridgeStore.enqueue 里截获 play 家族指令（play / playQueueFromStart /
//    addAndPlay / addToQueue / transport），映射 SongResult → FoliaTrack 后
//    交给 QueueManager 原生起播；BridgeStore 同步置 nativePlaybackActive，
//    /__bridge/cmds 不再把这族指令发给网页播放表面（防双出声），
//    /__bridge/session 不再给网页表面 lastPlay 快照（防它自恢复网页播放）。
// 2. 把原生引擎状态按 BridgePlaybackState 形状回发 BridgeStore，
//    浏览表面的网页迷你条照常显示与控制（toggle/next/prev 走 transport
//    指令回到本协调器）。原生迷你条因此停用，避免双条（见 MainViewController）。
// 3. 「显示播放面」在原生队列已有曲目时改开原生全屏播放器（MainViewController
//    .showSurface 处理），网页播放表面不再被创建。
//
// 平台范围：网易云完整接通；QQ/酷狗曲目按 qqMid/kgHash 映射入队，
// 取流未接通时由 QueueManager 的失败跳歌 + 熔断兜底（与既定口径一致）。

import Combine
import Foundation

final class NativePlaybackCoordinator {

    static let shared = NativePlaybackCoordinator()

    private let queueManager = QueueManager.shared
    private let engine = PlaybackEngine.shared

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    /// 原始 SongResult 字典（按 FoliaTrack.id 索引）：发布桥状态时回填
    /// 网页侧的 id / 封面，保证浏览迷你条显示与网页时代一致。
    private var rawByTrackId: [String: [String: Any]] = [:]

    private var lastPublishSignature = ""
    private var lastPositionPublishAt: TimeInterval = 0

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        BridgeStore.shared.onCommand = { [weak self] cmd in
            // enqueue 在服务器线程调用；一切处理回主线程。BridgeStore 在
            // 触发本回调之后才派发表面切换通知，主队列 FIFO 保证点歌先于
            // 「显示播放面」执行，showSurface 检查队列时曲目已就位。
            DispatchQueue.main.async {
                self?.handle(cmd)
            }
        }

        // 状态发布：曲目 / 播放态 / 队列变化即发；播放中进度每 2 秒补发
        //（与网页播放表面原发布节奏一致，浏览迷你条 800ms 轮询读取）。
        engine.$currentTrack
            .sink { [weak self] _ in self?.publishState(force: true) }
            .store(in: &cancellables)
        engine.$isPlaying
            .sink { [weak self] _ in self?.publishState(force: true) }
            .store(in: &cancellables)
        queueManager.$currentIndex
            .sink { [weak self] _ in self?.publishState(force: true) }
            .store(in: &cancellables)
        queueManager.$queue
            .sink { [weak self] _ in self?.publishState(force: true) }
            .store(in: &cancellables)
        engine.$currentTime
            .sink { [weak self] _ in self?.publishState(force: false) }
            .store(in: &cancellables)
    }

    // MARK: - 指令处理（主线程）

    private func handle(_ cmd: [String: Any]) {
        guard let type = cmd["type"] as? String else { return }
        switch type {
        case "play":
            guard let song = cmd["song"] as? [String: Any] else { return }
            let queueDicts = (cmd["queue"] as? [[String: Any]]) ?? []
            play(song: song, queue: queueDicts)
        case "playQueueFromStart":
            let songs = (cmd["songs"] as? [[String: Any]]) ?? []
            let pairs = songs.compactMap(Self.mapPair)
            guard !pairs.isEmpty else { return }
            registerRaw(pairs)
            queueManager.setQueue(pairs.map(\.track), startingAt: 0)
        case "addAndPlay":
            guard let song = cmd["song"] as? [String: Any],
                  let pair = Self.mapPair(song) else { return }
            registerRaw([pair])
            queueManager.insertAndPlay(pair.track)
        case "addToQueue":
            let songs = (cmd["songs"] as? [[String: Any]]) ?? []
            let pairs = songs.compactMap(Self.mapPair)
            guard !pairs.isEmpty else { return }
            registerRaw(pairs)
            queueManager.appendToQueue(pairs.map(\.track))
        case "transport":
            handleTransport(cmd["action"] as? String)
        default:
            break
        }
    }

    private func play(song: [String: Any], queue: [[String: Any]]) {
        var pairs = queue.compactMap(Self.mapPair)
        guard let songPair = Self.mapPair(song) else {
            // 点的歌本身映射不了（缺 id/name）：退回只播队列第一首。
            if !pairs.isEmpty {
                registerRaw(pairs)
                queueManager.setQueue(pairs.map(\.track), startingAt: 0)
            }
            return
        }
        registerRaw(pairs + [songPair])
        if pairs.isEmpty {
            pairs = [songPair]
        }
        var startIndex = pairs.firstIndex(where: { $0.track.id == songPair.track.id }) ?? -1
        if startIndex < 0 {
            // 队列里没有点的歌：把它排到队首起播（与网页 playSong 语义对齐）。
            pairs.insert(songPair, at: 0)
            startIndex = 0
        }
        queueManager.setQueue(pairs.map(\.track), startingAt: startIndex)
    }

    private func handleTransport(_ action: String?) {
        switch action {
        case "toggle":
            engine.togglePlayPause()
        case "resume":
            engine.play()
        case "pause":
            engine.pause()
        case "next":
            queueManager.playNext(manual: true)
        case "prev":
            queueManager.playPrevious()
        default:
            break
        }
    }

    // MARK: - SongResult → FoliaTrack 映射

    private struct MappedPair {
        let raw: [String: Any]
        let track: FoliaTrack
    }

    private func registerRaw(_ pairs: [MappedPair]) {
        for pair in pairs {
            rawByTrackId[pair.track.id] = pair.raw
        }
    }

    /// 平台判定按身份字段：qqMid → QQ，kgHash → 酷狗，其余按网易云
    ///（id 取数值或字符串原样）。映射不了（缺 name 或缺一切 id）返回 nil。
    private static func mapPair(_ song: [String: Any]) -> MappedPair? {
        guard let name = song["name"] as? String, !name.isEmpty else { return nil }

        let artists = (song["artists"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String } ?? []
        let artistText = artists.isEmpty ? "未知歌手" : artists.joined(separator: " / ")

        let album = song["album"] as? [String: Any]
        let albumName = album?["name"] as? String ?? ""
        var picUrl = album?["picUrl"] as? String ?? ""
        if picUrl.hasPrefix("http://") {
            picUrl = "https://" + String(picUrl.dropFirst("http://".count))
        }
        let artworkURL = picUrl.isEmpty ? nil : URL(string: picUrl)
        let durationMs = (song["durationMs"] as? NSNumber)?.doubleValue ?? 0
        let duration = durationMs / 1000.0

        if let mid = song["qqMid"] as? String, !mid.isEmpty {
            return MappedPair(raw: song, track: FoliaTrack(
                id: "qq_\(mid)", sourceType: .qq, title: name,
                artist: artistText, album: albumName,
                duration: duration, artworkURL: artworkURL))
        }
        if let hash = song["kgHash"] as? String, !hash.isEmpty {
            return MappedPair(raw: song, track: FoliaTrack(
                id: "kg_\(hash)", sourceType: .kugou, title: name,
                artist: artistText, album: albumName,
                duration: duration, artworkURL: artworkURL))
        }
        let rawId: String
        if let number = song["id"] as? NSNumber {
            rawId = number.stringValue
        } else if let text = song["id"] as? String, !text.isEmpty {
            rawId = text
        } else {
            return nil
        }
        return MappedPair(raw: song, track: FoliaTrack(
            id: "ncm_\(rawId)", sourceType: .netease, title: name,
            artist: artistText, album: albumName,
            duration: duration, artworkURL: artworkURL))
    }

    // MARK: - 状态回发（BridgePlaybackState 形状）

    private func publishState(force: Bool) {
        let now = Date().timeIntervalSince1970
        if !force {
            // 进度补发节流：播放中每 2 秒一次；暂停时不补发。
            guard engine.isPlaying, now - lastPositionPublishAt >= 2.0 else { return }
        }

        let track = queueManager.currentTrack
        var songValue: Any = NSNull()
        var songId = ""
        if let track = track {
            songId = track.id
            let raw = rawByTrackId[track.id]
            let rawIdText: String = {
                if let number = raw?["id"] as? NSNumber { return number.stringValue }
                if let text = raw?["id"] as? String { return text }
                return track.id
            }()
            songValue = [
                "id": rawIdText,
                "name": track.title,
                "artistsText": track.artist,
                "coverUrl": track.artworkURL?.absoluteString ?? "",
                "durationMs": Int(track.duration * 1000)
            ] as [String: Any]
        }

        let playerState = engine.isPlaying ? "PLAYING" : "PAUSED"
        let signature = [songId, playerState,
                         "\(queueManager.currentIndex)",
                         "\(queueManager.queue.count)"].joined(separator: "|")
        // 与网页发布器同规则：签名未变且非播放中不重复发；播放中签名未变
        // 也发（那是 2 秒一次的进度补发，已在上方节流）。
        if signature == lastPublishSignature, !engine.isPlaying { return }
        lastPublishSignature = signature
        lastPositionPublishAt = now

        BridgeStore.shared.setState([
            "song": songValue,
            "playerState": playerState,
            "positionSec": engine.currentTime,
            "queueIndex": queueManager.queue.isEmpty ? -1 : queueManager.currentIndex,
            "queueLength": queueManager.queue.count,
            "updatedAt": Int(now * 1000)
        ])
    }
}
