import Foundation
import UIKit

// InteractionTrace.swift
//
// (61) WA 簇 · DS R61 单点 trace：为「点全屏/布局后卡死」未定级
// 问题埋的判别仪器。下一轮日志一轮判别三案：
//   · 沉浸假卡死——ping 全程通畅（maxPingMs 小）、沉浸期 tap 有
//     落行但 seamHit=0（点按没落到退出热区上）；
//   · 布局长帧——action=layout 窗口内 stall 行出现、maxPingMs
//     大（主线程被全量重排占住）；
//   · 退出逻辑 bug——tap 落行 seamHit=1 却无 endAction（退出
//     通路本身断了）。
//
// 设计约束：单例；ring buffer 只存最近 64 条定长结构事件、
// 低开销；ping 定时器只在 beginAction 后的 5s 窗口内活，不进
// 渲染循环、不常驻。全部状态经 lock 保护（ping 回调在主队列、
// 定时器在后台队列、tap/begin/end 由 UI 线程调入）。

final class InteractionTrace {

    static let shared = InteractionTrace()

    private init() {}

    // MARK: - ring buffer（最近 64 条）

    private struct Event {
        let at: CFTimeInterval
        let kind: String
        let detail: String
    }

    private static let capacity = 64
    private var ring: [Event] = []

    // MARK: - 窗口状态

    private let lock = NSLock()
    private var activeAction: String?
    private var windowStartAt: CFTimeInterval = 0
    private var generation = 0
    private var maxPingMs: Double = 0
    private var stallLoggedMaxMs: Double = 0
    private var tapCount = 0
    private var lastTapSeamHit = false
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(
        label: "folia.interaction-trace", qos: .utility)

    private static let windowDuration: CFTimeInterval = 5
    private static let pingInterval: CFTimeInterval = 0.1
    private static let stallThresholdMs: Double = 250

    // MARK: - API（其他簇接线面，签名以交付说明为准）

    /// 动作起点：SeamToolbarView 全屏钮传 "immersive"、布局钮
    /// 传 "layout"（已接线）；HomeWall 侧进入沉浸/切布局的等价
    /// 路径也可调。开启 5s 判别窗口：后台定时器每 ~100ms ping
    /// 主队列量往返延迟。已有窗口在途时先以 ended=superseded
    /// 汇总旧窗口再开新窗。
    func beginAction(_ action: String) {
        lock.lock()
        let hadActive = activeAction != nil
        lock.unlock()
        if hadActive {
            finalizeLocked(reason: "superseded")
        }
        lock.lock()
        generation += 1
        let gen = generation
        activeAction = action
        windowStartAt = CACurrentMediaTime()
        maxPingMs = 0
        stallLoggedMaxMs = 0
        tapCount = 0
        lastTapSeamHit = false
        appendLocked(kind: "begin", detail: action)
        lock.unlock()
        startTimer(generation: gen)
        Breadcrumbs.log("interaction.trace begin action=\(action)")
    }

    /// 沉浸期每次点按落一行（HomeWall seamImmersiveTap 接线面）：
    /// point 为点按在本视图坐标系的落点，hitViewChain 为该点
    /// hitTest 命中的视图类名链（自顶向下），seamFrame 为退出
    /// 热区（seamImmersiveTapView）的 frame，seamHit 为该点是
    /// 否落在退出热区内。窗口外调用只落 tap 行、不计数。
    func recordImmersiveTap(point: CGPoint, hitViewChain: [String],
                            seamFrame: CGRect, seamHit: Bool) {
        lock.lock()
        if activeAction != nil {
            tapCount += 1
            lastTapSeamHit = seamHit
        }
        appendLocked(kind: "tap",
                     detail: "seamHit=\(seamHit ? 1 : 0)"
                        + " point=\(Int(point.x)),\(Int(point.y))"
                        + " seam=\(Int(seamFrame.minX)),\(Int(seamFrame.minY)),"
                        + "\(Int(seamFrame.width))x\(Int(seamFrame.height))"
                        + " chain=\(hitViewChain.prefix(3).joined(separator: ">"))")
        lock.unlock()
        let chain = hitViewChain.prefix(3).joined(separator: ">")
        Breadcrumbs.log("interaction.trace tap seamHit=\(seamHit ? 1 : 0) chain=\(chain)")
    }

    /// 动作终点：退出沉浸/布局落定等收口路径调，reason 自由文
    /// 本（如 "tap-exit"、"layout-applied"）。窗口已超时汇总
    /// 时本调用无操作。
    func endAction(_ reason: String) {
        lock.lock()
        let wasActive = activeAction != nil
        lock.unlock()
        guard wasActive else { return }
        finalizeLocked(reason: reason)
    }

    /// ring buffer 快照（判读辅助，非面包屑通路）。
    func recentEventDescriptions() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return ring.map { "\($0.kind) \($0.detail)" }
    }

    // MARK: - 内部

    private func appendLocked(kind: String, detail: String) {
        ring.append(Event(at: CACurrentMediaTime(), kind: kind, detail: detail))
        if ring.count > Self.capacity {
            ring.removeFirst(ring.count - Self.capacity)
        }
    }

    private func startTimer(generation gen: Int) {
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now() + Self.pingInterval,
                        repeating: Self.pingInterval)
        source.setEventHandler { [weak self] in
            self?.timerTick(generation: gen)
        }
        lock.lock()
        timer?.cancel()
        timer = source
        lock.unlock()
        source.resume()
    }

    private func stopTimerLocked() {
        timer?.cancel()
        timer = nil
    }

    private func timerTick(generation gen: Int) {
        lock.lock()
        guard activeAction != nil, generation == gen else {
            lock.unlock()
            return
        }
        let elapsed = CACurrentMediaTime() - windowStartAt
        lock.unlock()
        if elapsed >= Self.windowDuration {
            finalizeLocked(reason: "timeout")
            return
        }
        let sentAt = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let dtMs = (CACurrentMediaTime() - sentAt) * 1000
            self.recordPing(dtMs: dtMs, generation: gen)
        }
    }

    private func recordPing(dtMs: Double, generation gen: Int) {
        lock.lock()
        guard activeAction != nil, generation == gen,
              let action = activeAction else {
            lock.unlock()
            return
        }
        if dtMs > maxPingMs { maxPingMs = dtMs }
        let isNewStall = dtMs > Self.stallThresholdMs && dtMs > stallLoggedMaxMs
        if isNewStall { stallLoggedMaxMs = dtMs }
        let maxNow = maxPingMs
        lock.unlock()
        if isNewStall {
            Breadcrumbs.log("interaction.trace stall ms=\(Int(maxNow.rounded())) action=\(action)")
        }
    }

    /// 汇总落行并关窗（ended=reason；超时由 timerTick 传
    /// "timeout"）。调用方不得持 lock（内部自锁）。
    private func finalizeLocked(reason: String) {
        lock.lock()
        guard let action = activeAction else {
            lock.unlock()
            return
        }
        let summary = "interaction.trace action=\(action)"
            + " maxPingMs=\(Int(maxPingMs.rounded()))"
            + " taps=\(tapCount) seamHit=\(lastTapSeamHit ? 1 : 0)"
            + " ended=\(reason)"
        appendLocked(kind: "end", detail: summary)
        activeAction = nil
        generation += 1
        stopTimerLocked()
        lock.unlock()
        Breadcrumbs.log(summary)
    }
}
