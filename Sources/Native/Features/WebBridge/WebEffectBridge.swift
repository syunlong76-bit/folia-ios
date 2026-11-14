import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

// MARK: - 桥事件枚举（native-arch.md §9：枚举化，前后端统一，不许两套并行）
//
// 事件语义：
// state 离散状态（播放/暂停/切歌）：{ playing, rate, t, trackId}
// progress 200ms 周期基准：{ t, rate}
// seek 锚点重置（松手 seek 乐观锚点 / 恢复补发锚点）：{ t, rate}
// queue 队列摘要（当前 ±3 首）：{ currentIndex, items: [{ id, title, artist}]}
// artwork 封面引用变化：{ trackId, ref}
// lyrics 歌词文本：{ trackId, lrc}
// theme 主题：{ backgroundMode: web | native-scene, palette}
// snapshot 全量状态快照（didFinish / reload 恢复唯一入口）
// renderState 渲染启停：{ active}
//   buffering   缓冲态（桥订阅 engine.$playbackState，.waiting 即发）：{ buffering }
// spectrum 预留，POC 前原生不发，只定型。
enum BridgeEvent: String {
    case state
    case progress
    case seek
    case queue
    case artwork
    case lyrics
    case theme
    case snapshot
    case renderState
    case buffering
    case spectrum
}

// MARK: - 全量状态快照 DTO（native-arch.md §9/§13：以后新增桥字段只改 DTO + 前端类型）

struct WebSnapshotDTO: Codable {
    struct Track: Codable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let isLiked: Bool
        let artworkRef: String?
    }
    struct QueueItem: Codable {
        let id: String
        let title: String
        let artist: String
    }
    struct Theme: Codable {
        let backgroundMode: String // "web" | "native-scene"
        let palette: [String: String]
    }

    let track: Track?
    let lrc: String
    let renderActive: Bool
    let theme: Theme
    let queue: [QueueItem]
    let currentIndex: Int
    let initialTime: TimeInterval
    let rate: Float
}

// MARK: - 滚动日志（native-arch.md §9 第六批：沙盒 2MB 双文件轮换 + Xcode Console）

/// 过桥日志与桥内诊断的唯一落盘点。
/// - 脱敏：落盘前剥掉 URL 查询串、mask token/cookie/auth 类键值；只许平台＋歌曲 id＋错误码。
/// - 限速：只作用于过桥写入（record），按 module#level 做 1 秒窗口去抖，
/// 同键每秒 ≤10 条，超限丢弃并把丢弃计数写进日志文件；Xcode Console 输出不限。
/// - 内部低频诊断走 write（不限速）。
final class FoliaBridgeLogStore {
    static let shared = FoliaBridgeLogStore()

    private let ioQueue = DispatchQueue(label: "com.miller.folia.bridge-log", qos:.utility)
    private let maxFileBytes = 2 * 1024 * 1024
    private let maxPerSecondPerKey = 10

    private var windowCounts: [String: (windowStart: Date, count: Int)] = [:]
    private var droppedCounts: [String: Int] = [:]
    private var currentFileIndex = 0

    private init() {}

