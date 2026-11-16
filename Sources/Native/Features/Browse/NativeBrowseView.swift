import SwiftUI

/// 原生浏览面（3.3 第二/三步）：主页（排行榜 + 推荐歌单）/ 歌单页 / 搜索。
/// 取代原 WKWebView 浏览面：网页只剩播放页里的特效画布，浏览、点歌、队列
/// 全在原生。数据走 EdgeOneAPIClient（Netlify 同源代理），点歌直接进
/// QueueManager 原生队列，不再经桥绕行。
struct NativeBrowseView: View {
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        NavigationStack {
            HomeView()
        }
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

// MARK: - 主页

private struct HomeView: View {
    @State private var toplist: [PlaylistSummary] = []
    @State private var personalized: [PlaylistSummary] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NavigationLink {
                    SearchView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("搜索歌曲")
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("加载中…")
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if loadFailed {
                    VStack(spacing: 10) {
                        Text("加载失败，检查网络后再试")
                            .foregroundColor(.secondary)
                        Button("重试") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    if !toplist.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("排行榜")
                                .font(.title3.weight(.bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(toplist.prefix(12)) { item in
                                        NavigationLink {
                                            PlaylistView(summary: item)
                                        } label: {
                                            playlistCard(item, width: 128)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if !personalized.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("推荐歌单")
                                .font(.title3.weight(.bold))
                            LazyVGrid(columns: gridColumns, spacing: 16) {
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
                }
            }
            .padding(16)
        }
        .navigationTitle("Folia")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if isLoading { await load() }
        }
    }

    private func playlistCard(_ item: PlaylistSummary, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeCoverView(url: item.coverURL, targetPixels: 300)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if item.trackCount > 0 {
                Text("\(item.trackCount) 首")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        async let tops = EdgeOneAPIClient.shared.fetchToplist()
        async let recs = EdgeOneAPIClient.shared.fetchPersonalizedPlaylists(limit: 30)
        do {
            toplist = try await tops
            personalized = try await recs
            if toplist.isEmpty && personalized.isEmpty { loadFailed = true }
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

// MARK: - 歌单页

private struct PlaylistView: View {
    let summary: PlaylistSummary

    @State private var tracks: [FoliaTrack] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载歌单…")
            } else if loadFailed {
                VStack(spacing: 10) {
                    Text("歌单加载失败")
                        .foregroundColor(.secondary)
                    Button("重试") { Task { await load() } }
                }
            } else {
                List {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                QueueManager.shared.setQueue(tracks, startingAt: index)
                                NativeBrowseView.openFullPlayer()
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundColor(.secondary)
                                        .frame(width: 30, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(formatDuration(track.duration))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 14) {
                                NativeCoverView(url: summary.coverURL, targetPixels: 500)
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(summary.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                    Text("\(tracks.count) 首")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .textCase(nil)
                        .padding(.bottom, 6)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isLoading { await load() }
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            let detail = try await EdgeOneAPIClient.shared.fetchPlaylistDetail(
                playlistId: String(summary.id))
            let ids = detail.trackIdList
            var byId: [Int: FoliaTrack] = [:]
            for track in detail.prefetchedTracks {
                if let numeric = Int(track.id.replacingOccurrences(of: "ncm_", with: "")) {
                    byId[numeric] = track
                }
            }
            let missing = ids.filter { byId[$0] == nil }
            if !missing.isEmpty {
                for track in try await EdgeOneAPIClient.shared.fetchSongDetails(ids: missing) {
                    if let numeric = Int(track.id.replacingOccurrences(of: "ncm_", with: "")) {
                        byId[numeric] = track
                    }
                }
            }
            tracks = ids.compactMap { byId[$0] }
            if tracks.isEmpty { loadFailed = true }
        } catch {
            loadFailed = true
        }
        isLoading = false
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索歌曲 / 歌手", text: $keyword)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button("搜索") { Task { await search() } }
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)

            if isSearching {
                Spacer()
                ProgressView("搜索中…")
                Spacer()
            } else if searchFailed {
                Spacer()
                Text("搜索失败，检查网络后再试")
                    .foregroundColor(.secondary)
                Spacer()
            } else if hasSearched && results.isEmpty {
                Spacer()
                Text("没有找到结果")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    if !results.isEmpty {
                        Section {
                            Button {
                                QueueManager.shared.setQueue(results, startingAt: 0)
                                NativeBrowseView.openFullPlayer()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                    Text("播放全部结果")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    Section {
                        ForEach(results) { track in
                            Button {
                                QueueManager.shared.insertAndPlay(track)
                                NativeBrowseView.openFullPlayer()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("\(track.artist) · \(track.album)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
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
