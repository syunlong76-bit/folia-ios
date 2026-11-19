import AVFoundation
import Foundation

/// 墙链歌词翻行事件锚定（3.7 (21)，DS R46 对账 + audit-3721 C5）：
/// 翻行改由 AVPlayer 的 boundary 事件驱动——行界注册到
/// PlaybackEngine 的 active 轨，音频时钟跨界即翻行；此前四轮
/// 迭代（(17) 台阶锚→(19) 真值锚+YRC→(20) LRC+settle）翻行全靠
/// LyricClockDriver 的自维护外推时钟逐帧比对，时钟恒定偏差无
/// 事件纠偏、每一行等量错下去。原 Web 详情页一直对得上，靠的
/// 正是行界 cue 事件锚定（audit-3721 C4 候选 1）；墙链同在原生
/// 侧，本类直接用 addBoundaryTimeObserver 原生直连，不经桥。
///
/// 职责划分（R46 拍板）：翻行只认事件；LyricClockDriver 退为
/// 只驱动扫光/进度（其 settle 重锚严格隔离在呈现时钟内，翻行
/// 路径不读）。本类的逐行兜底代翻是唯一例外，判据用媒体时间
/// 线（rawPlayhead），同样不读呈现时钟。
///
/// 护栏（DS R46 全套）：
/// - 注册带 trackId + 注册版本：回调按捕获的版本校验，旧版本/
///   旧曲事件一律丢弃；行号单调消费，迟到事件（≤已消费行）忽略。
/// - seek：先移除旧 observer 再按新位置重注册；seek 在途 +
///   settle 窗口（落定后 0.3s）内屏蔽兜底代翻，窗口结束按当前
///   时间静默对齐当前行（不补发历史行翻行面包屑）。
/// - 位置跳变（seekPending 没被 tick 观察到的 seek，如舞台页/
///   锁屏发起）：外推预期与真值差 >0.5s 即按 seek 同路静默对齐。
/// - 暂停清 pending（摘 observer、清兜底状态）；恢复只重注册
///   当前行起的行界，不补发历史。
/// - 切歌先解绑再绑定（VC 在切歌时调 unbind，新曲歌词到手后
///   bind）；注册失败（无 item/空行界等）立即降级：isDegraded
///   置位 + 面包屑告警，VC 回落 (20) 的时钟逐帧比对翻行。
/// - observer 释放防泄漏：解绑/重注册/VC 消失一律先移除旧
///   observer；player 身份变化（双轨切换预留）自动重注册。
///
/// 兜底代翻：某行 boundary 在「下一行已开始 +150ms」仍未触发
/// 时由本类按媒体时钟代翻（末行以自身行首 +150ms 为限）；每
/// 行最多代翻一次（单调消费保证）；代翻后升 epoch，同 epoch
/// 的迟到事件被单调消费自然吞掉，下一有效事件重新对齐。
///
/// 埋点：每次翻行落 `lrc flip src=boundary|fallback track= idx=`；
/// boundary 回调延迟（回调到达时 playhead − 行界时刻）逐次
/// 采样，每 30 次或解绑/切歌收尾时汇总一行 `lrc flip latency
/// p95=`。全部方法须主线程调用（VC tick 与 observer 的 .main
/// 队列同线程）。
///
/// (23) 职责再收窄（DS R49 改主推荐）：翻行主路径移交呈现钟
/// judge 直驱（VC tick 内逐帧按 judge 判当前行，与扫光同钟）；
/// 本类降为**校准/对账源**——注册、护栏状态机、兜底代翻与
/// 延迟采样全部保留（兜底状态仍供 VC 的 lineActive 兜底判据
/// 与两源偏差对账），但 UI 当前行不再读本类的 currentIndex。
/// 最近一次 boundary 翻行经 lastBoundaryFlip 暴露，VC 在
/// judge 翻行同行时落两源 lag 之差供真机对账。
final class LyricBoundaryFlipDriver {

