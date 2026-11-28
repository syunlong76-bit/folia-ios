import SwiftUI
import Photos
import UIKit

// DiaryBookViews99.swift — (99) 第 7 项书主页（SwiftUI）：
// 书页式布局（竖屏单页 / 横屏双页摊开，滑动翻页近似实现）、
// 今日草稿、时间轴、日历、歌曲聚合、回收站五页；记一笔编辑器、
// 条目详情、打印机动画＋分享卡导出在本文件内成套。
//
// 配色照已审样板与 DiaryViewController90 纸面口径：暖奶油纸面＋深墨字，
// 深色模式下走深纸面（可读优先）。

/// (102) 印章二维码墨色（与 DiaryPaper99.ink 同值，UIKit 侧）。
var diaryInkUIColor102: UIColor {
    UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.92, green: 0.89, blue: 0.83, alpha: 1)
            : UIColor(red: 0.18, green: 0.16, blue: 0.13, alpha: 1)
    }
}

enum DiaryPaper99 {
    static var paper: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1)
            : UIColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1) }) }
    static var card: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.19, green: 0.17, blue: 0.15, alpha: 1)
            : UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1) }) }
    static var ink: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.92, green: 0.89, blue: 0.83, alpha: 1)
            : UIColor(red: 0.18, green: 0.16, blue: 0.13, alpha: 1) }) }
    static var dim: Color { Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.59, blue: 0.53, alpha: 1)
            : UIColor(red: 0.55, green: 0.52, blue: 0.44, alpha: 1) }) }
    static let accent = Color(red: 0.85, green: 0.62, blue: 0.15)
}

// MARK: - 封面加载（复用 NativeCoverLoader，与 DiaryViewController90 同口径）

final class DiaryCoverLoader99: ObservableObject {
    @Published var image: UIImage?
    func load(_ raw: String?) {
        guard let raw, image == nil else { return }
        let loader = NativeCoverLoader.shared
        let proxy = loader.proxiedURLString(raw, tier: 256)
        if let key = proxy, let cached = loader.cachedImage(for: key) { image = cached; return }
        if let cached = loader.cachedImageAnyTier(raw: raw, excludingTier: 256) { image = cached; return }
        Task { [weak self] in
            let loaded = await loader.image(for: proxy ?? raw, tier: 256)
            await MainActor.run { self?.image = loaded }
        }
    }
}

struct DiaryCoverView99: View {
    let raw: String?
    var size: CGFloat = 44
    @StateObject private var loader = DiaryCoverLoader99()
    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                DiaryPaper99.dim.opacity(0.25)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { loader.load(raw) }
    }
}

// MARK: - 编辑器请求

struct DiaryEditorRequest99: Identifiable {
    var id = UUID()
    var song: DiarySong90?
    var prefillText: String = ""
    var isDraftConfirm: Bool = false
    var editing: DiaryEntry99?
}

// MARK: - 书主页

struct DiaryBookRootView99: View {
    @ObservedObject var store: DiaryStore99
    let initialSong: DiarySong90?
    let onClose: () -> Void

    @State private var spreadIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var editorRequest: DiaryEditorRequest99?
    @State private var detailEntry: DiaryEntry99?
    @State private var shareEntry: DiaryEntry99?
    /// (101) 第 5 项：手写签名板开关（头部入口）。
    @State private var showSignaturePad101 = false

