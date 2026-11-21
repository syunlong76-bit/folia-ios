import SwiftUI

// ExploreView.swift
//
// 探索页：按 port-spec-home.md 逐项移植 folia-major 的 ExploreSurface。
// 分区顺序照 neteaseExplore：自有分区（本机记录）→ 首页 blocks → 排行榜 →
// 热门歌单（第一页）；触底续接相似货架 → 新歌速递/新碟上架 → 官方榜歌曲货架。
// 每日推荐/每日推荐歌单（62 WC 簇补）：登录态已通后走既有
// fetchDailySongs/fetchRecommendedPlaylists 通路补两货架；
// 未登录时两架诚实不出现（不放假货架）。
// 分区形态照源码：1 条且无更多 = solo、第一分区 = lead、其余 = row 横滑行。

// MARK: - 数据模型

/// 不标类级 @MainActor（与 M1/M2 口径一致：避免非隔离上下文调用报错）；
/// 异步工作方法逐个标 @MainActor，保证 @Published 只在主线程变更，
/// 同步入口（按钮动作）本身就在主线程。
final class ExploreModel: ObservableObject {

    struct Shelf: Identifiable {
        let id: String
        let title: String
        var items: [ExploreItem]
        var hasMore: Bool
    }

    enum Phase {
        case loading
        case ready
        case failed
    }

    @Published private(set) var shelves: [Shelf] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshFailed = false
    @Published private(set) var isLoadingMoreParts = false
    @Published private(set) var partsFailed = false
    @Published private(set) var partsDone = false

