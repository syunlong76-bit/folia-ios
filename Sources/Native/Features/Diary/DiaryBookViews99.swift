import SwiftUI
import UIKit

// DiaryBookViews99.swift — (99) 第 7 项书主页（SwiftUI）：
// 书页式布局（竖屏单页 / 横屏双页摊开，滑动翻页近似实现）、
// 今日草稿、时间轴、日历、歌曲聚合、回收站五页；记一笔编辑器、
// 条目详情、打印机动画＋分享卡导出在本文件内成套。
//
// 配色照已审样板与 DiaryViewController90 纸面口径：暖奶油纸面＋深墨字，
// 深色模式下走深纸面（可读优先）。

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
                    .offset(x: dragOffset)
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
                        Text(entry.text).font(.system(size: 15.5))
                    }
                    HStack(spacing: 8) {
                        ForEach(entry.stickerNames, id: \.self) { name in
                            if let sticker = DiarySticker99.named(name), let image = sticker.image {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 44, height: 44)
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
                }
                .padding(20)
            }
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
    @State private var pickedStickers: [String] = []
    @State private var song: DiarySong90?

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
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(DiaryPaper99.card))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
                        .onChange(of: text) { _, newValue in
                            if request.editing == nil { store.setEditorAutosave(newValue) }
                        }
                    if !pickedStickers.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(pickedStickers, id: \.self) { name in
                                if let sticker = DiarySticker99.named(name), let image = sticker.image {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 40, height: 40)
                                        .onTapGesture { pickedStickers.removeAll { $0 == name } }
                                }
                            }
                        }
                    }
                    Text("此刻心情").font(.system(size: 13, weight: .semibold)).foregroundColor(DiaryPaper99.dim)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
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
                    Text("贴纸（点选贴入正文区）").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DiaryPaper99.dim)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(DiarySticker99.all) { sticker in
                            Group {
                                if let image = sticker.image {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(height: 44)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(
                                pickedStickers.contains(sticker.relativeName)
                                    ? DiaryPaper99.accent.opacity(0.25) : DiaryPaper99.card))
                            .onTapGesture {
                                if pickedStickers.contains(sticker.relativeName) {
                                    pickedStickers.removeAll { $0 == sticker.relativeName }
                                } else {
                                    pickedStickers.append(sticker.relativeName)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(DiaryPaper99.paper)
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
                                  && song == nil && pickedStickers.isEmpty)
                }
            }
            .onAppear {
                song = request.song
                mood = request.editing?.mood
                pickedStickers = request.editing?.stickerNames ?? []
                text = request.prefillText
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if var editing = request.editing {
            editing.text = trimmed
            editing.mood = mood
            editing.stickerNames = pickedStickers
            if let song {
                editing.songId = song.id
                editing.songTitle = song.title
                editing.songArtist = song.artist
                editing.songArtwork = song.artwork
            }
            store.updateEntry(editing)
        } else {
            store.addEntry(text: trimmed, mood: mood, stickerNames: pickedStickers, song: song)
            if request.isDraftConfirm { store.markDraftConfirmed() }
        }
        dismiss()
    }
}

// MARK: - 导出：打印机动画 → 分享卡

struct DiaryShareCard99: View {
    let entry: DiaryEntry99
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("音乐日记").font(.system(size: 13, weight: .bold)).foregroundColor(DiaryPaper99.accent)
            if let title = entry.songTitle {
                Text("♪ \(title)\(entry.songArtist.map { " · \($0)" } ?? "")")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(DiaryPaper99.ink)
            }
            if !entry.text.isEmpty {
                Text(entry.text).font(.system(size: 14)).foregroundColor(DiaryPaper99.ink)
            }
            HStack(spacing: 6) {
                ForEach(entry.stickerNames.prefix(5), id: \.self) { name in
                    if let sticker = DiarySticker99.named(name), let image = sticker.image {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 34, height: 34)
                    }
                }
            }
            Text(DiaryEntryCard99.timeText(entry.createdAt) + (entry.mood.map { " · \($0)" } ?? ""))
                .font(.system(size: 11)).foregroundColor(DiaryPaper99.dim)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiaryPaper99.card)
    }
}

struct DiaryShareView99: View {
    let entry: DiaryEntry99
    @Environment(\.dismiss) private var dismiss
    @State private var printProgress: CGFloat = 0
    @State private var showActivity = false
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                // 打印机：机身＋出纸口，纸自口中缓吐、内容随进度显现
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.systemGray3))
                        .frame(width: 240, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 200, height: 6)
                                .offset(y: 22))
                    DiaryShareCard99(entry: entry)
                        .frame(width: 300)
                        .clipShape(Rectangle())
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle().frame(height: max(1, 190 * printProgress))
                                Color.clear
                            }
                            .frame(maxHeight: .infinity, alignment: .top))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                }
                .padding(.top, 26)
                if printProgress >= 1 {
                    Button {
                        renderAndShare()
                    } label: {
                        Label("分享 / 存相册", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(Capsule().fill(DiaryPaper99.accent))
                            .foregroundColor(.white)
                    }
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
            .onAppear {
                Breadcrumbs.log("p99 diary export")
                withAnimation(.easeInOut(duration: 1.8)) { printProgress = 1 }
            }
            .sheet(isPresented: $showActivity) {
                if let renderedImage {
                    DiaryActivityView99(items: [renderedImage])
                }
            }
        }
    }

    @MainActor
    private func renderAndShare() {
        let renderer = ImageRenderer(content: DiaryShareCard99(entry: entry).frame(width: 340))
        renderer.scale = 3
        if let image = renderer.uiImage {
            renderedImage = image
            showActivity = true
        }
    }
}

struct DiaryActivityView99: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
