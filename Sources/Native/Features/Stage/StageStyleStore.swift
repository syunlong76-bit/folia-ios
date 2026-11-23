import Foundation
import UIKit

// 舞台样式的原生侧记录（UserDefaults）：
//  - currentStyleId：用户最近在原生选择器里选定的样式（或默认
//    classic）。注意边界：网页舞台内部改样式只发无载荷的
//    visualChanged 通知，原生无从得知其确切样式——本记录只是
//    「原生侧最后所知」，「当前样式未迁」提示以此为准（已知限制，
//    见 M2' 实施报告）。
//  - lastNativeStyleId：最近实际在原生舞台用过的已迁样式；当前
//    样式未迁时用它作替代样式（无记录时回默认 classic）。
enum StageStyleStore {
    private static let currentKey = "folia.stage.currentStyleId"
    private static let lastNativeKey = "folia.stage.lastNativeStyleId"

    static var currentStyleId: String {
        get {
            let stored = UserDefaults.standard.string(forKey: currentKey)
            if let stored, LyricStageRegistry.info(for: stored) != nil { return stored }
            return LyricStageRegistry.defaultStyleId
        }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }

    static var lastNativeStyleId: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: lastNativeKey)
            // (60) 第 4 条：锁定样式不得作回退落点（与未迁同等对待）。
            guard let stored, LyricStageRegistry.nativeStyleIds.contains(stored),
                  !LyricStageRegistry.isLocked(stored) else { return nil }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: lastNativeKey) }
    }

    /// 进原生舞台时应实际使用的样式：当前样式在本台可呈现
    /// （原生渲染或网页嵌入，3.7 (70) 口径）且未锁定则用它，
    /// 不可呈现/被锁定则用最近用过的已迁未锁样式（再无则默
    /// 认 classic——(70) 后 classic 走网页嵌入、同样可呈现）。
    /// 当前样式被锁定时同时把持久值改写为回退值并落面包屑。
    /// （74）machi 已解除锁定：存量 currentStyleId=machi 不
    /// 再触发本回退，按网页运行正常呈现。
    static func effectiveStyleId() -> String {
        let current = currentStyleId
        if LyricStageRegistry.isStagePresentable(current),
           !LyricStageRegistry.isLocked(current) { return current }
        let fallback = lastNativeStyleId ?? LyricStageRegistry.defaultStyleId
        if LyricStageRegistry.isLocked(current) {
            currentStyleId = fallback
            Breadcrumbs.log("style.lock fallback style=\(current) to=\(fallback)")
        }
        return fallback
    }

    /// 启动改写（3.7 (60) 第 4 条）：存量 currentStyleId 是锁定
    /// 样式时，在任何舞台呈现之前直接改写为回退值，避免
    /// 「当前样式」提示条等显示路径还报锁定样式。由
    /// runLaunchStyleGuard 在启动最先调用。（74）当前注册表
    /// 已无锁定样式，本守卫恒空转、仅作防御保留。
    static func applyLockedStyleFallbackIfNeeded() {
        let current = currentStyleId
        guard LyricStageRegistry.isLocked(current) else { return }
        _ = effectiveStyleId()
    }

    /// 当前记录样式能否在本台呈现（3.7 (70) 改名自
    /// currentStyleIsNative）：(70) 后网页 17 式经台面嵌入
    /// 呈现、「尚未原生化」提示的前提已不成立，判读改按可
    /// 呈现（原生渲染或网页嵌入）——注册表内样式恒可呈现，
    /// 提示条只剩未登记 id 的防御情形。
    static var currentStyleIsPresentable: Bool {
        LyricStageRegistry.isStagePresentable(currentStyleId)
    }

    // MARK: - 防卡死守卫（3.7 (44)）

    /// pending 标记：某样式已在舞台装配（mountRenderer）但尚
    /// 未被证明能存活渲染（StageViewController frameStep 满
    /// 60 帧或存活 2 秒后清除）。进程若在证明前消亡（卡死
    /// 被杀/崩溃），标记留存到下次启动——runLaunchStyleGuard
    /// 据此把该样式回退 classic，保证任何开台入口都不再撞
    /// 上同一块未证明的渲染路径。纵深防御：与冷启 route 取
    /// 消、莫奈成图异步化互不依赖。
    private static let stylePendingKey = "folia.stage.stylePending"

    static var stylePendingId: String? {
        UserDefaults.standard.string(forKey: stylePendingKey)
    }

    static func armStylePending(_ styleId: String) {
        UserDefaults.standard.set(styleId, forKey: stylePendingKey)
    }

    static func clearStylePending() {
        UserDefaults.standard.removeObject(forKey: stylePendingKey)
    }

    /// 启动守卫：SceneDelegate.willConnectTo 最先调用（任何
    /// 舞台呈现之前）。上次会话 pending 未清 = 上次开台未成
    /// 功：回退持久化样式至 classic 并清标记、落面包屑。
    /// 无 pending 时为空操作。
    static func runLaunchStyleGuard() {
        // (61) 第 3 条：内存警告计数观察者在启动最先注册一次。
        StyleOpenTrace.installMemoryWarningObserverIfNeeded()
        // (60) 第 4 条：锁定样式存量改写先行（与 pending 守卫互不依赖）。
        applyLockedStyleFallbackIfNeeded()
        guard let pending = stylePendingId else { return }
        clearStylePending()
        if currentStyleId == pending {
            currentStyleId = LyricStageRegistry.defaultStyleId
        }
        if lastNativeStyleId == pending {
            UserDefaults.standard.removeObject(forKey: lastNativeKey)
        }
        // (61) 第 3 条（DS R61 Q2 定案）：reset 行补 StyleOpenTrace
        // 的上次打开标记——lastMarker 停在 open/assembly 即进程死
        // 在首帧存活行之前，停在 firstFrame 则死在首帧之后；
        // attemptedStyle 为追踪记录的尝试样式（与 pending 不一
        // 致时以追踪为准对账）；reason 沿用原有原因（pending 未
        // 被证明清除）。
        Breadcrumbs.log("stage style-guard reset from=\(pending)"
            + " lastMarker=\(StyleOpenTrace.lastMarker)"
            + " attemptedStyle=\(StyleOpenTrace.attemptedStyleId ?? pending)"
            + " reason=pending-unproven")
    }
}

