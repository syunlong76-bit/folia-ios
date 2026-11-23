import UIKit

/// 迷你台台身视图（3.7 (21.1)）：收起态（16pt 细进度条）时
/// 把纵向命中带扩到 44pt（上下各外扩 14pt），视觉帧与布局
/// 不变；展开态 hitExpansionY 为 0，命中行为与 UIView 原样
/// 一致。扩展只改 point(inside:) 的判定范围：带内的点仍按
/// 原子视图层级分发——收起态子视图都不在扩展带内（seek 命
/// 中层贴底 20pt 带除外，其点按分发在收起态同样走展开），
/// 最终落到台身点按手势，与点细条本体同路（expandMiniBar）。
final class MiniBarHitView: UIView {

    /// 纵向单侧外扩量（pt）；0 = 不扩展（展开态恒 0）。
    var hitExpansionY: CGFloat = 0

    /// (75) 第 5 项②「点按到达」前置自证钩子：hitTest 真拿
    /// 到触摸（返回非 nil）时回调——宿主据此落 minibar
    /// .touch75，与识别器触发行（minibar.hit）对位：无
    /// touch75＝点按没进门（上层吞掉）；有 touch75 无 hit
    /// ＝死在识别器/守卫环（各死点另有 minibar.dead75）。
    var onHitLanded: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil { onHitLanded?() }
        return hit
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard hitExpansionY > 0 else {
            return super.point(inside: point, with: event)
        }
        return bounds.insetBy(dx: 0, dy: -hitExpansionY).contains(point)
    }
}
