import UIKit

// 宠物全屏停靠层（3.7 (43) 路4）：长按拖动落点全屏化的视图
// 宿主。审计 folia43 路4 定案：停靠落点此前被夹回迷你台宠
// 物层（恒高 246、钉在台框上）的 bounds——演员是台层直接
// 子视图，祖先链命中测试与台层显隐/位移决定了「只改夹取
// 范围」救不了，必须换宿主。本层只做一件事：当窗口级透
// 明层，收纳「拖放落定瞬间迁入」的停靠演员视图，坐标 =
// 窗口坐标。归属/登记/过期/告别过滤全由属主 MiniBarPetStage
// 的 tick 驱动（演员仍留在原 stage 的班底数组里），本层
// 不持有任何宠物状态机。
//
// 不复用 PetIslandLayer：岛层带落座/居民/停聊语义且刚经
// (39)/(41) 两轮定案，混入停靠会污染其 tick 与 hitTest；
// 但 install/置顶守护模式照抄岛层——同为**主窗本体的直接
// 子视图**（不新建独立 UIWindow，不碰 (39) 冻案红线）。
// z-order：岛层 > 停靠层 > 一切呈现内容——本层守护把自己
// 维持在岛层正下方（insertSubview belowSubview: island）；
// 岛层不在场时退化为置顶。两层 hitTest 均只认领自家宠物
// 本体、其余穿透，岛层在上不影响停靠宠物点击（岛层不认
// 领即穿透到本层）。横屏时在场停靠者按新窗口 bounds 重新
// 夹取一次，防旋出屏外。

final class PetDockLayer: UIView {

    static let shared = PetDockLayer()

    /// 宿主主窗（与岛层同口径）：本层是它的直接子视图；
    /// scene 重连换新窗时 install 重新挂载。
    private weak var hostWindow: UIWindow?
    /// 置顶守护：0.5s 一拍核对本层是否仍在岛层正下方（或
    /// 无岛层时置顶），不是则归位并落 dock.refront。
    private var refrontTimer: Timer?

    private init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: 安装（SceneDelegate 建窗后、岛层 install 之后一行）

    static func install(in windowScene: UIWindowScene) {
        let layer = PetDockLayer.shared
        let hostWindow = (windowScene.delegate as? SceneDelegate)?.window
            ?? windowScene.windows.first(where: { $0.isKeyWindow })
            ?? windowScene.windows.first
        guard let window = hostWindow else {
            Breadcrumbs.log("dock.install skipped=no-host")
            return
        }
        if layer.superview !== window {
            layer.removeFromSuperview()
            layer.frame = window.bounds
            layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(layer)
            layer.hostWindow = window
            layer.refrontIfNeeded(logged: false)
            Breadcrumbs.log("dock.install host=window docked=\(layer.subviews.count)")
        }
        layer.startRefrontGuard()
    }

    // MARK: 置顶守护（岛层同款，锚点 = 岛层正下方）

    private func startRefrontGuard() {
        guard refrontTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refrontIfNeeded(logged: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        refrontTimer = timer
    }

    /// 即时归位（事件驱动入口：演员迁入时调用）。
    func refrontIfNeeded() {
        refrontIfNeeded(logged: false)
    }

    private func refrontIfNeeded(logged: Bool) {
        guard let window = hostWindow, superview === window else { return }
        let island = PetIslandLayer.shared
        if island.superview === window {
            // 目标位：岛层正下方。已在位（岛层恰在本层之上）不动。
            let subs = window.subviews
            if let myIdx = subs.firstIndex(of: self),
               let islandIdx = subs.firstIndex(of: island),
               islandIdx == myIdx + 1 {
                return
            }
            window.insertSubview(self, belowSubview: island)
        } else {
            guard window.subviews.last !== self else { return }
            window.bringSubviewToFront(self)
        }
        if logged { Breadcrumbs.log("dock.refront") }
    }

    // MARK: 触摸穿透（只认领停靠宠物本体）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01 else { return nil }
        for sub in subviews.reversed() {
            guard !sub.isHidden, sub.isUserInteractionEnabled else { continue }
            let converted = sub.convert(point, from: self)
            if let hit = sub.hitTest(converted, with: event) { return hit }
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 横竖屏切换后把在场停靠者夹回窗口 bounds（半身
        // inset），防落点旋出屏外够不到。
        for sub in subviews {
            let half = sub.bounds.width / 2
            let cx = min(max(sub.center.x, half), max(half, bounds.width - half))
            let cy = min(max(sub.center.y, half), max(half, bounds.height - half))
            if sub.center != CGPoint(x: cx, y: cy) {
                sub.center = CGPoint(x: cx, y: cy)
            }
        }
    }
}