    /// 兜底代翻阈值（秒）：行界在下一行开始后此时长仍未触发
    /// 才代翻（R46 区间 120–150ms，本包先取 150ms）。
    private static let fallbackThreshold = 0.150
    /// 单次注册的行界窗口（与引擎桥 cue 的 24 同量级）：跨界后
    /// 滚动重注册，避免整表 observer 与已消费时刻残留。
    private static let windowSize = 24
    /// seek settle 窗口（秒）：seek 落定后再静默此时长才恢复
    /// 兜底与重注册对齐，防落点抖动期误代翻。
    private static let seekSettleWindow = 0.3
    /// 位置跳变判定（秒）：播放中外推预期与真值差超此值按
    /// seek 处理（静默对齐），不逐行补代翻。
    private static let jumpThreshold = 0.5

    /// 当前应居中的行（VC 每帧读它定窗口）；事件/代翻/对齐驱动。
    private(set) var currentIndex = 0
    /// 已消费到的行（含当前行）：lineActive 判定与单调消费用。
    private(set) var consumedThrough = -1
    /// 降级态（注册失败）：VC 应回落时钟比对翻行。
    private(set) var isDegraded = false
    /// 降级原因（no-lines / no-item）：同表重复 bind 时据此决定
    /// 是否允许重试（仅 no-item 在 item 到位后同表转正）。
    private var degradedReason: String?
    /// 已绑定且未降级（VC 据此决定翻行走事件还是时钟）。
    var isActive: Bool { boundTrackId != nil && !isDegraded }

    private var boundTrackId: String?
    private var lineTimes: [Double] = []
    private var observer: Any?
    private weak var registeredPlayer: AVPlayer?
    private var registrationVersion = 0
    /// 代翻世代：每次代翻/静默对齐 +1；与注册版本共同构成
    /// 「同 epoch 迟到事件忽略」的账本（迟到事件算出的行号
    /// ≤ consumedThrough 时被单调消费吞掉）。
    private var epoch = 0

    private var wasPlaying = false
    private var wasSeekPending = false
    private var seekSettleUntil: CFTimeInterval?
    /// 兜底/跳变判定的外推基准（上一帧的媒体时刻与单调时刻）。
    private var lastRawNow: Double?
    private var lastTickWall: CFTimeInterval = 0

    /// boundary 延迟采样（秒）：回调到达 playhead − 行界时刻。
    private var latencySamples: [Double] = []
    private var flipsSinceLatencyLog = 0
    /// 最近一次 boundary 翻行（3.7 (23) 校准对账用）：行号 +
    /// 该次回调延迟（playhead − 行界）；兜底代翻不记（非事件
    /// 源）。VC 在 judge 翻到同一行时读它算两源偏差。
    private(set) var lastBoundaryFlip: (index: Int, lag: Double)?

    // MARK: - 绑定生命周期

    /// 绑定当前曲行界（幂等：同曲同表重复调用无操作，VC 每帧
    /// 调用即可）。歌词未到手/切歌间隙由 VC 先 unbind 或不调。
    func bind(trackId: String, lines: [LyricLineData]) {
        let engine = PlaybackEngine.shared
        let sameTable = boundTrackId == trackId
            && lineTimes.count == lines.count
            && lineTimes.first == lines.first?.time
            && lineTimes.last == lines.last?.time
        if sameTable {
            if !isDegraded { return }
            // 降级同表不重复告警；仅 no-item 留恢复口：item 到位
            // 后允许同表转正，其余降级维持到换表/换曲。
            guard degradedReason == "no-item",
                  engine.currentTrack?.id == trackId,
                  engine.lyricBoundaryPlayer.currentItem != nil else { return }
        }
        unbind()
        boundTrackId = trackId
        lineTimes = lines.map(\.time)
        guard !lineTimes.isEmpty,
              engine.currentTrack?.id == trackId,
              engine.lyricBoundaryPlayer.currentItem != nil else {
            // 注册失败立即降级：VC 回落时钟代翻（(20) 口径）。
            isDegraded = true
            degradedReason = lineTimes.isEmpty ? "no-lines" : "no-item"
            Breadcrumbs.log("lrc flip degraded reason=\(degradedReason ?? "?") track=\(trackId)")
            return
        }
        degradedReason = nil
        // 初始对齐：静默落在当前播放位置所在行，不补发历史。
        realign(rawNow: engine.rawPlayhead())
        wasPlaying = engine.isPlaying
        registerUpcoming()
    }