    /// 货架每批条数（源码 BATCH = 12）。
    private let batch = 12
    /// 整表货架尚未展示的余量（「更多」从这里续）。
    private var held: [String: [ExploreItem]] = [:]
    /// 分页货架（新碟上架）的续拉位置。
    private var albumPaging: [String: (offset: Int, total: Int)] = [:]
    /// 待续接的 part 队列（0 相似 / 1 新歌新碟 / 2 官方榜歌曲）。
    private var pendingParts: [Int] = [0, 1, 2]
    private var lastPartHadError = false
    private var usedSeedIds = Set<String>()
    private var onShelfSongIds = Set<String>()
    private var toplistCache: [PlaylistSummary] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task { await loadFirstPage() }
    }

    func retry() {
        Task { await loadFirstPage() }
    }

    func refresh() {
        guard !isRefreshing, phase == .ready else { return }
        Task { await refreshFirstPage() }
    }

    // MARK: 第一页

    @MainActor
    private func loadFirstPage() async {
        phase = .loading
        let (built, networkOK) = await buildFirstPage()
        if built.isEmpty {
            phase = .failed
        } else {
            shelves = built
            phase = .ready
            refreshFailed = !networkOK
        }
    }

    @MainActor
    private func refreshFirstPage() async {
        isRefreshing = true
        refreshFailed = false
        let (built, networkOK) = await buildFirstPage()
        if built.isEmpty {
            refreshFailed = true
        } else {
            shelves = built
            pendingParts = [0, 1, 2]
            partsDone = false
            partsFailed = false
            refreshFailed = !networkOK
        }
        isRefreshing = false
    }

    /// 组装第一页分区（自有 → blocks → 排行榜 → 热门歌单）。
    /// 返回 (分区, 是否读到任何网络内容)；各路独立失败不拖垮整页。
    @MainActor
    private func buildFirstPage() async -> ([Shelf], Bool) {
        held = [:]
        albumPaging = [:]
        onShelfSongIds = []
        usedSeedIds = []
        toplistCache = []

        var result: [Shelf] = ownShelves()

        // 每日推荐两货架（62 WC）：仅登录态请求；任一路失败只空
        // 该架，不拖垮第一页。
        if NativeSessionStore.shared.load() != nil {
            async let dailySongsTask = try? NativeDataClient.shared.fetchDailySongs()
            async let dailyPlaylistsTask = try? NativeDataClient.shared.fetchRecommendedPlaylists()
            if let dailySongs = await dailySongsTask, !dailySongs.isEmpty {
                let items = dailySongs.map(workbenchFoliaTrack).map(ExploreItem.song)
                result.append(makeShelf(id: "netease-daily-songs62",
                                        title: "每日推荐歌曲", items: items))
            }
            if let dailyPlaylists = await dailyPlaylistsTask, !dailyPlaylists.isEmpty {
                let items = dailyPlaylists.compactMap { summary -> ExploreItem? in
                    guard let id = Int(summary.id) else { return nil }
                    return .collection(ExploreCollection(
                        kind: .playlist, id: id, name: summary.name,
                        coverURL: summary.coverUrl.flatMap { URL(string: $0) },
                        subtitle: summary.creatorName ?? "歌单"))
                }
                if !items.isEmpty {
                    result.append(makeShelf(id: "netease-daily-playlists62",
                                            title: "每日推荐歌单", items: items))
                }
            }
            Breadcrumbs.log("explore62.daily shelves=\(result.count)")
        }

        async let blocksTask = try? EdgeOneAPIClient.shared.fetchHomeBlockSections()
        async let toplistTask = try? EdgeOneAPIClient.shared.fetchToplist()
        async let personalizedTask = try? EdgeOneAPIClient.shared.fetchPersonalizedPlaylists(limit: 30)
        let blocks = await blocksTask
        let toplist = await toplistTask
        let personalized = await personalizedTask

        var networkCount = 0
        if let blocks {
            for section in blocks {
                result.append(makeShelf(id: section.id, title: section.title, items: section.items))
                networkCount += section.items.count
            }
        }
        if let toplist, !toplist.isEmpty {
            toplistCache = toplist
            let items = toplist.map { summary in
                ExploreItem.collection(ExploreCollection(
                    kind: .playlist, id: summary.id, name: summary.name,
                    coverURL: summary.coverURL,
                    subtitle: summary.updateFrequency ?? "歌单"))
            }
            result.append(makeShelf(id: "netease-charts", title: "排行榜", items: items))
            networkCount += items.count
        }
        if let personalized, !personalized.isEmpty {
            let items = personalized.map { summary in
                ExploreItem.collection(ExploreCollection(
                    kind: .playlist, id: summary.id, name: summary.name,
                    coverURL: summary.coverURL,
                    subtitle: summary.copywriter ?? "歌单"))
            }
            result.append(makeShelf(id: "netease-personalized", title: "热门歌单", items: items))
            networkCount += items.count
        }
        for shelf in result { registerOnShelf(shelf.items) }
        return (result, networkCount > 0)
    }

    /// 自有分区（照 ownSections.ts：无记录不出现，无「更多」）。
    private func ownShelves() -> [Shelf] {
        var result: [Shelf] = []
        let recent = PlayHistoryStore.shared.recentTracks()
        if !recent.isEmpty {
            result.append(Shelf(id: "folia-recent-plays", title: "最近播放",
                                items: recent.map(ExploreItem.song), hasMore: false))
        }
        let again = PlayHistoryStore.shared.playAgainTracks()
        if !again.isEmpty {
            result.append(Shelf(id: "folia-play-again", title: "再听一次",
                                items: again.map(ExploreItem.song), hasMore: false))
        }
        return result
    }

    /// 播放记录变化时原地更新自有分区（源码 useSyncExternalStore 语义）。
    func updateOwnSections() {
        guard phase == .ready else { return }
        let fresh = ownShelves()
        var rest = shelves.filter { $0.id != "folia-recent-plays" && $0.id != "folia-play-again" }
        for shelf in fresh.reversed() {
            rest.insert(shelf, at: 0)
        }
        shelves = rest
    }

    private func makeShelf(id: String, title: String, items: [ExploreItem]) -> Shelf {
        if items.count > batch {
            held[id] = Array(items.dropFirst(batch))
            return Shelf(id: id, title: title, items: Array(items.prefix(batch)), hasMore: true)
        }
        return Shelf(id: id, title: title, items: items, hasMore: false)
    }

    private func registerOnShelf(_ items: [ExploreItem]) {
        for item in items {
            if let song = item.song { onShelfSongIds.insert(song.id) }
        }
    }

    // MARK: 分区「更多」

    func loadMore(shelfId: String) {
        guard let index = shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        if var rest = held[shelfId], !rest.isEmpty {
            let next = Array(rest.prefix(batch))
            rest = Array(rest.dropFirst(batch))
            held[shelfId] = rest
            shelves[index].items.append(contentsOf: next)
            shelves[index].hasMore = !rest.isEmpty || albumPaging[shelfId] != nil
            registerOnShelf(next)
            return
        }
        if let paging = albumPaging[shelfId] {
            Task { await loadMoreAlbums(shelfId: shelfId, paging: paging) }
        }
    }

    @MainActor
    private func loadMoreAlbums(shelfId: String, paging: (offset: Int, total: Int)) async {
        guard let index = shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        do {
            let (albums, total) = try await EdgeOneAPIClient.shared.fetchNewAlbums(
                limit: batch, offset: paging.offset)
            let items = albums.map(ExploreItem.collection)
            shelves[index].items.append(contentsOf: items)
            let nextOffset = paging.offset + albums.count
            let goesOn = !albums.isEmpty && nextOffset < total
            shelves[index].hasMore = goesOn
            albumPaging[shelfId] = goesOn ? (nextOffset, total) : nil
        } catch {
            // 分页失败保留「更多」让用户重试，不吞掉已展示内容。
        }
    }

    // MARK: 触底续接（neteaseExplore 的 parts）

    func loadNextPartIfNeeded() {
        guard phase == .ready, !partsDone, !isLoadingMoreParts else { return }
        Task { await loadNextPart() }
    }

    func retryParts() {
        partsFailed = false
        loadNextPartIfNeeded()
    }

    @MainActor
    private func loadNextPart() async {
        isLoadingMoreParts = true
        partsFailed = false
        while let part = pendingParts.first {
            lastPartHadError = false
            let produced: Bool
            switch part {
            case 0: produced = await appendSimilarShelves()
            case 1: produced = await appendNewShelves()
            default: produced = await appendChartShelves()
            }
            if produced {
                pendingParts.removeFirst()
                break
            }
            if lastPartHadError {
                // 出错的 part 留在队首等重试（源码语义：读不到就跳过该 part，
                // 但整页失败时给用户重试入口；此处以哨兵区重试 pill 呈现）。
                partsFailed = true
                break
            }
            pendingParts.removeFirst() // 读到了但没货：该 part 自然结束，继续下一个
        }
        if pendingParts.isEmpty { partsDone = true }
        isLoadingMoreParts = false
    }

    /// 相似货架：以听过的歌为种子（自有分区优先），每页最多 3 个货架，
    /// 每货架 ≥4 首未上过架的歌（源码 SIMILAR_A_PAGE / SIMILAR_MIN）。
    @MainActor
    private func appendSimilarShelves() async -> Bool {
        var seeds: [FoliaTrack] = []
        var seen = Set<String>()
        for track in PlayHistoryStore.shared.playAgainTracks() + PlayHistoryStore.shared.recentTracks() {
            if seen.insert(track.id).inserted { seeds.append(track) }
        }
        for shelf in shelves {
            for item in shelf.items {
                if let song = item.song, seen.insert(song.id).inserted { seeds.append(song) }
            }
        }
        var made = 0
        var attempts = 0
        var failures = 0
        for seed in seeds where made < 3 {
            if usedSeedIds.contains(seed.id) { continue }
            usedSeedIds.insert(seed.id)
            guard let numericId = Int(seed.id.replacingOccurrences(of: "ncm_", with: "")) else { continue }
            attempts += 1
            guard let songs = try? await EdgeOneAPIClient.shared.fetchSimilarSongs(songId: numericId) else {
                failures += 1
                continue
            }
            var unique: [FoliaTrack] = []
            var localSeen = Set<String>()
            for song in songs where song.id != seed.id && !onShelfSongIds.contains(song.id) {
                if localSeen.insert(song.id).inserted { unique.append(song) }
            }
            guard unique.count >= 4 else { continue }
            let items = unique.map(ExploreItem.song)
            shelves.append(makeShelf(id: "netease-similar-\(seed.id)",
                                     title: "与《\(seed.title)》相似", items: items))
            registerOnShelf(items)
            made += 1
        }
        if made == 0, attempts > 0, failures == attempts { lastPartHadError = true }
        return made > 0
    }

    /// 新歌速递（整表分批）+ 新碟上架（分页货架）。
    @MainActor
    private func appendNewShelves() async -> Bool {
        var produced = false
        do {
            let songs = try await EdgeOneAPIClient.shared.fetchNewSongs()
            if !songs.isEmpty {
                let items = songs.map(ExploreItem.song)
                shelves.append(makeShelf(id: "netease-new-songs", title: "新歌速递", items: items))
                registerOnShelf(items)
                produced = true
            }
        } catch {
            lastPartHadError = true
        }
        do {
            let (albums, total) = try await EdgeOneAPIClient.shared.fetchNewAlbums(limit: batch, offset: 0)
            if !albums.isEmpty {
                let goesOn = albums.count < total
                shelves.append(Shelf(id: "netease-new-albums", title: "新碟上架",
                                     items: albums.map(ExploreItem.collection), hasMore: goesOn))
                if goesOn { albumPaging["netease-new-albums"] = (albums.count, total) }
                produced = true
            }
        } catch {
            lastPartHadError = true
        }
        return produced
    }

    /// 官方四榜的歌曲货架（toplist 中带 ToplistType 的榜；没有标记时退回前四榜）。
    @MainActor
    private func appendChartShelves() async -> Bool {
        let official = toplistCache.filter { $0.toplistType != nil }
        let charts = Array((official.isEmpty ? toplistCache : official).prefix(4))
        var produced = false
        for chart in charts {
            guard let detail = try? await EdgeOneAPIClient.shared.fetchPlaylistDetail(
                playlistId: String(chart.id)) else { continue }
            let firstIds = Array(detail.trackIdList.prefix(batch))
            var byId: [Int: FoliaTrack] = [:]
            for track in detail.prefetchedTracks {
                byId[Int(track.id.replacingOccurrences(of: "ncm_", with: "")) ?? -1] = track
            }
            let missing = firstIds.filter { byId[$0] == nil }
            if !missing.isEmpty,
               let fetched = try? await EdgeOneAPIClient.shared.fetchSongDetails(ids: missing) {
                for track in fetched {
                    byId[Int(track.id.replacingOccurrences(of: "ncm_", with: "")) ?? -1] = track
                }
            }
            let tracks = firstIds.compactMap { byId[$0] }
            if tracks.isEmpty { continue }
            let items = tracks.map(ExploreItem.song)
            shelves.append(Shelf(id: "netease-chart-\(chart.id)", title: chart.name,
                                 items: items, hasMore: false))
            registerOnShelf(items)
            produced = true
        }
        return produced
    }
}