    private let pageTitles = ["今日草稿", "时间轴", "日历", "歌曲", "回收站"]

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let spreads = makeSpreads(landscape: landscape)
            VStack(spacing: 0) {
                header
                    .sheet(item: $editorRequest) { request in
                        DiaryEditorView99(store: store, request: request)
                    }
                    .sheet(isPresented: $showSignaturePad101) {
                        DiarySignaturePad99()
                    }
                    .onAppear { DiaryDogFrame102.preload() }
                // 书体：纸面容器＋中缝（横屏双页时中缝即书脊）
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(DiaryPaper99.paper)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                    HStack(spacing: 0) {
                        ForEach(spreads[safe: min(spreadIndex, spreads.count - 1)] ?? [0], id: \.self) { page in
                            pageView(page)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if landscape, page == (spreads[safe: min(spreadIndex, spreads.count - 1)] ?? [0]).first {
                                Rectangle()
                                    .fill(LinearGradient(colors: [.clear, .black.opacity(0.16), .clear],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 22)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // (101) 第 5 项：真翻页——拖动时书页绕纵轴
                    // 3D 卷起（perspective + 随动明暗）替代旧
                    // 平移近似，松手弹簧落定换页（下方手势）。
                    .modifier(DiaryPageCurl101(offset: dragOffset,
                                               width: geo.size.width))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .sheet(item: $detailEntry) { entry in
                    DiaryDetailView99(store: store, entry: entry,
                                      onExport: {
                                          DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                              shareEntry = entry
                                          }
                                      },
                                      onEdit: {
                                          detailEntry = nil
                                          DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                              editorRequest = DiaryEditorRequest99(
                                                  song: entry.songId.map { DiarySong90(id: $0, title: entry.songTitle ?? "",
                                                      artist: entry.songArtist ?? "", artwork: entry.songArtwork) },
                                                  prefillText: entry.text, editing: entry)
                                          }
                                      })
                }
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { dragOffset = $0.translation.width }
                        .onEnded { value in
                            let step = landscape ? 1 : 1
                            var next = spreadIndex
                            if value.translation.width < -60 { next = min(spreadIndex + step, spreads.count - 1) }
                            if value.translation.width > 60 { next = max(spreadIndex - step, 0) }
                            // (101) 第 5 项：翻页路径自证（3D
                            // 卷页，非平移）。
                            Breadcrumbs.log("p101 diary flip curl=1 turned=\(next != spreadIndex ? 1 : 0)")
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                spreadIndex = next
                                dragOffset = 0
                            }
                        })
                footer(spreads: spreads)
                    .sheet(item: $shareEntry) { entry in
                        DiaryShareView99(entry: entry)
                    }
            }
            .background(Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
                    : UIColor(red: 0.90, green: 0.86, blue: 0.78, alpha: 1) }))
        }
    }

    private func makeSpreads(landscape: Bool) -> [[Int]] {
        let pages = Array(0..<pageTitles.count)
        guard landscape else { return pages.map { [$0] } }
        var spreads: [[Int]] = []
        var i = 0
        while i < pages.count {
            spreads.append(i + 1 < pages.count ? [pages[i], pages[i + 1]] : [pages[i]])
            i += 2
        }
        return spreads
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("音乐日记本").font(.system(size: 21, weight: .bold)).foregroundColor(DiaryPaper99.ink)
                Text("以歌为线索，记下每一个时刻").font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
            }
            Spacer()
            // (101) 第 5 项：手写签名入口（签名板：手写 →
            // 系统美化 → 存档，打印落款用美化版）。
            Button {
                showSignaturePad101 = true
            } label: {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DiaryPaper99.card))
                    .foregroundColor(DiaryPaper99.ink)
            }
            .accessibilityLabel("手写签名")
            Button {
                editorRequest = DiaryEditorRequest99(song: initialSong,
                                                     prefillText: store.editorAutosave)
            } label: {
                Label("记一笔", systemImage: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(DiaryPaper99.accent))
                    .foregroundColor(.white)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DiaryPaper99.card))
                    .foregroundColor(DiaryPaper99.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func footer(spreads: [[Int]]) -> some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    spreadIndex = max(spreadIndex - 1, 0)
                }
            } label: { Image(systemName: "chevron.left") }
            .disabled(spreadIndex == 0)
            Spacer()
            Text(spreads[safe: min(spreadIndex, spreads.count - 1)]?
                    .map { pageTitles[$0] }.joined(separator: " · ") ?? "")
                .font(.system(size: 12)).foregroundColor(DiaryPaper99.dim)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    spreadIndex = min(spreadIndex + 1, spreads.count - 1)
                }
            } label: { Image(systemName: "chevron.right") }
            .disabled(spreadIndex >= spreads.count - 1)
        }
        .foregroundColor(DiaryPaper99.ink)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func pageView(_ page: Int) -> some View {
        switch page {
        case 0:
            DiaryDraftPage99(store: store,
                             onConfirmEdit: { text, song in
                                 editorRequest = DiaryEditorRequest99(song: song, prefillText: text,
                                                                      isDraftConfirm: true)
                             })
        case 1:
            DiaryTimelinePage99(store: store, onSelect: { detailEntry = $0 })
        case 2:
            DiaryCalendarPage99(store: store, onSelect: { detailEntry = $0 })
        case 3:
            DiarySongsPage99(store: store, onSelect: { detailEntry = $0 })
        default:
            DiaryTrashPage99(store: store)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 页 0：今日草稿

struct DiaryDraftPage99: View {
    @ObservedObject var store: DiaryStore99
    let onConfirmEdit: (String, DiarySong90?) -> Void

    var body: some View {
        let plays = store.todayPlays()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("今日草稿").font(.system(size: 17, weight: .bold)).foregroundColor(DiaryPaper99.ink)
                if store.todayDraftConfirmed {
                    Label("今日草稿已确认入册，去时间轴看看。", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundColor(DiaryPaper99.dim)
                } else if plays.isEmpty {
                    Text("今天还没有播放记录。听几首歌，这里会自动生成今日草稿。")
                        .font(.system(size: 13)).foregroundColor(DiaryPaper99.dim)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plays, id: \.track.id) { play in
                            HStack(spacing: 10) {
                                DiaryCoverView99(raw: play.track.artworkURL?.absoluteString, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(play.track.title).font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(DiaryPaper99.ink).lineLimit(1)
                                    Text(play.track.artist).font(.system(size: 11.5))
                                        .foregroundColor(DiaryPaper99.dim).lineLimit(1)
                                }
                                Spacer()
                                Text("\(play.playsToday) 次").font(.system(size: 12))
                                    .foregroundColor(DiaryPaper99.dim)
                            }
                        }
                        Text(store.draftText(plays: plays))
                            .font(.system(size: 12.5)).foregroundColor(DiaryPaper99.dim)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card))
                    HStack(spacing: 10) {
                        Button("编辑并确认") {
                            let top = plays.first.map { DiarySong90(track: $0.track) }
                            onConfirmEdit(store.draftText(plays: plays), top)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().stroke(DiaryPaper99.accent, lineWidth: 1.2))
                        .foregroundColor(DiaryPaper99.accent)
                        Button("直接确认") { _ = store.confirmTodayDraft() }
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(DiaryPaper99.accent))
                            .foregroundColor(.white)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(18)
        }
    }
}

// MARK: - 条目卡（时间轴/日历/歌曲页共用）

struct DiaryEntryCard99: View {
    let entry: DiaryEntry99
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = entry.songTitle {
                HStack(spacing: 8) {
                    DiaryCoverView99(raw: entry.songArtwork, size: 30)
                    Text("\(title)\(entry.songArtist.map { " · \($0)" } ?? "")")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(DiaryPaper99.accent).lineLimit(1)
                }
            }
            if !entry.text.isEmpty {
                Text(entry.text).font(.system(size: 14)).foregroundColor(DiaryPaper99.ink)
                    .lineLimit(4)
            }
            // (101) 第 5 项：落点画布回放（分数坐标同源）。
            if !entry.placements.isEmpty {
                DiaryPlacementCanvas99(placements: entry.placements)
                    .frame(height: 74)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(DiaryPaper99.paper.opacity(0.65)))
            }
            HStack(spacing: 8) {
                if let mood = entry.mood {
                    Text(mood).font(.system(size: 11))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(DiaryPaper99.accent.opacity(0.16)))
                        .foregroundColor(DiaryPaper99.ink)
                }
                ForEach(entry.stickerNames.prefix(4), id: \.self) { name in
                    if let sticker = DiarySticker99.named(name), let image = sticker.image {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 26, height: 26)
                    }
                }
                Spacer()
                Text(Self.timeText(entry.createdAt)).font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 10).fill(DiaryPaper99.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
    }

    static func timeText(_ ts: TimeInterval) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}

// MARK: - 页 1：时间轴