    private var logDirectory: URL {
        let dir = FileManager.default.urls(for:.cachesDirectory, in:.userDomainMask)[0]
            .appendingPathComponent("folia-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(index: Int) -> URL {
        logDirectory.appendingPathComponent("folia-bridge-\(index).log")
    }

    /// 过桥日志入口（JS `log` 动作专用，带限速）。info 在调用前就被挡掉，这里再守一道。
    func record(level: String, module: String, message: String) {
        guard level == "warn" || level == "error" else { return}
        let key = "\(module)#\(level)"
        let now = Date()
        var allowed = false
        var droppedNote: String?
        ioQueue.sync {
            var entry = windowCounts[key] ?? (windowStart: now, count: 0)
            if now.timeIntervalSince(entry.windowStart) >= 1.0 {
                entry = (windowStart: now, count: 0)
            }
            if entry.count < maxPerSecondPerKey {
                entry.count += 1
                windowCounts[key] = entry
                allowed = true
                if let dropped = droppedCounts[key], dropped > 0 {
                    droppedCounts[key] = 0
                    droppedNote = "[dropped \(dropped) over-limit log lines for \(key)]"
                }
            } else {
                droppedCounts[key, default: 0] += 1
            }
        }
        guard allowed else { return}
        write(level: level, module: module, message: message)
        if let note = droppedNote {
            write(level: "warn", module: module, message: note)
        }
    }

    /// 桥内诊断写入（不限速）。调用方保证低频。
    func write(level: String, module: String, message: String) {
        let clean = sanitize(message)
        let line = "\(iso8601(Date())) [\(level.uppercased())][\(module)] \(clean)\n"
        // Xcode Console 与沙盒日志同步。
        NSLog("[FoliaBridge][\(module)] \(clean)")
        ioQueue.async { [weak self] in
            guard let self else { return}
            let url = self.fileURL(index: self.currentFileIndex)
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
            size.intValue >= self.maxFileBytes {
                self.currentFileIndex = 1 - self.currentFileIndex
                let next = self.fileURL(index: self.currentFileIndex)
                try? FileManager.default.removeItem(at: next)
                FileManager.default.createFile(atPath: next.path, contents: nil)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close()}
                try? handle.seekToEnd()
                if let data = line.data(using:.utf8) {
                    try? handle.write(contentsOf: data)
                }
            }
        }
    }

    /// 脱敏：剥 URL 查询串（禁带签名参数的完整音频 URL 过桥/落盘），
    /// mask token/cookie/auth/password/secret 类键值。
    func sanitize(_ message: String) -> String {
        // 1. http(s) URL：问号及之后（签名参数）全部去掉，只留裸址。
        var out = stripURLQueries(message)
        // 2. token/cookie/auth/password/secret/签名键：值 mask。
        if let regex = try? NSRegularExpression(
            pattern: #"(?i)(token|auth|cookie|password|secret|signature|sig|access_key)\s*=\s*[^&\s\"',;]+"#,
            options: []) {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "$1=***")
        }
        return out
    }

    private func stripURLQueries(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\"'<>`]+"#, options: []) else {
            return text
        }
        var result = text
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        // 从后往前替换，避免偏移失效。
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue}
            let url = String(text[range])
            let base = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
            if let nsRange = Range(match.range, in: result) {
                result.replaceSubrange(nsRange, with: base)
            }
        }
        return result
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - 弱引用消息 handler（防 WKUserContentController 强引用泄漏）

/// delegate 必须可后设：`foliaAction` 注册必须在创建 WKWebView 之前，
/// 而 self 在 super.init 之前不存在，所以先建 handler 注册、再把 delegate 挂上。
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - WebEffectBridge