    /// 解绑：移除 observer、升版本作废在途回调、汇总延迟埋点。
    func unbind() {
        removeObserver()
        registrationVersion += 1
        flushLatencySummary()
        boundTrackId = nil
        lineTimes = []
        isDegraded = false
        degradedReason = nil
        currentIndex = 0
        consumedThrough = -1
        lastBoundaryFlip = nil
        seekSettleUntil = nil
        wasSeekPending = false
        lastRawNow = nil
    }

    // MARK: - 逐帧状态机（VC tick 驱动；只做护栏与兜底，不判翻行）

    /// now 参数一律用媒体时刻（rawPlayhead 真值）——兜底与跳变
    /// 判定都在音频时间线上，与呈现时钟（含 settle/输出延迟
    /// 补偿）完全隔离。
    func tick(rawNow: Double, isPlaying: Bool, seekPending: Bool) {
        guard boundTrackId != nil, !isDegraded else { return }
        let engine = PlaybackEngine.shared
        // 曲目已被引擎换掉而 VC 尚未感知：自解绑防旧行界在新曲
        // 同位置误触发（回调侧另有 trackId 双检）。
        guard engine.currentTrack?.id == boundTrackId else {
            unbind()
            return
        }
        // player 身份变化（双轨切换预留）：按当前位置重注册。
        if let player = registeredPlayer, player !== engine.lyricBoundaryPlayer {
            realign(rawNow: rawNow)
            registerUpcoming()
        }
        let wall = CACurrentMediaTime()

        // — seek 边沿：进入即摘 observer + 屏蔽兜底；落定后开
        // settle 窗口，窗口结束静默对齐 + 重注册。
        if seekPending && !wasSeekPending {
            removeObserver()
            seekSettleUntil = nil
        }
        if !seekPending && wasSeekPending {
            seekSettleUntil = wall + Self.seekSettleWindow
        }
        wasSeekPending = seekPending
        if let settleUntil = seekSettleUntil, !seekPending {
            if wall >= settleUntil {
                seekSettleUntil = nil
                realign(rawNow: rawNow)
                registerUpcoming()
            }
        }
        let inSeekWindow = seekPending || seekSettleUntil != nil

        // — 播停边沿：暂停清 pending（摘 observer）；恢复只重
        // 注册当前行起的行界、不补发历史（先静默对齐再注册）。
        if wasPlaying && !isPlaying {
            removeObserver()
        } else if !wasPlaying && isPlaying {
            realign(rawNow: rawNow)
            registerUpcoming()
        }
        wasPlaying = isPlaying

        // — 位置跳变（未被 seekPending 观察到的 seek）：播放中
        // 外推预期与真值差 >0.5s，静默对齐，不逐行补代翻。
        if isPlaying, !inSeekWindow,
           let last = lastRawNow {
            let expected = last + (wall - lastTickWall)
            if abs(rawNow - expected) > Self.jumpThreshold {
                realign(rawNow: rawNow)
                registerUpcoming()
            }
        }
        lastRawNow = rawNow
        lastTickWall = wall

        // — 兜底代翻：下一行待翻行界过期未达，按媒体时钟代翻。
        guard isPlaying, !inSeekWindow else { return }
        let next = consumedThrough + 1
        guard next < lineTimes.count else { return }
        let deadlineBase = next + 1 < lineTimes.count
            ? lineTimes[next + 1] : lineTimes[next]
        if rawNow > deadlineBase + Self.fallbackThreshold {
            epoch += 1
            flip(to: next, src: .fallback, rawNow: rawNow, recordLatency: false)
            registerUpcoming()
        }
    }

    // MARK: - 注册与回调

    private func removeObserver() {
        if let observer, let player = registeredPlayer {
            player.removeTimeObserver(observer)
        }
        observer = nil
        registeredPlayer = nil
    }