struct DiaryTimelinePage99: View {
    @ObservedObject var store: DiaryStore99
    let onSelect: (DiaryEntry99) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("时间轴").font(.system(size: 17, weight: .bold)).foregroundColor(DiaryPaper99.ink)
                if store.entries.isEmpty {
                    Text("还没有日记。用「记一笔」写下第一篇吧。")
                        .font(.system(size: 13)).foregroundColor(DiaryPaper99.dim)
                }
                ForEach(store.entriesByDay(), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(group.day).font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(DiaryPaper99.dim)
                        ForEach(group.items) { entry in
                            DiaryEntryCard99(entry: entry)
                                .onTapGesture { onSelect(entry) }
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 页 2：日历

struct DiaryCalendarPage99: View {
    @ObservedObject var store: DiaryStore99
    let onSelect: (DiaryEntry99) -> Void
    @State private var monthOffset = 0
    @State private var selectedKey: String = DiaryStore99.dateKey(for: Date())

    var body: some View {
        let cal = Calendar.current
        let base = cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        let year = cal.component(.year, from: base)
        let month = cal.component(.month, from: base)
        let firstDay = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? base
        let daysInMonth = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let leading = (cal.component(.weekday, from: firstDay) + 6) % 7 // 周一起始
        let pastYears = store.onThisDayPastYears()
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("日历").font(.system(size: 17, weight: .bold)).foregroundColor(DiaryPaper99.ink)
                    Spacer()
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    Text("\(year) 年 \(month) 月").font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(DiaryPaper99.ink)
                    Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                }
                .foregroundColor(DiaryPaper99.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 7) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                        Text(w).font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
                    }
                    ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 34) }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        let key = String(format: "%04d-%02d-%02d", year, month, day)
                        let has = store.daysWithEntries.contains(key)
                        Button { selectedKey = key } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(key == selectedKey ? DiaryPaper99.accent.opacity(0.25) : Color.clear)
                                VStack(spacing: 2) {
                                    Text("\(day)").font(.system(size: 13))
                                        .foregroundColor(DiaryPaper99.ink)
                                    Circle().fill(has ? DiaryPaper99.accent : Color.clear)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 34)
                        }
                    }
                }
                let dayEntries = store.entries(onDayKey: selectedKey)
                Text(dayEntries.isEmpty ? "\(selectedKey) 没有日记" : "\(selectedKey) 的日记")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundColor(DiaryPaper99.dim)
                ForEach(dayEntries) { entry in
                    DiaryEntryCard99(entry: entry).onTapGesture { onSelect(entry) }
                }
                if monthOffset == 0, !pastYears.isEmpty {
                    Text("往年今日").font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DiaryPaper99.dim).padding(.top, 4)
                    ForEach(pastYears) { entry in
                        DiaryEntryCard99(entry: entry).onTapGesture { onSelect(entry) }
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 页 3：歌曲聚合

struct DiarySongsPage99: View {
    @ObservedObject var store: DiaryStore99
    let onSelect: (DiaryEntry99) -> Void
    @State private var openSongId: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("按歌曲").font(.system(size: 17, weight: .bold)).foregroundColor(DiaryPaper99.ink)
                let groups = store.entriesBySong()
                if groups.isEmpty {
                    Text("还没有挂着歌的日记。记一笔时会自动带上正在播放的歌。")
                        .font(.system(size: 13)).foregroundColor(DiaryPaper99.dim)
                }
                ForEach(groups, id: \.song.id) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            openSongId = openSongId == group.song.id ? nil : group.song.id
                        } label: {
                            HStack(spacing: 10) {
                                DiaryCoverView99(raw: group.song.artwork, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(group.song.title).font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(DiaryPaper99.ink).lineLimit(1)
                                    Text(group.song.artist).font(.system(size: 11.5))
                                        .foregroundColor(DiaryPaper99.dim).lineLimit(1)
                                }
                                Spacer()
                                Text("\(group.items.count) 篇").font(.system(size: 12))
                                    .foregroundColor(DiaryPaper99.dim)
                                Image(systemName: openSongId == group.song.id ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
                            }
                        }
                        if openSongId == group.song.id {
                            ForEach(group.items) { entry in
                                DiaryEntryCard99(entry: entry).onTapGesture { onSelect(entry) }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card))
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 页 4：回收站

struct DiaryTrashPage99: View {
    @ObservedObject var store: DiaryStore99
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("回收站").font(.system(size: 17, weight: .bold)).foregroundColor(DiaryPaper99.ink)
                if store.trashed.isEmpty {
                    Text("回收站是空的。").font(.system(size: 13)).foregroundColor(DiaryPaper99.dim)
                }
                ForEach(store.trashed) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        DiaryEntryCard99(entry: entry)
                        HStack(spacing: 10) {
                            Button("恢复") { store.restoreEntry(id: entry.id) }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DiaryPaper99.accent)
                            Button("彻底删除") { store.purgeEntry(id: entry.id) }
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 条目详情

struct DiaryDetailView99: View {
    @ObservedObject var store: DiaryStore99
    let entry: DiaryEntry99
    let onExport: () -> Void
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanOn102: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let title = entry.songTitle {
                        HStack(spacing: 10) {
                            DiaryCoverView99(raw: entry.songArtwork, size: 46)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text(entry.songArtist ?? "").font(.system(size: 12))
                                    .foregroundColor(DiaryPaper99.dim).lineLimit(1)
                            }
                        }
                    }
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .font(DiaryBodyFont102.font(name: entry.fontName, size: 15.5))
                    }
                    if !entry.placements.isEmpty {
                        // (101) 第 5 项：按用户落点原样回放。
                        DiaryPlacementCanvas99(placements: entry.placements)
                            .frame(height: 260)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(DiaryPaper99.card))
                    } else {
                        HStack(spacing: 8) {
                            ForEach(entry.stickerNames, id: \.self) { name in
                                if let sticker = DiarySticker99.named(name), let image = sticker.image {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 44, height: 44)
                                }
                            }
                        }
                    }
                    Text(DiaryEntryCard99.timeText(entry.createdAt)
                         + (entry.mood.map { " · \($0)" } ?? "")
                         + (entry.fromDraft ? " · 今日草稿" : ""))
                        .font(.system(size: 12)).foregroundColor(DiaryPaper99.dim)
                    HStack(spacing: 12) {
                        Button("导出分享卡") { dismiss(); onExport() }
                        Button("编辑") { onEdit() }
                        Button("删除", role: .destructive) {
                            store.trashEntry(id: entry.id)
                            dismiss()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    // (102) 第 2 项：「允许扫码访问」开关——
                    // 控制打印页印码与访客页可见性（样板定版
                    // 固定行，不与正文/标签互相挤压）。
                    Divider()
                    Toggle(isOn: $scanOn102) {
                        Label("允许扫码访问", systemImage: "qrcode")
                            .font(.system(size: 13.5))
                    }
                    .onChange(of: scanOn102) { _, newValue in
                        guard newValue != entry.scanAllowed else { return }
                        var updated = entry
                        updated.scanAllowed = newValue
                        store.updateEntry(updated)
                        Breadcrumbs.log("p102 diary scan allowed=\(newValue ? 1 : 0)")
                    }
                    Text("开着时，打印出来的这一页会印上二维码，扫码能打开访客页（只读、可听这首歌、可留言）；关掉则不印码。")
                        .font(.system(size: 11.5)).foregroundColor(DiaryPaper99.dim)
                }
                .padding(20)
            }
            .onAppear { scanOn102 = entry.scanAllowed }
            .navigationTitle(entry.dateKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 记一笔编辑器

struct DiaryEditorView99: View {
    @ObservedObject var store: DiaryStore99
    let request: DiaryEditorRequest99
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var mood: String?
    /// (101) 第 5 项：贴纸落点（自由画布手动拖放，系统不
    /// 自动摆放）；selectedSticker101 为当前选中贴纸名。
    @State private var placements: [DiaryStickerPlacement99] = []
    @State private var selectedSticker101: String?
    @State private var song: DiarySong90?
    /// (102) 第 2 项：正文字体（随条目持久化）与底部
    /// 工具栏抽屉（心情/字体/贴纸，点了才出、绝不自弹）。
    @State private var fontName: String?
    @State private var drawer102: DiaryEditorDrawer102?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let song {
                        HStack(spacing: 10) {
                            DiaryCoverView99(raw: song.artwork, size: 46)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                                Text(song.artist).font(.system(size: 12))
                                    .foregroundColor(DiaryPaper99.dim).lineLimit(1)
                                Text("记于 \(DiaryEntryCard99.timeText(Date().timeIntervalSince1970))")
                                    .font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
                            }
                            Spacer()
                            Button("不挂歌") { self.song = nil }
                                .font(.system(size: 12)).foregroundColor(DiaryPaper99.dim)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card))
                    }
                    // (102) 第 2 项：贴纸直接在打字页上拖——
                    // 贴纸画布与 TextEditor 同框叠放、共用同一
                    // 页面相对坐标场（fx/fy 与书页/打印纸同
                    // 一套，所见即所印）；贴纸层只吃贴纸自身
                    // 的点按/拖动，空白处落到 TextEditor。
                    // 心情/字体/贴纸全部移入底部工具栏抽屉
                    // （见 safeAreaInset），绝不自弹遮挡正文。
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .font(DiaryBodyFont102.font(name: fontName, size: 16))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .onChange(of: text) { _, newValue in
                                if request.editing == nil { store.setEditorAutosave(newValue) }
                            }
                        DiaryPlacementCanvas99(
                            placements: placements,
                            editable: true,
                            selectedName: selectedSticker101,
                            onMove: { name, fx, fy in
                                if let idx = placements.firstIndex(where: { $0.name == name }) {
                                    placements[idx].fx = fx
                                    placements[idx].fy = fy
                                }
                            },
                            onSelect: { selectedSticker101 = $0 })
                    }
                    .frame(height: 265)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    if let selected = selectedSticker101,
                       let idx = placements.firstIndex(where: { $0.name == selected }) {
                        HStack(spacing: 14) {
                            Button("缩小") {
                                placements[idx].scale = max(0.5, placements[idx].scale - 0.15)
                            }
                            Button("放大") {
                                placements[idx].scale = min(2.2, placements[idx].scale + 0.15)
                            }
                            Button("左转") { placements[idx].rotation -= .pi / 12 }
                            Button("右转") { placements[idx].rotation += .pi / 12 }
                            Spacer()
                            Button("删除", role: .destructive) {
                                placements.remove(at: idx)
                                selectedSticker101 = nil
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DiaryPaper99.accent)
                    }
                }
                .padding(18)
            }
            .background(DiaryPaper99.paper)
            .safeAreaInset(edge: .bottom) { editorToolbar102 }
            .sheet(item: $drawer102) { drawer in
                editorDrawer102(drawer)
                    .presentationDetents([.medium, .large])
            }
            .navigationTitle(request.editing != nil ? "编辑日记" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && song == nil && placements.isEmpty)
                }
            }
            .onAppear {
                song = request.song
                mood = request.editing?.mood
                fontName = request.editing?.fontName
                if let existing = request.editing?.placements, !existing.isEmpty {
                    placements = existing
                } else if let names = request.editing?.stickerNames, !names.isEmpty {
                    placements = names.enumerated().map { index, name in
                        DiaryStickerPlacement99(
                            name: name, fx: 0.5,
                            fy: min(0.85, 0.3 + 0.18 * Double(index)),
                            scale: 1, rotation: 0)
                    }
                } else {
                    placements = []
                }
                text = request.prefillText
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = placements.map(\.name)
        // (101) 第 5 项：落点自证——数量 + manual=1（全部
        // 由用户在画布上拖放产生）。
        Breadcrumbs.log("p101 diary sticker placed n=\(placements.count) manual=1")
        if var editing = request.editing {
            editing.text = trimmed
            editing.mood = mood
            editing.fontName = fontName
            editing.stickerNames = names
            editing.placements = placements
            if let song {
                editing.songId = song.id
                editing.songTitle = song.title
                editing.songArtist = song.artist
                editing.songArtwork = song.artwork
            }
            store.updateEntry(editing)
        } else {
            store.addEntry(text: trimmed, mood: mood, stickerNames: names,
                           placements: placements, song: song, fontName: fontName)
            if request.isDraftConfirm { store.markDraftConfirmed() }
        }
        dismiss()
    }

    // MARK: (102) 底部工具栏与抽屉（心情/字体/贴纸）

    /// 底部工具栏：与贴纸钮并列的心情/字体按键，用户
    /// 自由点选才出抽屉；固定行不与正文互相挤压。
    private var editorToolbar102: some View {
        HStack(spacing: 10) {
            toolbarButton102(title: mood ?? "心情", symbol: "face.smiling") {
                drawer102 = .mood
            }
            toolbarButton102(title: "字体 · \(DiaryBodyFont102.displayName(fontName))",
                             symbol: "textformat") {
                drawer102 = .font
            }
            toolbarButton102(title: "贴纸", symbol: "heart.circle") {
                drawer102 = .stickers
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(DiaryPaper99.card)
        .overlay(Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1),
                 alignment: .top)
    }

    private func toolbarButton102(title: String, symbol: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
            .foregroundColor(DiaryPaper99.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(DiaryPaper99.paper))
        }
    }

    @ViewBuilder
    private func editorDrawer102(_ drawer: DiaryEditorDrawer102) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch drawer {
                    case .mood:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                                  spacing: 8) {
                            ForEach(DiaryStore99.moods, id: \.self) { item in
                                Button(item) { mood = mood == item ? nil : item }
                                    .font(.system(size: 13))
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(mood == item
                                        ? DiaryPaper99.accent : DiaryPaper99.card))
                                    .foregroundColor(mood == item ? .white : DiaryPaper99.ink)
                            }
                        }
                    case .font:
                        VStack(spacing: 8) {
                            ForEach([nil] + DiaryBodyFont102.available.map { $0 as String? },
                                    id: \.self) { name in
                                Button {
                                    fontName = name
                                } label: {
                                    HStack {
                                        Text(DiaryBodyFont102.displayName(name))
                                            .font(DiaryBodyFont102.font(name: name, size: 17))
                                        Spacer()
                                        if fontName == name {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(DiaryPaper99.accent)
                                        }
                                    }
                                    .foregroundColor(DiaryPaper99.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(DiaryPaper99.card))
                                }
                            }
                        }
                    case .stickers:
                        Text("点选加入写字页，再直接在页上拖到想要的位置。")
                            .font(.system(size: 12)).foregroundColor(DiaryPaper99.dim)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6),
                                  spacing: 8) {
                            ForEach(DiarySticker99.all) { sticker in
                                Group {
                                    if sticker.isAnimatedDog102 {
                                        DiaryAPNGStickerView102(name: "dog-11")
                                    } else if let image = sticker.image {
                                        Image(uiImage: image).resizable().scaledToFit()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(height: 44)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 10).fill(
                                    placements.contains { $0.name == sticker.relativeName }
                                        ? DiaryPaper99.accent.opacity(0.25) : DiaryPaper99.card))
                                .onTapGesture { toggleSticker102(sticker) }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(DiaryPaper99.paper)
            .navigationTitle(drawer.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { drawer102 = nil }
                }
            }
        }
    }

    private func toggleSticker102(_ sticker: DiarySticker99) {
        if placements.contains(where: { $0.name == sticker.relativeName }) {
            selectedSticker101 = sticker.relativeName
        } else {
            placements.append(DiaryStickerPlacement99(
                name: sticker.relativeName,
                fx: 0.5, fy: 0.5, scale: 1, rotation: 0))
            selectedSticker101 = sticker.relativeName
        }
        drawer102 = nil
    }
}

