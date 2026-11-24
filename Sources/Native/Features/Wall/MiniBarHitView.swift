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
    /// (86) 第 9 条：静止点兜底派发（宿主接 expandMiniBar
    /// 同路）——触摸正常结束、无任何台身识别器认领、且
    /// 序列为静止短点时由 touchesEnded 直接派发（见彼处
    /// 定案注）。与取消救援并列、互不覆盖（cancel 走救
    /// 援、end 走本路）。
    var onStationaryTap86: (() -> Void)?
    private var downTime: CFTimeInterval = 0
    private var downLocation: CGPoint = .zero
    private var maxDeviation: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>,
                               with event: UIEvent?) {
        // (78) 第 8 条交付链见证（无条件）：(77) 日志定案
        // 派发段整段静默时，本视图 touchesBegan/Ended/
        // Cancelled 三路全无声——连 Ended/Cancelled 里的无
        // 条件回调（onDispatchUnclaimed/onDispatchCancelled）
        // 都没响，证明触摸序列根本没交付到本视图。本版三
        // 相位恒落 mb.tch78，与根级认领链（mb.claim78）对
        // 位：根链响而 tch78 不响＝分支吞触摸坐实；都响＝
        // 交付已通、问题在更下游。
        Breadcrumbs.log("mb.tch78 b host=\(crumbHostTag)"
            + " col=\(isCollapsedForm ? 1 : 0)")
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
        Breadcrumbs.log("mb.tch78 e host=\(crumbHostTag)"
            + " col=\(isCollapsedForm ? 1 : 0)")
        if isCollapsedForm { RouteInteractionHold.shared.end() }
        // (86) 第 9 条：tap86 原始点按落痕（宿主＋台内坐标
        // ＋结局）＋静止点兜底。(85) 日志窗内 ≥6 组收起态
        // 点按终止于 dead76 noRecog——结构性断点：台身点
        // 按识别器挂在 deckSurface 叶子层，触摸命中轨/钮
        // 等其他子视图时不经其子树、永不被喂；本视图是台
        // 身全体子视图的共同祖先、touchesEnded 恒达，故
        // 兜底落在此处。结局口径：claimed＝识别器已认领
        // （本路不动）；stat86＝静止短点未认领、本路兜底
        // 派发展开；moved/long＝非点按语义、只落痕。阈值
        // <0.5s：覆盖日志实测 461ms 一笔，又与台身 0.55s
        // 长按切主题留 50ms 余量、不抢长按。兜底派发后
        // 不再走 unclaimed（序列已被本路认领、dead76 不
        // 许再误报）。
        var claimedByFallback86 = false
        if isCollapsedForm, downTime > 0 {
            let duration = CACurrentMediaTime() - downTime
            let out: String
            if sequenceClaimed {
                out = "claimed"
            } else if duration < 0.5, maxDeviation < 10 {
                out = "stat86"
            } else if maxDeviation >= 10 {
                out = "moved"
            } else {
                out = "long"
            }
            Breadcrumbs.log("tap86 host=\(crumbHostTag)"
                + " col=1 x=\(Int(downLocation.x)) y=\(Int(downLocation.y))"
                + " out=\(out)")
            if out == "stat86" {
                claimedByFallback86 = true
                onStationaryTap86?()
            }
        }
        if !sequenceClaimed, !claimedByFallback86 { onDispatchUnclaimed?() }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>,
                                   with event: UIEvent?) {
        Breadcrumbs.log("mb.tch78 c host=\(crumbHostTag)"
            + " col=\(isCollapsedForm ? 1 : 0)")
        if isCollapsedForm {
            RouteInteractionHold.shared.end()
            onDispatchCancelled?()
            // (86) 第 9 条：取消结局同落 tap86（与 end 路对位）。
            if downTime > 0 {
                Breadcrumbs.log("tap86 host=\(crumbHostTag)"
                    + " col=1 x=\(Int(downLocation.x)) y=\(Int(downLocation.y))"
                    + " out=cancel")
            }
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

/// (78) 第 8 条：播放条根级认领（(77)⑥未达验收的续案重做）。
///
/// (77) 会话日志定案：细条点按 3 次全数到达 hitTest 层
/// （minibar.touch75 在场），但台身视图的 touches 全相位与
/// 全部台身识别器整段零发声——触摸序列在「到达」与「认领」
/// 之间丢失，(77) 挂在台身派发段上的三件修法（认领 hold、
/// 取消救援、路由退避）随之全灭。本版把认领搬到宿主根视
/// 图：根视图识别器俯瞰全部分支（台身/宠物台/浮层谁吞了
/// 触摸都拦不住它），无 require 链、无 delegate 门、
/// cancelsTouchesInView=false 不扰动原交付；命中判定全走
/// 几何（收起态＋落点在细条命中带内＋宠物台未认领该点），
/// 命中即落 mb.claim78→mb.disp78 并直接派发宿主展开——
/// 展开不再依赖任何会被 cancel 的台身识别器链。自证链第
/// 三环仍是既有 minibar expand。
final class MiniBarRootTap78: NSObject {

    private weak var bar: MiniBarHitView?
    private weak var petStage: MiniBarPetStage?
    private let hostTag: String
    private let isCollapsed: () -> Bool
    private let expand: () -> Void
    private(set) var recognizer: UITapGestureRecognizer!

    init(hostView: UIView, bar: MiniBarHitView,
         petStage: MiniBarPetStage?, hostTag: String,
         isCollapsed: @escaping () -> Bool,
         expand: @escaping () -> Void) {
        self.bar = bar
        self.petStage = petStage
        self.hostTag = hostTag
        self.isCollapsed = isCollapsed
        self.expand = expand
        super.init()
        let recognizer = UITapGestureRecognizer(
            target: self, action: #selector(handleTap))
        recognizer.cancelsTouchesInView = false
        hostView.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
        // (79) 第 13 条在场自证：(78)/(79) 两窗自证链全 0 时
        // 先分清「没装上」与「装上没响」——装配即落痕。
        Breadcrumbs.log("mb.root79 on host=\(hostTag)")
    }

    @objc private func handleTap() {
        guard let bar, !bar.isHidden else { return }
        // (79) 第 13 条让行落痕：落点在细条带内却没认领时
        // 不再静默——形态/宠物让行各落一行（带外点按不落，
        // 防全屏点按刷屏）。
        let hostPoint = recognizer.location(in: recognizer.view)
        let bandInHost = bar.convert(
            bar.bounds.insetBy(dx: 0, dy: -bar.hitExpansionY),
            to: recognizer.view)
        let inBand = bandInHost.contains(hostPoint)
        guard isCollapsed() else {
            if inBand {
                Breadcrumbs.log("mb.root79 bail=form host=\(hostTag)")
            }
            return
        }
        let point = recognizer.location(in: bar)
        // 命中带与台身 point(inside:) 同口径（视觉帧纵向外
        // 扩 hitExpansionY，收起态 44pt 带）。
        // (86) 第 9 条：本守卫旧为静默 return——(85) 判读
        // 分不开「没触发」与「静默退出」，tap86 各出口补
        // 落痕（band/pet/claim，坐标为台内坐标）。
        guard bar.bounds.insetBy(dx: 0, dy: -bar.hitExpansionY)
            .contains(point) else {
            Breadcrumbs.log("tap86 host=\(hostTag)"
                + " col=1 x=\(Int(point.x)) y=\(Int(point.y))"
                + " out=band")
            return
        }
        // 宠物本体/对话框/气泡认领优先：落点在宠物面上归宠
        // 物分支，本路不抢（宠物点按语义不变）。
        if let petStage,
           petStage.claimsPoint(recognizer.location(in: petStage)) {
            Breadcrumbs.log("mb.root79 bail=pet host=\(hostTag)")
            Breadcrumbs.log("tap86 host=\(hostTag)"
                + " col=1 x=\(Int(point.x)) y=\(Int(point.y))"
                + " out=pet")
            return
        }
        Breadcrumbs.log("tap86 host=\(hostTag)"
            + " col=1 x=\(Int(point.x)) y=\(Int(point.y))"
            + " out=claim")
        Breadcrumbs.log("mb.claim78 host=\(hostTag)")
        Breadcrumbs.log("mb.disp78 host=\(hostTag) via=root")
        expand()
    }
}
