import UIKit

/// port90（任务 23）：封面 ➕ 钮单一工厂——墙面砖/控制台条带/
/// 拍立得三处共用同一形态：24pt 深色半透圆钮＋白色 plus；
/// 已贴入态变琥珀底＋白色对勾。状态只读 DiaryStore90 单源。
enum DiaryAddButton90 {

    /// 尺寸恒 24×24：约束宿主自行钉宽高，帧管理宿主直接给帧
    /// （本工厂不预设 translatesAutoresizingMaskIntoConstraints）。
    static func make() -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 12
        button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        button.tintColor = .white
        button.accessibilityLabel = "贴进日记本"
        return button
    }

    static func refresh(_ button: UIButton, songId: String?) {
        let added = songId.map { DiaryStore90.contains(songId: $0) } ?? false
        let name = added ? "checkmark" : "plus"
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        button.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
        button.backgroundColor = added
            ? UIColor(red: 0.85, green: 0.62, blue: 0.15, alpha: 0.95)
            : UIColor.black.withAlphaComponent(0.55)
    }
}

/// port90（任务 22/23）：日记本数据层（日记本改名「日记本」后的
/// 歌曲收藏＋每日日记）。单源存储，各封面 ➕ 态、拍立得 ➕ 态、
/// 日记本页都读这一处，状态天然一致。
///
/// 存法（本机持久化）：
/// - 贴入歌曲与日记条目：JSON 编码后存 UserDefaults
///   （diary90.songs / diary90.entries），量级小、无需建库。
/// - 涂鸦画作：PNG 文件落 Documents/diary90/<条目id>.png，
///   条目里只存文件名。
/// 变更广播 .foliaDiary90Changed（计数角标/➕ 态回刷）。
struct DiarySong90: Codable, Equatable {
    var id: String
    var title: String
    var artist: String
    var artwork: String?

    init(track: FoliaTrack) {
        id = track.id
        title = track.title
        artist = track.artist
        artwork = track.artworkURL?.absoluteString
    }

    init(id: String, title: String, artist: String, artwork: String?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artwork = artwork
    }
}

struct DiaryEntry90: Codable, Identifiable {
    var id: String
    /// 听众日键 yyyy-MM-dd（本地时区）。
    var dateKey: String
    var text: String
    var songId: String?
    var songTitle: String?
    var songArtist: String?
    /// Documents/diary90/ 下的 PNG 文件名（无画作为 nil）。
    var sketchFile: String?
    var createdAt: TimeInterval
}

enum DiaryStore90 {

    private static let songsKey = "diary90.songs"
    private static let entriesKey = "diary90.entries"

    static var songs: [DiarySong90] {
        get {
            guard let data = UserDefaults.standard.data(forKey: songsKey),
                  let list = try? JSONDecoder().decode([DiarySong90].self, from: data)
            else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: songsKey)
            }
        }
    }

    static var entries: [DiaryEntry90] {
        get {
            guard let data = UserDefaults.standard.data(forKey: entriesKey),
                  let list = try? JSONDecoder().decode([DiaryEntry90].self, from: data)
            else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: entriesKey)
            }
        }
    }

    static func contains(songId: String) -> Bool {
        songs.contains { $0.id == songId }
    }

    /// 贴入/撤下切换（封面 ➕ 与拍立得 ➕ 共用）；返回切换后是否已贴入。
    @discardableResult
    static func toggle(_ song: DiarySong90) -> Bool {
        var list = songs
        if let idx = list.firstIndex(where: { $0.id == song.id }) {
            list.remove(at: idx)
            songs = list
            postChange()
            return false
        }
        list.insert(song, at: 0)
        songs = list
        postChange()
        return true
    }

    static func removeSong(id: String) {
        var list = songs
        list.removeAll { $0.id == id }
        songs = list
        postChange()
    }

    /// 存一条日记（文字可空但须至少有文字/歌曲/画作之一，调用方把关）。
    /// sketchPNG 非空时落盘并在条目里记文件名。
    @discardableResult
    static func addEntry(text: String, song: DiarySong90?, sketchPNG: Data?) -> DiaryEntry90 {
        let id = UUID().uuidString
        var sketchFile: String?
        if let png = sketchPNG, !png.isEmpty {
            let dir = sketchDirectory()
            let url = dir.appendingPathComponent("\(id).png")
            if (try? png.write(to: url, options: .atomic)) != nil {
                sketchFile = "\(id).png"
            }
        }
        let entry = DiaryEntry90(
            id: id,
            dateKey: Self.dateKey(for: Date()),
            text: text,
            songId: song?.id,
            songTitle: song?.title,
            songArtist: song?.artist,
            sketchFile: sketchFile,
            createdAt: Date().timeIntervalSince1970)
        var list = entries
        list.insert(entry, at: 0)
        entries = list
        postChange()
        return entry
    }

    static func sketchURL(for entry: DiaryEntry90) -> URL? {
        guard let file = entry.sketchFile else { return nil }
        return sketchDirectory().appendingPathComponent(file)
    }

    static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func sketchDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("diary90", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func postChange() {
        NotificationCenter.default.post(name: .foliaDiary90Changed, object: nil)
        Breadcrumbs.log("port90 diary songs=\(songs.count) entries=\(entries.count)")
    }
}

extension Notification.Name {
    static let foliaDiary90Changed = Notification.Name("foliaDiary90Changed")
}
