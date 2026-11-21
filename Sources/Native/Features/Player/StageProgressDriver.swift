import QuartzCore
import UIKit

/// 播放进度逐帧插值驱动（3.7 (13.4)，DS36 裁定抽共享）：迷你台
/// 进度原先靠 0.3 秒心跳直接读引擎时间步进，真机被 Miller 判
/// 「卡、不丝滑」；引擎 currentTime 本身是 200ms 周期缓存，逐帧
/// 直读仍是台阶。本驱动用锚点插值：以引擎时间为锚、按显示刷新
/// 逐帧外推（播放速率恒 1——PlaybackEngine.currentRate 只有
/// 1/0 两态）；引擎时间与外推偏差超过 0.3 秒（seek、切歌、
/// 漂移）即重锚。两个播放台（主页墙/曲目墙）共用一份，防数值
/// 机制漂移；宿主不可见时必须 stop（DS36：防双台驱动叠加）。
///
/// (23) 锚源改真值（DS R49 Q2，与舞台 PlaybackAnchor 同改）：
/// 锚与漂移比对都改读 rawPlayhead()（此前同用台阶缓存、自
/// 比自锚，恒定滞后锁死）；漂移阈值收紧 0.25s、连续 2 帧
/// 超限才重锚，漂移重锚落面包屑（启动/切歌重锚不落，防刷屏）。
final class StageProgressDriver {
    var onFraction: ((Double) -> Void)?

    private var displayLink: CADisplayLink?
    private var anchorTime: Double = 0
    private var anchorWall: CFTimeInterval = 0
    private var anchorTrackId: String?
    private var lastFraction: Double = -1
    /// 漂移连续超限帧数（3.7 (23)）：连续 2 帧 >0.25s 才重锚。
    private var driftOverFrames = 0

    func start() {
        guard displayLink == nil else { return }
        // (62) WB §4.4：静态模式开时逐帧驱动不起链（进度改由
        // 宿主低频心跳兜底，与既有 stop 口径一致）。
        guard !SettingsStore.staticModeEnabled else {
            Breadcrumbs.log("progressDriver62 start skipped=staticMode")
            return
        }
        // (62) WB §4.4：后台积极节流的停链态（回前台由
        // foliaBackgroundThrottleChanged 的 foreground 事件清）。
        guard !backgroundThrottled else {
            Breadcrumbs.log("progressDriver62 start skipped=backgroundThrottle")
            return
        }
        reanchor()
        let link = CADisplayLink(target: LinkProxy(owner: self),
                                 selector: #selector(LinkProxy.step))
        // (62) WB §4.4：帧率限制消费（开关/档位键见
        // SettingsStore62B，StageVC 的 DisplayLink 归 WA 同键消费）。
        FoliaMotion62.applyFrameRate(to: link)
        link.add(to: .main, forMode: .common)
        displayLink = link
        installThrottleObserversIfNeeded()
    }

    // MARK: - (62) WB：静态模式 / 后台节流订阅

    private var backgroundThrottled = false
    private var throttleObserversInstalled = false

    private func installThrottleObserversIfNeeded() {
        guard !throttleObserversInstalled else { return }
        throttleObserversInstalled = true
        NotificationCenter.default.addObserver(
            forName: .foliaStaticModeChanged, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if SettingsStore.staticModeEnabled {
                    self.stop()
                    Breadcrumbs.log("progressDriver62 stopped=staticMode")
                }
            }
        NotificationCenter.default.addObserver(
            forName: .foliaBackgroundThrottleChanged, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if (note.userInfo?["state"] as? String) == "background-aggressive" {
                    self.backgroundThrottled = true
                    self.stop()
                    Breadcrumbs.log("progressDriver62 stopped=backgroundAggressive")
                } else {
                    self.backgroundThrottled = false
                }
            }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastFraction = -1
    }

    deinit { stop() }

    private func reanchor() {
        let engine = PlaybackEngine.shared
        anchorTime = engine.rawPlayhead()
        anchorWall = CACurrentMediaTime()
        anchorTrackId = engine.currentTrack?.id
        driftOverFrames = 0
    }

    fileprivate func stepFrame() {
        let engine = PlaybackEngine.shared
        guard let track = engine.currentTrack, engine.duration > 0 else { return }
        if track.id != anchorTrackId { reanchor() }
        let playing = engine.isPlaying
        let predicted = playing
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        // 漂移比对改 rawPlayhead 真值（3.7 (23)）：阈值 0.25s、
        // 连续 2 帧超限才重锚（seek 的大跳变两帧内即纠正，
        // 单帧抖动不误锚）；漂移重锚落一行面包屑供对账。
        let drift = engine.rawPlayhead() - predicted
        if abs(drift) > 0.25 {
            driftOverFrames += 1
            if driftOverFrames >= 2 {
                Breadcrumbs.log("stage progress anchor drift=\(String(format: "%.3f", drift)) raw=\(String(format: "%.3f", engine.rawPlayhead())) cacheDelta=\(String(format: "%.3f", engine.rawPlayhead() - engine.currentTime))")
                reanchor()
            }
        } else {
            driftOverFrames = 0
        }
        let now = playing
            ? anchorTime + (CACurrentMediaTime() - anchorWall)
            : anchorTime
        let fraction = min(max(now / engine.duration, 0), 1)
        if abs(fraction - lastFraction) > 0.0004 {
            lastFraction = fraction
            onFraction?(fraction)
        }
    }

    /// CADisplayLink 强持有 target：弱代理断环，driver 释放后
    /// 代理收不到回调，link 在 driver deinit 时失效。
    private final class LinkProxy: NSObject {
        weak var owner: StageProgressDriver?
        init(owner: StageProgressDriver) { self.owner = owner }
        @objc func step() { owner?.stepFrame() }
    }
}
