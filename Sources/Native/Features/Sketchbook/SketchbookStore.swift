import Foundation
import Combine

// SketchbookStore.swift
//
// 速记簿数据层（(53) 工作流 D、(55) 工作流 H 补全六大块；对应
// folia-major 的 src/stores/useScratchpadStore.ts）：本机的、跨来源
// 的歌曲暂存区，与播放队列分开（收进来不动正在播的队列）、与歌单
// 分开（不在任何平台上建东西）。条目按加入先后追加（记事本语义），
// 按 FoliaTrack.id 去重（原生 id 已带来源前缀 ncm_/qq_/kg_/local_，
// 与网页版 getPlaybackSongKey 同一身份口径），满 1000 条拒收不挤旧。
//
// (55) H 起同文件内多带四份数据（同一份 JSON 信封 v2 落盘，老的
// 裸 [Entry] 数组文件照常读进来再升级）：
// - groups：用户自建分组（组头/折叠/条目归属）。网页版的分组是按
//   来源自动成组（scratchpadGroupKey），原生按 (55) 任务口径落
//   用户组：未归组的条目进「未分组」段，语义对照见 H 报告。
// - history：收进/移除/清空的历史事件（日期＋动作＋歌曲），从
//   (55) 起记，老数据没有历史（抽屉历史段如实空态）。
// - draft：队列草稿——从暂存条目编的一份独立顺序，一键替换当前
//   播放队列（QueueManager.setQueue），与抽屉里的「当前播放队列」
//   段是两回事。
// - 条目上的 canvasX/canvasY：画布形态里卡片的落点（槽位原点，
//   按 canvasLayout 的吸附语义算好后落盘；nil = 还没摆过，按组内
//   序号现算槽位）。
//
// 持久化照原生既有同类口径（LocalPlaylistStore / PlayHistoryStore
// 模板）：整表一份 JSON 落盘 Documents/folia-sketchbook.json、
// 原子写；曲目只存 FoliaTrack 元数据，播放在线地址按 id 现换，
// 不存任何流地址。

final class SketchbookStore: ObservableObject {

    static let shared = SketchbookStore()

    struct Entry: Codable {
        var track: FoliaTrack
        var addedAt: TimeInterval
        /// 收进来的出处小字（如「搜索」）；没有就不写（照网页版 origin）。
        var originLabel: String?
        /// 所在用户分组的 id；nil = 未分组。
        var groupId: String?
        /// 画布落点（槽位左上角，相对该组网格原点）；nil = 未摆过。
        var canvasX: Double?
        var canvasY: Double?
    }

    struct Group: Codable {
        var id: String
        var name: String
        var collapsed: Bool
    }

    /// 一条历史事件：收进（add）/ 移除（remove）/ 清空（clear）。
    struct HistoryEvent: Codable {
        var at: TimeInterval
        var action: String
        /// 歌曲标题/歌手快照（清空时 title 是「全部 N 首」）。
        var title: String
        var artist: String
    }

    private struct PersistedFile: Codable {
        var version: Int
        var entries: [Entry]
        var groups: [Group]
        var history: [HistoryEvent]
        var draft: [FoliaTrack]
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var groups: [Group] = []
    @Published private(set) var history: [HistoryEvent] = []
    @Published private(set) var draft: [FoliaTrack] = []

    private let fileURL: URL
    /// 网页版 SCRATCHPAD_CAPACITY：满了拒收而不挤掉旧的。
    private static let capacity = 1000
    /// 历史只留最近这么多条，防文件无限长。
    private static let historyCapacity = 500

    private init() {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("folia-sketchbook.json")
        load()
    }

    // MARK: - 查询

    func contains(trackId: String) -> Bool {
        entries.contains { $0.track.id == trackId }
    }

    /// 某组（nil = 未分组）的条目，保持整本里的先后序。
    func entries(inGroup groupId: String?) -> [Entry] {
        entries.filter { $0.groupId == groupId }
    }

    func group(id: String) -> Group? {
        groups.first { $0.id == id }
    }

    /// 今天（本地日历）新收进的条数，总览用。
    var addedTodayCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
            .timeIntervalSince1970
        return entries.filter { $0.addedAt >= start }.count
    }

