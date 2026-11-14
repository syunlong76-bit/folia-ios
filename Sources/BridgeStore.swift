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
        var show = cmd["show"] as? String
        if type == "show" { show = cmd["surface"] as? String }
        lock.unlock()
        if let show = show {
            DispatchQueue.main.async { [weak self] in
                self?.onShowSurface?(show)
            }
        }
        return mySeq
    }

    /// 取序号大于 since 的指令（播放表面轮询用）与当前最大序号
    func commands(since: Int) -> (seq: Int, cmds: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        let items = queue.filter { $0.seq > since }.map { ["seq": $0.seq, "cmd": $0.cmd] as [String: Any] }
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
        return (latestState, lastPlay)
    }
}
