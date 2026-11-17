import Foundation
import WebKit

/// M1 阶段 2：登录 Cookie 同步（规格 v2.1 §2 + R2）。
///
/// 关键事实（实查 LocalServer.swift 文件头）：本壳的源就是
/// http://127.0.0.1:<port>——登录 Cookie 由上游 Set-Cookie 透传后按
/// 浏览器规则存在这个本地源上，WebView 发往 LocalServer 的请求自动
/// 带 Cookie、代理再原样带给上游。原生 URLSession 不共享
/// WKWebView 的 Cookie 罐，所以原生数据链必须自己同步：
/// 从 WKWebsiteDataStore.default()（WebView 用的就是 default store）
/// 读本地源 Cookie，手工拼 Cookie 头注入原生请求。
///
/// 规则（R2）：
/// - 观察器驱动：Cookie 变化即刷新壳侧副本，不靠固定时机猜。
/// - 拼头手工做：按 domain/path/过期逐个匹配，不依赖
///   HTTPCookie.requestHeaderFields(with:)（它按请求 URL 过滤，
///   本地源与平台域名的关系会让它漏拼）。
/// - HttpOnly Cookie 只注入原生请求头，绝不暴露给 Web 层/JS 桥。
final class CookieSync: NSObject, WKHTTPCookieStoreObserver {

    static let shared = CookieSync()

    private let store = WKWebsiteDataStore.default().httpCookieStore
    private let lock = NSLock()
    private var snapshot: [HTTPCookie] = []
    private var waiters: [() -> Void] = []
    private var started = false

    private override init() { super.init() }

    /// 启动观察（幂等）。在 App 启动与首次原生请求前调用。
    func start() {
        guard !started else { return }
        started = true
        store.add(self)
        refresh()
    }

    // MARK: - WKHTTPCookieStoreObserver

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        refresh()
    }

    // MARK: - 副本刷新

    /// 重新读取全部 Cookie 并替换副本；完成后回调（登录成功后的原生
    /// 重拉必须等这个回调再发，防读到未落库的旧 Cookie——R2）。
    func refresh(completion: (() -> Void)? = nil) {
        if let completion {
            lock.lock()
            waiters.append(completion)
            lock.unlock()
        }
        store.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let local = cookies.filter { Self.isLocalOriginCookie($0) }
            self.lock.lock()
            self.snapshot = local
            let pending = self.waiters
            self.waiters.removeAll()
            self.lock.unlock()
            for waiter in pending { waiter() }
        }
    }

    /// 是否为本地源（127.0.0.1 / localhost）的 Cookie。
    private static func isLocalOriginCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain == "127.0.0.1" || domain == "localhost"
            || domain.hasSuffix(".127.0.0.1") || domain.hasSuffix(".localhost")
    }

    // MARK: - 拼头

    /// 为发往 LocalServer 的请求路径拼 Cookie 头；无可用 Cookie 时 nil。
    /// 过期与 path 前缀按 RFC 规则逐个判定；Secure 标志的 Cookie 在
    /// 本地可信源上由 WebView 本就会发送，原生手工拼头同样包含
    /// （我们构造的是发往同一本地源的请求头，与浏览器行为一致）。
    func cookieHeader(for path: String) -> String? {
        let now = Date()
        lock.lock()
        let cookies = snapshot
        lock.unlock()
        var pairs: [String] = []
        for cookie in cookies {
            if let expires = cookie.expiresDate, expires <= now { continue }
            if !path.hasPrefix(cookie.path) { continue }
            pairs.append("\(cookie.name)=\(cookie.value)")
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    /// 副本里是否已有任一 Cookie（未登录粗判；精确登录态走
    /// NativeDataClient.fetchLoginStatus 的接口判定）。
    var hasAnyCookie: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !snapshot.isEmpty
    }
}
