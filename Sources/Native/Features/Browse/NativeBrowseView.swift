import SwiftUI

/// 原生浏览面（3.3 第二/三步；3.4 按计划复刻 Folia 原版视觉）。
/// 视觉口径 = Folia 网页版默认主题（baseThemes 的 Midnight Default）：
/// 背景 #09090b、主文字 #f4f4f5、次级 #71717a、封面主导排版、深色全局。
/// 实现换原生，样子和用法保持 Folia 原样——这是计划，不是新设计。
/// 数据走 EdgeOneAPIClient，点歌直进 QueueManager 原生队列。
struct NativeBrowseView: View {
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .preferredColorScheme(.dark)
        // 底部给原生迷你条让位（迷你条是壳层浮层，不在 SwiftUI 布局内）。
        .safeAreaInset(edge: .bottom) {
            if engine.currentTrack != nil {
                Color.clear.frame(height: 80)
            }
        }
    }

    static func openFullPlayer() {
        RenderStateCenter.shared.setFullPlayerOpen(true)
    }
}

/// Folia 默认主题色板（Midnight Default，folia-major/src/services/baseThemes.ts）。
enum FoliaTheme {
    static let background = Color(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255)
    static let primary = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255)
    static let secondary = Color(red: 0x71 / 255, green: 0x71 / 255, blue: 0x7A / 255)
    static let card = Color.white.opacity(0.06)
    static let field = Color.white.opacity(0.09)
}

// MARK: - 主页