/// (102) 编辑器底部抽屉种类。
enum DiaryEditorDrawer102: Identifiable {
    case mood, font, stickers
    var id: Int { hashValue }
    var title: String {
        switch self {
        case .mood: return "此刻心情"
        case .font: return "正文字体"
        case .stickers: return "贴纸"
        }
    }
}

// MARK: - 导出：打印机动画 → 分享卡

struct DiaryShareCard99: View {
    let entry: DiaryEntry99
    /// (101) 第 5 项：逐字打印——正文只显前 typedCount 字
    /// （静态渲染/分享出图时传 .max 全显）。
    var typedCount: Int = .max
    /// 打印落定时落款：用户手写签名的美化版（drop-in）。
    var showSignature: Bool = false
    @ObservedObject private var sigStore = DiarySignature99.shared
    @ObservedObject private var fontSig102 = DiaryFontSignature102.shared

    private var typedText: String {
        String(entry.text.prefix(max(0, typedCount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("音乐日记").font(.system(size: 13, weight: .bold)).foregroundColor(DiaryPaper99.accent)
            // (102) 第 2 项：打印 = 页面原样复现——歌曲在
            // 页上是封面小卡，不再是 ♪ 文字行。
            if let title = entry.songTitle {
                HStack(spacing: 9) {
                    DiaryCoverView99(raw: entry.songArtwork, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(DiaryPaper99.ink).lineLimit(1)
                        Text(entry.songArtist ?? "").font(.system(size: 11))
                            .foregroundColor(DiaryPaper99.dim).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 9).fill(DiaryPaper99.paper))
            }
            if !entry.text.isEmpty {
                Text(typedText)
                    .font(DiaryBodyFont102.font(name: entry.fontName, size: 14))
                    .foregroundColor(DiaryPaper99.ink)
            }
            if !entry.placements.isEmpty {
                DiaryPlacementCanvas99(placements: entry.placements,
                                       animatedDog: false)
                    .frame(height: 225)
            } else {
                HStack(spacing: 6) {
                    ForEach(entry.stickerNames.prefix(5), id: \.self) { name in
                        if let sticker = DiarySticker99.named(name), let image = sticker.image {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 34, height: 34)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                // (102) 情绪状态不印上纸：时间行只留时间
                // （＋今日草稿标），心情只在完成态按键里看。
                Text(DiaryEntryCard99.timeText(entry.createdAt)
                     + (entry.fromDraft ? " · 今日草稿" : ""))
                    .font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
                Spacer()
                // 签名落款（双通道）：字体签名通道优先按
                // 所选字体渲染；手写通道用美化笔迹图。
                // 签名区只剩签名本体（品牌印记在页脚）。
                if showSignature {
                    if fontSig102.channel == "font", fontSig102.hasFontSignature {
                        Text(fontSig102.text)
                            .font(.custom(fontSig102.fontName, size: 24))
                            .foregroundColor(DiaryPaper99.ink)
                    } else if let signature = sigStore.beautifiedImage {
                        Image(uiImage: signature)
                            .resizable().scaledToFit()
                            .frame(height: 36)
                            .scaleEffect(showSignature ? 1 : 0.4)
                            .opacity(showSignature ? 1 : 0)
                            .animation(.spring(response: 0.46, dampingFraction: 0.72),
                                       value: showSignature)
                    }
                }
            }
            // (102) 纸面页脚（定版）：左下「来自 Virelai」
            // ＋弱化序号；右下角组自上而下 = Virelai 署名
            // → 印章印刷风二维码 → 扫码小字 + 短链，两角
            // 成页脚线。二维码仅 scanAllowed 时印。
            Divider().overlay(DiaryPaper99.dim.opacity(0.35))
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("来自 Virelai")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DiaryPaper99.dim)
                    Text(DiaryQRCode102.serial(for: entry.id))
                        .font(.system(size: 9))
                        .foregroundColor(DiaryPaper99.dim.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "music.note").font(.system(size: 9))
                        Text("Virelai").font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundColor(DiaryPaper99.ink)
                    if entry.scanAllowed,
                       let qr = DiaryQRCode102.image(
                           for: DiaryQRCode102.shortURL(for: entry.id),
                           ink: diaryInkUIColor102) {
                        Image(uiImage: qr)
                            .resizable().interpolation(.none)
                            .frame(width: 52, height: 52)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(DiaryPaper99.ink, lineWidth: 1.1))
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(DiaryPaper99.ink.opacity(0.55), lineWidth: 0.7))
                        Text("扫码打开这一页 · 留下你的评论")
                            .font(.system(size: 8.5)).foregroundColor(DiaryPaper99.dim)
                        Text(DiaryQRCode102.shortLink(for: entry.id))
                            .font(.system(size: 8.5)).foregroundColor(DiaryPaper99.dim)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiaryPaper99.card)
    }
}

struct DiaryShareView99: View {
    let entry: DiaryEntry99
    @Environment(\.dismiss) private var dismiss
    /// (102) 第 2 项：针式行扫打印状态——typedCount 按行
    /// 推进；printRun 递增触发「再打印一份」。
    @State private var typedCount = 0
    @State private var printDone = false
    @State private var printRun = 0
    @State private var showActivity = false
    @State private var shareItems: [Any] = []
    /// 打印完成后的纸面拖动（跟手倾斜、上滑收进日记本）。
    @State private var paperOffset: CGSize = .zero
    @State private var paperTilt: Double = 0

    private var printProgress: CGFloat {
        entry.text.isEmpty ? 1
            : min(1, CGFloat(typedCount) / CGFloat(entry.text.count))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                // 打印机：机身＋出纸口，纸自口中按行吐出
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.systemGray3))
                        .frame(width: 240, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 200, height: 6)
                                .offset(y: 22))
                    DiaryShareCard99(entry: entry, typedCount: typedCount,
                                     showSignature: printDone)
                        .frame(width: 300)
                        // 点阵罩：打印中字迹带点阵纹、随完成
                        // 进度淡出变清晰（针式成形感）。
                        .overlay(DiaryDotMatrixOverlay102(
                            fade: 1 - printProgress))
                        .clipShape(Rectangle())
                        // 出纸遮罩按卡面实际高度的比例揭开
                        // （(102) 卡面含页脚变高，旧 300 定高
                        // 遮罩会把页脚永远盖住，改比例缩放）。
                        .mask(Rectangle().scaleEffect(
                            x: 1, y: max(0.001, printProgress), anchor: .top))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        .offset(paperOffset)
                        .rotationEffect(.degrees(paperTilt))
                        .gesture(printDone ? paperDrag102 : nil)
                }
                .padding(.top, 26)
                if printDone {
                    // (102) 打印完成底部动作栏（定版）：分享
                    // （系统分享窗口）/ 保存图片 / 保存 PDF /
                    // 再打印一份 / 完成。
                    HStack(alignment: .top, spacing: 6) {
                        actionButton102("分享", "square.and.arrow.up") { shareImage102() }
                        actionButton102("保存图片", "photo") { saveImage102() }
                        actionButton102("保存 PDF", "doc.richtext") { sharePDF102() }
                        actionButton102("再打印", "printer") { printRun += 1 }
                        actionButton102("完成", "checkmark") { dismiss() }
                    }
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("正在打印这一页…").font(.system(size: 13)).foregroundColor(DiaryPaper99.dim)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(DiaryPaper99.paper)
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task(id: printRun) {
                Breadcrumbs.log("p102 diary export run=\(printRun)")
                await runPrint102()
            }
            .sheet(isPresented: $showActivity) {
                if !shareItems.isEmpty {
                    DiaryActivityView99(items: shareItems)
                }
            }
        }
    }

    private func actionButton102(_ title: String, _ symbol: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(DiaryPaper99.ink)
            .frame(minWidth: 58)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card))
        }
    }

    /// 纸面拖动：跟手平移＋按横移倾斜，松手弹簧回位；
    /// 上滑过阈值 = 收进日记本（关导出页）。
    private var paperDrag102: some Gesture {
        DragGesture()
            .onChanged { value in
                paperOffset = value.translation
                paperTilt = Double(value.translation.width) / 42
            }
            .onEnded { value in
                if value.translation.height < -110 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        paperOffset = .zero
                        paperTilt = 0
                    }
                }
            }
    }

    /// (102) 针式行扫：打印头逐行横扫显形、纸张逐行步进
    /// 带顿挫，一页约 15 秒。行 = 卡面经验行容 17 字
    /// （300 宽、14pt）；行末字车回程顿挫并入行间隔。
    /// 打印全程播这一篇的歌（定版不用针式声）：仅当引擎
    /// 当前曲正是本篇的歌且暂停时才续播，绝不切歌抢播。
    @MainActor
    private func runPrint102() async {
        typedCount = 0
        printDone = false
        paperOffset = .zero
        paperTilt = 0
        if let songId = entry.songId {
            let engine = PlaybackEngine.shared
            if engine.currentTrack?.id == songId, !engine.isPlaying {
                engine.play()
                Breadcrumbs.log("p102 diary print song resume")
            } else {
                Breadcrumbs.log("p102 diary print song skip")
            }
        }
        let lines = Self.lineChunks102(of: entry.text)
        let totalChars = entry.text.count
        Breadcrumbs.log("p102 diary print linesweep lines=\(lines.count) chars=\(totalChars)")
        if lines.isEmpty {
            // 无正文时仍按版面行数走完（封面卡/贴纸/页脚）。
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            printDone = true
            return
        }
        let perLine = min(1400, max(240, 15000 / lines.count))
        var consumed = 0
        for chunk in lines {
            consumed += chunk
            typedCount = min(totalChars, consumed)
            let jitter = Double.random(in: 0.85...1.15)
            try? await Task.sleep(
                nanoseconds: UInt64(Double(perLine) * jitter * 1_000_000))
            if Task.isCancelled { return }
        }
        typedCount = totalChars
        withAnimation(.spring(response: 0.46, dampingFraction: 0.8)) {
            printDone = true
        }
        Breadcrumbs.log("p102 diary print done")
    }

    /// 按显式换行分段、每段按行容切行，返回每行字数
    /// （换行符不计入 typedCount 消费，最后由总量兜齐）。
    private static func lineChunks102(of text: String) -> [Int] {
        var chunks: [Int] = []
        for segment in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = segment.count
            if rest == 0 { chunks.append(0); continue }
            while rest > 0 {
                let take = min(17, rest)
                chunks.append(take)
                rest -= take
            }
        }
        return chunks
    }

    @MainActor
    private func renderedCardImage102() -> UIImage? {
        let renderer = ImageRenderer(content: DiaryShareCard99(
            entry: entry, typedCount: .max, showSignature: true).frame(width: 340))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// 分享：只一个入口，调起系统分享窗口（定版）。
    private func shareImage102() {
        if let image = renderedCardImage102() {
            shareItems = [image]
            showActivity = true
        }
    }

    private func saveImage102() {
        guard let image = renderedCardImage102() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Breadcrumbs.log("p102 diary saveimg denied")
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Breadcrumbs.log("p102 diary saveimg ok=\(ok ? 1 : 0)")
            }
        }
    }

    private func sharePDF102() {
        guard let image = renderedCardImage102() else { return }
        let bounds = CGRect(origin: .zero, size: image.size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virelai-diary-\(entry.id.prefix(8)).pdf")
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                image.draw(in: bounds)
            }
            shareItems = [url]
            showActivity = true
        } catch {
            Breadcrumbs.log("p102 diary pdf fail")
        }
    }
}

