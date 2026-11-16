import SwiftUI

// CollectionView.swift
//
// 集合页：按 port-spec-lattice-collection.md 移植 grid 套件的 GridView
// （移动端形态：顶部胶囊 + 玻璃信息面板 + 拍立得卡片两列滚动网格；
// 源码的自由平移画布在触屏滚动网格下不成立，见移植报告偏差清单）。
// 分页照规格：首屏 150 首先出，后台每页 1000 首续拉，右上胶囊报进度。
// 点歌语义照规格：卡播放键 = 以当前已加载全表为队列从该曲播；
// 「+」= 单首追加不打断；播放全部 = 整单从头；加入队列 = 整单追加队尾。

struct CollectionView: View {
    let collection: ExploreCollection

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var engine = PlaybackEngine.shared

    @State private var headerName: String
    @State private var coverURL: URL?
    @State private var creatorName: String?
    @State private var creatorAvatarURL: URL?
    @State private var playCount: Int?
    @State private var totalCount = 0
    @State private var descriptionText: String?
    @State private var albumExtraLines: [String] = []
    @State private var tracks: [FoliaTrack] = []
    @State private var phase: Phase = .loading
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    @State private var favoriteHint: String?
    @State private var panelAppeared = false

    /// 歌单全量 id（去重保序）与已消费到的位置，续拉/重试共用。
    @State private var allIds: [Int] = []
    @State private var loadedThrough = 0

    private enum Phase {
        case loading
        case ready
        case failed
    }

    private static let firstScreen = 150
    private static let pageSize = 1000

    init(collection: ExploreCollection) {
        self.collection = collection
        _headerName = State(initialValue: collection.name)
        _coverURL = State(initialValue: collection.coverURL)
    }

    var body: some View {
        ZStack(alignment: .top) {
            FoliaTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    infoPanel

                    switch phase {
                    case .loading:
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(FoliaTheme.primary)
                            Text("加载中")
                                .font(.system(size: 12))
                                .foregroundColor(FoliaTheme.primary.opacity(0.6))
                        }
                        .padding(.top, 40)
                    case .failed:
                        VStack(spacing: 12) {
                            Text("加载失败")
                                .font(.system(size: 14))
                                .foregroundColor(FoliaTheme.primary.opacity(0.6))
                            Button("重试") { Task { await load() } }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(FoliaTheme.primary)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .overlay(Capsule().stroke(FoliaTheme.primary.opacity(0.12), lineWidth: 1))
                        }
                        .padding(.top, 40)
                    case .ready:
                        trackGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 72)
                .padding(.bottom, 32)
            }