// MARK: - 探索页视图

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ExploreView: View {
    /// 浏览面导航路径（NativeBrowseView 持有）：搜索页点开的集合在覆盖层
    /// 收起后经它压栈进集合页。
    var path: Binding<NavigationPath>
    @StateObject private var model = ExploreModel()
    @ObservedObject private var history = PlayHistoryStore.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var showSearch = false
    @State private var showLattice = false
    /// 搜索页选中的集合：先存下，搜索覆盖层收完再压栈（onDismiss 里执行）。
    @State private var pendingSearchCollection: ExploreCollection?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FoliaTheme.background.ignoresSafeArea()
            // ExploreLight：内容顶部一层柔光（源码为跟随首分区大图的辉光，
            // 原生侧以主色低透明径向光近似）。
            Ellipse()
                .fill(FoliaTheme.primary.opacity(0.07))
                .frame(width: 420, height: 300)
                .blur(radius: 70)
                .offset(x: -90, y: -120)
                .allowsHitTesting(false)

            content

            // 顶部 56px 渐隐（源码 mask）。
            VStack {
                LinearGradient(colors: [FoliaTheme.background, FoliaTheme.background.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 56)
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            refreshButton
                .padding(.top, 10)
                .padding(.trailing, 16)
        }
        .task { model.start() }
        .onChange(of: history.records.count) { _ in
            model.updateOwnSections()
        }
        // 搜索页（Folia 搜索工作区全屏覆盖层）：点集合先存待压栈，覆盖层
        // 收完（onDismiss）再经导航路径压栈，动画不打架。
        .fullScreenCover(isPresented: $showSearch, onDismiss: {
            if let pending = pendingSearchCollection {
                pendingSearchCollection = nil
                path.wrappedValue.append(pending)
            }
        }) {
            SearchWorkspaceView(
                onClose: { showSearch = false },
                onOpenCollection: { searchCollection in
                    pendingSearchCollection = ExploreCollection(
                        kind: searchCollection.kind == .album ? .album : .playlist,
                        id: searchCollection.id,
                        name: searchCollection.name,
                        coverURL: searchCollection.coverURL,
                        subtitle: searchCollection.ownerName)
                    showSearch = false
                })
        }
        // 格子（队列海报墙）：Folia 主页 chrome 的 onOpenLattice 入口。
        .fullScreenCover(isPresented: $showLattice) {
            LatticeWallView(
                onClose: { showLattice = false },
                onOpenPlayer: {
                    showLattice = false
                    NativeBrowseView.openFullPlayer()
                })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(FoliaTheme.primary)
                .opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 14) {
                Text("推荐内容没有读到")
                    .font(.system(size: 14))
                    .foregroundColor(FoliaTheme.primary.opacity(0.6))
                Button("重试") { model.retry() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FoliaTheme.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay(Capsule().stroke(FoliaTheme.primary.opacity(0.12), lineWidth: 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.shelves.isEmpty {
                Text("暂时没有推荐内容")
                    .font(.system(size: 14))
                    .foregroundColor(FoliaTheme.primary.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("exploreScroll")).minY)
                        }
                        .frame(height: 0)

                        searchEntry

                        ForEach(Array(model.shelves.enumerated()), id: \.element.id) { index, shelf in
                            ExploreShelfView(shelf: shelf, isFirst: index == 0, model: model)
                        }

                        sentinel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                    .opacity(model.isRefreshing ? 0.6 : 1)
                }
                .coordinateSpace(name: "exploreScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
            }
        }
    }

    /// 顶部入口行：搜索行（点开 Folia 搜索工作区全屏覆盖层）+ 右侧格子按钮
    /// （主页 chrome 的 onOpenLattice 入口，打开队列海报墙）。搜索行样式
    /// 沿用 3.3 起的主题字段底。
    private var searchEntry: some View {
        HStack(spacing: 10) {
            Button {
                showSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("搜索歌曲")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundColor(FoliaTheme.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(FoliaTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showLattice = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.subheadline)
                    .foregroundColor(FoliaTheme.secondary)
                    .frame(width: 42, height: 42)
                    .background(FoliaTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("队列拼贴")
        }
        .padding(.bottom, 26)
    }

    /// 底部状态区（h-28）：加载转圈 / 失败重试 pill / 触底哨兵。
    @ViewBuilder
    private var sentinel: some View {
        if !model.partsDone {
            VStack {
                if model.isLoadingMoreParts {
                    ProgressView()
                        .tint(FoliaTheme.primary)
                        .opacity(0.5)
                } else if model.partsFailed {
                    Button("重试") { model.retryParts() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FoliaTheme.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .overlay(Capsule().stroke(FoliaTheme.primary.opacity(0.12), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .onAppear { model.loadNextPartIfNeeded() }
        }
    }

    /// 右上「换一批」：32pt 圆形 pill；滚动时玻璃质；刷新失败带 amber 小圆点。
    private var refreshButton: some View {
        Button {
            model.refresh()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FoliaTheme.primary)
                    .frame(width: 32, height: 32)
                    .background {
                        if scrollOffset < -40 {
                            Circle().fill(.ultraThinMaterial)
                        } else {
                            Circle().fill(FoliaTheme.primary.opacity(0.10))
                        }
                    }
                    .overlay(Circle().stroke(FoliaTheme.primary.opacity(0.12), lineWidth: 1))
                    .clipShape(Circle())
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .default, value: model.isRefreshing)
                if model.refreshFailed {
                    Circle()
                        .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                        .frame(width: 6, height: 6)
                        .offset(x: 1, y: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("换一批")
    }
}

// MARK: - 分区

private struct ExploreShelfView: View {
    let shelf: ExploreModel.Shelf
    let isFirst: Bool
    @ObservedObject var model: ExploreModel

    private enum Form { case solo, lead, row }
    private var form: Form {
        if shelf.items.count == 1 && !shelf.hasMore { return .solo }
        return isFirst ? .lead : .row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 20)

            switch form {
            case .solo:
                if let item = shelf.items.first {
                    ExploreSoloCard(item: item, shelf: shelf)
                }
            case .lead:
                ExploreLeadBody(shelf: shelf)
            case .row:
                ExploreRowBody(shelf: shelf)
            }
        }
        .padding(.bottom, isFirst ? 72 : 56)
    }

    /// 分区标题行：衬线 28 + 1px 横线（主色 12%）+「更多」pill（仅有更多时）。
    private var header: some View {
        HStack(spacing: 12) {
            Text(shelf.title)
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundColor(FoliaTheme.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Rectangle()
                .fill(FoliaTheme.primary.opacity(0.12))
                .frame(height: 1)
            if shelf.hasMore {
                Button {
                    model.loadMore(shelfId: shelf.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("更多")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(FoliaTheme.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay(Capsule().stroke(FoliaTheme.primary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 点歌曲 = 以该分区全部歌曲为队列播放（源码语义）。
private func playFromShelf(_ track: FoliaTrack, shelf: ExploreModel.Shelf) {
    let songs = shelf.items.compactMap(\.song)
    guard let index = songs.firstIndex(where: { $0.id == track.id }) else { return }
    QueueManager.shared.setQueue(songs, startingAt: index)
    NativeBrowseView.openFullPlayer()
}

// MARK: - row 横滑行

private struct ExploreRowBody: View {
    let shelf: ExploreModel.Shelf

    var body: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(shelf.items) { item in
                        ExploreRowCard(item: item, shelf: shelf)
                    }
                }
            }
            // 行两端 56px 渐隐（源码 mask，以背景色渐变覆盖近似）。
            HStack {
                LinearGradient(colors: [FoliaTheme.background, FoliaTheme.background.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 56)
                Spacer()
                LinearGradient(colors: [FoliaTheme.background.opacity(0), FoliaTheme.background],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 56)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct ExploreRowCard: View {
    let item: ExploreItem
    let shelf: ExploreModel.Shelf
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        switch item {
        case .song(let track):
            Button {
                playFromShelf(track, shelf: shelf)
            } label: {
                card(title: track.title, subtitle: track.artist,
                     coverURL: track.artworkURL, round: false, track: track)
            }
            .buttonStyle(.plain)
        case .collection(let collection):
            NavigationLink(value: collection) {
                card(title: collection.name, subtitle: collection.subtitle,
                     coverURL: collection.coverURL, round: collection.kind == .artist, track: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func card(title: String, subtitle: String, coverURL: URL?, round: Bool, track: FoliaTrack?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                NativeCoverView(url: coverURL, targetPixels: 400)
                    .frame(width: 162, height: 162)
                    .clipShape(round
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
                if let track {
                    if engine.currentTrack?.id == track.id {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(8)
                    } else if track.duration > 0 {
                        Text(formatDuration(track.duration))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(8)
                    }
                }
            }
            .overlay {
                if round {
                    Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(FoliaTheme.primary)
                .lineLimit(1)
                .frame(width: 162, alignment: .leading)
                .padding(.top, 10)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(FoliaTheme.primary.opacity(0.6))
                .lineLimit(1)
                .frame(width: 162, alignment: .leading)
                .padding(.top, 4)
        }
    }
}

// MARK: - lead（第一分区：首条大图 + 其余列表行）

private struct ExploreLeadBody: View {
    let shelf: ExploreModel.Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let first = shelf.items.first {
                ExploreLeadLarge(item: first, shelf: shelf)
            }
            VStack(spacing: 2) {
                ForEach(Array(shelf.items.dropFirst())) { item in
                    ExploreLeadLine(item: item, shelf: shelf)
                }
            }
        }
    }
}

private struct ExploreLeadLarge: View {
    let item: ExploreItem
    let shelf: ExploreModel.Shelf

    var body: some View {
        switch item {
        case .song(let track):
            Button {
                playFromShelf(track, shelf: shelf)
            } label: {
                content(title: track.title, subtitle: track.artist,
                        coverURL: track.artworkURL, round: false)
            }
            .buttonStyle(.plain)
        case .collection(let collection):
            NavigationLink(value: collection) {
                content(title: collection.name, subtitle: collection.subtitle,
                        coverURL: collection.coverURL, round: collection.kind == .artist)
            }
            .buttonStyle(.plain)
        }
    }

    private func content(title: String, subtitle: String, coverURL: URL?, round: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NativeCoverView(url: coverURL, targetPixels: 640)
                .frame(width: 224, height: 224)
                .clipShape(round
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
                .shadow(color: .black.opacity(0.8), radius: 30, x: 0, y: 18)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(FoliaTheme.primary)
                .lineLimit(2)
                .frame(width: 224, alignment: .leading)
                .padding(.top, 14)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(FoliaTheme.primary.opacity(0.6))
                .lineLimit(1)
                .frame(width: 224, alignment: .leading)
                .padding(.top, 4)
        }
    }
}

private struct ExploreLeadLine: View {
    let item: ExploreItem
    let shelf: ExploreModel.Shelf

    var body: some View {
        switch item {
        case .song(let track):
            Button {
                playFromShelf(track, shelf: shelf)
            } label: {
                line(title: track.title, subtitle: track.artist, coverURL: track.artworkURL,
                     round: false, duration: track.duration)
            }
            .buttonStyle(.plain)
        case .collection(let collection):
            NavigationLink(value: collection) {
                line(title: collection.name, subtitle: collection.subtitle,
                     coverURL: collection.coverURL, round: collection.kind == .artist, duration: 0)
            }
            .buttonStyle(.plain)
        }
    }

    private func line(title: String, subtitle: String, coverURL: URL?, round: Bool, duration: Double) -> some View {
        HStack(spacing: 16) {
            NativeCoverView(url: coverURL, targetPixels: 200)
                .frame(width: 54, height: 54)
                .clipShape(round
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FoliaTheme.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(FoliaTheme.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if duration > 0 {
                Text(formatDuration(duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(FoliaTheme.primary.opacity(0.52))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - solo（仅 1 条且无更多）

private struct ExploreSoloCard: View {
    let item: ExploreItem
    let shelf: ExploreModel.Shelf

    var body: some View {
        switch item {
        case .song(let track):
            Button {
                playFromShelf(track, shelf: shelf)
            } label: {
                content(title: track.title, subtitle: track.artist,
                        coverURL: track.artworkURL, round: false)
            }
            .buttonStyle(.plain)
        case .collection(let collection):
            NavigationLink(value: collection) {
                content(title: collection.name, subtitle: collection.subtitle,
                        coverURL: collection.coverURL, round: collection.kind == .artist)
            }
            .buttonStyle(.plain)
        }
    }

    private func content(title: String, subtitle: String, coverURL: URL?, round: Bool) -> some View {
        HStack(spacing: 20) {
            NativeCoverView(url: coverURL, targetPixels: 300)
                .frame(width: 108, height: 108)
                .clipShape(round
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(FoliaTheme.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(FoliaTheme.primary.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 24))
        .background(FoliaTheme.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(Rectangle())
    }
}
