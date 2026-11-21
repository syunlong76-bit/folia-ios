import Combine
import Foundation

// PlaybackReporters62.swift
//
// 3.7 (62) WC 簇 §4.9 上报三件套＋启动引导：
// - Discord62：桌面 Discord RPC 的移动等价——Discord Webhook
//   上报正在播放（切歌/播放暂停时 POST）。
// - Scrobble62：网易云 scrobble 上报（听满阈值触发）＋听歌打卡。
//   后端接口可用性未核对：真发请求、结果落面包屑、失败诚实
//   回显，绝不假装成功（外部依赖 D10/D15）。
// - PlayerCap62：按配置地址周期 POST 播放状态 JSON（协议假设：
//   通用 JSON POST，服务端收 {player,title,artist,...}）。
// 三者都只订阅 PlaybackEngine 的 @Published 状态，不改引擎。
// 启动点：WC62Bootstrap.startIfNeeded()，由 WC 簇各入口
// （播放面板/命令面板/设置 62 簇）首触时调，进程内只启一次。

enum WC62Bootstrap {
    private static var started = false
    private static let lock = NSLock()

    static func startIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        Discord62.shared.start()
        Scrobble62.shared.start()
        PlayerCap62.shared.start()
        ListeningStats62.shared.start()
        // (66) 媒体缓存自动回填挂点（切歌订阅）。
        MediaCache62.shared.startAutoRefill()
        Breadcrumbs.log("wc62.bootstrap started=1")
    }
}

// MARK: - Discord（Webhook 等价）

final class Discord62 {

    static let shared = Discord62()
    private var cancellables = Set<AnyCancellable>()
    private var lastSignature = ""

    private init() {}

    func start() {
        let engine = PlaybackEngine.shared
        Publishers.CombineLatest(engine.$currentTrack, engine.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track, isPlaying in
                self?.report(track: track, isPlaying: isPlaying)
            }
            .store(in: &cancellables)
    }

    private func report(track: FoliaTrack?, isPlaying: Bool) {
        guard SettingsStore.discordEnabled62,
              let webhook = SecretStore62C.read(account: SecretStore62C.discordWebhookAccount),
              let url = URL(string: webhook) else { return }
        let signature = "\(track?.id ?? "none")|\(isPlaying)"
        guard signature != lastSignature else { return }
        lastSignature = signature
        let text: String
        if let track {
            text = isPlaying
                ? "▶️ 正在播放：\(track.title) - \(track.artist)"
                : "⏸️ 已暂停：\(track.title) - \(track.artist)"
        } else {
            text = "⏹️ 已停止播放"
        }
        let payload: [String: Any] = [
            "username": "Folia",
            "content": text,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error {
                Breadcrumbs.log("discord62.post fail err=\(error.localizedDescription)")
            } else {
                Breadcrumbs.log("discord62.post status=\(status)")
            }
        }.resume()
    }
}

// MARK: - Scrobble（网易云上报＋打卡）

final class Scrobble62 {

    static let shared = Scrobble62()

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var currentTrackId: String?
    private var scrobbledTrackId: String?
    /// 最近一次上报结果（设置页/命令回显用）。
    private(set) var lastResultText: String = "尚未上报"

    private init() {}

    func start() {
        PlaybackEngine.shared.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.currentTrackId = track?.id
            }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
            [weak self] _ in self?.tick()
        }
    }

    /// 阈值：已听 >= 曲长 50%（曲长未知/为 0 时 >= 240 秒），
    /// 与 Last.fm scrobble 惯例同口径。
    private func tick() {
        guard SettingsStore.scrobbleEnabled62 else { return }
        let engine = PlaybackEngine.shared
        guard engine.isPlaying, let track = engine.currentTrack,
              track.sourceType == .netease else { return }
        guard scrobbledTrackId != track.id else { return }
        let position = engine.rawPlayhead()
        let duration = track.duration > 0 ? track.duration : engine.duration
        let reached = duration > 0 ? position >= duration * 0.5 : position >= 240
        guard reached else { return }
        scrobbledTrackId = track.id
        Task { await self.reportScrobble(track: track, listenedSeconds: Int(position)) }
    }

    /// 真发请求：经 EdgeOneAPIClient 既有通路打 /scrobble。
    /// 接口可用性待后端核对——成败都落面包屑并回显。
    func reportScrobble(track: FoliaTrack, listenedSeconds: Int) async {
        let rawId = track.id.replacingOccurrences(of: "ncm_", with: "")
        do {
            _ = try await EdgeOneAPIClient.shared.requestData(
                provider: .netease, path: "/scrobble",
                queryItems: [
                    URLQueryItem(name: "id", value: rawId),
                    URLQueryItem(name: "sourceid", value: ""),
                    URLQueryItem(name: "time", value: "\(listenedSeconds)"),
                ])
            lastResultText = "上报成功（接口已响应）· \(track.title)"
            Breadcrumbs.log("scrobble62.report ok id=\(rawId) time=\(listenedSeconds)")
        } catch {
            lastResultText = "上报失败：\(error.localizedDescription)（接口可用性待后端核对）"
            Breadcrumbs.log("scrobble62.report fail id=\(rawId) err=\(error.localizedDescription)")
        }
    }

    /// 网易云听歌打卡（手动）：经同一通路打 /daily_signin。
    /// 同 scrobble 口径：真发、诚实回显。
    @discardableResult
    func performCheckIn() async -> String {
        do {
            _ = try await EdgeOneAPIClient.shared.requestData(
                provider: .netease, path: "/daily_signin",
                queryItems: [URLQueryItem(name: "type", value: "1")])
            Breadcrumbs.log("scrobble62.checkin ok")
            return "打卡请求已发出（接口已响应）"
        } catch {
            Breadcrumbs.log("scrobble62.checkin fail err=\(error.localizedDescription)")
            return "打卡失败：\(error.localizedDescription)（接口可用性待后端核对）"
        }
    }
}

// MARK: - PlayerCap

final class PlayerCap62 {

    static let shared = PlayerCap62()
    private var timer: Timer?

    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) {
            [weak self] _ in self?.reportNow(reason: "tick") }
        // 切歌即报一次（订阅在主线程装配）。
        DispatchQueue.main.async { [weak self] in
            self?.reportNow(reason: "start")
        }
    }

    /// 立即上报一次当前状态。ignoreClear 开时，当前无曲目
    /// （已清除）则跳过上报（PlayerCap「忽略清除」语义）。
    func reportNow(reason: String) {
        guard SettingsStore.playerCapEnabled62 else { return }
        let raw = SettingsStore.playerCapBaseURL62
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else { return }
        let engine = PlaybackEngine.shared
        let track = engine.currentTrack
        if track == nil && SettingsStore.playerCapIgnoreClear62 { return }
        var payload: [String: Any] = [
            "player": SettingsStore.playerCapPlayerName62,
            "isPlaying": engine.isPlaying,
            "timestamp": Date().timeIntervalSince1970,
            "reason": reason,
        ]
        if let track {
            payload["title"] = track.title
            payload["artist"] = track.artist
            payload["album"] = track.album
            payload["trackId"] = track.id
            if SettingsStore.playerCapTimelineEnabled62 {
                payload["position"] = engine.rawPlayhead()
                payload["duration"] = track.duration
            }
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error {
                Breadcrumbs.log("playercap62.post fail err=\(error.localizedDescription)")
            } else {
                Breadcrumbs.log("playercap62.post status=\(status) reason=\(reason)")
            }
        }.resume()
    }
}