// MARK: - 样式打开追踪（3.7 (61) 第 3 条，DS R61 Q2 定案）
//
// 九样式点开闪退未定级，本追踪只做仪器化（不定案）：三次打开
// 里程碑经 UserDefaults 持久化（open → assembly → firstFrame），
// 进程若在某一步被杀（trap/jetsam），下次启动 runLaunchStyle-
// Guard 的 reset 行带出 lastMarker/attemptedStyle，与系统崩溃
// 报告（trap 签名）/JetsamEvent 二分。内存警告计数只注册一次
// 观察者、进程级累加，供装配/首帧两行对账（与 Breadcrumbs 自
// 带的 memoryWarning 面包屑是两条独立线，互不替代）。
enum StyleOpenTrace {
    private static let markerKey = "folia.stage.openTrace.marker"
    private static let styleKey = "folia.stage.openTrace.styleId"
    private static let hashKey = "folia.stage.openTrace.dataHash"

    private(set) static var memoryWarningCount = 0
    private static var observerInstalled = false

    /// 内存警告观察者只注册一次（首个调用点为启动守卫与每次
    /// 打开标记，均为进程早期/主线程路径）。
    static func installMemoryWarningObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            memoryWarningCount += 1
        }
    }

    static var lastMarker: String {
        UserDefaults.standard.string(forKey: markerKey) ?? "none"
    }

    static var attemptedStyleId: String? {
        UserDefaults.standard.string(forKey: styleKey)
    }

    static var attemptedDataHash: String? {
        UserDefaults.standard.string(forKey: hashKey)
    }

    /// 数据指纹：当前 track id＋歌词行数＋首/末行时间戳的
    /// FNV-1a 64 位稳定哈希（便宜、确定性、无加密依赖）——同
    /// 一数据反复闪退时三行 dataHash 恒同，可与换曲对照二分
    /// 「数据相关 trap」与「样式本身」。
    static func dataHash(trackId: String?, lines: [LyricLine]) -> String {
        let first = lines.first.map { String(format: "%.3f", $0.start) } ?? "-"
        let last = lines.last.map { String(format: "%.3f", $0.end) } ?? "-"
        let raw = "\(trackId ?? "-")|\(lines.count)|\(first)|\(last)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    /// 推进里程碑标记（marker ∈ open/assembly/firstFrame）。
    static func mark(_ marker: String, styleId: String, dataHash: String) {
        installMemoryWarningObserverIfNeeded()
        let defaults = UserDefaults.standard
        defaults.set(marker, forKey: markerKey)
        defaults.set(styleId, forKey: styleKey)
        defaults.set(dataHash, forKey: hashKey)
    }

    /// phys = task_vm_info phys_footprint（MB），与 Breadcrumbs
    /// 尾巴 footprintMB 同口径同源；采样失败回 -1。
    static func physFootprintMB() -> Int {
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

    /// avail = os_proc_available_memory()（MB）。
    static func availableMemoryMB() -> Int {
        Int(os_proc_available_memory() / 1_048_576)
    }

    /// 装配/首帧两行的内存字段串：phys=<MB> avail=<MB> memWarn=<n>。
    static func memoryFields() -> String {
        "phys=\(physFootprintMB()) avail=\(availableMemoryMB()) memWarn=\(memoryWarningCount)"
    }
}
