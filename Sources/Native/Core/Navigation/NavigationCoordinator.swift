import Foundation

/// 原生表面快照：退出原生表面进 Web 时保存，回来时按它恢复
/// （相机偏移、展开卡）。墙在 M1 阶段 3/4 接入后填充具体数值，
/// 阶段 1 先立结构与存取口。
struct NativeSurfaceSnapshot {
    var cameraX: Double = 0
    var cameraY: Double = 0
    var expandedCollectionKey: String?
}

/// M1 导航协调器：NavStateMachine 的壳侧持有者，单一真源。
///
/// 阶段 1（当前）：只观察与记账，不执行任何表面切换——原生墙/详情
/// 尚未挂载，状态机产出的动作只写日志。阶段 4 表面接入后，动作在
/// 这里分发执行，调用方（桥、迷你条、原生墙）不直接碰状态机。
///
/// Web 侧 viewState 事件的来源判定：现协议没有 source 字段，壳侧按
/// 「自己刚下发过 restoreView 的时间窗」判定回声为 restore，其余为
/// user。Web 侧将来补 source/seq 字段后，这里改直读字段即可。
final class NavigationCoordinator {

    static let shared = NavigationCoordinator()

    private(set) var machine = NavStateMachine()
    /// 各原生表面的快照（key 为表面名）。
    private var snapshots: [String: NativeSurfaceSnapshot] = [:]
    /// 最后确认的 Web 集合 key（providerId/type/id），Web 被杀恢复用。
    private(set) var lastConfirmedWebCollectionKey: String?
    /// 协调器自赋的事件序号（现协议无 seq 时的替代，单调递增）。
    private var eventSeq = 0
    /// 最近一次下发 restoreView 的时刻；其后 3 秒内的同 key 上报判回声。
    private var restoreDispatchedAt: Date?
    private var restoreDispatchedKey: String?

    private init() {}

    var currentSurface: NavSurface { machine.surface }

    // MARK: - 快照存取

    func saveSnapshot(_ snapshot: NativeSurfaceSnapshot, for surface: NavSurface) {
        snapshots[Self.key(for: surface)] = snapshot
    }

    func snapshot(for surface: NavSurface) -> NativeSurfaceSnapshot? {
        snapshots[Self.key(for: surface)]
    }

    private static func key(for surface: NavSurface) -> String {
        switch surface {
        case .nativeHome: return "home"
        case .nativeExplore: return "explore"
        case .nativeQueue: return "queue"
        case .nativeDetail(let key): return "detail:\(key)"
        case .webPlayer: return "webPlayer"
        case .webSurface: return "webSurface"
        case .webLogin: return "webLogin"
        }
    }

    // MARK: - 桥事件入口（阶段 1：WebEffectBridge 转发）

    /// 桥的 viewState 上报（集合字典或 nil）。转换为状态机事件并记账。
    func noteWebViewState(_ view: [String: Any]?) {
        eventSeq += 1
        guard let view, let id = view["id"] else {
            _ = dispatch(.webLeftCollection(seq: eventSeq, source: .user))
            lastConfirmedWebCollectionKey = nil
            return
        }
        let key = "\(view["providerId"] as? String ?? "-")/\(view["type"] as? String ?? "-")/\(id)"
        lastConfirmedWebCollectionKey = key
        let source: NavEventSource
        if let at = restoreDispatchedAt, let rKey = restoreDispatchedKey,
           rKey == key, Date().timeIntervalSince(at) < 3 {
            source = .restore
        } else {
            source = .user
        }
        _ = dispatch(.webCollectionNav(collectionKey: key, seq: eventSeq, source: source))
    }

    /// 桥下发 restoreView 后调用：标记回声判定窗口。
    func noteRestoreDispatched(collectionKey: String) {
        restoreDispatchedAt = Date()
        restoreDispatchedKey = collectionKey
    }

    /// Web 进程被终止时调用（恢复链在桥侧执行，这里只记账表面归属）。
    func noteWebProcessTerminated() {
        _ = dispatch(.webProcessTerminated)
    }

    // MARK: - 动作分发（阶段 1 只记账）

    @discardableResult
    func dispatch(_ event: NavEvent) -> [NavAction] {
        let actions = machine.handle(event, now: Date().timeIntervalSince1970)
        if !actions.isEmpty {
            FoliaFileLog.write("nav", "event -> \(actions) surface=\(machine.surface)")
        }
        return actions
    }
}
