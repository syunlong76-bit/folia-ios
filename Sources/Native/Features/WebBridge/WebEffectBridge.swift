import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

extension Notification.Name {
    /// 前端 stageClosed 已过桥（WebEffectBridge 转发）：3.7 (51)
    /// 前定义在 WallPrototypeViewController.swift 随回程票类型同
    /// 文件存放，回程票链删除后迁至此处（发方即本桥）；唯一消费
    /// 者为 WebStageHostViewController（自 dismiss 回原生舞台）。
    static let foliaStageClosed = Notification.Name("FoliaStageClosed")
}

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
    /// 视图恢复（3.6 (4) 新增，只增不改）：{ source, providerId?, id, type,
    /// name?, coverUrl?, trackCount? }。页面进程被杀重载后，原生把持久化
    /// 的当前集合视图描述发回页面，页面用自有导航回到原集合页（治 #4
    /// 回弹主页）。桥脚本同时把 payload 暂存 window.__foliaRestoreView，
    /// 防事件先于页面 hook 挂载到达。
    case restoreView
    /// 打开播放页（3.7 (11) 新增，只增不改）：原生墙小喇叭点按时发，
    /// 请前端打开其播放页/歌词舞台（DS26 Q4 的 (a) 路）。前端监听器
    /// 随下一次前端包更新落地；未落地前本事件无声投递，原生侧同时
    /// 收起原生墙作降级 (b)，用户落在网页迷你播放器旁。
    case openStage
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
    /// 逐字载荷（3.7 (67) A5，只增字段）：原生已合并的逐行词表，
    /// 词戳已 rebase 到 LRC 行界，与原生舞台同源同时刻；无 YRC
    /// 的行 words 为 nil，网页侧按 LRC 同口径合成。旧版网页忽略
    /// 本字段不报错。
    struct WordLine: Codable {
        struct Word: Codable {
            let s: Double
            let d: Double
            let w: String
        }
        let t: Double
        let e: Double
        let text: String
        let words: [Word]?
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
    /// 逐字载荷（3.7 (67) A5）：当前曲的逐行词表；未取到/无词时 nil。
    let wlines: [WordLine]?
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

    /// 轮换下标落盘（3.7 (65) 件一，取证报告
    /// forensics-2026-11-21-log-retention-and-selfcheck 定稿）：
    /// (63) 前下标只存内存、每启动归零——文件 0 写满后每次
    /// 启动首写都整删文件 1，上一会话（含崩溃判别 logSync
    /// 行）在重启导出前被物理销毁。改从 UserDefaults 读初
    /// 值、翻转时同步写回，轮换恢复为真滚动窗口。
    private static let indexDefaultsKey = "folia.log.index"
    private var currentFileIndex: Int

    private init() {
        currentFileIndex = UserDefaults.standard.integer(
            forKey: Self.indexDefaultsKey)
        // 上一会话尾巴转存（同报告件一）：必须在首写之前、
        // 任何 appendToFile 之前执行一次（单例 init 即首访
        // 问点，本进程只跑一次）。
        preservePreviousSessionTail()
    }

    /// 上一会话尾巴转存：读两份轮换文件（按修改时间拼接、
    /// 与 recentLogText 同序），取合并后最后 200 行覆写到
    /// 同目录 folia-prev-tail.log（不参与轮换）；随后同步
    /// 落一行 prevtail.save 进新会话头部作凭据。文件缺失/
    /// 首装时尾巴为空、照常落 n=0。
    private func preservePreviousSessionTail() {
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
        let tail = Array(lines.suffix(200))
        let tailURL = logDirectory
            .appendingPathComponent("folia-prev-tail.log")
        let body = tail.isEmpty ? "" : tail.joined(separator: "\n") + "\n"
        try? body.write(to: tailURL, atomically: true, encoding: .utf8)
        writeSync(level: "info", module: "crumb",
                  message: "prevtail.save n=\(tail.count)")
    }

    /// 上一会话尾巴（设置页桥日志查看器置顶拼接用）：取证
    /// 报告件一导出口径。无转存文件/为空返回空串。
    func prevTailText() -> String {
        let url = logDirectory.appendingPathComponent("folia-prev-tail.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
    /// (62) WC 簇 §4.11 单 hunk：写入本地文件受
    /// SettingsStore.bridgeLogWriteEnabled62 门控（默认开＝既有
    /// 行为）；关时只走 NSLog 控制台、不落盘。
    func write(level: String, module: String, message: String) {
        // (66) 运行日志采集总门控（开发者页签）：关时本存储
        // 完全不记录（控制台与落盘都停），与「写入本地文件」
        // 子开关分层——采集关则子开关无意义。
        guard SettingsStore.logCaptureEnabled62 else { return }
        let clean = sanitize(message)
        let line = "\(iso8601(Date())) [\(level.uppercased())][\(module)] \(clean)\n"
        // Xcode Console 与沙盒日志同步。
        NSLog("[FoliaBridge][\(module)] \(clean)")
        guard SettingsStore.bridgeLogWriteEnabled62 else { return }
        ioQueue.async { [weak self] in
            self?.appendToFile(line)
        }
    }

    /// (63) 同步落盘版 write：调用返回时该行已写进文件。
    /// 背景（DS R63 M5 取证缺陷）：write 走 ioQueue.async，
    /// 进程在队列排空前被杀（闪退现场）时关键行永远到不了
    /// 磁盘——三轮双击闪退取证都只剩存活会话日志。本入口供
    /// 崩溃判别边界行专用（tap.dispatch / present.begin /
    /// asm 相位 / swap.begin / entry62.fire），调用方保证
    /// 低频；门控与 write 同口径。
    func writeSync(level: String, module: String, message: String) {
        // (66) 采集总门控同 write（见上）。
        guard SettingsStore.logCaptureEnabled62 else { return }
        let clean = sanitize(message)
        let line = "\(iso8601(Date())) [\(level.uppercased())][\(module)] \(clean)\n"
        NSLog("[FoliaBridge][\(module)] \(clean)")
        guard SettingsStore.bridgeLogWriteEnabled62 else { return }
        ioQueue.sync {
            appendToFile(line)
        }
    }

    /// (63) 冲刷屏障：等 ioQueue 上已排队的异步写入全部落盘
    /// 后才返回（供关键点后补一手 flush 用）。
    func flush() {
        ioQueue.sync {}
    }

    /// 实际追加写文件（2MB 双文件轮换）。只许在 ioQueue 上调。
    /// 与 (62) 前 write 内联实现逐行同语义（url 先捕获、轮换
    /// 后本行仍写旧文件，下一行起走新文件），(63) 只做抽取。
    private func appendToFile(_ line: String) {
        let url = fileURL(index: currentFileIndex)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
        size.intValue >= maxFileBytes {
            currentFileIndex = 1 - currentFileIndex
            // (65) 件一：翻转即落盘，下次启动接着当前文件写，
            // 不再回零整删上一会话所在文件。
            UserDefaults.standard.set(currentFileIndex,
                                      forKey: Self.indexDefaultsKey)
            let next = fileURL(index: currentFileIndex)
            try? FileManager.default.removeItem(at: next)
            FileManager.default.createFile(atPath: next.path, contents: nil)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            if let data = line.data(using:.utf8) {
                try? handle.write(contentsOf: data)
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
    /// 真致命错误（包体缺失等不可恢复项）。3.6 (6) 起进程终止不再写它：
    /// 终止走无限退避自愈，永不向用户呈现「已停止自动恢复」。
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

    /// 进程自愈退避：180 秒窗口内的 terminate 时间戳（3.6 (6)，DS
    /// 第十三轮定版）。退避序号与 CoverPolicy 连杀信号都只从这一个
    /// 数组出（单一计数源头）；旧记录滑出窗口即自然清零，不再有挂起态。
    private var terminateDates: [Date] = []
    /// 后台时进程被杀：不在后台硬重载（系统还会再杀），回前台再恢复。
    private var pendingReloadAfterTermination = false

    /// 视图恢复（3.6 (4)，治 #4/#5）：本次重载是否由进程终止触发（决定
    /// didFinish 后要不要下发 restoreView）。3.6 (6) 起恢复下发不再设
    /// 次数上限（旧上限与重载挂起叠加成「回主页」事故），尝试数只记日志；
    /// 用户手动导航到别的集合后计数清零。
    private var terminationReloadPending = false
    private var viewRestoreAttempts = 0
    private var lastRestoredViewKey: String?
    /// 恢复期间盖住重载黑屏的快照遮罩（无快照时纯色兜底）。
    private var snapshotMaskView: UIImageView?
    private var lastViewSnapshot: UIImage?
    private var lastSnapshotCaptureAt: Date?
    /// 3.6 (7) P2：内存警告触发的快照刷新节流（与 viewState 的 4 秒
    /// 基础节流相互独立，防警告风暴连环截图反噬内存）。
    private var lastMemorySnapshotAt: Date?

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
    /// 逐字载荷缓存（track id -> 逐行词表，3.7 (67) A5）：与
    /// lyricsCache 同一取词路径（LyricRepository.Entry）填充。
    private var wordLinesCache: [String: [WebSnapshotDTO.WordLine]] = [:]
    /// 台面内嵌态（3.7 (67) A2/A6）：网页特效层正嵌在原生舞台
    /// 台面时为真（StageViewController 装/卸时置位）。进程被杀
    /// 的看门狗与重载后样式补推都只在嵌入态额外动作。
    var isEmbeddedInStage = false
    /// 样式首帧回执回调（3.7 (67) A4）：StageViewController 等
    /// 淡换时挂，桥收到 styleFrame 消息即转交并落 webfx.frame。
    var onStyleFrame: ((String) -> Void)?
    /// 最近一次由原生指定的网页样式（重载后补推用）与下发时刻
    /// （首帧回执延迟量测用）。
    private var lastDesignatedWebStyle: String?
    private var lastVisualPushAt: CFTimeInterval = 0
    /// §0 网页通路量测节流（webfx.per5 每 5 秒一行）。
    private var lastBridgePer5At: CFTimeInterval = 0
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

        // 封面异步解码（3.6 (6)，DS 第十三轮 Q3 定版）：只给经壳 /img
        // 代理的封面图补 decoding="async"，让解码离开主线程关键路径；
        // 不加 loading="lazy"（会与前端自有滚动恢复/轮播预加载打架），
        // 不改任何 DOM 结构。dataset 标记防观察器重复处理同一元素。
        let asyncDecodeSource = """
        (function () {
          function mark(img) {
            if (!img || img.dataset.foliaAsyncDecode) return;
            img.dataset.foliaAsyncDecode = '1';
            try { img.decoding = 'async'; } catch (e) {}
          }
          function consider(node) {
            if (!node || node.nodeType !== 1) return;
            if (node.tagName === 'IMG') {
              var s = node.getAttribute('src') || '';
              if (s.indexOf('/img/') >= 0) mark(node);
            } else if (node.querySelectorAll) {
              var imgs = node.querySelectorAll('img');
              for (var i = 0; i < imgs.length; i++) {
                var s2 = imgs[i].getAttribute('src') || '';
                if (s2.indexOf('/img/') >= 0) mark(imgs[i]);
              }
            }
          }
          consider(document.documentElement);
          var mo = new MutationObserver(function (muts) {
            for (var i = 0; i < muts.length; i++) {
              var m = muts[i];
              if (m.type === 'attributes') { consider(m.target); }
              for (var j = 0; j < m.addedNodes.length; j++) consider(m.addedNodes[j]);
            }
          });
          mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
        })();
        """
        config.userContentController.addUserScript(WKUserScript(
                source: asyncDecodeSource, injectionTime:.atDocumentEnd, forMainFrameOnly: true))

        // 不可见图驱逐（3.6 (7) P3，红线内组合包）：只定义触发函数，常态
        // 不动作；原生在内存警告时 evaluateJavaScript 调用一轮。范围刻意
        // 保守——只处理经 /img 代理的封面 <img>、且完全离开视口（含 0.5
        // 屏边距）的元素：src 存 dataset 后置 1px 透明图释放解码，
        // IntersectionObserver 在元素接近视口时恢复。墙海报由前端自身
        // 代码涂绘（非 <img> 呈现，沙箱复核），不在此列；正在播放页的
        // 可见图永远在视口内、不会被误伤。
        let evictSource = """
        (function () {
          if (window.__foliaShellEvict) return;
          var BLANK = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
          // 恢复节流（DS 第十六轮 2.3C）：回视口的图排队恢复，每 100ms
          // 最多放 4 张，防批量回调瞬间重取+重解码把内存弹回去。
          var restoreQueue = [], restoreTimer = null;
          function drainRestore() {
            var n = 0;
            while (restoreQueue.length && n < 4) {
              var img = restoreQueue.shift();
              if (img.dataset && img.dataset.foliaEvictedSrc) {
                // 独立审查中-3：驱逐期间框架可能已把这张 <img> 就地改派
                // 给新内容（src 不再是 BLANK）——此时只清标记，绝不把
                // 旧图盖回去。审查中-2：cssText 还原按键存在性判断，
                // 原样式为空串时也要还原，否则占位宽高永久残留。
                var stillBlank = (img.getAttribute('src') || '') === BLANK;
                if (stillBlank) {
                  if (img.dataset.foliaEvictedSrcset !== undefined) { img.srcset = img.dataset.foliaEvictedSrcset; delete img.dataset.foliaEvictedSrcset; }
                  if (img.dataset.foliaEvictedSizes !== undefined) { img.sizes = img.dataset.foliaEvictedSizes; delete img.dataset.foliaEvictedSizes; }
                  img.src = img.dataset.foliaEvictedSrc;
                  if (img.dataset.foliaEvictedStyle !== undefined) { img.style.cssText = img.dataset.foliaEvictedStyle; delete img.dataset.foliaEvictedStyle; }
                } else {
                  delete img.dataset.foliaEvictedSrcset;
                  delete img.dataset.foliaEvictedSizes;
                  delete img.dataset.foliaEvictedStyle;
                }
                delete img.dataset.foliaEvictedSrc;
              }
              n++;
            }
            if (restoreQueue.length) { restoreTimer = setTimeout(drainRestore, 100); }
            else { restoreTimer = null; }
          }
          function queueRestore(img) {
            if (restoreQueue.indexOf(img) < 0) restoreQueue.push(img);
            if (!restoreTimer) restoreTimer = setTimeout(drainRestore, 30);
          }
          var io = ('IntersectionObserver' in window) ? new IntersectionObserver(function (entries) {
            for (var i = 0; i < entries.length; i++) {
              if (entries[i].isIntersecting) { queueRestore(entries[i].target); io.unobserve(entries[i].target); }
            }
          }, { rootMargin: '600px' }) : null;
          function inWall(img) {
            var el = img;
            while (el && el !== document.body) {
              var c = (el.className && el.className.baseVal !== undefined) ? el.className.baseVal : (el.className || '');
              if (typeof c === 'string' && c.toLowerCase().indexOf('wall') >= 0) return true;
              el = el.parentElement;
            }
            return false;
          }
          window.__foliaShellEvict = function () {
            var vh = window.innerHeight || 0, vw = window.innerWidth || 0;
            // 驱逐排除带（700px）必须大于恢复 rootMargin（600px），留
            // 100px 迟滞带，否则边缘图会被驱逐后立刻恢复来回折腾
            //（独立审查低）。
            var marginY = 700, marginX = 700;
            var imgs = document.images, count = 0;
            for (var i = 0; i < imgs.length; i++) {
              var img = imgs[i];
              if (!img || img.dataset.foliaEvictedSrc) continue;
              var s = img.getAttribute('src') || '';
              if (s.indexOf('/img/') < 0) continue;
              if (inWall(img)) continue;
              var r = img.getBoundingClientRect();
              if (r.width === 0 && r.height === 0) continue;
              if (r.bottom >= -marginY && r.top <= vh + marginY && r.right >= -marginX && r.left <= vw + marginX) continue;
              // srcset/sizes 一并保存清空（2.3A：只清 src 浏览器仍会按
              // srcset 取图，驱逐无效）；占位尺寸防布局塌陷（2.3B）。
              img.dataset.foliaEvictedSrc = s;
              var ss = img.getAttribute('srcset');
              if (ss) { img.dataset.foliaEvictedSrcset = ss; img.removeAttribute('srcset'); }
              var sz = img.getAttribute('sizes');
              if (sz) { img.dataset.foliaEvictedSizes = sz; img.removeAttribute('sizes'); }
              img.dataset.foliaEvictedStyle = img.style.cssText || '';
              img.style.width = r.width + 'px';
              img.style.height = r.height + 'px';
              img.src = BLANK;
              if (io) io.observe(img);
              count++;
            }
            return count;
          };
        })();
        """
        config.userContentController.addUserScript(WKUserScript(
                source: evictSource, injectionTime:.atDocumentEnd, forMainFrameOnly: true))

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

        // 点播失败展示（3.6 (3) → 3.7 (51) 改线）：原接线经桥推
        // playbackError 事件给网页展示；(51) 换根后网页不再是主
        // 界面，此接线断开，改由原生面自展——窗口级轻量 toast
        // （NativePlaybackFailureToast，本文件尾），墙/舞台共用。
        // 曲目墙展开卡的持久失败态走 QueueManager.$lastError 订
        // 阅（既有原生面，不经本回调），两路不重复：toast 只管
        // 一次性瞬时提示。
        QueueManager.shared.onManualLoadFailed = { track in
            NativePlaybackFailureToast.show(trackTitle: track.title)
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
        // 内存警告 → CoverPolicy 闸门级（只降取图并发 + 修剪缓存，
        // 不降清晰度；3.6 (6)，DS Q6 两级拆分）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        bindPlaybackEngine()
        bindRenderStateCenter()
        loadLocalEffectBundle()
    }

    @objc private func appDidReceiveMemoryWarning() {
        CoverPolicy.triggerGateLevel(source: "memoryWarning")
        // 3.6 (7) P2：内存警告时节流刷新视图快照（≥10 秒），保证之后
        // 万一被杀，遮罩盖的是最近画面而非旧帧；capture 内部另有
        // superview/isLoading 守卫与 4 秒基础节流。
        let now = Date()
        if lastMemorySnapshotAt == nil || now.timeIntervalSince(lastMemorySnapshotAt!) >= 10 {
            lastMemorySnapshotAt = now
            captureViewSnapshotThrottled()
        }
        // 3.6 (7) P3 页面侧驱逐已于 3.6 (8) 止损停用：墙祖先类名排除在
        // 生产类名（lattice/bravais）下失效、可能误伤书库墙 <img> 海报，
        // 且驱逐收益从未证实（review-367 取证 + DS 第十七轮）。注入脚本
        // 与 evictOffscreenImages 保留备查，不再调用。
    }

    /// 3.6 (7) P3：让页面卸下视口外 /img 封面的解码（脚本侧恢复逻辑
    /// 自带）。页面未就绪/函数不存在时 evaluate 自然失败，静默忽略。
    private func evictOffscreenImages() {
        webView.evaluateJavaScript("window.__foliaShellEvict ? window.__foliaShellEvict() : -1") { result, _ in
            if let count = result as? Int, count > 0 {
                FoliaFileLog.write("bridge", "offscreen image eviction count=\(count)")
            }
        }
    }

    @objc private func appDidBecomeActive() {
        flushPendingReloadIfVisible()
        // 开页闭环事件驱动补投（13.5）：回前台时意图未落地就补一发。
        redispatchOpenStage(source: "foreground")
    }

    /// 推迟中的终止恢复补发（3.6 (6)，独立审查中-2）：终止时不可见只置
    /// 标志，若应用一直保持 active、只是 webView 暂时不在 window 里，
    /// didBecomeActive 永不触发、页面会永久死亡。补发点共三个：
    /// didBecomeActive、WebEffectView.updateUIView（视图重新入窗时
    /// SwiftUI 会调）、退避闭包到期复查。都汇到这里统一判定可见性。
    func flushPendingReloadIfVisible() {
        guard pendingReloadAfterTermination else { return }
        guard UIApplication.shared.applicationState == .active, webView.window != nil else { return }
        pendingReloadAfterTermination = false
        terminationReloadPending = true
        logStore.write(level: "warn", module: "bridge",
            message: "WebEffect deferred reload flushed on becoming visible")
        FoliaFileLog.write("bridge", "deferred reload flushed (termination recovery)")
        showSnapshotMask()
        if webView.url != nil {
            webView.reload()
        } else {
            loadLocalEffectBundle()
        }
    }

    // MARK: - 视图恢复（3.6 (4)）

    /// 已存集合视图的 UserDefaults 键（JSON 字典：source/providerId/id/type…）。
    private static let savedViewKey = "folia.lastCollectionView"

    private func handleViewState(_ view: [String: Any]?) {
        guard let view, let id = view["id"] else {
            UserDefaults.standard.removeObject(forKey: Self.savedViewKey)
            lastRestoredViewKey = nil
            viewRestoreAttempts = 0
            // M1 阶段 1：导航协调器旁听记账（离开集合）。
            NavigationCoordinator.shared.noteWebViewState(nil)
            return
        }
        if let data = try? JSONSerialization.data(withJSONObject: view) {
            UserDefaults.standard.set(data, forKey: Self.savedViewKey)
        }
        let key = "\(view["providerId"] as? String ?? "-")/\(view["type"] as? String ?? "-")/\(id)"
        FoliaFileLog.write("bridge", "viewState \(key)")
        // 用户手动导航到与上次恢复目标不同的集合：恢复计数清零。
        if key != lastRestoredViewKey {
            viewRestoreAttempts = 0
        }
        captureViewSnapshotThrottled()
        // M1 阶段 1：导航协调器旁听记账（不执行任何表面切换）。
        NavigationCoordinator.shared.noteWebViewState(view)
    }

    private func savedCollectionView() -> [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: Self.savedViewKey),
              let object = try? JSONSerialization.jsonObject(with: data),
              let view = object as? [String: Any], view["id"] != nil else { return nil }
        return view
    }

    /// 终止重载完成（didFinish）后调用：把已存视图下发页面恢复。
    /// 3.6 (6) 起不再设尝试上限：旧上限耗尽后页面停在首页，与重载挂起
    /// 叠加成真机「回主页」事故；恢复-再被杀的循环由重载侧退避限速，
    /// 恢复下发本身只是导航，无需再设一道闸。
    private func dispatchViewRestoreIfNeeded() {
        // 开页意图优先（13.5，DS38 Q6）：意图未落地期间挂起
        // restore，防它把页面从播放页拽回集合页；终局后下次
        // 重载照常恢复（恢复目标仍存着）。
        if let intent = openStageIntent, !intent.landed {
            FoliaFileLog.write("bridge", "viewRestore suspended for openStage intent=\(openStageShortId(intent.intentId))")
            return
        }
        guard let view = savedCollectionView() else {
            hideSnapshotMask()
            return
        }
        viewRestoreAttempts += 1
        let key = "\(view["providerId"] as? String ?? "-")/\(view["type"] as? String ?? "-")/\(view["id"]!)"
        lastRestoredViewKey = key
        // M1 阶段 1：标记恢复回声判定窗口（协调器据此区分 user/restore）。
        NavigationCoordinator.shared.noteRestoreDispatched(collectionKey: key)
        FoliaFileLog.write("bridge", "restoreView dispatched attempt=\(viewRestoreAttempts) \(key)")
        dispatchToJS(.restoreView, payload: view)
        // 页面导航回原页后会再报一次 viewState；遮罩最迟 2.2 秒撤下，
        // 恢复失败时也不把用户困在快照上。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.hideSnapshotMask()
        }
    }

    /// 开页提示状态（3.7 (13.5)，DS38 Q7）：经 onOpenStageNotice
    /// 交承载 WebView 的宿主显示顶部小条（3.7 (51) 起为
    /// WebStageHostViewController，原 MainViewController 安装点
    /// 已随换根摘除）；nil 表示撤下。
    enum OpenStageNotice {
        case opening
        case failed
    }

    /// 开页意图状态机（3.7 (13.5)，DS38 对账）：单一 active 意图。
    /// 沿革：13.3 pending+pull+ack（意图不丢、载荷回派时现建，
    /// 不存在旧快照把用户刚切的歌纠回去的问题）；13.4 TTL 延至
    /// 60s + didFinish 补投（补投成功跳过本次 restore，防恢复的
    /// 长等待窗后发先至把人从播放页拽回集合页）。13.4 真机仍败：
    /// 通用 dispatchToJS 的 completionHandler=nil 让「投递→落地」
    /// 整段无回执，投递失败与前端静默吞掉不可分。13.5 闭环：
    /// ①投递走专属带回执通道（evaluateJavaScript 回调记结果/
    /// 错误）；②前端处理回 ack、真落到播放页（view==='player'）
    /// 回 landed，ack 不再清意图、landed 才清；③未 landed 时
    /// 快速重试（1.5s / 5s，带 force 让前端放行同 intentId），
    /// 其后转事件驱动补投（didFinish / 回前台 / 前端 pull，单一
    /// 调度、0.9s 内合并）；④收墙与投递解耦但有截止：landed
    /// 到达或登记后 1.2s（先到者）触发 onDismiss 收墙，超时未
    /// landed 先收墙并提示「正在打开」，不把用户锁在墙上；
    /// ⑤TTL 60s 终局失败亮可点重试的提示条。
    private struct OpenStageIntent {
        let intentId: String
        let createdAt: Date
        var attempts = 0
        var acked = false
        var landed = false
        var lastDispatchAt: Date?
        var dismissFired = false
        var onDismiss: (() -> Void)?
    }
    private var openStageIntent: OpenStageIntent?

    /// 开页提示回调（WebStageHostViewController 在 viewDidLoad
    /// 里挂、退场摘除；3.7 (51) 前由 MainViewController 挂）。
    var onOpenStageNotice: ((OpenStageNotice?) -> Void)?

    /// 开页意图存活上限（13.4 定 60s，13.5 沿用）：覆盖进程自愈
    /// 的单步退避（≤30s）+ 重载 + 前端启动。
    private static let openStageTTL: TimeInterval = 60
    /// 收墙等待上限（13.5，DS38 Q3）：landed 先到先收；超时先
    /// 收墙 + 后台继续补投。
    private static let openStageDismissDeadline: TimeInterval = 1.2

    private func openStageShortId(_ intentId: String) -> String {
        String(intentId.prefix(8))
    }

    /// 原生墙请求打开播放页（DS26 Q4）：见 BridgeEvent.openStage 注释。
    /// 事件带原生播放快照（全队列元数据 + currentIndex + 平台
    /// id）。(13) β 定案前端走主态直达（回主态 + navigateToPlayer）；
    /// 13.1 起快照当前曲是落点权威：回主态后若网页当前曲平台 id
    /// 与快照对不上，前端按平台 id 纠偏（在网页 playQueue 找富
    /// 条目、找不到用快照元数据构造），不再只 warn。仍禁止按下标
    /// 到网页 store 取歌：两边队列不是同一份，下标对齐会错开歌。
    /// onDismiss 由闭环在 landed 或 1.2s 截止（先到者）时调用一次。
    func requestOpenStage(onDismiss: (() -> Void)? = nil) {
        if var active = openStageIntent, !active.landed {
            // 等待期重复请求幂等（DS38 Q3）：不新登记、不重投。
            // 收墙截止已过的直接补收；未过的接管收墙回调（同一
            // 面墙同一个收法）。
            if active.dismissFired {
                onDismiss?()
            } else {
                active.onDismiss = onDismiss ?? active.onDismiss
                openStageIntent = active
            }
            FoliaFileLog.write("bridge", "openStage re-request folded into active intent=\(openStageShortId(active.intentId))")
            return
        }
        let intentId = UUID().uuidString
        openStageIntent = OpenStageIntent(intentId: intentId, createdAt: Date(), onDismiss: onDismiss)
        FoliaFileLog.write("bridge", "openStage intent created intent=\(openStageShortId(intentId))")
        Breadcrumbs.log("openStage intent \(openStageShortId(intentId)) created")
        deliverOpenStage(force: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openStageDismissDeadline) { [weak self] in
            self?.openStageDismissDeadlineFired(intentId: intentId)
        }
        for (delay, label) in [(1.5, "retry1"), (5.0, "retry2")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.openStageRetryFired(intentId: intentId, label: label)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openStageTTL) { [weak self] in
            self?.openStageTTLFired(intentId: intentId)
        }
    }

    /// 提示条上的手动重试（13.5）：撤提示、新意图重走闭环。
    func retryOpenStage() {
        onOpenStageNotice?(nil)
        openStageIntent = nil
        requestOpenStage()
    }

    private func openStageDismissDeadlineFired(intentId: String) {
        guard var intent = openStageIntent, intent.intentId == intentId, !intent.landed else { return }
        fireOpenStageDismiss(&intent)
        openStageIntent = intent
        onOpenStageNotice?(.opening)
        FoliaFileLog.write("bridge", "openStage dismiss deadline fired (not landed yet) intent=\(openStageShortId(intentId)) attempts=\(intent.attempts) acked=\(intent.acked)")
    }

    private func openStageRetryFired(intentId: String, label: String) {
        guard let intent = openStageIntent, intent.intentId == intentId, !intent.landed else { return }
        // 单一调度（13.5 审查低-1）：与上一发间隔 <0.9s 的定时
        // 重试合并掉，事件驱动补投会接住（DS38 Q6 并发只发一次）。
        if let last = intent.lastDispatchAt, Date().timeIntervalSince(last) < 0.9 {
            FoliaFileLog.write("bridge", "openStage \(label) merged (last dispatch <0.9s ago) intent=\(openStageShortId(intentId))")
            return
        }
        FoliaFileLog.write("bridge", "openStage \(label) intent=\(openStageShortId(intentId)) attempts=\(intent.attempts) acked=\(intent.acked)")
        deliverOpenStage(force: true)
    }

    private func openStageTTLFired(intentId: String) {
        guard let intent = openStageIntent, intent.intentId == intentId, !intent.landed else { return }
        openStageIntent = nil
        onOpenStageNotice?(.failed)
        FoliaFileLog.write("bridge", "openStage FAILED (TTL) intent=\(openStageShortId(intentId)) attempts=\(intent.attempts) acked=\(intent.acked)")
        Breadcrumbs.log("openStage intent \(openStageShortId(intentId)) failed after \(intent.attempts) attempts acked=\(intent.acked)")
    }

    private func fireOpenStageDismiss(_ intent: inout OpenStageIntent) {
        guard !intent.dismissFired else { return }
        intent.dismissFired = true
        intent.onDismiss?()
        intent.onDismiss = nil
    }

    /// 事件驱动补投（13.5，DS38 Q4/Q6）：didFinish / 回前台 /
    /// 前端 pull 汇到这里统一调度；与上一发间隔 <0.9s 的合并掉，
    /// 防多源同刻双投。
    private func redispatchOpenStage(source: String) {
        guard let intent = openStageIntent, !intent.landed else { return }
        if Date().timeIntervalSince(intent.createdAt) > Self.openStageTTL {
            openStageTTLFired(intentId: intent.intentId)
            return
        }
        if let last = intent.lastDispatchAt, Date().timeIntervalSince(last) < 0.9 { return }
        FoliaFileLog.write("bridge", "openStage redispatch source=\(source) intent=\(openStageShortId(intent.intentId)) attempts=\(intent.attempts)")
        deliverOpenStage(force: intent.attempts > 0)
    }

    /// 按当前队列现建快照并专属投递 openStage（13.5）：不走通用
    /// dispatchToJS 的无回执通道——evaluateJavaScript 回调把
    /// 结果/错误写进日志，「发了就信」到此为止。页面未就绪时
    /// 不硬投（投了也落在死文档上），记一笔 skipped，靠
    /// didFinish 补投与前端 pull 兜底。intentId 与 force 随载
    /// 荷走，前端据此跨通道去重、重试放行与回执。
    private func deliverOpenStage(force: Bool) {
        guard var intent = openStageIntent, !intent.landed else { return }
        let intentId = intent.intentId
        let short = openStageShortId(intentId)
        let queue = QueueManager.shared.queue
        let index = QueueManager.shared.currentIndex
        let items: [[String: Any]] = queue.map { track in
            var item: [String: Any] = [
                "nativeId": track.id,
                "platform": track.sourceType.rawValue,
                "platformTrackId": Self.platformTrackId(of: track),
                "title": track.title,
                "artist": track.artist,
                "album": track.album,
                "duration": track.duration
            ]
            if let cover = track.artworkURL?.absoluteString {
                item["cover"] = cover
            }
            return item
        }
        intent.attempts += 1
        intent.lastDispatchAt = Date()
        openStageIntent = intent
        let attempt = intent.attempts
        guard isPageLoaded else {
            FoliaFileLog.write("bridge", "openStage dispatch SKIPPED pageLoaded=false intent=\(short) attempt=\(attempt) force=\(force)")
            return
        }
        let payload: [String: Any] = [
            "intentId": intentId,
            "force": force,
            "snapshot": [
                "queue": items,
                "currentIndex": queue.isEmpty ? -1 : index % queue.count
            ] as [String: Any]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else {
            FoliaFileLog.write("bridge", "openStage dispatch FAILED serialize intent=\(short) attempt=\(attempt)")
            return
        }
        let js = "window.__FOLIA_BRIDGE__?.onNativeEvent('\(BridgeEvent.openStage.rawValue)', \(jsonStr));"
        FoliaFileLog.write("bridge", "openStage dispatch intent=\(short) attempt=\(attempt) force=\(force)")
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                FoliaFileLog.write("bridge", "openStage evaluate ERROR intent=\(short) attempt=\(attempt): \(error.localizedDescription)")
            } else {
                FoliaFileLog.write("bridge", "openStage evaluate ok intent=\(short) attempt=\(attempt)")
            }
        }
    }

    /// didFinish 后补投开页意图（13.4 起，13.5 并入统一调度）：
    /// 意图有效则补投并返回 true（调用方据此跳过本次 restore）；
    /// 无意图/已落地/已终局则返回 false 让行。
    @discardableResult
    private func flushPendingOpenStageIfValid() -> Bool {
        guard let intent = openStageIntent, !intent.landed else { return false }
        if Date().timeIntervalSince(intent.createdAt) > Self.openStageTTL {
            openStageTTLFired(intentId: intent.intentId)
            return false
        }
        redispatchOpenStage(source: "didFinish")
        return true
    }

    /// 前端拉取待处理开页意图：意图有效且未落地则经统一调度
    /// 回派（带同一 intentId、载荷现建）。
    fileprivate func handleGetPendingOpenStage() {
        guard let intent = openStageIntent, !intent.landed else { return }
        if Date().timeIntervalSince(intent.createdAt) > Self.openStageTTL {
            openStageTTLFired(intentId: intent.intentId)
            return
        }
        FoliaFileLog.write("bridge", "openStage pulled intent=\(openStageShortId(intent.intentId))")
        redispatchOpenStage(source: "pull")
    }

    /// 前端处理完开页的回执（13.5 起只记账不清意图）：处理≠
    /// 落地，意图活到 landed 或 TTL 终局。
    fileprivate func handleAckOpenStage(_ body: [String: Any]) {
        guard let intentId = body["intentId"] as? String,
              var intent = openStageIntent, intent.intentId == intentId else { return }
        intent.acked = true
        openStageIntent = intent
        FoliaFileLog.write("bridge", "openStage acked intent=\(openStageShortId(intentId)) attempts=\(intent.attempts)")
    }

    /// 前端真落到播放页的确认（13.5 新增，DS38 Q5：前端以
    /// useAppViewStore 的 view==='player' 为准回发）：清意图、
    /// 补收墙、撤提示。编号对不上（意图已终局）也至少撤提示——
    /// 页面明明开着，失败条不能赖着。
    fileprivate func handleLandedOpenStage(_ body: [String: Any]) {
        guard let intentId = body["intentId"] as? String,
              var intent = openStageIntent, intent.intentId == intentId else {
            // 编号对不上：无 active 意图时撤掉可能残留的提示；
            // 有 active 意图时不理会，防过期 landed 监视误撤新
            // 意图的提示（13.5 审查低-2）。
            if openStageIntent == nil { onOpenStageNotice?(nil) }
            return
        }
        intent.landed = true
        fireOpenStageDismiss(&intent)
        openStageIntent = nil
        onOpenStageNotice?(nil)
        FoliaFileLog.write("bridge", "openStage LANDED intent=\(openStageShortId(intentId)) attempts=\(intent.attempts) acked=\(intent.acked)")
        Breadcrumbs.log("openStage intent \(openStageShortId(intentId)) landed after \(intent.attempts) attempts")
    }

    /// 平台原始 id：剥 ncm_/qq_/kg_ 前缀（原生墙自建队列是纯数字
    /// id、无前缀，原样返回）。网页 SongResult.id 是平台纯数字，
    /// 前端按它匹配。
    private static func platformTrackId(of track: FoliaTrack) -> String {
        for prefix in ["ncm_", "qq_", "kg_"] where track.id.hasPrefix(prefix) {
            return String(track.id.dropFirst(prefix.count))
        }
        return track.id
    }

    private func captureViewSnapshotThrottled() {
        let now = Date()
        if let last = lastSnapshotCaptureAt, now.timeIntervalSince(last) < 4 { return }
        lastSnapshotCaptureAt = now
        guard webView.superview != nil, !webView.isLoading else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, let image else { return }
            // 3.6 (7) P2（DS 第十六轮 4.4）：遮罩只是过渡显示，存图降采样
            // 到最大边 1080 像素。注意 image.size 是点、image.scale 是
            // 像素比——必须按像素判阈值，且 renderer 的 format.scale
            // 钉为 1，否则点数阈值在 iPhone 上永不触发、渲染器默认
            // scale 还会把节省抵消（独立审查中-1）。
            let maxPixelEdge: CGFloat = 1080
            let pixelW = image.size.width * image.scale
            let pixelH = image.size.height * image.scale
            let longest = max(pixelW, pixelH)
            if longest > maxPixelEdge, pixelW > 0, pixelH > 0 {
                let ratio = maxPixelEdge / longest
                let target = CGSize(width: (pixelW * ratio).rounded(), height: (pixelH * ratio).rounded())
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: target, format: format)
                self.lastViewSnapshot = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            } else {
                self.lastViewSnapshot = image
            }
        }
    }

    private func showSnapshotMask(caption: String? = nil, minDuration: TimeInterval = 4) {
        guard let superview = webView.superview, snapshotMaskView == nil else { return }
        let mask = UIImageView(frame: webView.frame)
        mask.image = lastViewSnapshot
        mask.contentMode = .scaleAspectFill
        mask.backgroundColor = UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)
        mask.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mask.isUserInteractionEnabled = false
        // 高退避时的非阻断提示（3.6 (6)，DS Q4）：只在遮罩底部加一行
        // 小字说明仍在自动恢复，不新增交互控件、不出现「已停止」语义。
        if let caption {
            let label = UILabel()
            label.text = caption
            label.font = .systemFont(ofSize: 12)
            label.textColor = UIColor.white.withAlphaComponent(0.65)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            mask.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: mask.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: mask.bottomAnchor, constant: -28),
            ])
        }
        superview.addSubview(mask)
        snapshotMaskView = mask
        // 硬兜底：到期无论如何撤下，绝不困住用户。3.6 (6) 起兜底时长随
        // 调用方 minDuration 走（独立审查中-3）：高退避时遮罩要陪跑到
        // 重载发起，否则 caption 只活 4 秒、剩下时间用户面对空白页。
        // 上限 40 秒保留防困死语义。
        let fallback = min(max(4, minDuration), 40)
        DispatchQueue.main.asyncAfter(deadline: .now() + fallback) { [weak self] in
            self?.hideSnapshotMask()
        }
    }

    private func hideSnapshotMask() {
        guard let mask = snapshotMaskView else { return }
        snapshotMaskView = nil
        UIView.animate(withDuration: 0.2, animations: { mask.alpha = 0 }) { _ in
            mask.removeFromSuperview()
        }
    }

    // 点播失败推网页展示的 pushPlaybackError 已于 3.7 (51) 删除：
    // 接线改原生 toast（见 init 的 onManualLoadFailed 与文件尾
    // NativePlaybackFailureToast）。BridgeEvent.playbackError 枚举
    // 值保留（桥协议只增不改），(52) 删桥时一并清理。

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

    /// 下一首预备·网页样式预热（3.7 (80) 第 1 项）：下一首的
    /// 记忆样式为网页运行时，提前确保特效页装载完成——首装
    /// （本地服务起服＋页面加载＋桥自检）的耗时不压在切歌瞬
    /// 间。已装载恒为空操作；不推任何视觉状态，当前曲呈现
    /// 不受影响，切换仍走 pushVisual 原路。
    func prewarmEffectPage80() {
        guard !isPageLoaded else { return }
        loadLocalEffectBundle()
        Breadcrumbs.log("prep.web80 warm")
    }

    /// (81) 第 3 条：旋转落定后催网页层按新尺寸重排——向
    /// 页面派发一记 resize 事件，画布监听者（WebGL 场景/
    /// 町景 OrbitControls 宿主）即刻按新宽高重绘，不等系
    /// 统布局的自然 resize 时序。揭盖回执走 onStyleFrame
    /// 原路（舞台侧结算）。
    func nudgeEffectResize81() {
        webView.evaluateJavaScript(
            "window.dispatchEvent(new Event('resize'))",
            completionHandler: nil)
    }

    /// 人工重试入口（诊断面板 / 设置页调用）：清退避计数与致命错误后重载。
    func retryAfterFatalError() {
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
            epochMs: Date().timeIntervalSince1970 * 1000,
            wlines: track.flatMap { wordLinesCache[$0.id] })
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
            // 取词改经共享仓库（3.7 (23)）：与墙面/舞台同一张
            // 缓存——任一面取过，本桥直接命中仓库的原始 LRC
            // 文本，不再单独发一次 /lyric 请求。仓库负结果
            // lrcText 为空串，与旧失败口径一致落 ""。
            let entry = await LyricRepository.shared.entry(for: track.id)
            DispatchQueue.main.async {
                self.lyricsCache[track.id] = entry.lrcText
                // 逐字载荷（3.7 (67) A5）：同一 Entry 的合并行表
                // 转桥 DTO；wordSrc 口径与仓库判读一致（全行有
                // 戳=yrc、无戳=uniform、混合=mixed）。
                let wordLines = Self.wordLines(from: entry, duration: track.duration)
                self.wordLinesCache[track.id] = wordLines
                let withWords = entry.lines.filter { $0.words != nil }.count
                let wordSrc = entry.lines.isEmpty ? "none"
                    : withWords == 0 ? "uniform"
                    : withWords == entry.lines.count ? "yrc" : "mixed"
                Breadcrumbs.log("bridge.wlines n=\(wordLines.count) w=\(withWords) src=\(wordSrc)")
                if PlaybackEngine.shared.currentTrack?.id == track.id {
                    self.pushLyricsEvent()
                }
            }
        }
    }
    
    /// 队列摘要：当前 ±3 首的窗口 + 全队长度/窗口偏移（3.6 (3) 对账字段）。
    func pushQueueEvent() {
        let window = queueWindow()
        // 闪退取证（3.7 (13.1)，DS32 清单）：推送是点播后 2 秒窗口内
        // 最重的跨界动作，事件锚定的内存读数比 3 秒采样更能定案。
        Breadcrumbs.log("queue push total=\(window.total) idx=\(QueueManager.shared.currentIndex)")
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

    /// Entry 合并行表 → 桥逐字载荷：行尾取下一行行首；末行取
    /// 词尾与曲长兜底（与网页 parseLRC 的行尾估计同口径域）。
    private static func wordLines(
        from entry: LyricRepository.Entry, duration: TimeInterval
    ) -> [WebSnapshotDTO.WordLine] {
        let lines = entry.lines
        return lines.enumerated().map { idx, line in
            let nextStart = idx + 1 < lines.count ? lines[idx + 1].time : nil
            let wordsEnd = line.words?.map { $0.start + $0.duration }.max()
            let end = nextStart ?? wordsEnd ?? max(line.time, duration)
            return WebSnapshotDTO.WordLine(
                t: line.time, e: max(end, line.time), text: line.text,
                words: line.words?.map {
                    WebSnapshotDTO.WordLine.Word(s: $0.start, d: $0.duration, w: $0.text)
                })
        }
    }

    /// 歌词文本变化（歌词后到 / 切换译文时调这个）。
    func pushLyricsEvent() {
        guard let track = PlaybackEngine.shared.currentTrack else { return}
        var payload: [String: Any] = [
                "trackId": track.id,
                "lrc": lyricsProvider?(track) ?? lyricsCache[track.id] ?? "",
        ]
        if let wordLines = wordLinesCache[track.id] {
            payload["wlines"] = wordLines.map { line in
                var dict: [String: Any] = ["t": line.t, "e": line.e, "text": line.text]
                if let words = line.words {
                    dict["words"] = words.map { ["s": $0.s, "d": $0.d, "w": $0.w] }
                }
                return dict
            }
        }
        dispatchToJS(.lyrics, payload: payload)
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
        if let lyricMode {
            // (67) A4/A7 量测与补推账：记最近指定样式与下发时刻，
            // styleFrame 回执据此算端到端延迟；进程重载后据此补推。
            lastDesignatedWebStyle = lyricMode
            lastVisualPushAt = CACurrentMediaTime()
            Breadcrumbs.log("webfx.push style=\(lyricMode)")
        }
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
        // §0 网页通路量测（3.7 (67) B 组）：每 5 秒一行桥锚点
        // 采样——t/epochMs/seekSeq 与网页侧日志对位算投递延迟。
        let now = CACurrentMediaTime()
        if now - lastBridgePer5At >= 5 {
            lastBridgePer5At = now
            Breadcrumbs.log("webfx.per5 t=\(String(format: "%.3f", time)) seq=\(seekSeq) wall=\(String(format: "%.3f", now))")
        }
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
        case "getPendingOpenStage":
            handleGetPendingOpenStage()
        case "ackOpenStage":
            handleAckOpenStage(body)
        case "openStageLanded":
            handleLandedOpenStage(body)
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
        case "viewState":
            // 当前集合视图上报（3.6 (4)）：持久化到 UserDefaults，进程被杀
            // 重载后据此恢复原页。view 为 null（或缺失）表示已回首页，清除。
            handleViewState(body["view"] as? [String: Any])
        case "stageClosed":
            // 网页舞台已关闭（3.7 (13) #6 → (51) 新链）：转发给网
            // 页舞台宿主 WebStageHostViewController，它自 dismiss
            // 回原生舞台。回程票恢复链已于 (51) 整链删除，不再有
            // 按票重建墙的消费者。
            logStore.write(level: "info", module: "bridge",
                           message: "stageClosed received")
            NotificationCenter.default.post(name: .foliaStageClosed, object: nil)
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
                tracks, startingAt: min(max(start, 0), tracks.count - 1),
                source: "web-bridge")
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
        case "styleFrame":
            // 样式首帧回执（3.7 (67) A4）：指定样式已画出第一帧，
            // 原生据此放行台面淡换；dt 为 visual 下发→回执端到端。
            let styleId = (body["styleId"] as? String) ?? ""
            let dtMs = lastVisualPushAt > 0
                ? (CACurrentMediaTime() - lastVisualPushAt) * 1000 : -1
            Breadcrumbs.log("webfx.frame style=\(styleId) dt=\(String(format: "%.0f", dtMs))")
            onStyleFrame?(styleId)
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
        // 桥自检（3.7 (13.7)，R39 定案）：folia-bridge.js 未进页面时，
        // 全部带回执的投递会被可选链静默吞掉——#1 点台进不了播放页
        // 六个版本的真因。每次加载完查一次，缺失就大声记日志。
        webView.evaluateJavaScript("typeof window.__FOLIA_BRIDGE__") { result, error in
            if error != nil {
                // 求值本身失败（页面恰在重载/终止竞速中）：不下结论，
                // 避免一条假 MISSING 污染后续排障的日志判读。
                Breadcrumbs.log("bridge self-check skipped (eval failed)")
            } else if let kind = result as? String, kind == "object" {
                Breadcrumbs.log("bridge self-check ok")
            } else {
                FoliaBridgeLogStore.shared.write(
                    level: "warn", module: "crumb",
                    message: "BRIDGE MISSING: window.__FOLIA_BRIDGE__ is \(String(describing: result))")
            }
        }
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
        // 嵌入台面重载恢复（3.7 (67) A6）：快照不带 visual 指令，
        // 页面自持久化的样式可能与原生当前指定不一致——嵌入态
        // 下把最近指定样式补推一次，台面不落回网页上次自选。
        if isEmbeddedInStage, let designated = lastDesignatedWebStyle {
            Breadcrumbs.log("webfx.repush style=\(designated)")
            pushVisual(lyricMode: designated, backgroundMode: nil)
        }
        // 终止重载的页面：快照之后补发视图恢复（3.6 (4)），把用户带回
        // 被杀前所在的集合页而不是停在首页。延时 0.9 秒等页面 App 挂载
        // 与恢复 hook 注册；桥脚本有暂存兜底，早到也不会丢。
        if terminationReloadPending {
            terminationReloadPending = false
            FoliaFileLog.write("bridge", "termination reload finished; scheduling view restore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self else { return }
                // 开页意图优先（13.4，DS36）：补投成功就跳过本次
                // restore 下发，恢复目标仍存着、下次重载照常。
                if self.flushPendingOpenStageIfValid() { return }
                self.dispatchViewRestoreIfNeeded()
            }
        } else if openStageIntent != nil {
            // 非终止重载（首启/手动重载）同样补投有效意图（DS36：
            // 无害，条件仍是意图有效）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.flushPendingOpenStageIfValid()
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        // 导航失败时终止恢复标志一并清掉（独立审查 L2），防残留误触发。
        terminationReloadPending = false
        logStore.write(level: "error", module: "bridge",
            message: "WebEffect navigation failed: \(error.localizedDescription)")
    }

    /// 特效页进程自愈：terminate → 退避后 reload → didFinish 后快照恢复。
    /// 3.6 (6) 定版（DS 第十三轮）：永不挂起。旧规则（60 秒 ≥3 次停恢复）
    /// 在封面墙连杀场景里必然触发，用户被永久挡在「已停止自动恢复」页、
    /// 手动重载又冷启回主页——恢复机制本身成了事故源。改为 180 秒窗口
    /// 退避 [0.6, 1.5, 3, 6, 12, 30] 秒、其后恒 30 秒，旧记录滑出窗口
    /// 自然清零；确定性必杀页最坏 30 秒一次重载，电量可接受。
    /// 保留 3.6 (3) 两点：①不立即重载（撞系统内存回收期）；②后台/不可见
    /// 时被杀不硬重载，标记待恢复、回前台再重载，音频不受影响。
    /// 连杀信号（30 秒内 ≥2 次）同时触发 CoverPolicy 降档级（墙档 320）。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // M1 阶段 1：导航协调器记账（表面归属不变，恢复链仍走桥侧既有逻辑）。
        NavigationCoordinator.shared.noteWebProcessTerminated()
        // 嵌入台面看门狗（3.7 (67) A6）：嵌入态被杀单独落屑，
        // 与既有退避重载链对位判读（重载＋didFinish 补推闭环）。
        if isEmbeddedInStage {
            Breadcrumbs.log("webfx.kill style=\(lastDesignatedWebStyle ?? "-")")
        }
        isPageLoaded = false
        lastSentRenderActive = nil
        unackedEvent = nil
        let now = Date()
        terminateDates.append(now)
        terminateDates.removeAll { now.timeIntervalSince($0) > 180 }
        let recentCount = terminateDates.filter { now.timeIntervalSince($0) <= 30 }.count
        if recentCount >= 2 {
            CoverPolicy.triggerLowTier(source: "terminations")
        }
        let backoffTable: [TimeInterval] = [0.6, 1.5, 3, 6, 12, 30]
        let delay = backoffTable[min(terminateDates.count - 1, backoffTable.count - 1)]
        FoliaFileLog.write("bridge", "webContentProcessDidTerminate count180s=\(terminateDates.count) backoff=\(delay)s state=\(UIApplication.shared.applicationState == .active ? "active" : "background")")
        // (86) 第 9 条：重载路径见证（只加见证、不改重载
        // 策略）——(85) 日志 WARN「后台被杀延迟重载」与旋
        // 转 gen=1 landed 缺行同源嫌疑，下轮按本行判读。
        Breadcrumbs.log("webfx.reload cnt=\(terminateDates.count)"
            + " backoff=\(delay)"
            + " state=\(UIApplication.shared.applicationState == .active ? "active" : "bg")")
        let visible = UIApplication.shared.applicationState == .active && webView.window != nil
        if !visible {
            pendingReloadAfterTermination = true
            logStore.write(level: "warn", module: "bridge",
                message: "WebEffect content process terminated while not visible; deferring reload")
            return
        }
        terminationReloadPending = true
        showSnapshotMask(caption: delay >= 12 ? "页面多次中断，正在低频自动恢复…" : nil,
                         minDuration: delay + 2)
        logStore.write(level: "warn", module: "bridge",
            message: "WebEffect content process terminated; reloading in \(delay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // 到期复查可见性（独立审查低-1）：退避期间用户可能已切后台，
            // 不可见就转入推迟、不硬重载（回前台/重新入窗时补发）。
            guard UIApplication.shared.applicationState == .active, self.webView.window != nil else {
                self.terminationReloadPending = false
                self.pendingReloadAfterTermination = true
                self.hideSnapshotMask()
                return
            }
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
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 视图重新入窗时的终止恢复补发点（3.6 (6)，独立审查中-2）。
        if uiView.window != nil {
            WebEffectBridge.shared.flushPendingReloadIfVisible()
        }
    }
}

