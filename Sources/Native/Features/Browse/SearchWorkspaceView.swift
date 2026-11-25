import SwiftUI
import UIKit

/// 搜索结果中的集合条目（专辑 / 歌单）。点整行经 onOpenCollection 交协调者开集合页，
/// 本视图不直接管导航。
struct SearchCollection: Identifiable {
    enum Kind {
        case album
        case playlist
    }

    let id: Int
    let kind: Kind
    let name: String
    let coverURL: URL?
    /// 专辑 = 歌手名；歌单 = 创建者昵称。
    let ownerName: String
    /// 专辑 = 发行年份；歌单 = nil。
    let year: Int?
    /// 歌单 = 播放量（原始计数）；专辑 = nil。
    let playCount: Int?
    let trackCount: Int
}

/// 搜索页（SearchWorkspace）原生移植（移植规格 port-spec-search-player.md 第一节）。
///
/// 形态照 folia-major 源码（SearchWorkspace / SearchTabs / SearchResultRow /
/// SearchCollectionRow / search.css）：全屏覆盖层（dark rgba(8,8,10,0.94) + blur 24）、
/// 无边框仅底部 2px 线的搜索框、来源排、种类排、状态行、结果行、底部加载更多。
/// 本轮只有网易云可达（QQ search 接口回 400、酷狗形状未核对，见 EdgeOneAPIClient 注释），
/// 来源排只列网易云。专辑 / 歌单走代理 /search 的 type=10 / 1000（实测支持，见交付报告）。
/// 点单曲行 = 以当前结果整列为队列播放该曲：默认实现直接调 QueueManager（沿现有
/// 搜索页 SearchView 的接法），协调者也可注入 onPlaySong 覆盖。
struct SearchWorkspaceView: View {
    var onClose: () -> Void = {}
    var onPlaySong: (FoliaTrack, [FoliaTrack]) -> Void = { song, queue in
        QueueManager.shared.setQueue(
            queue, startingAt: queue.firstIndex { $0.id == song.id } ?? 0)
    }
    var onOpenCollection: (SearchCollection) -> Void = { _ in }

    private enum SearchKind: Int, CaseIterable {
        case song, album, playlist

        var label: String {
            switch self {
            case .song: return "单曲"
            case .album: return "专辑"
            case .playlist: return "歌单"
            }
        }

        var placeholder: String {
            switch self {
            case .song: return "搜索歌曲..."
            case .album: return "搜索专辑..."
            case .playlist: return "搜索歌单..."
            }
        }

        /// 网易云 /search 的 type 参数（cloudsearch 口径：1 单曲 / 10 专辑 / 1000 歌单）。
        var apiType: Int {
            switch self {
            case .song: return 1
            case .album: return 10
            case .playlist: return 1000
            }
        }
    }

    private struct SongItem: Identifiable {
        let track: FoliaTrack
        /// status < 0（已下架）：整行 opacity 0.5 禁点，标签「已下架」。
        let isUnavailable: Bool
        /// mvid != 0：标签「MV」。
        let hasVideo: Bool
        var id: String { track.id }
    }

    /// 速记簿（(53) 工作流 D）：行尾按钮的已收/未收视觉态随它刷新。
    @ObservedObject private var sketchbookStore = SketchbookStore.shared
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var kind: SearchKind = .song
    @State private var songs: [SongItem] = []
    @State private var collections: [SearchCollection] = []
    @State private var totalCount = 0
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var searchFailed = false
    /// 行入场动画开关（从左滑入、按序 32ms 递延、上限 12 行）。
    @State private var entered = false
    /// 搜索代际：快速连搜时过期结果直接丢弃。
    @State private var searchGeneration = 0
    /// 星标刷新代次（(55) 工作流 F）：订阅 FoliaStarChanged 后
    /// 自增，强制行重算 StarStore 显态（他面切换星标也同步）。
    @State private var starRefreshTick = 0
    /// 「收藏到歌单」弹层的目标歌曲（(55) 工作流 F）：加号点按
    /// 置入后由 sheet 呈 AddToPlaylistViewController。
    @State private var addTarget: SongItem?
    /// 搜索框前置小方块的旋转角（搜索中旋转成菱形代替 spinner）。
    @State private var markRotation: Double = 0
    /// (62) §3 来源范围：网易云恒开，QQ/酷狗为多选开关
    /// （SettingsStore62D 两键持久化）。
    @State private var qqEnabled62 = SettingsStore.searchProviderQQEnabled62
    @State private var kugouEnabled62 = SettingsStore.searchProviderKugouEnabled62
    /// (62) 各来源聚合注记（失败诚实空态的说明行）。
    @State private var providerNotes62: [String] = []
    /// (62) §7 批量收进：多选态与已选集（行长按进入）。
    @State private var selecting62 = false
    @State private var selectedIds62: Set<String> = []

