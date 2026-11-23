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

    /// (76) ⑤派发段见证（(75) 会话日志判读改靶）：(75) 实
    /// 证出现「到达环全登记、expand 与三守卫死点双零」——
    /// 死点不在守卫环、而在到达之后、识别器认领之前的派
    /// 发段（守卫全在识别器回调里，回调没触发就永远静
    /// 默）。本视图补两路见证：触摸序列被取消
    /// （onDispatchCancelled）、触摸正常结束却无任何台身
    /// 识别器认领（onDispatchUnclaimed）。认领旗由宿主在
    /// 任一台身识别器回调入口调 noteRecognizerClaimed()
    /// 置位。本类只发信号、分环落痕在宿主；其他宿主不接
    /// 线即无行为变化。
    var onDispatchCancelled: (() -> Void)?
    var onDispatchUnclaimed: (() -> Void)?
    private var sequenceClaimed = false

    func noteRecognizerClaimed() { sequenceClaimed = true }

    // MARK: - (77) ⑥触摸认领与取消救援（(76) 日志定案）
    //
    // (76) 会话日志实证：歌单页 2 次点按全死于 at=cancel——
    // nowplaying.route 的呈现在飞时把细条触摸取消（与 route
    // settle 同毫秒相撞）。本版双保险：①认领先行——收起态
    // 触摸一落台身即置 RouteInteractionHold，route 的呈现
    // 步骤见 hold 必让行（SceneDelegate.routeStep 咨询点），
    // 路由 churn 不许再取消在飞的条触摸；②取消救援——呈现
    // 已在飞、触摸仍被取消时，若序列是静止短点（<0.35s、
    // 位移 <10pt、无识别器认领），按点按意图直接派发展开，
    // 不让用户白点。滚动起手位移大、天然出局。

    /// 面包屑宿主名（wallproto/homewall/stage，宿主装配时写）。
    var crumbHostTag = ""
    /// 当前是否收起形态（宿主 setMiniBarForm 同步）。
    var isCollapsedForm = false
    /// 取消救援派发（宿主接 expandMiniBar 同路）。
    var onCancelledTapRescue: (() -> Void)?
    private var downTime: CFTimeInterval = 0
    private var downLocation: CGPoint = .zero
    private var maxDeviation: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>,
                               with event: UIEvent?) {
        sequenceClaimed = false
        if isCollapsedForm {
            downTime = CACurrentMediaTime()
            downLocation = touches.first?.location(in: self) ?? .zero
            maxDeviation = 0
            RouteInteractionHold.shared.begin()
            Breadcrumbs.log("minibar.claim77 host=\(crumbHostTag)")
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>,
                               with event: UIEvent?) {
        if isCollapsedForm, downTime > 0, let touch = touches.first {
            let now = touch.location(in: self)
            maxDeviation = max(maxDeviation,
                               hypot(now.x - downLocation.x,
                                     now.y - downLocation.y))
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>,
                               with event: UIEvent?) {
        if isCollapsedForm { RouteInteractionHold.shared.end() }
        if !sequenceClaimed { onDispatchUnclaimed?() }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>,
                                   with event: UIEvent?) {
        if isCollapsedForm {
            RouteInteractionHold.shared.end()
            onDispatchCancelled?()
            let stationary = CACurrentMediaTime() - downTime < 0.35
                && maxDeviation < 10
            if stationary, !sequenceClaimed {
                Breadcrumbs.log("minibar.claim77 host=\(crumbHostTag)"
                    + " via=rescue")
                onCancelledTapRescue?()
            }
        } else {
            onDispatchCancelled?()
        }
        super.touchesCancelled(touches, with: event)
    }

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