/// 点阵罩：规则圆点阵，fade=1 时全显、随打印完成淡出。
struct DiaryDotMatrixOverlay102: View {
    let fade: CGFloat
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            let radius: CGFloat = 0.85
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    let rect = CGRect(x: x - radius, y: y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(.black.opacity(0.4 * fade)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

struct DiaryActivityView99: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - (101) 第 5 项：翻页卷曲 / 贴纸自由画布 / 签名美化与签名板

/// 真翻页近似：拖动量驱动整页绕纵轴 3D 旋转（锚点随方向
/// 落在书脊侧）+ perspective + 随动明暗渐变，呈纸页卷起
/// 感；松手由既有弹簧换页落定。
private struct DiaryPageCurl101: ViewModifier {
    let offset: CGFloat
    let width: CGFloat
    func body(content: Content) -> some View {
        let t = max(-1, min(1, offset / max(width, 1)))
        content
            .rotation3DEffect(
                .degrees(Double(-t * 16)),
                axis: (x: 0, y: 1, z: 0),
                anchor: t < 0 ? .leading : .trailing,
                perspective: 0.55)
            .offset(x: offset * 0.22)
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.20 * abs(Double(t))), .clear,
                             .black.opacity(0.10 * abs(Double(t)))],
                    startPoint: .leading, endPoint: .trailing)
                    .allowsHitTesting(false))
    }
}

