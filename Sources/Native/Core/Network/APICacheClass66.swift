import Foundation

/// (66) API 缓存分类（网页「缓存分类·歌单数据分仓」的原生
/// 落点）：LocalServer 的 GET 磁盘缓存文件名是哈希、无从
/// 按类区分——写缓存时按 target 路径分类登记 sidecar 清
/// 单（folia-api/folia-class-manifest.json），设置页据此
/// 对「歌单数据」单独统计与清除，其余 API 缓存不受影响。
/// 清单为尽力登记（并发写以末写为准），漏记的文件仍在
/// API 总缓存内、可经宿主「API 缓存」整类清除。
enum APICacheClass66 {

    static let playlistClass = "playlist"

    /// folia-api 目录（与 LocalServer.Proxy 的 apiCacheDir
    /// 同口径；Proxy 为文件私有，本面按既定目录名直查）。
    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-api", isDirectory: true)
    }

    private static var manifestURL: URL {
        cacheDirectory.appendingPathComponent("folia-class-manifest.json")
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private static func save(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// 写缓存时调用：歌单类 target（路径含 playlist）登记。
    static func note(file: URL, target: String) {
        guard target.contains("playlist") else { return }
        var map = load()
        map[file.lastPathComponent] = playlistClass
        save(map)
    }

    /// 某分类的缓存文件总字节（文件已被淘汰的条目自动忽略）。
    static func sizeBytes(forClass cls: String) -> Int {
        let dir = APICacheClass66.cacheDirectory
        return load().filter { $0.value == cls }.reduce(0) { sum, entry in
            let url = dir.appendingPathComponent(entry.key)
            return sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// 逐分类清除：删该类文件并摘清单条目，返回释放字节。
    @discardableResult
    static func clear(cls: String) -> Int {
        let dir = APICacheClass66.cacheDirectory
        var map = load()
        var freed = 0
        for (name, value) in map where value == cls {
            let url = dir.appendingPathComponent(name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if (try? FileManager.default.removeItem(at: url)) != nil { freed += size }
            map.removeValue(forKey: name)
        }
        save(map)
        Breadcrumbs.log("settings66.cacheClass clear=\(cls) freed=\(freed)")
        return freed
    }
}
