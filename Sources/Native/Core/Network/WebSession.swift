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
/// (51) A 组口径变更：本类降为**一次性迁移源 + 异常兜底**。
/// 登录态权威数据源是 NativeSessionStore（Keychain）；迁移完成
/// （session.migrate.state=done）后启动不再读 WebView。本类保留
/// 结构化读取供 SessionMigrator 做三分判据（未登录/无效/读取
/// 失败），以及迁移未完成窗口期的旧法兜底读取。
/// 会话串是凭据：绝不写日志（只许 len/hash8，见 NativeSessionStore）。
enum WebSession {

    /// 结构化读取结果（DS 风险一三分判据）：
    /// - absent：两键皆不存在 = 未登录（可信判据，不迁移不切源）
    /// - value：键存在，原文待调用方校验（空串/半串归 invalid）
    /// - readFail：JS 异常/非预期返回/超时（reason: jsError|timeout）
    enum StructuredRead {
        case absent
        case value(String)
        case readFail(reason: String)
    }

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

    /// 结构化读取：一次 JS 往返同时区分「键不存在」与「键存在
    /// 但值为空/半串」，并带 3 秒超时（evaluateJavaScript 本身
    /// 无超时，页面未就绪时会悬挂——迁移判据里归 readFail/timeout，
    /// 与 invalid 同处理：不写不覆盖、下次启动重试）。
    static func readNeteaseCookieStructured(timeout: TimeInterval = 3) async -> StructuredRead {
        // 返回 JSON 串：{"p":true/false,"v":"..."}；p=false 表示
        // 两键皆不存在（getItem 皆 null）。键存在但为空串时
        // p=true、v=""，由调用方按 invalid 处理。
        let script = """
        (function(){
          var a = localStorage.getItem('online_provider:netease:cookie');
          var b = localStorage.getItem('netease_cookie');
          var v = (a !== null && a !== undefined) ? a : b;
          if (v === null || v === undefined) return JSON.stringify({p:false, v:""});
          return JSON.stringify({p:true, v:String(v)});
        })()
        """
        let box = await evaluateWithTimeout(script, timeout: timeout)
        guard let box else { return .readFail(reason: "timeout") }
        guard let text = box.value as? String else {
            // JS 回调已回但结果非 String = JS 异常/页面未就绪。
            return .readFail(reason: "jsError")
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let present = dict["p"] as? Bool else {
            return .readFail(reason: "jsError")
        }
        if !present { return .absent }
        return .value((dict["v"] as? String) ?? "")
    }

    /// 清除 Web 侧两键（退出登录/会话失效时与原生存储同步清，
    /// 防兜底回读把已清会话复活）。尽力而为，失败静默。
    static func clearNeteaseCookie() async {
        let script = "localStorage.removeItem('online_provider:netease:cookie');"
            + "localStorage.removeItem('netease_cookie'); true"
        _ = await evaluateWithTimeout(script, timeout: 3)
    }

    // MARK: - 带超时的 evaluateJavaScript

    private final class ResumeGuard {
        private let lock = NSLock()
        private var resumed = false
        private var continuation: CheckedContinuation<EvalBox?, Never>?
        init(_ continuation: CheckedContinuation<EvalBox?, Never>) {
            self.continuation = continuation
        }
        func resume(_ value: EvalBox?) {
            lock.lock()
            guard !resumed else { lock.unlock(); return }
            resumed = true
            let target = continuation
            continuation = nil
            lock.unlock()
            target?.resume(returning: value)
        }
    }

    /// JS 求值结果包：超时返回 nil 本身，JS 回调（哪怕结果为
    /// nil/异常）返回非 nil 的包，供上层区分 timeout 与 jsError。
    private final class EvalBox {
        let value: Any?
        init(_ value: Any?) { self.value = value }
    }

    /// 返回 nil = 超时未回；返回非 nil EvalBox = JS 回调已回
    /// （value 可能为 nil，表示 JS 异常/结果为空）。
    private static func evaluateWithTimeout(_ script: String,
                                            timeout: TimeInterval) async -> EvalBox? {
        await withCheckedContinuation { continuation in
            let guardBox = ResumeGuard(continuation)
            DispatchQueue.main.async {
                WebEffectBridge.shared.webView.evaluateJavaScript(script) { result, _ in
                    guardBox.resume(EvalBox(result))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guardBox.resume(nil)
            }
        }
    }
}
