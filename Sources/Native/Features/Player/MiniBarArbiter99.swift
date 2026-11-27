import UIKit

/// (99) 第 3 条：迷你台全局单实例可见性仲裁。
///
/// home（主页墙）/ wallproto（歌单墙）/ stage（舞台）三宿
/// 主各持一份 minibar 实例，旧制无可见性对账：非当前宿主
/// 的台（尤其 h=16 收起条）在转场与半透明覆盖下仍同屏渲
/// 染——(98) 真机日志三宿主 fm86 同一毫秒齐发，Miller 截
/// 图屏底出现第二条进度条、横屏出现重影。
///
/// 口径：任一时刻只许最后 claim 的宿主台可见，其余整台隐
/// 藏。claim 发生在各宿主 viewDidAppear；形态收口（各宿
/// 主 setMiniBarForm / setStageBarForm 尾）调 enforce 复断
/// 言，防止其他路径把被仲裁隐藏的台重新亮出。仲裁只隐藏
/// 自己隐藏过的台：宿主自有显隐（如舞台 hideBottomBar 设
/// 置）不在仲裁的恢复名单内，互不打架。
///
/// 自证：每次仲裁状态真变化落一行 p99 deck vis（act=当前
/// 可见宿主、hid=被仲裁隐藏的宿主清单）。
final class MiniBarArbiter99 {
    static let shared = MiniBarArbiter99()

    private final class WeakBar {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    private var bars: [String: WeakBar] = [:]
    private var hiddenByArbiter: Set<String> = []
    private(set) var activeHost: String?

    private init() {}

    /// 宿主露面时认领：登记本台并成为唯一可见宿主。
    func claim(host: String, bar: UIView?) {
        if let bar { bars[host] = WeakBar(bar) }
        activeHost = host
        apply()
    }

    /// 形态收口后复断言（状态未变不落痕、不动视图）。
    func enforce() { apply() }

    private func apply() {
        var changed = false
        for (host, box) in bars {
            guard let view = box.view else { continue }
            if host == activeHost {
                // 只恢复仲裁自己隐藏过的台；宿主自有隐藏
                // （设置/状态）不代为点亮。
                if hiddenByArbiter.contains(host), view.isHidden {
                    view.isHidden = false
                    hiddenByArbiter.remove(host)
                    changed = true
                }
            } else {
                if !view.isHidden {
                    view.isHidden = true
                    hiddenByArbiter.insert(host)
                    changed = true
                }
            }
        }
        if changed {
            let hid = hiddenByArbiter.sorted().joined(separator: ",")
            Breadcrumbs.log("p99 deck vis act=\(activeHost ?? "-")"
                + " hid=\(hid.isEmpty ? "-" : hid)")
        }
    }
}
