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
