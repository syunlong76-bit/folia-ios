import Foundation

/// (51) A 组：会话迁移器（DS 风险一对账结论落地）。
///
/// 时序：不挂 SceneDelegate（B 组在动它）。由 NativeDataClient
/// 在首次需要 cookie 且 migrate.state=pending、原生存储为空时
/// 懒触发；全程异步不阻塞调用方——调用方先拿旧 WebView 读法
/// 的结果用着，迁移成功后下一次刷新自动切源（source=native）。
///
/// 判据三分（结构化读取，见 WebSession.StructuredRead）：
/// - absent（两键皆空）= 未登录：不写不切源，state 保持
///   pending，下次登录后再迁；
/// - value 但校验不过（无 MUSIC_U/非 name=value 形态，含空串
///   与半串）= invalid：不写不覆盖、保留 webview 源、下次重试；
/// - readFail（JS 异常/超时）= 同 invalid 处理。
/// 写 Keychain 后立即回读比对（长度＋hash8）一致才标 done 并
/// 切源；不一致不切源、记 fail。
/// 面包屑只记 len/hash8，绝不记 cookie 原文。
enum SessionMigrator {

    static let stateKey = "session.migrate.state"

    enum State: String {
        case pending
        case done
    }

    static var state: State {
        get {
            guard let raw = UserDefaults.standard.string(forKey: stateKey),
                  let value = State(rawValue: raw) else { return .pending }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: stateKey) }
    }

    private static let triggerLock = NSLock()
    private static var inFlight = false

    /// 懒触发（去重：并发调用只跑一条迁移任务）。
    static func triggerIfNeeded() {
        guard state == .pending else { return }
        guard NativeSessionStore.shared.load() == nil else {
            // 原生存储已有会话（原生登录写入等）：无需迁移。
            state = .done
            return
        }
        triggerLock.lock()
        guard !inFlight else { triggerLock.unlock(); return }
        inFlight = true
        triggerLock.unlock()
        Task {
            await run()
            triggerLock.lock()
            inFlight = false
            triggerLock.unlock()
        }
    }

    static func run() async {
        Breadcrumbs.log("session.migrate.begin")
        let result = await WebSession.readNeteaseCookieStructured()
        switch result {
        case .absent:
            // 未登录：不写不切源，仅记录（state 保持 pending）。
            Breadcrumbs.log("session.migrate.fail reason=absent")
        case .readFail(let reason):
            Breadcrumbs.log("session.migrate.fail reason=\(reason == "timeout" ? "timeout" : "readFail")")
        case .value(let raw):
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard NativeSessionStore.isValidNeteaseCookie(value) else {
                Breadcrumbs.log("session.migrate.fail reason=invalid len=\(value.count)")
                return
            }
            guard NativeSessionStore.shared.save(value) else {
                Breadcrumbs.log("session.migrate.fail reason=readFail stage=keychain-write")
                return
            }
            // 回读比对：直读 Keychain，长度＋hash8 一致才切源。
            let readback = NativeSessionStore.shared.loadDirect()
            guard let readback,
                  readback.count == value.count,
                  NativeSessionStore.hash8(readback) == NativeSessionStore.hash8(value) else {
                Breadcrumbs.log("session.migrate.fail reason=readFail stage=readback")
                return
            }
            state = .done
            Breadcrumbs.log("session.migrate.ok len=\(value.count) hash=\(NativeSessionStore.hash8(value))")
            NativeDataClient.shared.noteSessionSource(.native)
        }
    }
}
