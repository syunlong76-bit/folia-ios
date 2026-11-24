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

    /// (63) 同步落盘版 log（DS R63 对账口径）：调用返回时该行
    /// 已在磁盘上，进程紧接着被杀也不丢。仅供崩溃判别边界
    /// 行使用（tap.dispatch / stage.present.begin / asm 相位 /
    /// swap.begin / entry62.fire）；普通行仍走 log（异步）。
    /// 内存告警行 memoryWarning 为既有机制（本类 install 时
    /// 已订阅 didReceiveMemoryWarningNotification 落面包屑，
    /// DS M3 的 OOM/watchdog 方向靠它＋本行尾的 availMB 判读）。
    static func logSync(_ event: String) {
        installIfNeeded()
        let availMB = os_proc_available_memory() / 1_048_576
        FoliaBridgeLogStore.shared.writeSync(
            level: "info", module: "crumb",
            message: "\(event) · availMB=\(availMB) footprintMB=\(footprintMB())")
    }

    /// (78) 见证启动自检：(77) 两处见证（seam.flash77 被
    /// wrapActiveNow 条件挡住、minibar.claim77 所在派发段整
    /// 段没跑）整轮哑火而报告无从察觉的教训——本包每个新见
    /// 证先在启动时于本行登记在册，证明当轮面包屑通道活
    /// 着；此后某见证在日志中缺席，即可判「站点没跑」而非
    /// 「日志没收」。名册：flash=seam.flash78（设置台形变，
    /// 无条件落）、tap=mb.claim78/mb.disp78（播放条根级认
    /// 领新链）、dec=wall.dec78（封面解码量测）、tile=
    /// wall.tile78（砖面占位量测）。
    static func witnessBoot78() {
        log("wit78.live flash=1 tap=1 dec=1 tile=1")
        // (79) 名册续登：sb=状态栏隐藏五页自证（home/wall/
        // lattice/stage/entry 的 prefersStatusBarHidden)、
        // root=mb.root79 根级认领在场、fin=pet.fin79 拖动
        // 收尾落痕、drop=isl.drop79 落座未命中落痕、
        // geo=isl.geo79 岛带几何、req=wall.req79 砖请求链。
        log("wit79.live sb=1 root=1 fin=1 drop=1 geo=1 req=1")
        // (80) 名册续登：prep=prep.hit80/prep.ms80（下一首预
        // 备命中与就绪延迟）、guard=style.guard80（洗牌袋最
        // 近三首挡位）、mem=style.mem80（逐歌记忆记录/套用）。
        log("wit80.live prep=1 guard=1 mem=1")
        // (81) 名册续登：form=minibar.form 的 tw= 两态轨宽
        // （第 1 条）、cov=isl.cov81 岛中封面（第 4 条）、
        // geo=isl.geo81 岛带收窄（第 5 条）、machi=
        // webfx.machi81 町景触摸放行（第 6 条）、deck=
        // deck.size81 三宿主统一尺寸（第 9 条）、paw=
        // paw.tap81/paw.act81 爪印单击（第 10 条）、dir=
        // dir81.pick 导演判定（第 11 条）、rot=webfx.rot81
        // 特效页旋转量测（第 3 条）。
        log("wit81.live form=1 cov=1 geo=1 machi=1 deck=1 paw=1 dir=1 rot=1")
        // (82) 名册续登：ph=wall.ph82（封面命中/空白）、
        // tap=tap82（新台/控制台逐钮点按）、loc=locate82
        // （封面单击切换在播歌曲）、cov=isl.cov82（岛中
        // 簇重发）、fm=minibar.fm82（小白条形态）、rot=
        // rot82（特效旋转无门控量测）、light=light82
        // （开灯/关灯开关与点亮）。
        log("wit82.live ph=1 tap=1 loc=1 cov=1 fm=1 rot=1 light=1")
        // (83) 名册续登：q=wall.q83（快滑窗解码队列深度＋
        // 帧max）、dbl=dbltap83（双击全路径同步落盘）、
        // light=light83（关灯点亮放大＋启动复位）、cov=
        // isl.cov83（岛簇声波条＋横屏隐藏）、fm=minibar
        // .fm83（小白条量测对齐四项）、pf=pf83（prefetch
        // 真接线触发/入队计数）、hit=wall.hit83（cell 同
        // 步命中率新口径）。双击闪退已由 .ips 定行修复
        // （约束块删除），ph83 相位行随之取消、未入册。
        log("wit83.live q=1 dbl=1 light=1 cov=1 fm=1 pf=1 hit=1")
        // (84) 见证总表：tap84（逐钮 down/up＋命中链）／
        // wall.hit84（分墙命中窗）／pf84（预取转化率）／
        // wall.dec84（解码队列等待）／rot84（旋转落盘汇
        // 总）／minibar.fm84（小白条新口径）／DeckLayout84
        // （台高 70 单源）／sidebar84（主页竖条侧栏）。
        log("wit84.live tap=1 hit=1 pf=1 dec=1 rot=1 fm=1 deck=1 side=1")
        // (85) 见证总表：seam=seam85/sidebar85（世界缝开
        // 合/选界/逐钮去向）／loc=locate85（点头像定位
        // via/result/fail）／seek=seek85（收起态 seek 带互
        // 斥）／light=light85（关灯放大存活）／console=
        // console85（控制台小卡逐元素点按）。
        log("wit85.live seam=1 loc=1 seek=1 light=1 console=1")
        // (86) 见证总表：seam=seam86（缝油画底/头像代理链
        // 落痕）／loc=locate86（歌单页点头像定位全程）／
        // fm=fm86（旋转落定按朝向重写收起轨宽）／tap=
        // tap86（收起态点按原始落痕＋静止点兜底）／rot=
        // rot86（舞台旋转逐段毫秒）／pf=pf86（预取丢弃
        // 原因细分）／tb=toolbar86（工具条无痕展开入口）。
        log("wit86.live seam=1 loc=1 fm=1 tap=1 rot=1 pf=1 tb=1")
        // (84) 第 5 条：上次旋转摘要补发——Stage landed 时
        // 存 UserDefaults（emitted=false），本次启动补一行
        // 并置 emitted，杜绝导出截断丢失旋转量测。
        if var last = UserDefaults.standard.dictionary(forKey: "folia.rot84.last"),
           (last["emitted"] as? Bool) != true {
            log("rot84 prev gen=\(last["gen"] as? Int ?? -1)"
                + " f2l=\(last["f2l"] as? Int ?? -1)"
                + " f2r=\(last["f2r"] as? Int ?? -1)"
                + " style=\(last["style"] as? String ?? "?")"
                + " web=\(last["web"] as? Int ?? -1)")
            last["emitted"] = true
            UserDefaults.standard.set(last, forKey: "folia.rot84.last")
        }
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
