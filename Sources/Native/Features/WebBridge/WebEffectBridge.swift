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
    /// 点播装载失败（3.6 (3) 新增，只增不改）：{ trackId, title, message }。
    /// 此前原生失败只写 lastError，而全量前端壳没有原生报错面，点了没反应
    /// 也没提示；经此事件交前端用它自己的状态消息展示。
    case playbackError
    /// 歌词行边界（3.6 (3) 新增）：{ cueId, t }。前端注册 cue 表后，原生在
    /// 音频时钟跨过行界时发，前端据此钉锚点，页面忙时歌词也不漂。
    case cue
    /// 视觉切换（3.3 新增，只增不改）：{ lyricMode?, backgroundMode? }，
    /// 特效面据此调 visualizer 设置 store 的现成 setter。
    case visual
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
        /// 来源平台（AudioSourceType rawValue：netease/qq/kugou/local）。
        /// 网页面板据此识别歌曲平台（SongCredits 平台链接、在线歌词页签），
        /// 缺了它网页只能默认按网易云处理（2026-11-16 网页侧审查指出）。
        let provider: String
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
    /// 循环模式（桥词表 off/all/one）与音量 0...1：网页面板采纳回显用，
    /// 可选字段，旧版网页忽略不报错（2026-11-16 随原版面板恢复补上）。
    let loopMode: String?
    let volume: Double?
    /// 队列窗口对账（3.6 (3) 新增）：queue 是当前 ±3 的窗口，queueTotal 是
    /// 全队长度、queueOffset 是窗口首项在全队中的下标。网页镜像据此把下标
    /// 对回自己的全量队列，不再把窗口当全队（长歌单切歌后歌词页不更新的根源）。
    let queueTotal: Int
    let queueOffset: Int
    /// 锚点纪元（3.6 (3) 新增）：seek/切歌时 +1，网页据此丢弃迟到的旧锚点。
    let seekSeq: Int
    /// 快照采样时刻（epoch 毫秒，与网页 Date.now() 同钟）：网页据此扣除
    /// evaluateJavaScript 的投递延迟，锚点不再系统性慢半拍。
    let epochMs: Double
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

    /// 设置页桥日志查看器用：两份轮换文件按修改时间拼接，取最后 maxLines 行。
    func recentLogText(maxLines: Int) -> String {
        let urls = [fileURL(index: 0), fileURL(index: 1)]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return a < b
            }
        var lines: [String] = []
        for url in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                lines += text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            }
        }
        return lines.suffix(maxLines).joined(separator: "\n")
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
    /// 后台时进程被杀：不在后台硬重载（系统还会再杀），回前台再恢复。
    private var pendingReloadAfterTermination = false

    /// 锚点纪元：seek / 切歌 / 快照时递增，网页丢弃纪元更旧的锚点（3.6 (3)）。
    private var seekSeq = 0

    /// 状态事件可靠投递（3.6 (3)）：state / queue / snapshot 带 seq，网页经
    /// foliaNative 回 ack；500ms 未 ack 重发，最多 2 次。progress / seek /
    /// tick 类高频事件不走这套（丢了有下一跳，只有状态事件要求必达）。
    private var outboundSeq = 0
    private var unackedEvent: (seq: Int, js: String, retries: Int)?

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

        // P9 兜底（3.6 全量前端，审计 fullapp-exit-audit）：网页绝不出声的
        // 最后一道保险。deck 已在源码层饿死（audioSrc 恒 null、无 play 路径），
        // 这里再封 HTMLAudioElement.play()，防漏网写源路径被调用出声；
        // video 只强制静音不封 play——VideoLayer 的静音背景视频是原版视觉
        // 功能。元数据探针（localMusicService）从不调 play()，不受影响。
        let audioGuardSource = """
        (function () {
          HTMLAudioElement.prototype.play = function () {
            try { console.warn('[FoliaShell] blocked HTMLAudioElement.play()'); } catch (e) {}
            return Promise.reject(new Error('folia-native-audio-only'));
          };
          var originalVideoPlay = HTMLVideoElement.prototype.play;
          HTMLVideoElement.prototype.play = function () {
            this.muted = true;
            return originalVideoPlay.call(this);
          };
        })();
        """
        config.userContentController.addUserScript(WKUserScript(
                source: audioGuardSource, injectionTime:.atDocumentStart, forMainFrameOnly: false))

        // 长按抑制（沿用旧壳口径）：全局关 touch callout；文本选择只对
        // 非输入元素关闭，input/textarea/contenteditable 的编辑能力保持原样。
        let calloutSuppressSource = """
        (function () {
          var css = '* { -webkit-touch-callout: none !important; }'
            + '*:not(input):not(textarea):not([contenteditable]) { -webkit-user-select: none !important; }';
          var style = document.createElement('style');
          style.textContent = css;
          document.documentElement.appendChild(style);
        })();
        """
        config.userContentController.addUserScript(WKUserScript(
                source: calloutSuppressSource, injectionTime:.atDocumentStart, forMainFrameOnly: false))

        // foliaAction 注册必须在创建 WKWebView 之前——
        // 先 config.userContentController.add，后 WKWebView(frame:configuration:)。
        // 事后改 config 不生效，网页回传会全部收不到。
        let weakHandler = WeakScriptMessageHandler()
        config.userContentController.add(weakHandler, name: "foliaAction")
        // 播放页自带 UI 的指令通道（foliaNative，2026-11-16 随 Folia 原版
        // 胶囊条 + 玻璃面板恢复新增）：与 foliaAction 同一个弱引用 handler，
        // 同样必须在创建 WKWebView 之前注册。
        config.userContentController.add(weakHandler, name: "foliaNative")

        // 手势穿透框架（M2 末落地）：默认 passthroughRects 为空，行为与 WKWebView 一致。
        // 3.6 全量前端：这台 WebView 就是整个 App 的界面，滚动恢复常态。
        let webView = PassthroughWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        webView.allowsLinkPreview = false
        // 透明白闪处置：didFinish 前 alpha=0，完成后 150ms 渐入。
        webView.alpha = 0

        self.webView = webView
        super.init()

        weakHandler.delegate = self
        webView.navigationDelegate = self

        // 点播失败要上浮到前端展示（3.6 (3)）：全量前端壳没有原生报错面，
        // 不推事件就是点了没反应还没提示。
        QueueManager.shared.onManualLoadFailed = { [weak self] track in
            self?.pushPlaybackError(for: track)
        }
        // 歌词行边界：引擎跨过 cue 时发 cue 事件（前端注册 cue 表，见
        // handleNativeMessage 的 registerCues）。
        PlaybackEngine.shared.onLyricCue = { [weak self] cueId, time in
            // 带 epochMs：桥 JS 钉锚点时扣掉投递延迟，与其余四路口径一致（审查低 5）。
            self?.dispatchToJS(.cue, payload: ["cueId": cueId, "t": time,
                                                "epochMs": Date().timeIntervalSince1970 * 1000])
        }
        // 后台被杀后的延迟恢复：回前台时补一次重载 + 快照。
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)

        bindPlaybackEngine()
        bindRenderStateCenter()
        loadLocalEffectBundle()
    }

    @objc private func appDidBecomeActive() {
        guard pendingReloadAfterTermination, !autoReloadSuspended else { return }
        pendingReloadAfterTermination = false
        logStore.write(level: "warn", module: "bridge",
            message: "WebEffect deferred reload on becoming active")
        if webView.url != nil {
            webView.reload()
        } else {
            loadLocalEffectBundle()
        }
    }

    /// 点播装载失败事件：前端用自己的状态消息展示（文案与原生 lastError 同口径）。
    private func pushPlaybackError(for track: FoliaTrack) {
        dispatchToJS(.playbackError, payload: [
            "trackId": track.id,
            "title": track.title,
            "message": "《\(track.title)》暂时无法播放，可能需要 VIP 或受版权限制",
        ])
    }

    // MARK: - 加载

    private func loadLocalEffectBundle() {
        guard Bundle.main.url(
            forResource: "index", withExtension: "html", subdirectory: "WebEffect") != nil else {
            // 包缺失必须暴露，不许静默白屏。
            let message = "WebEffect bundle missing: Resources/WebEffect/index.html not found in app bundle"
            lastFatalError = message
            logStore.write(level: "error", module: "bridge", message: message)
            assertionFailure(message)
            return
        }
        // 3.6 (2)：必须走本地 http 同源加载。file:// 直读会让原版 App 的
        // IndexedDB（Dexie）初始化挂死、开机动画无限转（3.6 (1) 真机实证：
        // 同一产物 http 加载可完整启动）。数据接口走 LocalServer 的 /api
        // 同源代理，登录 Cookie 也按本机源规则流转。
        let server = LocalServer.shared
        if server.isRunning {
            loadPageURL(port: server.port)
            return
        }
        server.onReady = { [weak self] port in
            self?.loadPageURL(port: port)
        }
        server.start()
    }

    private func loadPageURL(port: UInt16) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/index.html") else { return }
        webView.load(URLRequest(url: url))
    }

    /// 防抖触发后的人工重试入口（诊断面板 / 设置页调用）。
    func retryAfterFatalError() {
        autoReloadSuspended = false
        terminateDates.removeAll()
        lastFatalError = nil
        // 手动恢复后清掉后台终止的待恢复标志，否则下次回前台会多一次无谓重载（审查低 11）。
        pendingReloadAfterTermination = false
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
    /// 原生 PlayMode → 桥 loopMode 词表（off/all/one）。shuffle 在桥词表里
    /// 没有对应词（面板的循环磁贴只循环 off/all/one），按 all 报。
    private static func bridgeLoopMode(_ mode: QueueManager.PlayMode) -> String {
        switch mode {
        case .loopAll, .shuffle:
            return "all"
        case .repeatOne:
            return "one"
        case .off:
            return "off"
        }
    }

    func pushSnapshot() {
        // 快照即新锚点纪元：切歌、恢复、模式变更都经这里，迟到的旧 progress
        // 锚点由网页按 seekSeq 丢弃。
        seekSeq += 1
        let engine = PlaybackEngine.shared
        let track = engine.currentTrack
        let window = queueWindow()
        let dto = WebSnapshotDTO(
            track: track.map {
                WebSnapshotDTO.Track(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    album: $0.album,
                    duration: $0.duration,
                    isLiked: isLikedProvider?($0.id) ?? false,
                    artworkRef: $0.artworkURL?.absoluteString,
                    provider: $0.sourceType.rawValue)
            },
            lrc: track.flatMap { lyricsProvider?($0) ?? lyricsCache[$0.id] } ?? "",
            renderActive: renderActive,
            theme: themeProvider?() ?? WebSnapshotDTO.Theme(backgroundMode: "web", palette: [:]),
            queue: window.items,
            currentIndex: QueueManager.shared.currentIndex,
            initialTime: engine.currentTime,
            rate: currentRate,
            loopMode: Self.bridgeLoopMode(QueueManager.shared.playMode),
            volume: Double(engine.volume),
            queueTotal: window.total,
            queueOffset: window.offset,
            seekSeq: seekSeq,
            epochMs: Date().timeIntervalSince1970 * 1000)
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
    
    /// 队列摘要：当前 ±3 首的窗口 + 全队长度/窗口偏移（3.6 (3) 对账字段）。
    func pushQueueEvent() {
        let window = queueWindow()
        dispatchToJS(.queue, payload: [
                "currentIndex": QueueManager.shared.currentIndex,
                "items": window.items.map { ["id": $0.id, "title": $0.title, "artist": $0.artist]},
                "total": window.total,
                "offset": window.offset,
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
    /// 歌词样式 / 背景类型切换（原生播放页的特效面板调用）。
    /// 特效面自己的 store 会把选择持久化，页面重载后仍是用户选的样式。
    func pushVisual(lyricMode: String?, backgroundMode: String?) {
        var payload: [String: Any] = [:]
        if let lyricMode { payload["lyricMode"] = lyricMode }
        if let backgroundMode { payload["backgroundMode"] = backgroundMode }
        guard !payload.isEmpty else { return }
        dispatchToJS(.visual, payload: payload)
    }

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
        seekSeq += 1
        dispatchToJS(.seek, payload: [
                "t": target, "rate": currentRate,
                "epochMs": Date().timeIntervalSince1970 * 1000, "seekSeq": seekSeq,
        ])
    }

    private func pushAnchor() {
        dispatchToJS(.seek, payload: [
                "t": PlaybackEngine.shared.currentTime,
                "rate": currentRate,
                "epochMs": Date().timeIntervalSince1970 * 1000, "seekSeq": seekSeq,
        ])
    }

    private func pushStateEvent() {
        let engine = PlaybackEngine.shared
        dispatchToJS(.state, payload: [
                "playing": engine.isPlaying,
                "rate": currentRate,
                "t": engine.currentTime,
                "trackId": engine.currentTrack?.id ?? "",
                "epochMs": Date().timeIntervalSince1970 * 1000, "seekSeq": seekSeq,
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
        dispatchToJS(.progress, payload: [
                "t": time, "rate": currentRate,
                "epochMs": Date().timeIntervalSince1970 * 1000, "seekSeq": seekSeq,
        ])
    }

    private func queueSummary() -> [WebSnapshotDTO.QueueItem] {
        queueWindow().items
    }

    /// 队列窗口：当前 ±3 首 + 窗口首项在全队中的下标 + 全队长度。
    private func queueWindow() -> (items: [WebSnapshotDTO.QueueItem], offset: Int, total: Int) {
        let queue = QueueManager.shared.queue
        let index = QueueManager.shared.currentIndex
        guard !queue.isEmpty, queue.indices.contains(index) else {
            // 队列未建时退到当前单曲，保证快照里至少有正在播的那首。
            if let track = PlaybackEngine.shared.currentTrack {
                // total 口径是「全队长度」：items 里有 1 首时 total 必须是 1，
                // 报 0 会让镜像的 aligned 对账快路径永远进不去（审查中 3）。
                return ([WebSnapshotDTO.QueueItem(id: track.id, title: track.title, artist: track.artist)],
                        0, 1)
            }
            return ([], 0, queue.count)
        }
        let lower = max(index - 3, 0)
        let upper = min(index + 3, queue.count - 1)
        return (queue[lower...upper].map {
            WebSnapshotDTO.QueueItem(id: $0.id, title: $0.title, artist: $0.artist)
        }, lower, queue.count)
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

    /// 需要可靠投递的状态事件（3.6 (3)）：带 seq、等 ack、超时重发。
    private static let trackedEvents: Set<BridgeEvent> = [.state, .queue, .snapshot]

    private func dispatchToJS(_ event: BridgeEvent, payload: [String: Any]) {
        guard isPageLoaded else { return }
        var payload = payload
        let tracked = Self.trackedEvents.contains(event)
        if tracked {
            outboundSeq += 1
            payload["seq"] = outboundSeq
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
        let jsonStr = String(data: data, encoding:.utf8) else { return}
        // event 是枚举 rawValue，无注入风险；payload 走 JSONSerialization，防歌名引号破坏 JS。
        let js = "window.__FOLIA_BRIDGE__?.onNativeEvent('\(event.rawValue)', \(jsonStr));"
        if tracked {
            unackedEvent = (seq: outboundSeq, js: js, retries: 0)
            scheduleAckCheck(seq: outboundSeq)
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// 500ms 未收到 ack 就重发同一条（最多 2 次）；新事件发出后旧的自动作废。
    private func scheduleAckCheck(seq: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let pending = self.unackedEvent, pending.seq == seq else { return }
            guard pending.retries < 2 else {
                self.logStore.write(level: "warn", module: "bridge",
                    message: "state event seq=\(seq) unacked after retries; dropping")
                self.unackedEvent = nil
                return
            }
            self.unackedEvent = (seq: seq, js: pending.js, retries: pending.retries + 1)
            self.webView.evaluateJavaScript(pending.js, completionHandler: nil)
            self.scheduleAckCheck(seq: seq)
        }
    }

    /// 网页经 foliaNative 回的 ack：清掉待确认事件。
    private func handleAck(_ body: [String: Any]) {
        guard let seq = (body["seq"] as? NSNumber)?.intValue else { return }
        if unackedEvent?.seq == seq { unackedEvent = nil }
    }

    // MARK: - JS -> Native

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }

        // 播放页自带 UI 的指令通道：独立分发，与 foliaAction 互不影响。
        if message.name == "foliaNative" {
            handleNativeMessage(body)
            return
        }

        guard message.name == "foliaAction",
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

    /// 播放页自带 UI（Folia 原版胶囊条 + 玻璃面板）的指令通道分发。
    /// 消息形状定版见 Resources/WebEffect/folia-bridge.js 的 sendNative 注释：
    /// transport / seek / queuePlay / queueRemove / playMode / volume /
    /// dismissPlayer / visualChanged，只增不改。
    private func handleNativeMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "ack":
            handleAck(body)
        case "registerCues":
            // 歌词行边界注册（3.6 (3)）：前端把当前曲的行界时间交原生，
            // 引擎跨界时回 cue 事件。切歌后旧表自动失效（trackId 对不上）。
            let trackId = (body["trackId"] as? String) ?? ""
            let cues = (body["cues"] as? [[String: Any]]) ?? []
            let parsed: [(id: String, time: TimeInterval)] = cues.compactMap { cue in
                guard let id = cue["id"] as? String,
                      let t = (cue["t"] as? NSNumber)?.doubleValue else { return nil }
                return (id: id, time: t)
            }
            PlaybackEngine.shared.setLyricCues(trackId: trackId, cues: parsed)
        case "transport":
            switch body["action"] as? String {
            case "play":
                PlaybackEngine.shared.play()
            case "pause":
                PlaybackEngine.shared.pause()
            case "toggle":
                PlaybackEngine.shared.togglePlayPause()
            case "next":
                QueueManager.shared.playNext(manual: true)
            case "previous":
                QueueManager.shared.playPrevious()
            default:
                break
            }
        case "seek":
            if let seconds = body["seconds"] as? TimeInterval {
                // 与原生拖动同一条路：先推乐观锚点并挂起周期推送，再 seek。
                noteSeekStarted(target: seconds)
                PlaybackEngine.shared.seek(to: seconds)
            }
        case "queuePlay":
            if let index = body["index"] as? Int {
                QueueManager.shared.playAtIndex(index)
            }
        case "queueRemove":
            if let index = body["index"] as? Int {
                QueueManager.shared.removeFromQueue(at: index)
                // 队列摘要由 $queue 订阅另行推送；这里再补一份全量快照，
                // 让面板队列页的行与当前下标一次对齐。
                pushSnapshot()
            }
        case "playMode":
            switch body["mode"] as? String {
            case "off":
                QueueManager.shared.playMode = .off
            case "all":
                QueueManager.shared.playMode = .loopAll
            case "one":
                QueueManager.shared.playMode = .repeatOne
            default:
                break
            }
            // loopMode 只在快照里下发，改完立即补发让面板磁贴回显新状态。
            pushSnapshot()
        case "volume":
            if let value = body["value"] as? Double {
                PlaybackEngine.shared.setVolume(Float(value))
            }
        case "setQueuePlay":
            // 3.6 全量前端起播漏斗：网页交来完整队列 + 起始下标，原生装载起播。
            // 入口留痕（3.6 (3) 取证）：主页点歌放不了时先分清「消息没到 /
            // 到了但队列为空 / 到了但装载失败」三岔口，日志在壳设置页可查。
            let tracks = Self.tracks(fromSongDTOs: body["songs"])
            logStore.write(level: "info", module: "bridge",
                message: "setQueuePlay songs=\(tracks.count) start=\((body["startIndex"] as? NSNumber)?.intValue ?? -1) first=\(tracks.first?.id ?? "-")")
            guard !tracks.isEmpty else { break }
            let start = (body["startIndex"] as? Int) ?? 0
            QueueManager.shared.setQueue(
                tracks, startingAt: min(max(start, 0), tracks.count - 1))
        case "setQueue":
            // 3.6 全量前端队列变异后的全量重发：静默替换，不打断当前播放；
            // 补发快照让网页镜像的下标与原生一次对齐。
            let tracks = Self.tracks(fromSongDTOs: body["songs"])
            let index = (body["currentIndex"] as? Int) ?? -1
            QueueManager.shared.replaceQueueSilently(tracks, currentIndex: index)
            pushSnapshot()
        case "dismissPlayer":
            RenderStateCenter.shared.setFullPlayerOpen(false)
        case "visualChanged":
            // 外观状态以特效面 store 为唯一真源（它自带持久化），原生仅记录、
            // 不回改、不回推 visual 事件，防两边互相覆盖。
            logStore.write(level: "info", module: "bridge", message: "visualChanged (record only)")
        default:
            break
        }
    }

    /// 网页 SongDTO -> FoliaTrack（3.6）。id 规则与 EdgeOneAPIClient 的
    /// toFoliaTrack 对齐：ncm_/qq_/kg_ 前缀 + 平台原始 id；取流 id 以
    /// mediaId 为准（仅与 id 不同时才带），缺省用 id。
    /// local/navidrome 归 .local：原生暂无本地文件通道，仍入队保下标与
    /// 网页队列对齐，轮到它时走引擎既有失败跳歌路径。
    private static func tracks(fromSongDTOs raw: Any?) -> [FoliaTrack] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { dto in
            let rawId = (dto["mediaId"] as? String)
                ?? (dto["id"] as? String)
                ?? (dto["mediaId"] as? NSNumber)?.stringValue
                ?? (dto["id"] as? NSNumber)?.stringValue
            guard let rawId, let provider = dto["provider"] as? String else { return nil }
            let sourceType: AudioSourceType
            let prefixedId: String
            switch provider {
            case "netease":
                sourceType = .netease
                prefixedId = "ncm_\(rawId)"
            case "qq":
                sourceType = .qq
                prefixedId = "qq_\(rawId)"
            case "kugou":
                sourceType = .kugou
                prefixedId = "kg_\(rawId)"
            default:
                sourceType = .local
                prefixedId = "local_\(rawId)"
            }
            var coverURL: URL?
            if let coverStr = dto["coverUrl"] as? String {
                coverURL = URL(string: coverStr.replacingOccurrences(
                    of: "http://", with: "https://"))
            }
            let durationMs = (dto["durationMs"] as? NSNumber)?.doubleValue ?? 0
            return FoliaTrack(
                id: prefixedId,
                sourceType: sourceType,
                title: (dto["title"] as? String) ?? "",
                artist: (dto["artist"] as? String) ?? "",
                album: (dto["album"] as? String) ?? "",
                duration: durationMs / 1000.0,
                artworkURL: coverURL)
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
    /// 3.6 (3) 两点修正：①立即重载会撞上系统刚杀进程的内存回收期，延迟
    /// 0.6 秒再重载；②后台时被杀不在后台硬重载（多半立刻再被杀，还白耗
    /// 电），标记待恢复，回前台（didBecomeActive）再重载，音频不受影响。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageLoaded = false
        lastSentRenderActive = nil
        unackedEvent = nil
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
        if UIApplication.shared.applicationState != .active {
            pendingReloadAfterTermination = true
            logStore.write(level: "warn", module: "bridge",
                message: "WebEffect content process terminated in background; deferring reload")
            return
        }
        logStore.write(level: "warn", module: "bridge",
            message: "WebEffect content process terminated; reloading in 0.6s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.autoReloadSuspended else { return }
            if self.webView.url != nil {
                self.webView.reload()
            } else {
                self.loadLocalEffectBundle()
            }
        }
    }
}

// MARK: - SwiftUI 包装器

struct WebEffectView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView}
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