    // MARK: - 增删（带历史）

    /// 收进一首：已在里面或已满则拒收，返回是否真收下了。
    /// source 只进面包屑（如 search / drawer），不落盘。
    @discardableResult
    func add(_ track: FoliaTrack, source: String, originLabel: String? = nil) -> Bool {
        if contains(trackId: track.id) {
            Breadcrumbs.log("sketchbook.add source=\(source) id=\(track.id) dup=1")
            return false
        }
        guard entries.count < Self.capacity else {
            Breadcrumbs.log("sketchbook.add source=\(source) id=\(track.id) full=1")
            return false
        }
        entries.append(Entry(
            track: track,
            addedAt: Date().timeIntervalSince1970,
            originLabel: originLabel))
        recordHistory(action: "add", title: track.title, artist: track.artist)
        save()
        Breadcrumbs.log("sketchbook.add source=\(source) id=\(track.id) total=\(entries.count)")
        return true
    }

    func remove(trackId: String, source: String) {
        guard let victim = entries.first(where: { $0.track.id == trackId })
        else { return }
        entries.removeAll { $0.track.id == trackId }
        draft.removeAll { $0.id == trackId }
        recordHistory(
            action: "remove", title: victim.track.title,
            artist: victim.track.artist)
        save()
        Breadcrumbs.log("sketchbook.remove source=\(source) id=\(trackId) total=\(entries.count)")
    }

    func clear(source: String) {
        guard !entries.isEmpty else { return }
        let count = entries.count
        entries = []
        draft = []
        recordHistory(action: "clear", title: "全部 \(count) 首", artist: "")
        save()
        Breadcrumbs.log("sketchbook.clear source=\(source)")
    }

    // MARK: - 分组

    @discardableResult
    func createGroup(name: String) -> Group {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = Group(
            id: "g_\(Int(Date().timeIntervalSince1970 * 1000))_\(groups.count)",
            name: trimmed.isEmpty ? "分组 \(groups.count + 1)" : trimmed,
            collapsed: false)
        groups.append(group)
        save()
        Breadcrumbs.log("sketchbook.group create id=\(group.id) total=\(groups.count)")
        return group
    }

    /// 删组：组内条目回未分组，不删歌。
    func deleteGroup(id: String, source: String) {
        guard groups.contains(where: { $0.id == id }) else { return }
        groups.removeAll { $0.id == id }
        for index in entries.indices where entries[index].groupId == id {
            entries[index].groupId = nil
            entries[index].canvasX = nil
            entries[index].canvasY = nil
        }
        save()
        Breadcrumbs.log("sketchbook.group delete source=\(source) id=\(id)")
    }