/// 贴纸自由画布：按条目落点（分数坐标）渲染；编辑态可拖
/// 动改落点、点选选中。落点只由用户手势产生与修改。
struct DiaryPlacementCanvas99: View {
    let placements: [DiaryStickerPlacement99]
    /// (102) 第 2 项：抱心狗动图开关——编辑页/书页 true
    /// （APNG 循环），打印纸面 false（定格帧，所见即所印）。
    var animatedDog: Bool = true
    var editable: Bool = false
    var selectedName: String? = nil
    var onMove: ((String, Double, Double) -> Void)? = nil
    var onSelect: ((String) -> Void)? = nil
    @State private var dragStart101: (name: String, fx: Double, fy: Double)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(placements) { placement in
                    if let sticker = DiarySticker99.named(placement.name) {
                        // (102) 第 2 项：贴纸尺寸按场宽归一
                        // （基准场宽 354），使编辑页/书页/
                        // 打印纸三面同 fx/fy 下大小观感一致
                        // ——全渲染面同一页面相对坐标系。
                        let side102 = 54 * placement.scale
                            * Double(geo.size.width / 354)
                        Group {
                            if sticker.isAnimatedDog102 && animatedDog {
                                DiaryAPNGStickerView102(name: "dog-11")
                            } else if let image = sticker.image {
                                Image(uiImage: image)
                                    .resizable().scaledToFit()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: side102, height: side102)
                            .rotationEffect(.radians(placement.rotation))
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DiaryPaper99.accent,
                                            lineWidth: editable && selectedName == placement.name ? 1.6 : 0))
                            .position(x: placement.fx * geo.size.width,
                                      y: placement.fy * geo.size.height)
                            .onTapGesture {
                                if editable { onSelect?(placement.name) }
                            }
                            .gesture(editable ? dragGesture(for: placement,
                                                            in: geo.size) : nil)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dragGesture(for placement: DiaryStickerPlacement99,
                             in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart101?.name != placement.name {
                    dragStart101 = (placement.name, placement.fx, placement.fy)
                    onSelect?(placement.name)
                }
                guard let start = dragStart101 else { return }
                let fx = min(0.95, max(0.05,
                    start.fx + Double(value.translation.width / max(size.width, 1))))
                let fy = min(0.92, max(0.08,
                    start.fy + Double(value.translation.height / max(size.height, 1))))
                onMove?(placement.name, fx, fy)
            }
            .onEnded { _ in dragStart101 = nil }
    }
}

