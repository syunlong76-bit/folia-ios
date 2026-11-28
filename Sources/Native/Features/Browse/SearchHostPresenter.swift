import SwiftUI
import UIKit

/// 搜索挂载（3.7 (51) D 组）：把从未挂载的 SwiftUI 搜索工作区
/// （SearchWorkspaceView）以 UIHostingController 全屏呈到原生
/// 主页墙之上，关闭 dismiss 回墙。挂载点只此一处（主页墙顶部
/// 带齿轮旁的搜索按钮，见 HomeWallViewController 的新增段落）。
///
/// 接线口径（与既有浏览面同路，不另造通路）：
/// - 点单曲：沿 SearchWorkspaceView 默认语义——以当前搜索结果
///   整列为队列经 QueueManager.setQueue 起播（与曲目墙点歌
///   WallPrototypeViewController 的 setQueue(source:"native-
///   wall") 同一漏斗，仅 source 标记为 "search"）；setQueue →
///   loadTrackAtCurrentIndex → PlaybackEngine.load → play()
///   自动起播，回墙后主页墙迷你台经 PlaybackEngine.$current-
///   Track 订阅自动刷新（墙内既有接线，本处不另接）。
/// - 点专辑/歌单行：SearchWorkspaceView 的 onOpenCollection
///   默认是空操作，必须由挂载方接——这里映射为 Explore-
///   Collection 后以第二个 UIHostingController 全屏呈
///   CollectionView（与 ExploreView 的映射同口径），其关闭
///   （左上 chevron 的 dismiss）回搜索页、播放语义自带
///   （setQueue / appendToQueue 直进 QueueManager）。
/// - ExploreView 本轮不挂载：其搜索入口与本挂载重复，推荐
///   货架不是 (51) 搜索挂载的任务面，避免双入口语义打架。
enum SearchHostPresenter {

    static func presentSearch(from presenter: UIViewController) {
        Breadcrumbs.log("search.open from=home-wall")
        // (101) 第 2 项：呈现层自证——搜索页进场时主台（播
        // 放台）当前主题值在此落盘，页内再读同源并跟随。
        Breadcrumbs.log("p101 search present stage-theme="
            + "\(String(describing: MiniPlayerTheme.effective))"
            + " fx=\(MiniPlayerTheme.effectsEnabled ? 1 : 0)")
        // (104) 搜索线①：宿主改容器（SearchDeckHostVC104）
        // ——SwiftUI 搜索页＋搜索内播放台同窗，点播放经同
        // 一 setQueue 漏斗起播、台当场在搜索页内弹出（旧
        // 宿主只有 UIHostingController，台在被盖住的墙上、
        // 点播无台可见）。onClose/右滑退出改关容器。
        let host = UIHostingController(rootView: SearchWorkspaceView())
        let container = SearchDeckHostVC104(hosting: host)
        host.rootView = SearchWorkspaceView(
            onClose: { [weak container] in
                container?.dismiss(animated: true)
            },
            onPlaySong: { song, queue in
                Breadcrumbs.log("search.play track=\(song.id) queue=\(queue.count)")
                QueueManager.shared.setQueue(
                    queue,
                    startingAt: queue.firstIndex { $0.id == song.id } ?? 0,
                    source: "search")
            },
            onOpenCollection: { [weak container] collection in
                guard let container else { return }
                presentCollection(collection, from: container)
            })
        host.view.backgroundColor = .clear
        container.modalPresentationStyle = .fullScreen
        // (101) 第 3 项：搜索页补左缘右滑退出（头部 ✕ 已按
        // 定版撤除，关闭走本手势 + onClose 同路 dismiss）。
        EdgeBack101.install(on: container, page: "search") { [weak container] in
            container?.dismiss(animated: true)
        }
        presenter.present(container, animated: true)
    }

    private static func presentCollection(_ collection: SearchCollection,
                                          from presenter: UIViewController) {
        Breadcrumbs.log("search.openCollection kind=\(collection.kind) id=\(collection.id)")
        let mapped = ExploreCollection(
            kind: collection.kind == .album ? .album : .playlist,
            id: collection.id,
            name: collection.name,
            coverURL: collection.coverURL,
            subtitle: collection.ownerName)
        let host = UIHostingController(rootView: CollectionView(collection: mapped))
        host.modalPresentationStyle = .fullScreen
        // (76) ④左缘滑动返回（歌单详情）：本页关闭无特殊
        // 契约，dismiss 直达；SwiftUI 内部滚动 pan 无法自
        // UIKit 侧 require-to-fail 接线，左缘 ~20pt 起手带
        // 与横向货架的残余冲突见 (76) 报告④冲突清单。
        EdgeBack76.install(on: host) { [weak host] in
            host?.dismiss(animated: true)
        }
        presenter.present(host, animated: true)
    }
}