/// 原生 ↔ 特效 WebView 的唯一桥（M2，native-arch.md §9/§10）。
///
/// - 单一状态源：原生是唯一播放状态源，WebView 只读。
/// - 200ms 周期：订阅 PlaybackEngine @Published currentTime（不占 onTimeSync
/// 单回调；迷你条/锁屏另有订阅时互不顶掉）。
/// - 恢复统一走全量快照 pushSnapshot，不再逐字段补发。
/// - renderState 由 RenderStateCenter 驱动；桥内不再私自 setRenderActive。
/// - M1 依赖：PlaybackEngine（@Published currentTrack/isPlaying/currentTime/duration，
/// togglePlayPause/seek）、QueueManager（@Published queue/currentIndex，
/// playNext(manual:)/playPrevious()）、FoliaTrack。M1 已落地，接口逐项对齐见 M2-SELFCHECK.md。
final class WebEffectBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    static let shared = WebEffectBridge()

    let webView: WKWebView

    @Published private(set) var isPageLoaded = false
    /// 进程自愈防抖触发后的致命错误（1 分钟 ≥3 次 terminate，自动 reload 已停）。
    @Published private(set) var lastFatalError: String?

    /// 网页请求收起播放页（JS `minimize` 动作）。由 MainViewController 注入。
    var onMinimizeRequested: (() -> Void)?
    /// 网页请求切换收藏（JS `like` 动作）。由 M1/M3 的 DatabaseManager 侧注入。
    var onToggleLikeRequested: ((String) -> Void)?

    /// 歌词来源（默认空串；M1/M3 接入缓存歌词后注入）。
    var lyricsProvider: ((FoliaTrack) -> String)?
    /// 收藏态来源（默认 false；M1/M3 接入 DatabaseManager 后注入）。
    var isLikedProvider: ((String) -> Bool)?
    /// 主题来源（默认 backgroundMode web、空 palette；原生场景层排期时注入）。
    var themeProvider: (() -> WebSnapshotDTO.Theme)?

    private var cancellables = Set<AnyCancellable>()
    private let logStore = FoliaBridgeLogStore.shared

    /// 页面未加载完时缓存的 renderState，didFinish 时补发（不得丢事件）。
    private var pendingRenderActive: Bool?
    /// 已发给页面的最后一个 renderState（幂等判断；didFinish 后清掉，恢复必重发）。
    private var lastSentRenderActive: Bool?
    private var renderActive: Bool = false

    /// seek 竞态三件套之②③：松手 seek 后，周期 observer 跳过推送，直到
    /// 引擎时间落到目标附近（在线 tolerance 2s）或 3s 超时，再回推真实位置。
    private var pendingSeek: (target: TimeInterval, startedAt: Date)?

    /// 进程自愈防抖：60 秒窗口内的 terminate 时间戳。
    private var terminateDates: [Date] = []
    private var autoReloadSuspended = false

    private var lastKnownTime: TimeInterval = 0
    /// 歌词缓存（track id -> LRC 文本）；失败也记 ""，避免反复请求。
    private var lyricsCache: [String: String] = [:]
    /// 上次发给页面的 buffering 值（变化才发）。
    private var lastBufferingState: Bool?

    private var currentRate: Float {
        PlaybackEngine.shared.isPlaying ? 1.0 : 0.0
    }

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // 调试标志：folia-bridge.js 内 gated Logger 用。Release 恒 false。
        #if DEBUG
        let debugFlagSource = "window.__FOLIA_BRIDGE_DEBUG__ = true;"
        #else
        let debugFlagSource = "window.__FOLIA_BRIDGE_DEBUG__ = false;"
        #endif
        config.userContentController.addUserScript(WKUserScript(
                source: debugFlagSource, injectionTime:.atDocumentStart, forMainFrameOnly: true))

        // foliaAction 注册必须在创建 WKWebView 之前——
        // 先 config.userContentController.add，后 WKWebView(frame:configuration:)。
        // 事后改 config 不生效，网页回传会全部收不到。
        let weakHandler = WeakScriptMessageHandler()
        config.userContentController.add(weakHandler, name: "foliaAction")

        // 手势穿透框架（M2 末落地）：默认 passthroughRects 为空，行为与 WKWebView 一致。
        let webView = PassthroughWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        // 透明白闪处置：didFinish 前 alpha=0，完成后 150ms 渐入。
        webView.alpha = 0

        self.webView = webView
        super.init()

        weakHandler.delegate = self
        webView.navigationDelegate = self

        bindPlaybackEngine()
        bindRenderStateCenter()
        loadLocalEffectBundle()
    }

    // MARK: - 加载

    private func loadLocalEffectBundle() {
        guard let htmlURL = Bundle.main.url(
            forResource: "index", withExtension: "html", subdirectory: "WebEffect") else {
            // 包缺失必须暴露，不许静默白屏。
            let message = "WebEffect bundle missing: Resources/WebEffect/index.html not found in app bundle"
            lastFatalError = message
            logStore.write(level: "error", module: "bridge", message: message)
            assertionFailure(message)
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    /// 防抖触发后的人工重试入口（诊断面板 / 设置页调用）。
    func retryAfterFatalError() {
        autoReloadSuspended = false
        terminateDates.removeAll()
        lastFatalError = nil
        loadLocalEffectBundle()
    }

    // MARK: - 订阅

    private func bindPlaybackEngine() {
        let engine = PlaybackEngine.shared
        // 200ms 周期基准：订阅 @Published，不占 onTimeSync 单回调。
        engine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.handleEngineTime(time)}
            .store(in: &cancellables)
        // 离散状态：播放/暂停翻转即推 state 事件（带当前锚点）。
        engine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushStateEvent()}
            .store(in: &cancellables)
        // 缓冲态：playbackState == .waiting 时推 buffering（变化才发）。
        engine.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let buffering = (state == .waiting)
                if self.lastBufferingState != buffering {
                    self.lastBufferingState = buffering
                    self.pushBuffering(buffering)
                }
            }
            .store(in: &cancellables)
        // 切歌：全量快照一次推齐（track / lrc / queue / artwork / theme / time / rate）。
        engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.pushSnapshot()
                if let track { self?.fetchLyricsIfNeeded(for: track) }
            }
            .store(in: &cancellables)
        // 队列变化：只推 queue 摘要，不动其他字段。
        QueueManager.shared.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushQueueEvent()}
            .store(in: &cancellables)
        QueueManager.shared.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushQueueEvent()}
            .store(in: &cancellables)
    }

    private func bindRenderStateCenter() {
        RenderStateCenter.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
            guard let self else { return}
            self.applyRenderActive(active)
            if active {
                // 恢复即推锚点：scenePhase 回.active 时不等下个 200ms tick。
                self.pushAnchor()
            }
        }
            .store(in: &cancellables)
    }

    // MARK: - Native -> JS

    /// 全量状态快照：didFinish / reload 恢复 / 切歌的统一入口。
    /// 以后新增桥字段只改 WebSnapshotDTO + 前端类型，不再维护逐字段补发清单。
    func pushSnapshot() {
        let engine = PlaybackEngine.shared
        let track = engine.currentTrack
        let dto = WebSnapshotDTO(
            track: track.map {
                WebSnapshotDTO.Track(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    album: $0.album,
                    duration: $0.duration,
                    isLiked: isLikedProvider?($0.id) ?? false,
                    artworkRef: $0.artworkURL?.absoluteString)
            },
            lrc: track.flatMap { lyricsProvider?($0) ?? lyricsCache[$0.id] } ?? "",
            renderActive: renderActive,
            theme: themeProvider?() ?? WebSnapshotDTO.Theme(backgroundMode: "web", palette: [:]),
            queue: queueSummary(),
            currentIndex: QueueManager.shared.currentIndex,
            initialTime: engine.currentTime,
            rate: currentRate)
        guard let data = try? JSONEncoder().encode(dto),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logStore.write(level: "error", module: "bridge", message: "snapshot encode failed")
            return
        }
        dispatchToJS(.snapshot, payload: object)
    }

    /// 歌词后到：切歌时若缓存无歌词，向网易云接口现取（仅 netease；
    /// QQ/酷狗/本地暂无歌词源，记 "" 不再请求），到后经 pushLyricsEvent 补发。
    /// 外部已注入 lyricsProvider 时不自己取。失败只打 warn，不阻断播放。
    private func fetchLyricsIfNeeded(for track: FoliaTrack) {
        if lyricsProvider != nil { return }
        if lyricsCache[track.id] != nil { return }
        guard track.sourceType == .netease else {
            lyricsCache[track.id] = ""
            return
        }
        Task {
            do {
                let text = try await EdgeOneAPIClient.shared.fetchLyricText(songId: track.id)
                DispatchQueue.main.async {
                    self.lyricsCache[track.id] = text
                    if PlaybackEngine.shared.currentTrack?.id == track.id {
                        self.pushLyricsEvent()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lyricsCache[track.id] = ""
                    self.logStore.write(level: "warn", module: "lyrics",
                        message: "lyric fetch failed track=\(track.id) error=\(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 队列摘要：当前 ±3 首。
    func pushQueueEvent() {
        dispatchToJS(.queue, payload: [
                "currentIndex": QueueManager.shared.currentIndex,
                "items": queueSummary().map { ["id": $0.id, "title": $0.title, "artist": $0.artist]},
        ])
    }

    /// 封面引用变化（切歌时快照已含；独立换封面时调这个）。
    func pushArtworkEvent() {
        guard let track = PlaybackEngine.shared.currentTrack else { return}
        dispatchToJS(.artwork, payload: [
                "trackId": track.id,
                "ref": track.artworkURL?.absoluteString ?? "",
        ])
    }

    /// 歌词文本变化（歌词后到 / 切换译文时调这个）。
    func pushLyricsEvent() {
        guard let track = PlaybackEngine.shared.currentTrack else { return}
        dispatchToJS(.lyrics, payload: [
                "trackId": track.id,
                "lrc": lyricsProvider?(track) ?? lyricsCache[track.id] ?? "",
        ])
    }

    /// 主题变化（播放页背景归属切换 web/native-scene 时调这个）。
    func pushThemeEvent() {
        let theme = themeProvider?() ?? WebSnapshotDTO.Theme(backgroundMode: "web", palette: [:])
        dispatchToJS(.theme, payload: [
                "backgroundMode": theme.backgroundMode,
                "palette": theme.palette,
        ])
    }

    /// 缓冲态。由 bindPlaybackEngine 订阅 engine.$playbackState 驱动
    ///（.waiting -> true，其余 -> false，变化才发）；也供 M1 直接调用。waiting 时锁屏 rate=0.
    func pushBuffering(_ buffering: Bool) {
        dispatchToJS(.buffering, payload: ["buffering": buffering])
    }

    /// 恢复即推锚点：中断恢复 play 后（M1 调用）与 scenePhase 回.active 时（中心订阅）各补发一次。
    func repushAnchor() {
        pushAnchor()
    }

    /// seek 竞态三件套之①：松手 seek 前由调用方（FullPlayerContainer / JS seek 动作）
    /// 先调这个，立即推乐观锚点；随后周期 observer 跳过推送，直到落点确认。
    func noteSeekStarted(target: TimeInterval) {
        pendingSeek = (target: target, startedAt: Date())
        dispatchToJS(.seek, payload: ["t": target, "rate": currentRate])
    }

    private func pushAnchor() {
        dispatchToJS(.seek, payload: [
                "t": PlaybackEngine.shared.currentTime,
                "rate": currentRate,
        ])
    }

    private func pushStateEvent() {
        let engine = PlaybackEngine.shared
        dispatchToJS(.state, payload: [
                "playing": engine.isPlaying,
                "rate": currentRate,
                "t": engine.currentTime,
                "trackId": engine.currentTrack?.id ?? "",
        ])
    }

    private func handleEngineTime(_ time: TimeInterval) {
        lastKnownTime = time
        guard time.isFinite else { return}
        if let pending = pendingSeek {
            // ② pendingSeek 期间周期 observer 跳过推送。
            if abs(time - pending.target) <= 2.0
            || Date().timeIntervalSince(pending.startedAt) > 3.0 {
                // ③ 完成回调无论 finished 真假都回推真实位置。
                pendingSeek = nil
                pushAnchor()
            }
            return
        }
        dispatchToJS(.progress, payload: ["t": time, "rate": currentRate])
    }

    private func queueSummary() -> [WebSnapshotDTO.QueueItem] {
        let queue = QueueManager.shared.queue
        let index = QueueManager.shared.currentIndex
        guard !queue.isEmpty, queue.indices.contains(index) else {
            // 队列未建时退到当前单曲，保证快照里至少有正在播的那首。
            if let track = PlaybackEngine.shared.currentTrack {
                return [WebSnapshotDTO.QueueItem(id: track.id, title: track.title, artist: track.artist)]
            }
            return []
        }
        let lower = max(index - 3, 0)
        let upper = min(index + 3, queue.count - 1)
        return queue[lower...upper].map {
            WebSnapshotDTO.QueueItem(id: $0.id, title: $0.title, artist: $0.artist)
        }
    }

    /// renderState 应用点：幂等（同值不重发），页面未加载完时缓存待发，
    /// didFinish 时补发；恢复必重发（didFinish 会清 lastSentRenderActive）。
    private func applyRenderActive(_ active: Bool) {
        renderActive = active
        guard isPageLoaded else {
            pendingRenderActive = active
            return
        }
        guard lastSentRenderActive != active else { return }
        lastSentRenderActive = active
        dispatchToJS(.renderState, payload: ["active": active])
    }

    private func dispatchToJS(_ event: BridgeEvent, payload: [String: Any]) {
        guard isPageLoaded,
        let data = try? JSONSerialization.data(withJSONObject: payload),
        let jsonStr = String(data: data, encoding:.utf8) else { return}
        // event 是枚举 rawValue，无注入风险；payload 走 JSONSerialization，防歌名引号破坏 JS。
        let js = "window.__FOLIA_BRIDGE__?.onNativeEvent('\(event.rawValue)', \(jsonStr));"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - JS -> Native

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "foliaAction",
        let body = message.body as? [String: Any],
        let action = body["action"] as? String else { return}

        switch action {
        case "togglePlay":
            PlaybackEngine.shared.togglePlayPause()
        case "next":
            QueueManager.shared.playNext(manual: true)
        case "prev":
            QueueManager.shared.playPrevious()
        case "seek":
            if let time = body["time"] as? TimeInterval {
                noteSeekStarted(target: time)
                PlaybackEngine.shared.seek(to: time)
            }
        case "like":
            if let trackId = PlaybackEngine.shared.currentTrack?.id {
                onToggleLikeRequested?(trackId)
            }
        case "minimize":
            onMinimizeRequested?()
        case "log":
            // fire-and-forget：只转发 warn/error，info 不过桥；不要求回执。
            let level = body["level"] as? String ?? "warn"
            guard level == "warn" || level == "error" else { return}
            let module = body["module"] as? String ?? "web"
            let messageText = body["message"] as? String ?? ""
            logStore.record(level: level, module: module, message: messageText)
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate：恢复 / 自愈 / 白闪

extension WebEffectBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        lastSentRenderActive = nil
        // 透明白闪处置：完成后 150ms 渐入。
        UIView.animate(withDuration: 0.15) {
            webView.alpha = 1.0
        }
        // 缓存的 renderState 补发（页面未加载完时不得丢事件）。
        if let pending = pendingRenderActive {
            pendingRenderActive = nil
            applyRenderActive(pending)
        } else {
            applyRenderActive(RenderStateCenter.shared.isActive)
        }
        // 恢复统一走全量快照。
        pushSnapshot()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        logStore.write(level: "error", module: "bridge",
            message: "WebEffect navigation failed: \(error.localizedDescription)")
    }

    /// 特效页进程自愈：terminate → reload → didFinish 后快照恢复。
    /// 防抖：60 秒内 ≥3 次停止自动 reload 并落盘报错，防包体损坏时死循环重载。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageLoaded = false
        lastSentRenderActive = nil
        let now = Date()
        terminateDates.append(now)
        terminateDates.removeAll { now.timeIntervalSince($0) > 60}
        if terminateDates.count >= 3 {
            autoReloadSuspended = true
            let message = "WebEffect content process terminated \(terminateDates.count)x in 60s; auto-reload suspended"
            lastFatalError = message
            logStore.write(level: "error", module: "bridge", message: message)
            return
        }
        logStore.write(level: "warn", module: "bridge",
            message: "WebEffect content process terminated; reloading")
        if webView.url != nil {
            webView.reload()
        } else {
            loadLocalEffectBundle()
        }
    }
}

// MARK: - SwiftUI 包装器

struct WebEffectView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView}
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