private struct HomeView: View {
    @State private var toplist: [PlaylistSummary] = []
    @State private var personalized: [PlaylistSummary] = []
    @State private var toplistFailed = false
    @State private var personalizedFailed = false
    @State private var isLoading = true

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                // 顶部：品牌 + 搜索入口（照网页版的克制排版，不用系统大标题栏）。
                VStack(alignment: .leading, spacing: 16) {
                    Text("Folia")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(FoliaTheme.primary)

                    NavigationLink {
                        SearchView()
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
                    }
                    .buttonStyle(.plain)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(FoliaTheme.primary)
                        Spacer()
                    }
                    .padding(.top, 48)
                } else {
                    if !toplist.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("排行榜")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(toplist.prefix(12)) { item in
                                        NavigationLink {
                                            PlaylistView(summary: item)
                                        } label: {
                                            playlistCard(item, width: 138)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if !personalized.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("推荐歌单")
                            LazyVGrid(columns: gridColumns, spacing: 18) {
                                ForEach(personalized) { item in
                                    NavigationLink {
                                        PlaylistView(summary: item)
                                    } label: {
                                        playlistCard(item, width: nil)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if toplist.isEmpty && personalized.isEmpty {
                        VStack(spacing: 10) {
                            Text("加载失败，检查网络后再试")
                                .foregroundColor(FoliaTheme.secondary)
                            Button("重试") { Task { await load() } }
                                .foregroundColor(FoliaTheme.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(FoliaTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if isLoading { await load() }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .bold))
            .foregroundColor(FoliaTheme.primary)
    }

    private func playlistCard(_ item: PlaylistSummary, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            NativeCoverView(url: item.coverURL, targetPixels: 400)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(item.name)
                .font(.caption)
                .foregroundColor(FoliaTheme.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if item.trackCount > 0 {
                Text("\(item.trackCount) 首")
                    .font(.caption2)
                    .foregroundColor(FoliaTheme.secondary)
            }
        }
        .frame(width: width)
    }

    private func load() async {
        isLoading = true
        // 两路独立：一路失败不拖垮另一路。
        async let tops = try? EdgeOneAPIClient.shared.fetchToplist()
        async let recs = try? EdgeOneAPIClient.shared.fetchPersonalizedPlaylists(limit: 30)
        toplist = await tops ?? []
        personalized = await recs ?? []
        toplistFailed = toplist.isEmpty
        personalizedFailed = personalized.isEmpty
        isLoading = false
    }
}

// MARK: - 歌单页

private struct PlaylistView: View {
    let summary: PlaylistSummary

    @ObservedObject private var queueManager = QueueManager.shared
    @State private var tracks: [FoliaTrack] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            FoliaTheme.background.ignoresSafeArea()

            if isLoading && tracks.isEmpty {
                ProgressView()
                    .tint(FoliaTheme.primary)
            } else if loadFailed && tracks.isEmpty {
                VStack(spacing: 10) {
                    Text("歌单加载失败")
                        .foregroundColor(FoliaTheme.secondary)
                    Button("重试") { Task { await load() } }
                        .foregroundColor(FoliaTheme.primary)
                }
            } else {
                List {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            trackRow(index: index, track: track)
                        }
                    } header: {
                        playlistHeader
                    }
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(FoliaTheme.primary)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FoliaTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if isLoading { await load() }
        }
    }

    private var playlistHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                NativeCoverView(url: summary.coverURL, targetPixels: 500)
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    Text(summary.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(FoliaTheme.primary)
                        .lineLimit(3)
                    Text("\(tracks.count) 首")
                        .font(.caption)
                        .foregroundColor(FoliaTheme.secondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                QueueManager.shared.setQueue(tracks, startingAt: 0)
                NativeBrowseView.openFullPlayer()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("播放全部")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(FoliaTheme.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }

    private func trackRow(index: Int, track: FoliaTrack) -> some View {
        let isCurrent = queueManager.currentTrack?.id == track.id
        return Button {
            QueueManager.shared.setQueue(tracks, startingAt: index)
            NativeBrowseView.openFullPlayer()
        } label: {
            HStack(spacing: 12) {
                NativeCoverView(url: track.artworkURL, targetPixels: 150)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.subheadline.weight(isCurrent ? .bold : .regular))
                        .foregroundColor(isCurrent ? FoliaTheme.primary : FoliaTheme.primary.opacity(0.92))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundColor(FoliaTheme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(FoliaTheme.primary)
                        .font(.caption)
                } else {
                    Text(formatDuration(track.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(FoliaTheme.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    /// 渐进加载：detail 自带的曲目先渲染，其余 id 走并行分片补齐，
    /// 不再全部取齐才出列表（3.3 白屏转圈的教训）。
    private func load() async {
        loadFailed = false
        do {
            let detail = try await EdgeOneAPIClient.shared.fetchPlaylistDetail(
                playlistId: String(summary.id))
            let ids = detail.trackIdList
            var byId: [Int: FoliaTrack] = [:]
            for track in detail.prefetchedTracks {
                byId[numericId(of: track)] = track
            }
            let firstBatch = ids.compactMap { byId[$0] }
            if !firstBatch.isEmpty {
                tracks = firstBatch
                isLoading = false
            }
            let missing = ids.filter { byId[$0] == nil }
            if !missing.isEmpty {
                let fetched = try await EdgeOneAPIClient.shared.fetchSongDetails(ids: missing)
                for track in fetched {
                    byId[numericId(of: track)] = track
                }
                tracks = ids.compactMap { byId[$0] }
            }
            if tracks.isEmpty { loadFailed = true }
        } catch {
            if tracks.isEmpty { loadFailed = true }
        }
        isLoading = false
    }

    private func numericId(of track: FoliaTrack) -> Int {
        Int(track.id.replacingOccurrences(of: "ncm_", with: "")) ?? -1
    }
}

// MARK: - 搜索

private struct SearchView: View {
    @State private var keyword = ""
    @State private var results: [FoliaTrack] = []
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        ZStack {
            FoliaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(FoliaTheme.secondary)
                        TextField("搜索歌曲 / 歌手", text: $keyword)
                            .foregroundColor(FoliaTheme.primary)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(FoliaTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button("搜索") { Task { await search() } }
                        .foregroundColor(FoliaTheme.primary)
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)

                if isSearching {
                    Spacer()
                    ProgressView()
                        .tint(FoliaTheme.primary)
                    Spacer()
                } else if searchFailed {
                    Spacer()
                    Text("搜索失败，检查网络后再试")
                        .foregroundColor(FoliaTheme.secondary)
                    Spacer()
                } else if hasSearched && results.isEmpty {
                    Spacer()
                    Text("没有找到结果")
                        .foregroundColor(FoliaTheme.secondary)
                    Spacer()
                } else {
                    List {
                        if !results.isEmpty {
                            Button {
                                QueueManager.shared.setQueue(results, startingAt: 0)
                                NativeBrowseView.openFullPlayer()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                    Text("播放全部结果")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(FoliaTheme.primary)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                        ForEach(results) { track in
                            Button {
                                QueueManager.shared.insertAndPlay(track)
                                NativeBrowseView.openFullPlayer()
                            } label: {
                                HStack(spacing: 12) {
                                    NativeCoverView(url: track.artworkURL, targetPixels: 150)
                                        .frame(width: 46, height: 46)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .font(.subheadline)
                                            .foregroundColor(FoliaTheme.primary)
                                            .lineLimit(1)
                                        Text("\(track.artist) · \(track.album)")
                                            .font(.caption)
                                            .foregroundColor(FoliaTheme.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.white.opacity(0.08))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FoliaTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func search() async {
        let query = keyword.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        searchFailed = false
        do {
            results = try await EdgeOneAPIClient.shared.searchSongs(keywords: query, limit: 30)
            hasSearched = true
        } catch {
            searchFailed = true
        }
        isSearching = false
    }
}

private func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}
