import AVFoundation
import UIKit

// (97) 第 9 条：梵高烟花视频层——替换现原生粒子烟花的视觉。
// 素材＝过审样板 v4 的 4K 规格版（Resources/FxMedia/
// vangogh-fireworks.mp4）：前 1.2s 程序金色火花发射轨迹，
// 之后从原片 4.6s 接入点火→转绿→绽放→巅峰，纯黑底抠像。
// 播放走 AVPlayerLayer＋compositingFilter=screenBlendMode
// （黑＝透明的滤色叠加，沿样板口径：特效只是叠加层、墙面
// 背景保持原样不压暗）。App 内按 drawable 原生分辨率渲染
// （videoGravity=resizeAspectFill、不降清不封顶）。
// 行为面对齐旧烟花：开启即起播、开启期间循环重播、点按
// ＝从头发射一发、关闭即停播隐藏；点火时刻（起播＋1.2s）
// 回调引擎走既有 onFwBurst91 联动（封面提亮＋宠物欢呼）。

final class VangoghFwView97: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer97: AVPlayerLayer { layer as! AVPlayerLayer }

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var ignitionWork: DispatchWorkItem?
    private(set) var isRunning97 = false

    /// 点火时刻回调（主线程）。
    var onIgnition97: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        playerLayer97.videoGravity = .resizeAspectFill
        // 滤色叠加：纯黑底在 screen 混合下等价透明。
        playerLayer97.compositingFilter = "screenBlendMode"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 起播。素材缺失返回 false（引擎据此回落原生粒子烟花）。
    func start97() -> Bool {
        if player == nil {
            guard let url = Bundle.main.url(
                forResource: "vangogh-fireworks", withExtension: "mp4",
                subdirectory: "FxMedia") else {
                Breadcrumbs.log("p97 vgfw miss")
                return false
            }
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            p.isMuted = true
            p.actionAtItemEnd = .pause
            player = p
            playerLayer97.player = p
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item, queue: .main) { [weak self] _ in
                    guard let self, self.isRunning97 else { return }
                    self.replay97()
                }
            let dur = item.asset.duration.seconds
            Breadcrumbs.log("p97 vgfw dur=\(String(format: "%.2f", dur))")
        }
        isRunning97 = true
        isHidden = false
        replay97()
        return true
    }

    private func replay97() {
        guard let player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        scheduleIgnition97()
    }

    /// 点按补发：从头发射（对齐旧点按 launch 的语义）。
    func restart97() {
        guard isRunning97 else { return }
        replay97()
        Breadcrumbs.log("p97 vgfw tap")
    }

    func stop97() {
        isRunning97 = false
        ignitionWork?.cancel()
        ignitionWork = nil
        player?.pause()
        isHidden = true
    }

    /// 点火在起播后 1.2s（发射段恰走完、原片段接入点）。
    private func scheduleIgnition97() {
        ignitionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning97 else { return }
            self.onIgnition97?()
        }
        ignitionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
