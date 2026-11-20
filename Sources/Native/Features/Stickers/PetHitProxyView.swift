import UIKit

// 岛层命中代理（3.7 (53) 工作流 G，DS 终审路线 c 的触摸半）：
// 宠物根层已改作 window.layer 直属 CALayer（见 PetIslandLayer
// 文件头 (53) G），CALayer 不进 hitTest 链、宠物视图本体也不
// 进任何窗口视图树——点按必须另有入口。本视图是岛层在窗口
// 里的唯一子视图，职责只有一件：把落在宠物本体/气泡上的点
// 按转发给岛层，其余一律穿透。
//
// 穿透论证：
// - frame 只覆盖屏幕顶部固定带（seat 区 + 气泡区，高见
//   PetIslandLayer 的 proxyZoneHeight），带外触摸根本不进
//   本视图的 hitTest。
// - point(inside:) 不吃整带：逐个目标矩形（岛层实时给出的
//   在座宠物 frame + 当前气泡 frame）判定，带内空白照样
//   返回 false，不许用 union/整带默认判定吃空白。
// - hitTest 只有命中目标才返回 self；手势识别器只在本视图
//   被 hitTest 认领后才有机会触发，空白触摸直接落到下方
//   呈现内容（舞台/网页照常可点）。
// - 岛上无宠物时岛层把本视图 isHidden + 关 interaction，
//   hitTest 链整体跳过（转场/空岛期间 proxy 停用）。
// - 坐标不变量：本视图 frame 原点恒 (0,0)，本地坐标 == 窗
//   口坐标 == 岛层 hitTargets 的矩形坐标系（petRootLayer
//   frame = window.bounds、原点同为 (0,0)）。
final class PetHitProxyView: UIView {

    weak var islandLayer: PetIslandLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // 单击/双击与旧 IslandPetView 手势同构（单击须等双击
        // 落空，旧口径即如此，延迟手感不变）。
        let single = UITapGestureRecognizer(
            target: self, action: #selector(handleSingleTap(_:)))
        addGestureRecognizer(single)
        let double = UITapGestureRecognizer(
            target: self, action: #selector(handleDoubleTap(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        single.require(toFail: double)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// 逐目标判定（DS 硬要求）：只有宠物本体/气泡矩形算命
    /// 中，带内其余空白一律 false 穿透。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let islandLayer else { return false }
        return islandLayer.hitTargets().contains { $0.rect.contains(point) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        return point(inside: point, with: event) ? self : nil
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        forwardTap(recognizer, doubleTap: false)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        forwardTap(recognizer, doubleTap: true)
    }

    private func forwardTap(_ recognizer: UITapGestureRecognizer,
                            doubleTap: Bool) {
        guard let islandLayer else { return }
        let point = recognizer.location(in: self)
        // 逆序查：后入列的气泡绘制在最上（与岛层 addSubview
        // 序一致），重叠时以气泡属主优先。
        guard let target = islandLayer.hitTargets().reversed()
            .first(where: { $0.rect.contains(point) }) else { return }
        islandLayer.proxyTapped(asset: target.asset, doubleTap: doubleTap)
    }
}