// MARK: - 点播失败原生提示（3.7 (51)）

/// 点播装载失败的原生轻量提示（3.7 (51) 新增）：窗口级胶囊 toast，
/// 墙/舞台共用——挂在当前 key window 顶部安全区下，弹簧入场、
/// 3.2 秒后淡出自撤，连续失败只保留最新一条。
///
/// 来由：QueueManager.onManualLoadFailed 原靠桥推 playbackError 给
/// 网页展示（3.6 (3)），(51) 换根后网页不再是主界面、该接线断开；
/// 原生面此前只有曲目墙展开卡的持久失败态（走 $lastError 订阅、
/// 只认领本墙在途点播），主页墙/舞台无任何失败提示，故最小新增
/// 本 toast 补齐「点了没反应还没提示」的缺口（审计 §6-7）。文案
/// 与 QueueManager.lastError 同口径。
enum NativePlaybackFailureToast {

    private static weak var currentPill: UIView?

    static func show(trackTitle: String) {
        show(message: "《\(trackTitle)》暂时无法播放，可能需要 VIP 或受版权限制")
    }

    /// 通用文案入口（3.7 (54) 工作流 L）：曲目墙定位瞬时提示
    /// （不在本歌单/定位失败）随行动胶囊撤除改走本 toast——
    /// 窗口级、自动消失、不在墙面留任何常驻条/胶囊；与点播
    /// 失败 toast 同一实现（弹簧入场、3.2 秒淡出、只留最新）。
    static func show(message: String) {
        let message = sanitized91(message)
        DispatchQueue.main.async {
            guard let window = keyWindow() else { return }
            currentPill?.removeFromSuperview()
            currentPill = nil

            let pill = UIView()
            pill.backgroundColor = UIColor.black.withAlphaComponent(0.82)
            pill.layer.cornerRadius = 16
            pill.layer.borderWidth = 0.5
            pill.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            pill.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.numberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(label)
            window.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                pill.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 10),
                pill.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 24),
                pill.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -24),
                label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 7),
                label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -7)
            ])
            window.bringSubviewToFront(pill)
            currentPill = pill

            // iOS 系统弹簧口径入场（AGENTS.md UI 设定）：自顶部
            // 轻落 + 淡入，禁止线性/跳变。
            pill.alpha = 0
            pill.transform = CGAffineTransform(translationX: 0, y: -10)
            UIView.animate(withDuration: 0.45, delay: 0,
                           usingSpringWithDamping: 0.85,
                           initialSpringVelocity: 0.1,
                           options: [.allowUserInteraction]) {
                pill.alpha = 1
                pill.transform = .identity
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                guard currentPill === pill else { return }
                currentPill = nil
                UIView.animate(withDuration: 0.3, animations: {
                    pill.alpha = 0
                }, completion: { _ in
                    pill.removeFromSuperview()
                })
            }
        }
    }

    /// port91（任务 10）：原始 i18n 键拦截——(90) 录屏实锤
    /// 顶部 toast 露出 `status.songPreviewPlaying` 原始键。
    /// 定案：该键为上游 Folia 同源键（上游语言包有正式译文
    /// 「当前账号仅可试听，正在播放 {{seconds}} 秒片段」），
    /// 本 fork 的四语言包缺失此键、运行时回退显键；同族
    /// `status.songPreviewLoading` 全仓无字面量、疑动态拼接
    /// 键，一并兜底。凡形如 `status.*` 的无空格串到达本
    /// toast，一律映射为正式文案并落 p91 toast key 自证，
    /// 原始键永不上屏。语言包侧已同步补键（folia-major
    /// 四语言 status 段），双保险。
    private static func sanitized91(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("status."), !trimmed.contains(" ") else { return raw }
        Breadcrumbs.log("p91 toast key=\(trimmed)")
        if trimmed.contains("songPreview") { return "当前账号仅可试听此歌曲" }
        if trimmed.contains("loadingSong") { return "正在获取歌曲链接…" }
        if trimmed.contains("songRetrying") { return "连接失败，正在重试…" }
        if trimmed.contains("songVip") { return "第三方播放器暂时无法获取完整 VIP 歌曲" }
        if trimmed.contains("loginExpired") { return "登录状态已失效，请重新登录" }
        return "操作未完成，请稍后再试"
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
