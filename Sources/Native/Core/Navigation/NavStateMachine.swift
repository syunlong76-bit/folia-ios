import Foundation

/// M1 混合导航状态机（规格 v2.1 §1 + R1）。纯逻辑、无 UIKit 依赖：
/// 壳级单一真源，决定当前前台表面是原生墙/原生详情还是 Web 落点，
/// 并仲裁 Web 上报的集合导航是否由原生接管。
///
/// 规则要点（与规格逐条对应）：
/// - 启动落 nativeHome；Web 层后台恢复不抢前台。
/// - 只有 user 来源的 Web 集合导航可触发接管；restore/programmatic 永不触发。
/// - 原生详情存续期间 suppressWebNav：Web 集合导航事件只记录不接管；
///   详情关闭后若 Web 重报同一集合，按新事件正常判定（防回跳成环靠
///   「事件必须带递增序号 + 同集合去抖」两条，不靠长期抑制）。
/// - Web 进程被杀不改变当前表面归属；恢复落点由协调器按最后确认的
///   viewState 决定（无记录落 webPlayer 的规则在协调器侧）。
enum NavSurface: Equatable {
    case nativeHome
    case nativeExplore
    case nativeQueue
    case nativeDetail(collectionKey: String)
    case webPlayer
    case webSurface
    case webLogin
}

enum NavEventSource: Equatable {
    case user
    case restore
    case programmatic
}

enum NavEvent {
    /// App 冷启动完成。
    case appLaunched
    /// 原生表面内点开集合（from 为发起表面：home/explore/queue）。
    case openCollectionFromNative(collectionKey: String, from: NavSurface)
    /// Web 上报集合导航（viewState 流）。seq 为 Web 侧单调序号，壳侧
    /// 只接受严格递增者；source 区分用户行为与恢复回声。
    case webCollectionNav(collectionKey: String, seq: Int, source: NavEventSource)
    /// Web 上报已离开集合（viewState 为 null，回首页类落点）。
    case webLeftCollection(seq: Int, source: NavEventSource)
    /// 原生详情关闭（返回手势/关闭按钮）。
    case closeNativeDetail
    /// 常驻迷你条点击 → Web 播放页。
    case miniPlayerTapped
    /// 原生详情的非 MVP 入口 → Web 表面（设置/搜索/批量管理等）。
    case openWebSurface
    /// 当前 Web 表面退出（Web 内部返回到顶层后由壳收回前台）。
    case webSurfaceExited
    /// 请求登录（未登录空态/失效提示条）。
    case openLogin
    /// 登录流程结束。
    case loginFinished(success: Bool)
    /// 原生墙之间切换（主页/探索/队列）。
    case nativeWallSwitched(to: NavSurface)
    /// Web 进程被终止（WKWebView content process 死亡通知）。
    case webProcessTerminated
}

enum NavAction: Equatable {
    case presentNativeDetail(collectionKey: String)
    case dismissNativeDetail
    /// 把前台交还进入前的原生表面（按协调器保存的快照恢复相机/展开卡）。
    case restoreNativeSurface
    case presentWebPlayer
    case presentWebSurface
    case presentWebLogin
    case dismissWebLogin
    /// Web 被杀后的恢复由协调器执行（占位 → 冷加载 → 交接），
    /// 状态机只确认表面归属不变。
    case noteWebTerminated
}

struct NavStateMachine {

    private(set) var surface: NavSurface = .nativeHome
    /// 进入 Web 表面（player/surface/login）前的原生表面，退出时按它回程。
    private(set) var returnSurface: NavSurface = .nativeHome
    /// 原生详情的来源原生表面（详情关闭后回到它）。
    private(set) var detailOrigin: NavSurface = .nativeHome
    /// 已接受的 Web 导航事件最大序号；小于等于它的事件一律丢弃。
    private var lastWebSeq: Int = 0
    /// 同集合去抖：上次接管判定的集合与时间（注入时钟便于测试）。
    private var lastTakeoverKey: String?
    private var lastTakeoverAt: TimeInterval = 0
    /// suppressWebNav 期间被记录未接管的最后一个集合（详情关闭后
    /// 若 Web 以新序号重报同一集合，按新事件重新判定）。
    private(set) var suppressedCollectionKey: String?

    private let debounceInterval: TimeInterval = 0.3

    var isNativeDetailActive: Bool {
        if case .nativeDetail = surface { return true }
        return false
    }

    mutating func handle(_ event: NavEvent, now: TimeInterval) -> [NavAction] {
        switch event {

        case .appLaunched:
            surface = .nativeHome
            returnSurface = .nativeHome
            return []

        case .openCollectionFromNative(let key, let from):
            detailOrigin = from
            surface = .nativeDetail(collectionKey: key)
            suppressedCollectionKey = nil
            return [.presentNativeDetail(collectionKey: key)]

        case .webCollectionNav(let key, let seq, let source):
            guard seq > lastWebSeq else { return [] }
            lastWebSeq = seq
            // 恢复/程序化导航永不触发接管（规格 §1）。
            guard source == .user else { return [] }
            if isNativeDetailActive {
                suppressedCollectionKey = key
                return []
            }
            // 只从 Web 表面接管；原生表面在前台时 Web 不可见，
            // 其用户导航事件不成立（防御性忽略）。
            switch surface {
            case .webPlayer, .webSurface:
                break
            default:
                return []
            }
            // 同集合 300ms 内重复事件去抖。
            if key == lastTakeoverKey, now - lastTakeoverAt < debounceInterval {
                return []
            }
            lastTakeoverKey = key
            lastTakeoverAt = now
            detailOrigin = returnSurface
            surface = .nativeDetail(collectionKey: key)
            return [.presentNativeDetail(collectionKey: key)]

        case .webLeftCollection(let seq, _):
            guard seq > lastWebSeq else { return [] }
            lastWebSeq = seq
            return []

        case .closeNativeDetail:
            guard isNativeDetailActive else { return [] }
            surface = detailOrigin
            suppressedCollectionKey = nil
            return [.dismissNativeDetail]

        case .miniPlayerTapped:
            switch surface {
            case .nativeHome, .nativeExplore, .nativeQueue:
                returnSurface = surface
                surface = .webPlayer
                return [.presentWebPlayer]
            case .nativeDetail:
                // 详情在前台时迷你条属于详情层内 UI，不触发表面转移。
                return []
            default:
                return []
            }

        case .openWebSurface:
            if isNativeDetailActive {
                returnSurface = detailOrigin
            } else {
                returnSurface = surface
            }
            surface = .webSurface
            return [.presentWebSurface]

        case .webSurfaceExited:
            guard surface == .webSurface || surface == .webPlayer else { return [] }
            surface = returnSurface
            return [.restoreNativeSurface]

        case .openLogin:
            if isNativeDetailActive {
                returnSurface = detailOrigin
            } else if surface != .webLogin {
                returnSurface = surface
            }
            surface = .webLogin
            return [.presentWebLogin]

        case .loginFinished:
            guard surface == .webLogin else { return [] }
            surface = returnSurface
            return [.dismissWebLogin, .restoreNativeSurface]

        case .nativeWallSwitched(let to):
            switch to {
            case .nativeHome, .nativeExplore, .nativeQueue:
                surface = to
                return []
            default:
                return []
            }

        case .webProcessTerminated:
            // 表面归属不变；恢复链由协调器负责。
            return [.noteWebTerminated]
        }
    }
}