    @FocusState private var fieldFocused: Bool

    private let pageSize = 30

    // 搜索令牌（search.css）：ink = 主色、accent = 强调色（Midnight 下同为 #f4f4f5）、
    // paper dark = #08080a、发丝线 = ink 9%。
    private var ink: Color { FoliaTheme.primary }
    private var accent: Color { FoliaTheme.primary }
    private var paper: Color { Color(red: 0x08 / 255, green: 0x08 / 255, blue: 0x0A / 255) }
    private var hairline: Color { ink.opacity(0.09) }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            paper.opacity(0.94).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                resultsArea
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            // (62) §7 多选底栏：收进速记簿（addBatch）/ 加入
            // 队列 / 取消。收进后退出多选态并 toast 回执。
            if selecting62 {
                VStack {
                    Spacer()
                    HStack(spacing: 18) {
                        Text("已选 \(selectedIds62.count) 首")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ink)
                        Spacer()
                        Button("收进速记簿") {
                            let picked = songs.map(\.track)
                                .filter { selectedIds62.contains($0.id) }
                            let added = sketchbookStore.addBatch(picked, source: "search")
                            Breadcrumbs.log("search62.batch sketchbook added=\(added)")
                            NativePlaybackFailureToast.show(
                                message: "已收进速记簿 \(added) 首")
                            selecting62 = false
                            selectedIds62 = []
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ink)
                        Button("加入队列") {
                            let picked = songs.map(\.track)
                                .filter { selectedIds62.contains($0.id) }
                            QueueManager.shared.appendToQueue(picked)
                            NativePlaybackFailureToast.show(message: "已加入播放队列")
                            selecting62 = false
                            selectedIds62 = []
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ink)
                        Button("取消") {
                            selecting62 = false
                            selectedIds62 = []
                        }
                        .font(.system(size: 13))
                        .foregroundColor(FoliaTheme.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(paper.opacity(0.97))
                    .overlay(Rectangle().fill(hairline).frame(height: 1),
                             alignment: .top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .foliaStarChanged)) { _ in
            starRefreshTick += 1
        }
        .sheet(item: $addTarget) { item in
            AddToPlaylistSheet(track: item.track)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: isSearching) { _, busy in
            // 前置方块：搜索中 1100ms 一周旋转（search.css search-mark-busy 的近似）。
            if busy {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    markRotation = 180
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { markRotation = 0 }
            }
        }
    }

    /// (62) 来源多选片：勾选态以方块+下划线示之（与来源排同语言）。
    private func providerToggle62(title: String, isOn: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(13 * 0.06)
                }
                .foregroundColor(isOn ? ink : FoliaTheme.secondary)
                Rectangle().fill(isOn ? accent : Color.clear).frame(height: 3)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 头部（搜索框 + 来源排 + 种类排 + 状态行，gap 20）

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            // (62) §3 面包屑行（网页同位）。
            Text("书库 › 搜索")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FoliaTheme.secondary)
            // (62) §3 说明文案（底账 §3 网页原话）。
            Text("联网搜索…结果在搜索页打开、不会收窄当前墙")
                .font(.system(size: 12))
                .foregroundColor(FoliaTheme.secondary)
            // 搜索框行：方块 + 输入（22px/700、仅底部 2px ink 线）+ 关闭 X（44×44、1.5px ink 边）。
            HStack(spacing: 16) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(markRotation))
                        TextField(kind.placeholder, text: $query)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(ink)
                            .focused($fieldFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit { submitSearch() }
                    }
                    .padding(.bottom, 10)
                    Rectangle().fill(ink).frame(height: 2)
                }

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20))
                        .foregroundColor(ink)
                        .frame(width: 44, height: 44)
                        .background(paper)
                        .overlay(Rectangle().stroke(ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

            // 来源排（13px/700/字距 0.06em，选中底部 3px 强调条）：
            // (62) §3 改多选——网易云恒开，QQ/酷狗可勾选聚合。
            HStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("网易云")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(13 * 0.06)
                        .foregroundColor(ink)
                    Rectangle().fill(accent).frame(height: 3)
                }
                .fixedSize()
                providerToggle62(title: "QQ 音乐", isOn: qqEnabled62) {
                    qqEnabled62.toggle()
                    SettingsStore.searchProviderQQEnabled62 = qqEnabled62
                    if !submittedQuery.isEmpty { submitSearch() }
                }
                providerToggle62(title: "酷狗", isOn: kugouEnabled62) {
                    kugouEnabled62.toggle()
                    SettingsStore.searchProviderKugouEnabled62 = kugouEnabled62
                    if !submittedQuery.isEmpty { submitSearch() }
                }
            }
            if !providerNotes62.isEmpty {
                Text(providerNotes62.joined(separator: "；"))
                    .font(.system(size: 11))
                    .foregroundColor(FoliaTheme.secondary)
            }

            // 种类排（序号 11px 等宽 + 标签 22px/900，选中前 11×11 强调方块）。
            // (89) §10-1：种类签间距对齐网页 28。
            HStack(spacing: 28) {
                ForEach(Array(SearchKind.allCases.enumerated()), id: \.offset) { index, item in
                    Button {
                        guard item != kind else { return }
                        kind = item
                        if !submittedQuery.isEmpty { submitSearch() }
                    } label: {
                        HStack(spacing: 8) {
                            if item == kind {
                                Rectangle().fill(accent).frame(width: 11, height: 11)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(FoliaTheme.secondary)
                                Text(item.label)
                                    .font(.system(size: 22, weight: .black))
                            }
                        }
                        .foregroundColor(item == kind ? ink : ink.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 状态行（11px 等宽 600、字距 0.1em：来源名 + 结果数 + 发丝线延伸）。
            HStack(spacing: 12) {
                Text("网易云")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(11 * 0.1)
                if hasSearched, !isSearching, totalCount > 0 {
                    Text("共 \(totalCount) 条")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(11 * 0.1)
                }
                Rectangle().fill(hairline).frame(height: 1)
            }
            .foregroundColor(ink.opacity(0.6))
        }
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultsArea: some View {
        if isSearching {
            // 搜索中：加载动画整体替换列表（源码分支 isSearching 优先于结果判断；
            // 加载更多不置 isSearching，不受影响）。
            SearchLoaderShapes(ink: ink, accent: accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchFailed && currentResultCount == 0 {
            voidState(text: "搜索失败，请重试。", showRetry: true)
        } else if currentResultCount == 0 {
            // 含未搜初始态：源码分支即 resultCount == 0 → 空态（home.noResults）。
            // 贴纸层（3.7 (24)，纯新增）：真搜过且无结果时出猫
            // 贴纸，未搜初始态不出（sticker 传 hasSearched）。
            voidState(text: "未找到相关结果", showRetry: false, sticker: hasSearched)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if kind == .song {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, item in
                            songRow(index: index, item: item)
                        }
                    } else {
                        ForEach(Array(collections.enumerated()), id: \.element.id) { index, item in
                            collectionRow(index: index, item: item)
                        }
                    }

                    if canLoadMore {
                        loadMoreButton
                    }
                }
            }
        }
    }

    private var currentResultCount: Int {
        kind == .song ? songs.count : collections.count
    }

    private var canLoadMore: Bool {
        hasSearched && !isSearching && currentResultCount > 0 && currentResultCount < totalCount
    }

    private var loadMoreButton: some View {
        Button {
            guard !isLoadingMore else { return }
            isLoadingMore = true
            let generation = searchGeneration
            let offset = currentResultCount
            Task { await performSearch(generation: generation, offset: offset) }
        } label: {
            HStack(spacing: 10) {
                if isLoadingMore {
                    ProgressView().tint(ink)
                }
                Text("加载更多")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ink)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 40)
            .overlay(Rectangle().stroke(ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// 空 / 错误态：88px 空心圆（2px ink 边、opacity 0.4）+ 强调色斜杠（124×6、-32°）。
    /// sticker 为真时（3.7 (24) 新增，搜索无结果专用）在圆圈上方
    /// 出 cat-02（举手无果）90pt，播一次停末帧；错误态不传。
    private func voidState(text: String, showRetry: Bool, sticker: Bool = false) -> some View {
        VStack(spacing: 24) {
            if sticker {
                StickerViewRepresentable(asset: "cat-02", mode: .once(holdLast: true))
                    .frame(width: 90, height: 90)
            }
            ZStack {
                Circle()
                    .stroke(ink.opacity(0.4), lineWidth: 2)
                    .frame(width: 88, height: 88)
                Rectangle()
                    .fill(accent)
                    .frame(width: 124, height: 6)
                    .rotationEffect(.degrees(-32))
            }
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ink.opacity(showRetry ? 0.7 : 0.6))
            if showRetry {
                Button { submitSearch() } label: {
                    Text("重试")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ink)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 40)
                        .overlay(Rectangle().stroke(ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 单曲行（高 76）

    private func songRow(index: Int, item: SongItem) -> some View {
        // (62) 多选态行首选中标（渲染在行容器外层 HStack 前导）。
        let track = item.track
        // 读一次星标代次，把 FoliaStarChanged 的刷新依赖挂到行渲染上。
        _ = starRefreshTick
        return HStack(spacing: 14) {
            if selecting62 {
                Image(systemName: selectedIds62.contains(item.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selectedIds62.contains(item.id)
                                     ? ink : FoliaTheme.secondary)
                    .frame(width: 20, alignment: .leading)
            } else {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(FoliaTheme.secondary)
                    // (89) §10-2：序号列宽对齐网页 28。
                    .frame(width: 28, alignment: .leading)
            }

            NativeCoverView(url: track.artworkURL, targetPixels: 150)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ink)
                        .lineLimit(1)
                    if let tag = item.isUnavailable ? "已下架" : (item.hasVideo ? "MV" : nil) {
                        Text(tag)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(ink.opacity(0.2), lineWidth: 1))
                            .opacity(0.6)
                    }
                }
                Text(track.album.isEmpty ? track.artist : "\(track.artist) / \(track.album)")
                    .font(.system(size: 12))
                    .foregroundColor(FoliaTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(searchFormatDuration(track.duration))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(FoliaTheme.secondary)

            // 行尾动作（命中区 40×40）：速记簿已接通（(53) 工作流 D，点按收进/移出，
            // 视觉态随已收切换，本轮只放大命中框、语义不动）；星标 (55) 工作流 F
            // 接 StarStore 本地真源（显态随 FoliaStarChanged 刷新）；加号 (55) F
            // 改义对齐网页版——点按开「收藏到歌单」弹层，原「追加队列」降为长按。
            HStack(spacing: 2) {
                let inSketchbook = sketchbookStore.contains(trackId: track.id)
                Button {
                    if inSketchbook {
                        sketchbookStore.remove(trackId: track.id, source: "search")
                    } else {
                        sketchbookStore.add(track, source: "search")
                    }
                } label: {
                    Image(systemName: inSketchbook ? "checkmark.circle.fill" : "note.text")
                        .font(.system(size: 16))
                        .foregroundColor(inSketchbook ? ink : FoliaTheme.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let starred = StarStore.shared.isStarred(track.id)
                Button {
                    let on = StarStore.shared.toggle(track.id)
                    Breadcrumbs.log("search.row.star id=\(track.id) on=\(on)")
                } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundColor(starred ? ink : FoliaTheme.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(starred ? "取消星标" : "星标")

                Image(systemName: "plus")
                    .font(.system(size: 16))
                    .foregroundColor(ink)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Breadcrumbs.log("search.row.addtoplaylist id=\(track.id)")
                        addTarget = item
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        QueueManager.shared.appendToQueue([track])
                        Breadcrumbs.log("search.row.queue.longpress id=\(track.id)")
                        NativePlaybackFailureToast.show(message: "已加入播放队列")
                    }
                    .accessibilityLabel("添加到歌单，长按加入播放队列")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: 76)
        .background(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // (62) 多选态下点按改切换选中，不起播。
            if selecting62 {
                if selectedIds62.contains(item.id) {
                    selectedIds62.remove(item.id)
                } else {
                    selectedIds62.insert(item.id)
                }
                return
            }
            guard !item.isUnavailable else { return }
            onPlaySong(track, songs.map(\.track))
        }
        // (62) §7：行长按进多选态（批量收进速记簿/加入队列，
        // 底栏承接；加号钮自身的长按加队列语义不动）。
        .onLongPressGesture(minimumDuration: 0.5) {
            if !selecting62 {
                selecting62 = true
                selectedIds62 = [item.id]
                Breadcrumbs.log("search62.multiselect enter")
            }
        }
        .opacity(item.isUnavailable ? 0.5 : 1)
        // 入场：(62) §3 换网页版行入场——淡入 + 上移 10pt、
        // 按序 32ms 递延（上限 12 行）；原生左滑入退役。
        .opacity(entered || index >= 12 ? 1 : 0)
        .offset(y: entered || index >= 12 ? 0 : 10)
        .animation(.easeOut(duration: 0.3).delay(Double(min(index, 12)) * 0.032), value: entered)
    }

    // MARK: - 集合行（高 84）

    private func collectionRow(index: Int, item: SearchCollection) -> some View {
        HStack(spacing: 14) {
            NativeCoverView(url: item.coverURL, targetPixels: 200)
                // (89) §10-3：集合行封面对齐网页 48×48。
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                Text(collectionSubtitle(item))
                    .font(.system(size: 12))
                    .foregroundColor(FoliaTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text("\(item.trackCount) 首")
                    .font(.system(size: 12))
                    .foregroundColor(FoliaTheme.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13))
                    .foregroundColor(FoliaTheme.secondary)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: 84)
        .background(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenCollection(item) }
        // 入场：(62) 同单曲行——淡入 + 上移 stagger。
        .opacity(entered || index >= 12 ? 1 : 0)
        .offset(y: entered || index >= 12 ? 0 : 10)
        .animation(.easeOut(duration: 0.3).delay(Double(min(index, 12)) * 0.032), value: entered)
    }

    /// 专辑 = 「歌手 / 年份」；歌单 = 「创建者 / 播放量」。
    private func collectionSubtitle(_ item: SearchCollection) -> String {
        switch item.kind {
        case .album:
            if let year = item.year { return "\(item.ownerName) / \(year)" }
            return item.ownerName
        case .playlist:
            if let playCount = item.playCount {
                return "\(item.ownerName) / \(searchFormatPlayCount(playCount)) 次播放"
            }
            return item.ownerName
        }
    }

    // MARK: - 搜索执行

    private func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submittedQuery = trimmed
        searchGeneration += 1
        isSearching = true
        isLoadingMore = false
        searchFailed = false
        entered = false
        let generation = searchGeneration
        Task { await performSearch(generation: generation, offset: 0) }
    }

    private func performSearch(generation: Int, offset: Int) async {
        do {
            switch kind {
            case .song:
                let page = try await fetchSongPage(keywords: submittedQuery, offset: offset)
                guard generation == searchGeneration else { return }
                if offset == 0 {
                    songs = page.items
                    // (62) §3 来源聚合：勾选的 QQ/酷狗在首面
                    // 追加（客户端聚合，按标题+歌手去重）。
                    await aggregateExtraProviders62(generation: generation)
                } else {
                    let known = Set(songs.map(\.id))
                    songs.append(contentsOf: page.items.filter { !known.contains($0.id) })
                }
                totalCount = page.total
            case .album, .playlist:
                let page = try await fetchCollectionPage(kind: kind, keywords: submittedQuery, offset: offset)
                guard generation == searchGeneration else { return }
                if offset == 0 {
                    collections = page.items
                } else {
                    let known = Set(collections.map(\.id))
                    collections.append(contentsOf: page.items.filter { !known.contains($0.id) })
                }
                totalCount = page.total
            }
            hasSearched = true
            searchFailed = false
            if offset == 0 {
                // 结果落地后放行入场动画。
                Task {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    if generation == searchGeneration { entered = true }
                }
            }
        } catch {
            guard generation == searchGeneration else { return }
            if offset == 0 {
                searchFailed = true
                hasSearched = true
                songs = []
                collections = []
                totalCount = 0
            }
        }
        if generation == searchGeneration {
            isSearching = false
            isLoadingMore = false
        }
    }

    /// 单曲页：走代理 /search 原始响应（要 status / mvid / songCount 做标签与分页，
    /// 类型化 searchSongs 不带这些字段），再用 /song/detail 批量补封面（/search 的
    /// album 不带 picUrl，只有 picId）。补封面失败则回退无封面行，不整页失败。
    /// (62) §3 来源聚合（首面、单曲页）：QQ 真发请求——后端
    /// 现回 400（审计 D5），失败记诚实注记不塞假结果；酷狗
    /// 按实测形状宽松解析（data.lists：FileHash/OriSongName/
    /// SingerName/AlbumName/Duration，2026-11-21 本机实测）。
    private func aggregateExtraProviders62(generation: Int) async {
        var notes: [String] = []
        if qqEnabled62 {
            do {
                let data = try await EdgeOneAPIClient.shared.searchRaw(
                    provider: .qq, keywords: submittedQuery, limit: pageSize)
                // QQ 形状未实测核对：宽松解析 data.song.list，
                // 解不出即诚实注记、不并入（防假结果）。
                let items = Self.parseQQSearch62(data)
                guard generation == searchGeneration else { return }
                if items.isEmpty {
                    notes.append("QQ 音乐：已返回但形状未核对，暂不并入")
                } else {
                    let known = Set(songs.map { $0.track.id })
                    songs.append(contentsOf: items.filter { !known.contains($0.track.id) })
                    notes.append("QQ 音乐：\(items.count) 首")
                }
            } catch {
                notes.append("QQ 音乐：后端未通，暂无结果（D5）")
                Breadcrumbs.log("search62.provider qq failed")
            }
        }
        if kugouEnabled62 {
            do {
                let data = try await EdgeOneAPIClient.shared.searchRaw(
                    provider: .kugou, keywords: submittedQuery, limit: pageSize)
                let items = Self.parseKugouSearch62(data)
                guard generation == searchGeneration else { return }
                let known = Set(songs.map {
                    "\($0.track.title.lowercased())|\($0.track.artist.lowercased())"
                })
                let fresh = items.filter {
                    !known.contains(
                        "\($0.track.title.lowercased())|\($0.track.artist.lowercased())")
                }
                songs.append(contentsOf: fresh)
                notes.append("酷狗：\(fresh.count) 首")
            } catch {
                notes.append("酷狗：搜索失败，暂无结果")
                Breadcrumbs.log("search62.provider kugou failed")
            }
        }
        guard generation == searchGeneration else { return }
        providerNotes62 = notes
    }

    /// QQ 搜索宽松解析（形状未核对，QQMusicApi 常见形状
    /// data.song.list：songmid/name/singer[].name/albumname/
    /// interval）：解不出即空，由调用方诚实注记。
    private static func parseQQSearch62(_ data: Data) -> [SongItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let song = dataObj["song"] as? [String: Any],
              let list = song["list"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let mid = entry["songmid"] as? String, !mid.isEmpty else { return nil }
            let title = (entry["name"] as? String) ?? (entry["songname"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let singers = (entry["singer"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String } ?? []
            let duration = (entry["interval"] as? NSNumber)?.doubleValue ?? 0
            let track = FoliaTrack(
                id: "qq_\(mid)", sourceType: .qq, title: title,
                artist: singers.joined(separator: " / "),
                album: (entry["albumname"] as? String) ?? "",
                duration: duration, artworkURL: nil, fee: nil)
            return SongItem(track: track, isUnavailable: false, hasVideo: false)
        }
    }

    /// 酷狗搜索宽松解析（形状实测，见上）：解析不了即空。
    private static func parseKugouSearch62(_ data: Data) -> [SongItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let lists = dataObj["lists"] as? [[String: Any]] else { return [] }
        return lists.compactMap { entry in
            guard let hash = entry["FileHash"] as? String, !hash.isEmpty else { return nil }
            let title = (entry["OriSongName"] as? String)
                ?? (entry["SongName"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let artist = (entry["SingerName"] as? String) ?? ""
            let album = (entry["AlbumName"] as? String) ?? ""
            let duration = (entry["Duration"] as? NSNumber)?.doubleValue ?? 0
            let track = FoliaTrack(
                id: "kg_\(hash)", sourceType: .kugou, title: title,
                artist: artist, album: album, duration: duration,
                artworkURL: nil, fee: nil)
            return SongItem(track: track, isUnavailable: false, hasVideo: false)
        }
    }

    private func fetchSongPage(keywords: String, offset: Int) async throws -> (items: [SongItem], total: Int) {
        let data = try await EdgeOneAPIClient.shared.requestData(
            provider: .netease,
            path: "/search",
            queryItems: [
                URLQueryItem(name: "keywords", value: keywords),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "type", value: "\(SearchKind.song.apiType)")
            ]
        )
        let response = try JSONDecoder().decode(SearchSongResponse.self, from: data)
        let rawSongs = response.result?.songs ?? []

        var detailedById: [Int: FoliaTrack] = [:]
        if !rawSongs.isEmpty,
           let detailed = try? await EdgeOneAPIClient.shared.fetchSongDetails(ids: rawSongs.map(\.id)) {
            for track in detailed {
                detailedById[searchNumericId(of: track)] = track
            }
        }

        let items = rawSongs.map { raw in
            SongItem(
                track: detailedById[raw.id] ?? raw.toFoliaTrack(),
                isUnavailable: (raw.status ?? 0) < 0,
                hasVideo: (raw.mvid ?? 0) != 0
            )
        }
        return (items, response.result?.songCount ?? items.count)
    }

    /// 专辑 / 歌单页：代理 /search 的 type=10 / 1000（2026-11-16 实测支持，形状见 DTO）。
    private func fetchCollectionPage(kind: SearchKind, keywords: String, offset: Int) async throws -> (items: [SearchCollection], total: Int) {
        let data = try await EdgeOneAPIClient.shared.requestData(
            provider: .netease,
            path: "/search",
            queryItems: [
                URLQueryItem(name: "keywords", value: keywords),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "type", value: "\(kind.apiType)")
            ]
        )
        switch kind {
        case .album:
            let response = try JSONDecoder().decode(SearchAlbumResponse.self, from: data)
            let items = (response.result?.albums ?? []).map { album in
                SearchCollection(
                    id: album.id,
                    kind: .album,
                    name: album.name,
                    coverURL: album.picUrl.flatMap(searchSecureURL),
                    ownerName: album.artist?.name
                        ?? (album.artists ?? []).map(\.name).joined(separator: " / "),
                    year: album.publishTime.map(searchYear(fromEpochMilliseconds:)),
                    playCount: nil,
                    trackCount: album.size ?? 0
                )
            }
            return (items, response.result?.albumCount ?? items.count)
        case .playlist:
            let response = try JSONDecoder().decode(SearchPlaylistResponse.self, from: data)
            let items = (response.result?.playlists ?? []).map { playlist in
                SearchCollection(
                    id: playlist.id,
                    kind: .playlist,
                    name: playlist.name,
                    coverURL: playlist.coverImgUrl.flatMap(searchSecureURL),
                    ownerName: playlist.creator?.nickname ?? "",
                    year: nil,
                    playCount: playlist.playCount,
                    trackCount: playlist.trackCount ?? 0
                )
            }
            return (items, response.result?.playlistCount ?? items.count)
        case .song:
            // 单曲不走集合页（performSearch 已分流），到这里返回空页。
            return ([], 0)
        }
    }
}

/// 「收藏到歌单」弹层的 SwiftUI 挂载（(55) 工作流 F）：UIKit 本体
/// AddToPlaylistViewController 包一层导航控制器以 pageSheet 呈出
/// （系统下拉关闭 + 导航栏 ✕ 双通道），关闭后回搜索结果原位。
private struct AddToPlaylistSheet: UIViewControllerRepresentable {
    let track: FoliaTrack

    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: AddToPlaylistViewController(track: track))
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

/// 加载三形（search.css .search-loader）：18×18 强调方块 / 18×18 ink 圆 / 42×6 ink 横条，
/// 底部对齐、高 36，依次起落（延迟 0 / 150 / 300ms，落差 14，opacity 0.35 ↔ 1）。
private struct SearchLoaderShapes: View {
    let ink: Color
    let accent: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            SearchLoaderShape(delay: 0) {
                Rectangle().fill(accent).frame(width: 18, height: 18)
            }
            SearchLoaderShape(delay: 0.15) {
                Circle().fill(ink).frame(width: 18, height: 18)
            }
            SearchLoaderShape(delay: 0.3) {
                Rectangle().fill(ink).frame(width: 42, height: 6)
            }
        }
        .frame(height: 36)
    }
}

private struct SearchLoaderShape<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: () -> Content
    @State private var up = false

    var body: some View {
        content()
            .offset(y: up ? -14 : 0)
            .opacity(up ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

// MARK: - 网易云 /search 原始响应 DTO（按 2026-11-16 实测形状；新旧键互为回退）

private struct SearchSongResponse: Decodable {
    let result: Result?
    struct Result: Decodable {
        let songs: [Song]?
        let songCount: Int?
    }
    struct Song: Decodable {
        let id: Int
        let name: String
        let duration: Int?
        let dt: Int?
        let artists: [Artist]?
        let ar: [Artist]?
        let album: Album?
        let al: Album?
        let status: Int?
        let mvid: Int?

        struct Artist: Decodable { let name: String }
        struct Album: Decodable {
            let name: String
            let picUrl: String?
        }

        func toFoliaTrack() -> FoliaTrack {
            let artistNames = (artists ?? ar ?? []).map(\.name).joined(separator: " / ")
            let albumInfo = album ?? al
            return FoliaTrack(
                id: "ncm_\(id)",
                sourceType: .netease,
                title: name,
                artist: artistNames.isEmpty ? "未知歌手" : artistNames,
                album: albumInfo?.name ?? "",
                duration: Double(duration ?? dt ?? 0) / 1000.0,
                artworkURL: albumInfo?.picUrl.flatMap(searchSecureURL)
            )
        }
    }
}

private struct SearchAlbumResponse: Decodable {
    let result: Result?
    struct Result: Decodable {
        let albums: [Album]?
        let albumCount: Int?
    }
    struct Album: Decodable {
        let id: Int
        let name: String
        let picUrl: String?
        let size: Int?
        let publishTime: Int?
        let artist: Artist?
        let artists: [Artist]?

        struct Artist: Decodable { let name: String }
    }
}

private struct SearchPlaylistResponse: Decodable {
    let result: Result?
    struct Result: Decodable {
        let playlists: [Playlist]?
        let playlistCount: Int?
    }
    struct Playlist: Decodable {
        let id: Int
        let name: String
        let coverImgUrl: String?
        let trackCount: Int?
        let playCount: Int?
        let creator: Creator?

        struct Creator: Decodable { let nickname: String }
    }
}

// MARK: - 小工具

/// http → https + URL 化（与 EdgeOneAPIClient 的归一化同口径）。
private func searchSecureURL(_ text: String) -> URL? {
    URL(string: text.replacingOccurrences(of: "http://", with: "https://"))
}

private func searchNumericId(of track: FoliaTrack) -> Int {
    Int(track.id.replacingOccurrences(of: "ncm_", with: "")) ?? -1
}

private func searchYear(fromEpochMilliseconds ms: Int) -> Int {
    Calendar.current.component(.year, from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
}

/// mm:ss（与 SearchResultRow 的 formatDuration 同口径：四舍五入到秒）。
private func searchFormatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// 播放量紧凑格式（万 / 亿，一位小数、去尾零）。
private func searchFormatPlayCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return searchTrimZero(Double(count) / 100_000_000) + "亿"
    }
    if count >= 10_000 {
        return searchTrimZero(Double(count) / 10_000) + "万"
    }
    return "\(count)"
}

private func searchTrimZero(_ value: Double) -> String {
    let text = String(format: "%.1f", value)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
}