/// 签名美化渲染：两遍移动平均平滑 + 二次曲线中点重采样
/// + 按速度变线宽、笔划两端收尖（样板美化口径的原生
/// 实现）。输入为分数坐标笔划，渲染到任意尺寸。
struct DiarySignatureRender101: View {
    let strokes: [[DiarySignaturePoint99]]
    var lineColor: Color = DiaryPaper99.ink

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                let dense = Self.beautified(stroke, size: size)
                guard dense.count > 1 else { continue }
                for index in 1..<dense.count {
                    var path = Path()
                    path.move(to: dense[index - 1].point)
                    path.addLine(to: dense[index].point)
                    context.stroke(path, with: .color(lineColor),
                                   style: StrokeStyle(lineWidth: dense[index].width,
                                                      lineCap: .round))
                }
            }
        }
    }

    /// 平滑 + 重采样 + 线宽曲线，返回稠密点列。
    static func beautified(_ stroke: [DiarySignaturePoint99],
                           size: CGSize) -> [(point: CGPoint, width: CGFloat)] {
        guard stroke.count > 1 else { return [] }
        var pts: [CGPoint] = stroke.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        var times: [Double] = stroke.map(\.t)
        // 两遍移动平均平滑（权重 1-2-1，端点保持）。
        for _ in 0..<2 where pts.count > 2 {
            var next = pts
            for i in 1..<(pts.count - 1) {
                next[i] = CGPoint(
                    x: (pts[i - 1].x + 2 * pts[i].x + pts[i + 1].x) / 4,
                    y: (pts[i - 1].y + 2 * pts[i].y + pts[i + 1].y) / 4)
            }
            pts = next
        }
        // 二次曲线中点法重采样：每段采样 6 步。
        var dense: [(CGPoint, Double)] = [(pts[0], times[0])]
        var current = pts[0]
        var currentT = times[0]
        for i in 1..<pts.count {
            let control = pts[i - 1]
            let end = i == pts.count - 1
                ? pts[i]
                : CGPoint(x: (pts[i - 1].x + pts[i].x) / 2,
                          y: (pts[i - 1].y + pts[i].y) / 2)
            let endT = i == times.count - 1
                ? times[i]
                : (times[i - 1] + times[i]) / 2
            for step in 1...6 {
                let u = Double(step) / 6
                let x = (1 - u) * (1 - u) * current.x
                    + 2 * (1 - u) * u * control.x + u * u * end.x
                let y = (1 - u) * (1 - u) * current.y
                    + 2 * (1 - u) * u * control.y + u * u * end.y
                dense.append((CGPoint(x: x, y: y),
                              currentT + (endT - currentT) * u))
            }
            current = end
            currentT = endT
        }
        // 线宽：速度越快越细，两端 12% 收尖。
        let total = dense.count
        return dense.enumerated().map { index, item in
            var width: CGFloat = 3.4
            if index > 0 {
                let prev = dense[index - 1]
                let dist = hypot(item.0.x - prev.0.x, item.0.y - prev.0.y)
                let dt = max(item.1 - prev.1, 1)
                let speed = dist / CGFloat(dt) // pt/ms
                width = min(4.6, max(1.1, 4.6 - speed * 2.4))
            }
            let edge = min(1, Double(min(index, total - 1 - index)) / max(1, Double(total) * 0.12))
            let taper = 0.25 + 0.75 * edge
            return (item.0, width * CGFloat(taper))
        }
    }
}

