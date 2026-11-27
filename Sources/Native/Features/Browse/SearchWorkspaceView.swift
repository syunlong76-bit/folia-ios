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
/// 形态（2026-11-27 换设计 A 拍立得版，Miller 点选
/// design-samples-92/search-design-a.png）：暖黑底、圆角填充搜索框、
/// 平台胶囊排（选中奶油填充）、文字页签 + 金色短下划线、结果为
/// 2–4 列错落拍立得卡（奶油白边卡面 + 封面 + 题注区歌名/歌手、
/// 轻微不规则倾斜、第二列下沉）。功能通路与旧排版完全一致：
/// 三平台勾选、单曲/专辑/歌单三页签、请求与数据流、点卡播放/
/// 开集合均不变（锚点见各段注释）。专辑 / 歌单走代理 /search
/// 的 type=10 / 1000（实测支持，见交付报告）。
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

    /// 日记本（(53) 工作流 D）：行尾按钮的已收/未收视觉态随它刷新。
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
    /// (98) 第 7 条：喜欢刷新代次——订阅 .foliaLikesChanged91
    /// 后自增，强制卡重算 LikesStore 显态（全 App 同一喜欢源）。
    @State private var likeRefreshTick98 = 0
    /// (98) 第 7 条：单击展开的卡 id（卡内详情：大播放钮＋
    /// 收藏到歌单/进日记本/我喜欢）；双击直接进详情播放页。
    @State private var expandedId98: String?
    /// 「收藏到歌单」弹层的目标歌曲（(55) 工作流 F）：加号点按
    /// 置入后由 sheet 呈 AddToPlaylistViewController。
    @State private var addTarget: SongItem?
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

    // 设计 A 色令牌：paper = 暖黑底 #171310、cardCream = 拍立得
    // 卡面奶油白 #F6F0E1、cardInk / cardSub = 卡面题注深字 / 灰褐
    // 副字、gold = 页签下划线与封面角标的金 #D9A441；ink 仍走
    // FoliaTheme.primary（深底文字）、accent 归金（加载形/空态斜杠）。
    private var ink: Color { FoliaTheme.primary }
    private var accent: Color { gold }
    private var paper: Color { Color(red: 0x17 / 255, green: 0x13 / 255, blue: 0x10 / 255) }
    private var hairline: Color { ink.opacity(0.09) }
    private var cardCream: Color { Color(red: 0xF6 / 255, green: 0xF0 / 255, blue: 0xE1 / 255) }
    private var cardInk: Color { Color(red: 0x21 / 255, green: 0x1D / 255, blue: 0x18 / 255) }
    private var cardSub: Color { Color(red: 0x8A / 255, green: 0x7D / 255, blue: 0x6B / 255) }
    private var gold: Color { Color(red: 0xD9 / 255, green: 0xA4 / 255, blue: 0x41 / 255) }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            paper.opacity(0.94).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                GeometryReader { geo in
                    resultsArea(columnCount: columnCount(for: geo.size.width))
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }

            // (62) §7 多选底栏：收进日记本（addBatch）/ 加入
            // 队列 / 取消。收进后退出多选态并 toast 回执。
            if selecting62 {
                VStack {
                    Spacer()
                    HStack(spacing: 18) {
                        Text("已选 \(selectedIds62.count) 首")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ink)
                        Spacer()
                        Button("收进日记本") {
                            let picked = songs.map(\.track)
                                .filter { selectedIds62.contains($0.id) }
                            let added = sketchbookStore.addBatch(picked, source: "search")
                            Breadcrumbs.log("search62.batch sketchbook added=\(added)")
                            NativePlaybackFailureToast.show(
                                message: "已收进日记本 \(added) 首")
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
        .onReceive(NotificationCenter.default.publisher(for: .foliaLikesChanged91)) { _ in
            likeRefreshTick98 += 1
        }
        .sheet(item: $addTarget) { item in
            AddToPlaylistSheet(track: item.track)
        }
        .onAppear { fieldFocused = true }
    }

    /// (62) 来源多选胶囊（设计 A）：选中 = 奶油填充深字，未选 =
    /// 发丝描边胶囊灰字；点按切换 + SettingsStore 持久化 + 已搜
    /// 重搜的通路与旧开关完全一致。
    private func providerPill62(title: String, isOn: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isOn ? .bold : .regular))
                .foregroundColor(isOn ? cardInk : FoliaTheme.secondary)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Capsule().fill(isOn ? cardCream : Color.clear))
                .overlay(Capsule().stroke(Color.white.opacity(isOn ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 头部（面包屑 + 圆形关闭钮 / 圆角搜索框 / 平台胶囊排 / 页签排 / 状态行）

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 面包屑行：左「书库 › 搜索」，右圆形关闭钮（设计 A 同位）；
            // 关闭通路 onClose 不变。旧版的说明文案行按设计 A 撤除
            // （语义由 SearchHostPresenter 呈现层保证，不靠文案）。
            HStack(alignment: .center) {
                Text("书库 › 搜索")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(FoliaTheme.secondary)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            // 搜索框（设计 A）：圆角 14 填充面 + 放大镜 + 输入；
            // 焦点/提交/占位随页签切换的通路不变。
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(FoliaTheme.secondary)
                TextField(kind.placeholder, text: $query)
                    .font(.system(size: 16))
                    .foregroundColor(ink)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { submitSearch() }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(FoliaTheme.field))

            // 平台排（设计 A 胶囊）：网易云恒开 = 选中态奶油胶囊
            // （静态、无点按）；QQ/酷狗走 providerPill62 多选通路。
            HStack(spacing: 10) {
                Text("网易云")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(cardInk)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(cardCream))
                providerPill62(title: "QQ音乐", isOn: qqEnabled62) {
                    qqEnabled62.toggle()
                    SettingsStore.searchProviderQQEnabled62 = qqEnabled62
                    if !submittedQuery.isEmpty { submitSearch() }
                }
                providerPill62(title: "酷狗", isOn: kugouEnabled62) {
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

            // 页签排（设计 A）：文字签 + 选中金色短下划线；
            // 切换 kind + 已搜重搜的通路不变。
            HStack(spacing: 30) {
                ForEach(SearchKind.allCases, id: \.self) { item in
                    Button {
                        guard item != kind else { return }
                        kind = item
                        if !submittedQuery.isEmpty { submitSearch() }
                    } label: {
                        VStack(spacing: 6) {
                            Text(item.label)
                                .font(.system(size: 17, weight: item == kind ? .bold : .regular))
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(item == kind ? gold : Color.clear)
                                .frame(width: 24, height: 3)
                        }
                        .foregroundColor(item == kind ? ink : FoliaTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 状态行（11px 等宽：来源名 + 结果数 + 发丝线延伸，信息保留）。
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

    /// 结果列数（横竖屏自适应）：窄屏 2 列（设计 A 竖屏口径）、
    /// 中屏 3 列、宽屏 4 列。
    private func columnCount(for width: CGFloat) -> Int {
        if width >= 900 { return 4 }
        if width >= 560 { return 3 }
        return 2
    }

    /// 拍立得卡的不规则倾斜角（按结果序循环取，-1.8°…+1.5°，设计 A 口径）。
    private func cardTilt(_ index: Int) -> Double {
        let tilts: [Double] = [-1.4, 0.9, -0.7, 1.2, -1.0, 0.6, -1.8, 1.5]
        return tilts[index % tilts.count]
    }

    @ViewBuilder
    private func resultsArea(columnCount: Int) -> some View {
        if isSearching {
            // 搜索中：加载动画整体替换列表（分支优先级与旧版一致；
            // 加载更多不置 isSearching，不受影响）。
            SearchLoaderShapes(ink: ink, accent: accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchFailed && currentResultCount == 0 {
            voidState(text: "搜索失败，请重试。", showRetry: true)
        } else if currentResultCount == 0 {
            // 含未搜初始态：空态（贴纸口径不变：真搜过无结果才出猫）。
            voidState(text: "未找到相关结果", showRetry: false, sticker: hasSearched)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if kind == .song {
                        songColumns(columnCount)
                    } else {
                        collectionColumns(columnCount)
                    }

                    if canLoadMore {
                        loadMoreButton
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
    }

    /// 单曲卡列阵：结果按序轮分到各列，第二列下沉 30pt（设计 A
    /// 错落）、第三列下沉 12pt；列内纵距 18、列距 14。
    private func songColumns(_ columnCount: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(0..<columnCount, id: \.self) { column in
                LazyVStack(spacing: 18) {
                    ForEach(songs.indices.filter { $0 % columnCount == column }, id: \.self) { index in
                        songCard(index: index, item: songs[index])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, column == 1 ? 30 : (column == 2 ? 12 : 0))
            }
        }
    }

    /// 集合卡列阵：与单曲同列阵口径。
    private func collectionColumns(_ columnCount: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(0..<columnCount, id: \.self) { column in
                LazyVStack(spacing: 18) {
                    ForEach(collections.indices.filter { $0 % columnCount == column }, id: \.self) { index in
                        collectionCard(index: index, item: collections[index])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, column == 1 ? 30 : (column == 2 ? 12 : 0))
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
            .overlay(Capsule().stroke(ink.opacity(0.45), lineWidth: 1))
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

    // MARK: - 单曲拍立得卡

    /// (98) 第 7 条：展开详情内的语义动作小钮（图标＋11pt 标签）。
    private func expandedAction98(icon: String, label: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(cardInk)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func songCard(index: Int, item: SongItem) -> some View {
        let track = item.track
        // 读一次喜欢代次，把 .foliaLikesChanged91 的刷新依赖挂到卡渲染上。
        _ = likeRefreshTick98
        return VStack(alignment: .leading, spacing: 0) {
            // 封面区：卡面内缩 10pt、圆角 4；右下角标承接旧行尾的
            // MV / 已下架标签（落在设计 A 的封面角标位）；多选态
            // 的选中标移封面左上（旧行首圆标的通路保留）。
            NativeCoverView(url: track.artworkURL, targetPixels: 300)
                .aspectRatio(1.22, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topTrailing) {
                    if let tag = item.isUnavailable ? "已下架" : (item.hasVideo ? "MV" : nil) {
                        Text(tag)
                            .font(.system(size: 11, weight: .bold))   // (95) 集成：字号下限 11pt 硬线，角标由 9 抬到 11
                            .foregroundColor(gold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(Color.black.opacity(0.72)))
                            .padding(6)
                    }
                }
                // (98) 第 7 条：封面右下毛玻璃播放角标（原右下
                // MV/已下架标签移右上让位）。
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if selecting62 {
                        Image(systemName: selectedIds62.contains(item.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(selectedIds62.contains(item.id)
                                             ? gold : Color.white.opacity(0.85))
                            .padding(6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

            // 题注区：歌名（衬线粗 15）/ 歌手·专辑（灰褐 12）/
            // 时长 + 动作排（旧行尾三钮通路原样保留；(96) D：
            // 命中框由 30 扩到 44，视觉字形仍 14 不变）。
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(cardInk)
                    .lineLimit(1)
                Text(track.album.isEmpty ? track.artist : "\(track.artist) / \(track.album)")
                    .font(.system(size: 12))
                    .foregroundColor(cardSub)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    Text(searchFormatDuration(track.duration))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(cardSub)
                        .lineLimit(1)
                        .frame(width: 46, alignment: .leading)   // (98) 第 7 条：时长单行定宽，不许被动作钮挤成竖排
                    Spacer(minLength: 0)
                    // 日记本（(53) 工作流 D）：点按收进/移出，视觉态随已收切换。
                    let inSketchbook = sketchbookStore.contains(trackId: track.id)
                    Button {
                        if inSketchbook {
                            sketchbookStore.remove(trackId: track.id, source: "search")
                        } else {
                            sketchbookStore.add(track, source: "search")
                        }
                    } label: {
                        Image(systemName: inSketchbook ? "checkmark.circle.fill" : "note.text")
                            .font(.system(size: 14))
                            .foregroundColor(inSketchbook ? cardInk : cardSub)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // (98) 第 7 条：星标删除——收藏语义全 App 统一
                    // 到爱心「我喜欢」（LikesStore 唯一真源）。
                    let liked98 = LikesStore.shared.isLiked(track.id)
                    Button {
                        let on = LikesStore.shared.toggle(track.id)
                        Breadcrumbs.log("p98 search like id=\(track.id) on=\(on ? 1 : 0)")
                    } label: {
                        Image(systemName: liked98 ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                            .foregroundColor(liked98
                                ? Color(red: 0xC8 / 255, green: 0x10 / 255, blue: 0x2E / 255)
                                : cardSub)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(liked98 ? "取消喜欢" : "我喜欢")

                    // 加号（(55) F）：点按开「收藏到歌单」弹层，长按追加队列。
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundColor(cardInk)
                        .frame(width: 44, height: 44)
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

                // (98) 第 7 条：单击展开的卡内详情——大播放钮
                // （起播后回墙、由 84 胶囊台承接）＋三枚语义
                // 动作（收藏到歌单/进日记本/我喜欢）。
                if expandedId98 == item.id {
                    VStack(spacing: 10) {
                        Button {
                            guard !item.isUnavailable else { return }
                            Breadcrumbs.log("p98 search play id=\(track.id)")
                            onPlaySong(track, songs.map(\.track))
                            onClose()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text("播放")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(cardInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(gold))
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 8) {
                            expandedAction98(icon: "plus.circle", label: "收藏到歌单") {
                                Breadcrumbs.log("search.row.addtoplaylist id=\(track.id)")
                                addTarget = item
                            }
                            expandedAction98(
                                icon: sketchbookStore.contains(trackId: track.id)
                                    ? "checkmark.circle.fill" : "note.text",
                                label: "进日记本") {
                                if sketchbookStore.contains(trackId: track.id) {
                                    sketchbookStore.remove(trackId: track.id, source: "search")
                                } else {
                                    sketchbookStore.add(track, source: "search")
                                }
                            }
                            expandedAction98(
                                icon: LikesStore.shared.isLiked(track.id)
                                    ? "heart.fill" : "heart",
                                label: "我喜欢") {
                                let on = LikesStore.shared.toggle(track.id)
                                Breadcrumbs.log("p98 search like id=\(track.id) on=\(on ? 1 : 0)")
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(cardCream))
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        .rotationEffect(.degrees(cardTilt(index)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: 2) {
            // (98) 第 7 条：双击＝进入详情播放页（起播＋开
            // 全屏播放页＋收搜索页回墙）。
            if selecting62 || item.isUnavailable { return }
            Breadcrumbs.log("p98 search dbl id=\(track.id)")
            onPlaySong(track, songs.map(\.track))
            NativeBrowseView.openFullPlayer()
            onClose()
        }
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
            // (98) 第 7 条：单击＝卡内展开/收起歌曲详情
            // （与墙面展开逻辑对齐，不再直接起播）。
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedId98 = expandedId98 == item.id ? nil : item.id
            }
            Breadcrumbs.log("p98 search exp id=\(track.id) on=\(expandedId98 == item.id ? 1 : 0)")
        }
        // (62) §7：卡长按进多选态（批量收进日记本/加入队列，
        // 底栏承接；加号钮自身的长按加队列语义不动）。
        .onLongPressGesture(minimumDuration: 0.5) {
            if !selecting62 {
                selecting62 = true
                selectedIds62 = [item.id]
                Breadcrumbs.log("search62.multiselect enter")
            }
        }
        .opacity(item.isUnavailable ? 0.55 : 1)
        // 入场：淡入 + 上移 10pt、按序 32ms 递延（上限 12 卡）、
        // 系统弹簧曲线（旧行 easeOut 口径按 iOS 系统动效规矩升级）。
        .opacity(entered || index >= 12 ? 1 : 0)
        .offset(y: entered || index >= 12 ? 0 : 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.85)
            .delay(Double(min(index, 12)) * 0.032), value: entered)
    }

    // MARK: - 集合拍立得卡（专辑 / 歌单）

    private func collectionCard(index: Int, item: SearchCollection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NativeCoverView(url: item.coverURL, targetPixels: 300)
                .aspectRatio(1.22, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 10)
                .padding(.top, 10)

            // 题注区：名称 / 副题（歌手·年份 或 创建者·播放量）/
            // 曲数 + 右上箭头（旧集合行的信息与开页通路不变）。
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(cardInk)
                    .lineLimit(1)
                Text(collectionSubtitle(item))
                    .font(.system(size: 12))
                    .foregroundColor(cardSub)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(item.trackCount) 首")
                        .font(.system(size: 11))
                        .foregroundColor(cardSub)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundColor(cardSub)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(cardCream))
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        .rotationEffect(.degrees(cardTilt(index)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onOpenCollection(item) }
        // 入场：与单曲卡同口径（淡入 + 上移 stagger、系统弹簧）。
        .opacity(entered || index >= 12 ? 1 : 0)
        .offset(y: entered || index >= 12 ? 0 : 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.85)
            .delay(Double(min(index, 12)) * 0.032), value: entered)
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
                notes.append("QQ 音乐：后端未通，暂无结果")
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
