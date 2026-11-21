import Foundation
import UIKit

/// 崩溃面包屑（3.7 (13)，DS 第三十轮）：关键动作 + 内存水位写进桥
/// 日志（沙盒落盘、进程被杀后下次启动仍可读）。闪退后先看日志尾
/// 部：可用内存持续走低 = Jetsam；内存平稳 = 代码缺陷。
/// 墙在场时另开 3 秒周期采样（引用计数，多面墙共用一个计时器）。
enum Breadcrumbs {

    private static var installed = false
    private static let installLock = NSLock()
    private static var samplerTimer: Timer?
    private static var samplerRefs = 0
    private static var lastAvailMB = -1

    static func log(_ event: String) {
        installIfNeeded()
        let availMB = os_proc_available_memory() / 1_048_576
        FoliaBridgeLogStore.shared.write(
            level: "info", module: "crumb",
            message: "\(event) · availMB=\(availMB) footprintMB=\(footprintMB())")
    }

    /// 墙面出现/消失时成对调用；首个调用者启动采样，最后一个停。
    static func samplerStart() {
        samplerRefs += 1
        guard samplerTimer == nil else { return }
        log("sampler start")
        samplerTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            tick()
        }
    }

    static func samplerStop() {
        samplerRefs -= 1
        guard samplerRefs <= 0 else { return }
        samplerRefs = 0
        samplerTimer?.invalidate()
        samplerTimer = nil
    }

    private static func tick() {
        let availMB = os_proc_available_memory() / 1_048_576
        // 只在水位明显变化或告急时落盘，避免刷屏。
        if abs(availMB - lastAvailMB) >= 16 || availMB < 120 {
            lastAvailMB = availMB
            log("mem tick")
        }
    }

    private static func installIfNeeded() {
        // log() 可从后台队列进来（引擎 load），标志位加锁防重复注册。
        installLock.lock()
        defer { installLock.unlock() }
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            Breadcrumbs.log("memoryWarning")
        }
    }

    private static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / 1_048_576)
    }
}

/// 回调耗时登记表（3.7 (58) 定稿②）：入场掉帧量测的嫌疑回调
/// 耗时收集点——各嫌疑点（入场 0.1s 周期观察者、island.
/// refront、queue.restore 冷启恢复）经 measure/record 登记
/// 本入场周期内的最大耗时，入场 teardown 时由
/// EntryIntroViewController 汇总为 entry framedrops summary
/// 的 top3 caller（与 >50ms 帧间隔逐次记录对位定罪）。只记
/// 最大值不记分布（判读只问「谁能打出 50ms 级尖峰」）。全
/// 局静态＋锁：登记点跨模块（Core/Features）且调用线程不尽
/// 相同，入口一律加锁。
enum EntryCallbackTimings {

    private static var maximaMs: [String: Double] = [:]
    private static let lock = NSLock()

    static func record(_ name: String, ms: Double) {
        lock.lock()
        if ms > (maximaMs[name] ?? 0) { maximaMs[name] = ms }
        lock.unlock()
    }

    static func measure<T>(_ name: String, _ body: () -> T) -> T {
        let start = CACurrentMediaTime()
        let result = body()
        record(name, ms: (CACurrentMediaTime() - start) * 1000)
        return result
    }

    /// 耗时最大的前三名（name=ms 串），无登记时返回 "none"。
    static func top3Description() -> String {
        lock.lock()
        defer { lock.unlock() }
        let top = maximaMs.sorted { $0.value > $1.value }.prefix(3)
        if top.isEmpty { return "none" }
        return top.map { "\($0.key)=\(String(format: "%.1f", $0.value))ms" }
            .joined(separator: " ")
    }

    static func reset() {
        lock.lock()
        maximaMs = [:]
        lock.unlock()
    }
}