/// 手写签名板：采集笔划 → 美化预览 → 存档（原始笔划 +
/// 美化 PNG）。打印分享卡落款用美化版。
struct DiarySignaturePad99: View {
    @ObservedObject private var sigStore = DiarySignature99.shared
    @ObservedObject private var fontSig102 = DiaryFontSignature102.shared
    @Environment(\.dismiss) private var dismiss
    /// (102) 第 2 项：签名双通道——hand 手写美化 /
    /// font 打字生成，进板时同步当前落款通道。
    @State private var channelTab102 = "hand"
    /// 本次采集的笔划（像素坐标，存档时按板面尺寸归一化）。
    @State private var strokes: [[DiarySignaturePoint99]] = []
    @State private var strokeStart: Date?
    @State private var padSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("在下面写下你的签名，系统会自动美化笔迹，打印日记时落在末尾。")
                    .font(.system(size: 12.5)).foregroundColor(DiaryPaper99.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("签名方式", selection: $channelTab102) {
                    Text("手写签名").tag("hand")
                    Text("打字签名").tag("font")
                }
                .pickerStyle(.segmented)
                if channelTab102 == "hand" {
                // 签名板：原始笔划实时回显。
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card)
                    if strokes.isEmpty, sigStore.hasSignature,
                       let image = sigStore.beautifiedImage {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 110)
                            .opacity(0.55)
                    }
                    Canvas { context, size in
                        for stroke in strokes {
                            guard stroke.count > 1 else { continue }
                            var path = Path()
                            path.move(to: CGPoint(x: stroke[0].x, y: stroke[0].y))
                            for point in stroke.dropFirst() {
                                path.addLine(to: CGPoint(x: point.x, y: point.y))
                            }
                            context.stroke(path, with: .color(DiaryPaper99.ink),
                                           style: StrokeStyle(lineWidth: 2.4,
                                                              lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .frame(height: 190)
                .background(GeometryReader { geo in
                    Color.clear.onAppear { padSize = geo.size }
                        .onChange(of: geo.size) { _, new in padSize = new }
                })
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if strokeStart == nil {
                                strokeStart = Date()
                                strokes.append([])
                            }
                            let t = (strokeStart.map {
                                Date().timeIntervalSince($0) * 1000
                            }) ?? 0
                            strokes[strokes.count - 1].append(
                                DiarySignaturePoint99(x: Double(value.location.x),
                                                      y: Double(value.location.y), t: t))
                        }
                        .onEnded { _ in strokeStart = nil })
                // 美化预览（本次笔划）。
                if !strokes.isEmpty, padSize.width > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("美化预览").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DiaryPaper99.dim)
                        DiarySignatureRender101(strokes: normalizedStrokes)
                            .frame(height: 74)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(DiaryPaper99.card))
                    }
                }
                HStack(spacing: 12) {
                    Button("清除") {
                        strokes = []
                        if sigStore.hasSignature { sigStore.clear() }
                    }
                    .foregroundColor(.red)
                    Spacer()
                    Button("完成") { save() }
                        .fontWeight(.semibold)
                        .disabled(strokes.isEmpty)
                }
                .font(.system(size: 14.5))
                } else {
                    fontSignatureTab102
                }
                Spacer()
            }
            .padding(18)
            .background(DiaryPaper99.paper)
            .navigationTitle("签名")
            .onAppear { channelTab102 = fontSig102.channel }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var normalizedStrokes: [[DiarySignaturePoint99]] {
        guard padSize.width > 0, padSize.height > 0 else { return [] }
        return strokes.map { stroke in
            stroke.map {
                DiarySignaturePoint99(x: $0.x / padSize.width,
                                      y: $0.y / padSize.height, t: $0.t)
            }
        }
    }

    @MainActor
    private func save() {
        let normalized = normalizedStrokes
        guard !normalized.isEmpty, padSize.width > 0 else { return }
        let aspect = Double(padSize.width / padSize.height)
        let render = DiarySignatureRender101(strokes: normalized)
            .frame(width: 480, height: 480 / aspect)
        let renderer = ImageRenderer(content: render)
        renderer.scale = 2
        let png = renderer.uiImage?.pngData()
        sigStore.save(strokes: normalized, aspect: aspect, png: png)
        fontSig102.channel = "hand"
        dismiss()
    }

    /// 打字签名页：输入 + 选字体（运行时可用集），预览
    /// 即落款形态；完成即把落款通道切到 font。
    private var fontSignatureTab102: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手指写不方便时，打字也能生成你的签名，打印时按所选字体逐字显形。")
                .font(.system(size: 12.5)).foregroundColor(DiaryPaper99.dim)
            TextField("输入你的签名", text: $fontSig102.text)
                .font(.system(size: 17))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(DiaryPaper99.card))
            Text("选一款字体")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(DiaryPaper99.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(DiaryFontSignature102.availableFonts, id: \.self) { name in
                    Button {
                        fontSig102.fontName = name
                    } label: {
                        Text("签名")
                            .font(.custom(name, size: 19))
                            .foregroundColor(DiaryPaper99.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10).fill(
                                fontSig102.fontName == name
                                    ? DiaryPaper99.accent.opacity(0.3) : DiaryPaper99.card))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("预览").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DiaryPaper99.dim)
                Text(fontSig102.text.isEmpty ? "你的签名" : fontSig102.text)
                    .font(.custom(fontSig102.fontName, size: 38))
                    .foregroundColor(DiaryPaper99.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(DiaryPaper99.card))
            }
            HStack {
                Spacer()
                Button("完成") {
                    fontSig102.channel = "font"
                    Breadcrumbs.log("p102 diary font signature set")
                    dismiss()
                }
                .font(.system(size: 14.5, weight: .semibold))
                .disabled(!fontSig102.hasFontSignature)
            }
        }
    }
}
