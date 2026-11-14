import UIKit
import WebKit

/// 手势穿透路由框架（M2 末落地，M3 才接区域）。
///
/// 默认 `passthroughRects` 为空：不开任何区域，行为与普通 WKWebView 完全一致。
/// 区域注册表由 M3 的原生特效按需声明（粒子捏合 / 唱片墙 / 视差），一律以本框架为前置。
/// 命中穿透区的触摸返回 nil，落到下层视图；其余触摸走默认 hitTest。
final class PassthroughWebView: WKWebView {
    /// 穿透区（本视图坐标系）。
    var passthroughRects: [CGRect] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for rect in passthroughRects where rect.contains(point) {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}
