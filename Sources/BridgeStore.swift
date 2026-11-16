import Foundation

/// 双壳跨表面桥（壳 3.0）：指令队列 + 最新播放状态 + 最近一次 play 快照。
/// 状态只存内存（应用进程级），由 LocalServer 的 /__bridge/* 路由读写，
/// 两个 WebView 经同源 HTTP 访问，故不需要任何 JS 注入通道。
///
/// 指令流向：浏览表面 POST /__bridge/cmd → 本处入队（并通知壳切表面）→
/// 播放表面轮询 GET /__bridge/cmds 取走执行；播放状态反向经 state 通道
/// 给浏览表面的迷你播放条。播放表面进程被杀重建后，靠 lastPlay 快照恢复。
final class BridgeStore {

    static let shared = BridgeStore()

    /// 壳层回调：需要切换可见表面时调用（"browse" / "player"），已切到主线程
    var onShowSurface: ((String) -> Void)?

    /// 3.2 原生接管回调：play 家族指令入队时同步触发（在 onShowSurface
    /// 派发之前），由 NativePlaybackCoordinator 处理并改道原生引擎。
    var onCommand: (([String: Any]) -> Void)?

    /// play 家族指令类型：3.2 起由原生引擎执行，不再下发网页播放表面。
    static let nativeHandledTypes: Set<String> = [
        "play", "playQueueFromStart", "addAndPlay", "addToQueue", "transport"
    ]

    /// 是否已有 play 家族指令被原生接管（首条到达即置位，只增不减）。
    /// 置位后 commands() 过滤该族指令、snapshot() 不再给 lastPlay 快照，
    /// 防网页播放表面自启播或按快照恢复出第二路声音。
    private(set) var nativePlaybackActive = false

    private let lock = NSLock()
    private var seq = 0
    private var queue: [(seq: Int, cmd: [String: Any])] = []
    private var latestState: [String: Any]?
    private var lastPlay: [String: Any]?

    private init() {}

    /// 入队一条指令，返回分配的序号。play 指令同时刷新 lastPlay 快照；
    /// 带 show 字段（或 show 指令本身）的，通知壳层切换可见表面。
    @discardableResult
    func enqueue(_ cmd: [String: Any]) -> Int {
        lock.lock()
        seq += 1
        let mySeq = seq
        queue.append((seq: mySeq, cmd: cmd))
        if queue.count > 50 { queue.removeFirst(queue.count - 50) }
        let type = cmd["type"] as? String
        if type == "play" {
            lastPlay = ["song": cmd["song"] ?? NSNull(), "queue": cmd["queue"] ?? []]
        }
        let isNativeHandled = type.map { Self.nativeHandledTypes.contains($0) } ?? false
        if isNativeHandled { nativePlaybackActive = true }
        var show = cmd["show"] as? String
        if type == "show" { show = cmd["surface"] as? String }
        lock.unlock()
        if isNativeHandled {
            onCommand?(cmd)
        }
        if let show = show {
            DispatchQueue.main.async { [weak self] in
                self?.onShowSurface?(show)
            }
        }
        return mySeq
    }

    /// 取序号大于 since 的指令（播放表面轮询用）与当前最大序号。
    /// 原生接管置位后，play 家族指令不再下发（已由原生引擎执行）。
    func commands(since: Int) -> (seq: Int, cmds: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        let items = queue.filter { item in
            guard item.seq > since else { return false }
            if nativePlaybackActive,
               let type = item.cmd["type"] as? String,
               Self.nativeHandledTypes.contains(type) {
                return false
            }
            return true
        }.map { ["seq": $0.seq, "cmd": $0.cmd] as [String: Any] }
        return (seq, items)
    }

    func setState(_ state: [String: Any]) {
        lock.lock()
        latestState = state
        lock.unlock()
    }

    func snapshot() -> (state: [String: Any]?, lastPlay: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        // 原生接管后不给快照：网页播放表面即使被旧路径拉起，也不能按
        // lastPlay 恢复网页播放（会和原生引擎双出声）。state 照常返回。
        return (latestState, nativePlaybackActive ? nil : lastPlay)
    }
}