            capsules
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if phase == .loading { await load() }
        }
    }

    // MARK: - 顶部胶囊

    private var capsules: some View {
        ZStack {
            // 中央标题胶囊（18 bold、背景色 20% 底 + blur、rounded-2xl）。
            Text(headerName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(FoliaTheme.primary)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Rectangle().fill(FoliaTheme.background.opacity(0.2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: 200)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FoliaTheme.primary)
                        .frame(width: 32, height: 32)
                        .background {
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                Circle().fill(FoliaTheme.background.opacity(0.35))
                            }
                        }
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                Spacer()

                syncCapsule
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// 右上同步胶囊：「已加载 X / Y」（tabular-nums），续拉出错追加「重试」。
    private var syncCapsule: some View {
        Button {
            if loadMoreFailed { Task { await continueLoading() } }
        } label: {
            HStack(spacing: 5) {
                if isLoadingMore || phase == .loading {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isLoadingMore || phase == .loading ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false),
                                   value: isLoadingMore)
                }
                Text("已加载 \(tracks.count) / \(totalCount)")
                    .font(.system(size: 12).monospacedDigit())
                if loadMoreFailed {
                    Text("重试")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(FoliaTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(FoliaTheme.background.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 信息面板

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 封面整宽正方形 + 右下收藏星。
            ZStack(alignment: .bottomTrailing) {
                NativeCoverView(url: coverURL, targetPixels: 700)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button {
                    favoriteTapped()
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.5))
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityLabel("收藏歌单")
            }

            Text(headerName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(FoliaTheme.primary)
                .lineLimit(2)
                .padding(.top, 16)

            if let creatorName {
                HStack(spacing: 6) {
                    NativeCoverView(url: creatorAvatarURL, targetPixels: 100)
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                    Text(creatorName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FoliaTheme.primary.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.top, 8)
            }

            Text(metaLine)
                .font(.system(size: 10))
                .foregroundColor(FoliaTheme.primary.opacity(0.4))
                .padding(.top, 6)

            ForEach(albumExtraLines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12))
                    .foregroundColor(FoliaTheme.primary.opacity(0.6))
                    .padding(.top, 4)
            }

            if let descriptionText, !descriptionText.isEmpty {
                ScrollView {
                    Text(descriptionText)
                        .font(.system(size: 12))
                        .foregroundColor(FoliaTheme.primary.opacity(0.65))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(.top, 8)
            }

            Rectangle()
                .fill(FoliaTheme.primary.opacity(0.12))
                .frame(height: 1)
                .padding(.top, 16)

            VStack(spacing: 8) {
                Button {
                    playAll()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                        Text("播放全部")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(FoliaTheme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FoliaTheme.primary)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
                .opacity(tracks.isEmpty ? 0.4 : 1)

                Button {
                    QueueManager.shared.appendToQueue(tracks)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 14))
                        Text("加入队列")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(FoliaTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(FoliaTheme.primary.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
                .opacity(tracks.isEmpty ? 0.4 : 1)

                if let favoriteHint {
                    Text(favoriteHint)
                        .font(.system(size: 12))
                        .foregroundColor(FoliaTheme.primary.opacity(0.6))
                        .padding(.top, 2)
                }
            }
            .padding(.top, 16)
        }
        .padding(24)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FoliaTheme.background.opacity(0.55))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        .offset(x: panelAppeared ? 0 : -60)
        .scaleEffect(panelAppeared ? 1 : 0.95)
        .opacity(panelAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { panelAppeared = true }
        }
    }

    private var metaLine: String {
        var line = "\(totalCount) 首"
        if let playCount {
            line += " • \(Self.formatPlayCount(playCount)) 次播放"
        }
        return line
    }

    static func formatPlayCount(_ count: Int) -> String {
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }

    /// 收藏依赖登录（omni 能力位把门）：登录未接，只给诚实提示，不做假动作。
    private func favoriteTapped() {
        favoriteHint = "登录还没接上，收藏暂时用不了"
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            favoriteHint = nil
        }
    }

    // MARK: - 拍立得卡片网格

    private var trackGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 20) {
            ForEach(tracks) { track in
                PolaroidCard(track: track,
                             isCurrent: queueManager.currentTrack?.id == track.id,
                             isPlaying: engine.isPlaying,
                             onPlay: { playFrom(track) },
                             onToggle: { engine.togglePlayPause() },
                             onAppend: { QueueManager.shared.appendToQueue([track]) })
            }
        }
    }

    // MARK: - 播放语义

    private func playAll() {
        guard !tracks.isEmpty else { return }
        QueueManager.shared.setQueue(tracks, startingAt: 0)
        NativeBrowseView.openFullPlayer()
    }

    private func playFrom(_ track: FoliaTrack) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        QueueManager.shared.setQueue(tracks, startingAt: index)
        NativeBrowseView.openFullPlayer()
    }

    // MARK: - 加载

    private func load() async {
        phase = .loading
        loadMoreFailed = false
        switch collection.kind {
        case .album:
            await loadAlbum()
        case .playlist, .artist:
            await loadPlaylist()
        }
    }

    private func loadPlaylist() async {
        do {
            let detail = try await EdgeOneAPIClient.shared.fetchPlaylistDetail(
                playlistId: String(collection.id))
            headerName = detail.name
            coverURL = detail.coverURL ?? coverURL
            creatorName = detail.creator?.nickname
            creatorAvatarURL = detail.creatorAvatarURL
            playCount = detail.playCount
            descriptionText = detail.description

            // 按 key 去重保序（规格）。
            var seen = Set<Int>()
            let ids = detail.trackIdList.filter { seen.insert($0).inserted }
            allIds = ids
            totalCount = ids.count

            var byId: [Int: FoliaTrack] = [:]
            for track in detail.prefetchedTracks {
                byId[Self.numericId(of: track)] = track
            }
            let firstIds = Array(ids.prefix(Self.firstScreen))
            let missing = firstIds.filter { byId[$0] == nil }
            if !missing.isEmpty {
                let fetched = try await EdgeOneAPIClient.shared.fetchSongDetails(ids: missing)
                for track in fetched {
                    byId[Self.numericId(of: track)] = track
                }
            }
            tracks = firstIds.compactMap { byId[$0] }
            loadedThrough = firstIds.count
            phase = .ready
            Task { await continueLoading() }
        } catch {
            phase = .failed
        }
    }

    /// 后台续拉：每页 1000 首，进度由胶囊的 tracks.count 实时反映；
    /// 失败停在原地，点胶囊重试续拉。
    private func continueLoading() async {
        guard collection.kind == .playlist, !isLoadingMore,
              loadedThrough < allIds.count else { return }
        isLoadingMore = true
        loadMoreFailed = false
        while loadedThrough < allIds.count {
            let page = Array(allIds[loadedThrough..<min(loadedThrough + Self.pageSize, allIds.count)])
            do {
                let fetched = try await EdgeOneAPIClient.shared.fetchSongDetails(ids: page)
                tracks.append(contentsOf: fetched)
                loadedThrough += page.count
            } catch {
                loadMoreFailed = true
                break
            }
        }
        isLoadingMore = false
    }

    private func loadAlbum() async {
        do {
            let detail = try await EdgeOneAPIClient.shared.fetchAlbumDetail(
                albumId: String(collection.id))
            headerName = detail.info.name
            coverURL = detail.coverURL ?? coverURL
            descriptionText = detail.info.description
            var extras: [String] = []
            if !detail.artistLabel.isEmpty { extras.append(detail.artistLabel) }
            let publishLine = [detail.publishDateText, detail.info.company]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            if !publishLine.isEmpty { extras.append(publishLine) }
            albumExtraLines = extras
            tracks = detail.tracks
            totalCount = detail.info.size ?? detail.tracks.count
            allIds = []
            loadedThrough = 0
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    private static func numericId(of track: FoliaTrack) -> Int {
        Int(track.id.replacingOccurrences(of: "ncm_", with: "")) ?? -1
    }
}

// MARK: - 拍立得卡

private struct PolaroidCard: View {
    let track: FoliaTrack
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onToggle: () -> Void
    let onAppend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                NativeCoverView(url: track.artworkURL, targetPixels: 300)
                    .aspectRatio(1, contentMode: .fill)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if track.isMarkedUnplayable {
                    Text("不可播")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FoliaTheme.primary.opacity(0.9))
                    .lineLimit(4)
                Text(track.artist)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(FoliaTheme.primary.opacity(0.55))
                    .lineLimit(3)
                HStack(alignment: .bottom, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.album)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(FoliaTheme.primary.opacity(0.35))
                            .lineLimit(2)
                        Text(formatDuration(track.duration))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(FoliaTheme.primary.opacity(0.35))
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 10) {
                        Button {
                            if isCurrent { onToggle() } else { onPlay() }
                        } label: {
                            Image(systemName: isCurrent && isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15))
                                .foregroundColor(FoliaTheme.primary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(track.isMarkedUnplayable)
                        .opacity(track.isMarkedUnplayable ? 0.3 : 1)
                        .accessibilityLabel(isCurrent ? "暂停/继续" : "播放")

                        Button {
                            onAppend()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15))
                                .foregroundColor(FoliaTheme.primary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(track.isMarkedUnplayable)
                        .opacity(track.isMarkedUnplayable ? 0.3 : 1)
                        .accessibilityLabel("加入队列")
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 12)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FoliaTheme.primary.opacity(0.05), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
