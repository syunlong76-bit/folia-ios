import Foundation
import WebKit

/// M1 阶段 4 修复（3.7 (5)）：原生侧读取 Web 的登录会话。
///
/// 真机实证的机制纠正（2026-11-18，3.7 (4) 验收）：Folia 的网易云
/// 登录态**不在浏览器 Cookie 罐里**。Web 侧 netease.ts 的做法是：
/// 扫码确认时把整串会话 Cookie 存进 localStorage
/// （providerStorage.ts：键 `online_provider:netease:cookie`，
/// 旧键 `netease_cookie`），之后每个请求把会话以 URL 查询参数
/// `cookie=<整串>` 附在请求上发给后端。阶段 2 的 CookieSync 只同步
/// WKWebView 的 Cookie 罐，罐里没有 MUSIC_U——原生请求全程匿名，
/// /login/status 自然无 profile，主页墙误判「未登录」。
///
/// 本类做的就是 Web 同一件事：从 App 的 WKWebView 页面上下文读
/// localStorage 里的会话串，交给 NativeDataClient 拼 `cookie` 参数。
/// 会话串是凭据：只在原生层内存中短暂缓存、只发往 LocalServer
/// 本地源，绝不写日志、绝不回暴露给 JS。
enum WebSession {

    /// 在 WebView 页面上下文读网易云会话串（主线程 evaluateJavaScript）。
    /// 页面未加载/未登录时返回 nil。
    static func readNeteaseCookie() async -> String? {
        let script = "(localStorage.getItem('online_provider:netease:cookie')"
            + " || localStorage.getItem('netease_cookie'))"
        let raw: Any? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WebEffectBridge.shared.webView.evaluateJavaScript(script) { result, _ in
                    continuation.resume(returning: result)
                }
            }
        }
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
