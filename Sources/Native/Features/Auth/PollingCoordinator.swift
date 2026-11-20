import Foundation

/// (53) B 组：三家扫码共用的轮询协调器（DS 定案 4）。
///
/// 纪律：
/// - 同一时刻只允许一个活跃扫码会话：begin() 先取消上一轮；
/// - 切换 provider、离开页面、退后台都必须 cancelActive()；
/// - 每轮 begin() 发一个 generation token，旧轮询的异步回调
///   在落存前必须 isCurrent(_:) 校验 token，防旧回调串写
///   另一个 provider 的会话。
/// per-provider 的间隔/超时/终止码由各 strategy（登录页内
/// 各家的轮询闭包）自带，协调器只管生命周期与代次。
final class PollingCoordinator {

    static let shared = PollingCoordinator()

    private let lock = NSLock()
    private var currentTask: Task<Void, Never>?
    private var generation = 0
    private var activeProvider: NativeSessionStore.Provider?

    private init() {}

    /// 开始新一轮轮询：取消上一轮并返回本轮 generation token。
    @discardableResult
    func begin(provider: NativeSessionStore.Provider) -> Int {
        lock.lock()
        generation += 1
        let gen = generation
        let old = currentTask
        currentTask = nil
        activeProvider = provider
        lock.unlock()
        old?.cancel()
        return gen
    }

    /// 挂上本轮的轮询任务（代次已过期则直接取消，不挂）。
    func attach(_ task: Task<Void, Never>, generation gen: Int) {
        lock.lock()
        if gen == generation {
            currentTask = task
            lock.unlock()
        } else {
            lock.unlock()
            task.cancel()
        }
    }

    /// 取消当前活跃轮询（切换/离开/退后台统一入口）。
    func cancelActive(reason: String) {
        lock.lock()
        generation += 1
        let old = currentTask
        let provider = activeProvider
        currentTask = nil
        activeProvider = nil
        lock.unlock()
        old?.cancel()
        if let provider {
            Breadcrumbs.log("login.poll.cancel provider=\(provider.rawValue) reason=\(reason)")
        }
    }

    /// token 是否仍是当前代次（落存前必查）。
    func isCurrent(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gen == generation
    }

    /// 本轮正常结束（成功/过期收尾）后摘除任务登记。
    func finish(generation gen: Int) {
        lock.lock()
        if gen == generation {
            currentTask = nil
            activeProvider = nil
        }
        lock.unlock()
    }
}