    func setGroupCollapsed(id: String, collapsed: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == id }),
              groups[index].collapsed != collapsed else { return }
        groups[index].collapsed = collapsed
        save()
        Breadcrumbs.log("sketchbook.group collapse id=\(id) collapsed=\(collapsed)")
    }

    /// 把一条挪进某组（nil = 未分组）；换组后画布落点作废、回槽位序。
    func assign(trackId: String, toGroup groupId: String?, source: String) {
        guard let index = entries.firstIndex(where: { $0.track.id == trackId }),
              entries[index].groupId != groupId else { return }
        entries[index].groupId = groupId
        entries[index].canvasX = nil
        entries[index].canvasY = nil
        save()
        Breadcrumbs.log(
            "sketchbook.group assign source=\(source) id=\(trackId) group=\(groupId ?? "none")")
    }

    // MARK: - 画布落点 / 组内排序（canvasLayout 语义）

    /// 画布拖动松手：记下落点（已按槽位吸附算好的原点）。
    func setCanvasPosition(trackId: String, x: Double, y: Double) {
        guard let index = entries.firstIndex(where: { $0.track.id == trackId })
        else { return }
        entries[index].canvasX = x
        entries[index].canvasY = y
        save()
    }

    /// 组内挪动（照网页版 moveWithinGroup）：把一条挪到组内
    /// targetIndex（以挪走之后为准），只改这一组在整本里占着的
    /// 那些位置，别的组的条目原地不动。
    func moveWithinGroup(trackId: String, groupId: String?, targetIndex: Int) {
        var slots: [Int] = []
        var groupEntries: [Entry] = []
        for (index, entry) in entries.enumerated()
        where entry.groupId == groupId {
            slots.append(index)
            groupEntries.append(entry)
        }
        guard let from = groupEntries.firstIndex(where: { $0.track.id == trackId })
        else { return }
        let moving = groupEntries.remove(at: from)
        let at = min(max(targetIndex, 0), groupEntries.count)
        guard at != from else { return }
        groupEntries.insert(moving, at: at)
        for (offset, slot) in slots.enumerated() {
            entries[slot] = groupEntries[offset]
        }
        save()
        Breadcrumbs.log(
            "sketchbook.canvas move id=\(trackId) group=\(groupId ?? "none") to=\(at)")
    }

    // MARK: - 队列草稿

    @discardableResult
    func addToDraft(_ track: FoliaTrack, source: String) -> Bool {
        guard !draft.contains(where: { $0.id == track.id }) else {
            Breadcrumbs.log("sketchbook.draft add source=\(source) id=\(track.id) dup=1")
            return false
        }
        draft.append(track)
        save()
        Breadcrumbs.log("sketchbook.draft add source=\(source) id=\(track.id) total=\(draft.count)")
        return true
    }

    func removeFromDraft(trackId: String, source: String) {
        let before = draft.count
        draft.removeAll { $0.id == trackId }
        guard draft.count != before else { return }
        save()
        Breadcrumbs.log("sketchbook.draft remove source=\(source) id=\(trackId) total=\(draft.count)")
    }

    /// 草稿内换序（上/下移一格或拖拽落点都收敛到这一处）。
    func moveDraftItem(from: Int, to: Int) {
        guard draft.indices.contains(from) else { return }
        let target = min(max(to, 0), draft.count - 1)
        guard target != from else { return }
        let item = draft.remove(at: from)
        draft.insert(item, at: target)
        save()
        Breadcrumbs.log("sketchbook.draft move from=\(from) to=\(target)")
    }

    func clearDraft(source: String) {
        guard !draft.isEmpty else { return }
        draft = []
        save()
        Breadcrumbs.log("sketchbook.draft clear source=\(source)")
    }

    // MARK: - 历史

    private func recordHistory(action: String, title: String, artist: String) {
        history.append(HistoryEvent(
            at: Date().timeIntervalSince1970,
            action: action, title: title, artist: artist))
        if history.count > Self.historyCapacity {
            history.removeFirst(history.count - Self.historyCapacity)
        }
    }

    /// 历史按天分段（新的在前）：照网页版 historyDays 的本地零点
    /// 分界口径，只是事件源是速记簿自己的收进/移除（见文件头）。
    func historyByDay() -> [(dayStart: TimeInterval, events: [HistoryEvent])] {
        var days: [(dayStart: TimeInterval, events: [HistoryEvent])] = []
        for event in history.reversed() {
            let start = Calendar.current.startOfDay(
                for: Date(timeIntervalSince1970: event.at))
                .timeIntervalSince1970
            if var last = days.last, last.dayStart == start {
                last.events.append(event)
                days[days.count - 1] = last
            } else {
                days.append((dayStart: start, events: [event]))
            }
        }
        return days
    }

    // MARK: - 落盘

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(PersistedFile.self, from: data) {
            entries = file.entries
            groups = file.groups
            history = file.history
            draft = file.draft
            Breadcrumbs.log(
                "sketchbook.load n=\(entries.count) groups=\(groups.count) history=\(history.count) draft=\(draft.count)")
            return
        }
        // (53)/(54) 的裸 [Entry] 数组：照读，写回时自动升级信封。
        if let legacy = try? decoder.decode([Entry].self, from: data) {
            entries = legacy
            Breadcrumbs.log("sketchbook.load n=\(entries.count) legacy=1")
        }
    }

    private func save() {
        let file = PersistedFile(
            version: 2, entries: entries, groups: groups,
            history: history, draft: draft)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