    /// 注册已消费行之后一个窗口的行界；无待注册行界时 observer
    /// 置空（全表已翻完）。注册时刻一律 > 当前 playhead（已过
    /// 的行界进了 observer 也永不触发，与引擎桥 cue 同教训）。
    private func registerUpcoming() {
        removeObserver()
        guard let trackId = boundTrackId, !lineTimes.isEmpty else { return }
        let engine = PlaybackEngine.shared
        let rawNow = engine.rawPlayhead()
        let start = consumedThrough + 1
        guard start < lineTimes.count else { return }
        let end = min(lineTimes.count, start + Self.windowSize)
        let times = (start..<end)
            .filter { lineTimes[$0] > rawNow + 0.02 }
            .map { NSValue(time: CMTime(seconds: lineTimes[$0], preferredTimescale: 600)) }
        guard !times.isEmpty else { return }
        registrationVersion += 1
        let version = registrationVersion
        let player = engine.lyricBoundaryPlayer
        registeredPlayer = player
        observer = player.addBoundaryTimeObserver(
            forTimes: times, queue: .main
        ) { [weak self] in
            self?.handleBoundary(version: version, trackId: trackId)
        }
    }

    /// boundary 回调不指明跨的是哪一界：按当前 playhead 算最后
    /// 一个已跨过的行界，单调消费到它为止。版本/曲目双检作废
    /// 旧注册与旧曲的迟到回调。
    private func handleBoundary(version: Int, trackId: String) {
        guard version == registrationVersion,
              trackId == boundTrackId, !isDegraded else { return }
        let engine = PlaybackEngine.shared
        guard engine.currentTrack?.id == trackId, engine.isPlaying else { return }
        // seek 在途/窗口内不消费事件（落定后由 tick 静默对齐）。
        guard !engine.isSeekPending, seekSettleUntil == nil else { return }
        let rawNow = engine.rawPlayhead()
        guard rawNow.isFinite else { return }
        var latest = consumedThrough
        for i in (consumedThrough + 1)..<lineTimes.count {
            if lineTimes[i] <= rawNow + 0.05 { latest = i } else { break }
        }
        guard latest > consumedThrough else { return }
        for i in (consumedThrough + 1)...latest {
            flip(to: i, src: .boundary, rawNow: rawNow,
                 recordLatency: i == latest)
        }
        registerUpcoming()
    }

    // MARK: - 翻行与对齐

    /// 单调消费一行：更新当前行、落翻行面包屑、计延迟汇总。
    private func flip(to index: Int, src: FlipSource, rawNow: Double, recordLatency: Bool) {
        guard index > consumedThrough, index < lineTimes.count,
              let trackId = boundTrackId else { return }
        consumedThrough = index
        currentIndex = index
        if src == .boundary && recordLatency {
            let lag = max(0, rawNow - lineTimes[index])
            latencySamples.append(lag)
            lastBoundaryFlip = (index: index, lag: lag)
        }
        Breadcrumbs.log("lrc flip src=\(src == .boundary ? "boundary" : "fallback") track=\(trackId) idx=\(index)")
        flipsSinceLatencyLog += 1
        if flipsSinceLatencyLog >= 30 { flushLatencySummary() }
    }

    /// 静默对齐到媒体时刻所在行：切歌绑定/seek 落定/暂停恢复/
    /// 位置跳变共用。不落逐行翻行面包屑（历史行不补发），只
    /// 更新消费位与当前行，随后由调用方重注册行界。
    private func realign(rawNow: Double) {
        var k = -1
        for i in lineTimes.indices {
            if lineTimes[i] <= rawNow { k = i } else { break }
        }
        consumedThrough = k
        currentIndex = max(k, 0)
        epoch += 1
    }

    /// 延迟汇总：每 30 次翻行或收尾（解绑/切歌）时一行。
    private func flushLatencySummary() {
        guard flipsSinceLatencyLog > 0 else { return }
        flipsSinceLatencyLog = 0
        guard !latencySamples.isEmpty else { return }
        let sorted = latencySamples.sorted()
        latencySamples = []
        let p95 = sorted[min(sorted.count - 1, Int((0.95 * Double(sorted.count)).rounded(.up)) - 1)]
        Breadcrumbs.log("lrc flip latency p95=\(String(format: "%.3f", p95)) n=\(sorted.count)")
    }

    private enum FlipSource { case boundary, fallback }
}
