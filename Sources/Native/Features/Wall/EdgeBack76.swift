import UIKit

private var edgeBack76AssocKey: UInt8 = 0

/// (76) ④左缘滑动返回（Miller 21:48 点名）：呈现页统一的
/// 系统式左缘返回——UIScreenEdgePanGestureRecognizer 只
/// 认最左缘（系统识别器固有 ~20pt 起手带）＋
/// UIPercentDrivenInteractiveTransition 驱动本页既有
/// dismiss 转场（动画器仍走系统默认/页面既有口径，本类
/// 只供交互控制器、不供动画器），跟随手指、过阈值或快
/// 甩完成、否则取消回弹，跟随系统 present/dismiss 节奏
/// 与弹簧。关闭落点由宿主以 onDismiss 注入（各页自己的
/// 关闭契约：歌单页 closeTapped 的背板契约、舞台
/// closeStage 的闸门登记），本类不绕行、不自造 dismiss。
///
/// 冲突纪律（逐项核查见 (76) 报告④）：
/// - 墙面横向平移（滚动视图 pan）：宿主把滚动 pan 以
///   require(toFail: 本识别器）接线，左缘起手先判返回、
///   非左缘起手滚动照旧。
/// - 点按类（细条/工具条/顶栏）：离散手势与 pan 天然互
///   斥（无位移不触发 pan），但宿主以 shouldBeginAt 排
///   除点播台条带区域起手，防「从细条左端起手横拖 seek」
///   被返回偷走。
/// - 宠物拖拽：舞台宠物在点播台条带内（同上排除）；岛
///   上宠物命中代理是窗口层、触摸不达本页视图，无冲突。
/// - 本页既有 tap/longpress 链：pan 与 tap 不共存于同
///   一触摸序列（位移起 pan、无位移落 tap），不接线。
final class EdgeBack76: NSObject, UIViewControllerTransitioningDelegate,
    UIGestureRecognizerDelegate {

    private weak var host: UIViewController?
    private let interaction = UIPercentDrivenInteractiveTransition()
    private var interacting = false
    private let shouldBeginAt: (CGPoint) -> Bool
    private let onDismiss: () -> Void
    private(set) var pan: UIScreenEdgePanGestureRecognizer?

    private init(host: UIViewController,
                 shouldBeginAt: @escaping (CGPoint) -> Bool,
                 onDismiss: @escaping () -> Void) {
        self.host = host
        self.shouldBeginAt = shouldBeginAt
        self.onDismiss = onDismiss
        super.init()
    }

    @discardableResult
    static func install(
        on host: UIViewController,
        shouldBeginAt: @escaping (CGPoint) -> Bool = { _ in true },
        onDismiss: @escaping () -> Void
    ) -> EdgeBack76 {
        let back = EdgeBack76(host: host, shouldBeginAt: shouldBeginAt,
                              onDismiss: onDismiss)
        let pan = UIScreenEdgePanGestureRecognizer(
            target: back, action: #selector(EdgeBack76.handle(_:)))
        pan.edges = .left
        pan.delegate = back
        host.view.addGestureRecognizer(pan)
        back.pan = pan
        host.transitioningDelegate = back
        objc_setAssociatedObject(host, &edgeBack76AssocKey, back,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Breadcrumbs.log("edge.back76 install"
            + " host=\(String(describing: type(of: host)))")
        return back
    }

    // MARK: 转场委托（只供交互控制器，动画器恒 nil＝系统默认）

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        interacting ? interaction : nil
    }

    // MARK: 起手门（未被呈现/落在宿主排除带不起手）

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let host, host.presentingViewController != nil else {
            return false
        }
        return shouldBeginAt(gestureRecognizer.location(in: host.view))
    }

    // MARK: 驱动

    @objc private func handle(_ g: UIScreenEdgePanGestureRecognizer) {
        guard let host, let view = host.view else { return }
        let progress = min(max(g.translation(in: view).x
                               / max(view.bounds.width, 1), 0), 1)
        switch g.state {
        case .began:
            interacting = true
            Breadcrumbs.log("edge.back76 begin")
            onDismiss()
            // 关闭契约未放行（舞台闸门 veto/背板契约）时
            // dismiss 没启动：交互作废，不留悬空控制器。
            if !host.isBeingDismissed {
                interacting = false
                Breadcrumbs.log("edge.back76 veto")
            }
        case .changed:
            if interacting, host.isBeingDismissed {
                interaction.update(progress)
            }
        case .ended, .cancelled:
            if interacting, host.isBeingDismissed {
                if progress > 0.35 || g.velocity(in: view).x > 550 {
                    interaction.finish()
                    Breadcrumbs.log("edge.back76 fin"
                        + " p=\(Int(progress * 100))")
                } else {
                    interaction.cancel()
                    Breadcrumbs.log("edge.back76 can"
                        + " p=\(Int(progress * 100))")
                }
            }
            interacting = false
        default:
            break
        }
    }
}

/// (101) 第 3 项：全局右滑退出补齐装配口——复用 EdgeBack76
/// 机制（左缘 pan + 百分比驱动 dismiss，阈值/冲突纪律同
/// (76) 定版），仅加装配面包屑供真机日志逐页验路径。各
/// 页 onDismiss 仍走该页自己的关闭契约。
enum EdgeBack101 {

    @discardableResult
    static func install(
        on host: UIViewController,
        page: String,
        shouldBeginAt: @escaping (CGPoint) -> Bool = { _ in true },
        onDismiss: @escaping () -> Void
    ) -> EdgeBack76 {
        Breadcrumbs.log("p101 edgeback install page=\(page)")
        return EdgeBack76.install(on: host,
                                  shouldBeginAt: shouldBeginAt,
                                  onDismiss: onDismiss)
    }
}
