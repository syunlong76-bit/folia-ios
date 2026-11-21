import Foundation

// NavidromeClient62.swift
//
// 3.7 (62) WC 簇 §4.9 组 L：Navidrome / Subsonic REST 客户端。
// 协议按 Subsonic API 规范（https://www.subsonic.org/pages/api.jsp）：
// - 认证：u=<user>&t=md5(password+salt)&s=<salt>&v=1.16.1&c=Folia&f=json
// - 端点：/rest/ping、/rest/getPlaylists、/rest/getMusicDirectory、
//   /rest/getAlbumList2、/rest/getSong、/rest/stream?id=
// 配置读 SettingsStore62C（开关/地址/用户名）＋ SecretStore62C
// （密码，Keychain）。无服务器可测：以协议正确＋失败诚实回显
// 为准，未真机联调（见交付报告外部依赖表）。

struct NavidromePlaylist62: Identifiable, Equatable {
    let id: String
    let name: String
    let songCount: Int
    let coverArtId: String?
}

struct NavidromeAlbum62: Identifiable, Equatable {
    let id: String
    let name: String
    let artist: String
    let songCount: Int
    let coverArtId: String?
}

struct NavidromeDirectory62 {
    let id: String
    let name: String
    let childTracks: [FoliaTrack]
    let childAlbums: [NavidromeAlbum62]
}

enum NavidromeError62: Error, LocalizedError {
    case notConfigured
    case disabled
    case badURL
    case http(status: Int)
    case api(code: Int, message: String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Navidrome 地址/用户名/密码未配置完整"
        case .disabled: return "Navidrome 连接未开启"
        case .badURL: return "Navidrome 服务器地址无效"
        case .http(let s): return "Navidrome 服务器返回 HTTP \(s)"
        case .api(let c, let m): return "Navidrome 接口错误 \(c)：\(m)"
        case .decoding: return "Navidrome 响应无法解析"
        }
    }
}

final class NavidromeClient62 {

    static let shared = NavidromeClient62()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    var isConfigured: Bool {
        !SettingsStore.navidromeBaseURL62.trimmingCharacters(in: .whitespaces).isEmpty
            && !SettingsStore.navidromeUsername62.trimmingCharacters(in: .whitespaces).isEmpty
            && SecretStore62C.read(account: SecretStore62C.navidromePasswordAccount) != nil
    }

    // MARK: - 认证与基础请求

    /// Subsonic token 认证参数（每次请求新盐）。
    private func authQueryItems() throws -> [URLQueryItem] {
        guard SettingsStore.navidromeEnabled62 else { throw NavidromeError62.disabled }
        guard isConfigured else { throw NavidromeError62.notConfigured }
        let password = SecretStore62C.read(account: SecretStore62C.navidromePasswordAccount) ?? ""
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let token = MD5Hex62.of(password + salt)
        return [
            URLQueryItem(name: "u", value: SettingsStore.navidromeUsername62),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Folia"),
            URLQueryItem(name: "f", value: "json"),
        ]
    }

    private func baseURL() throws -> URL {
        let raw = SettingsStore.navidromeBaseURL62
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty else { throw NavidromeError62.notConfigured }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: withScheme) else { throw NavidromeError62.badURL }
        return url
    }

    /// GET /rest/<endpoint>，返回 subsonic-response 的内层字典。
    private func request(_ endpoint: String,
                         extra: [URLQueryItem] = []) async throws -> [String: Any] {
        let base = try baseURL()
        var components = URLComponents(
            url: base.appendingPathComponent("rest").appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false)
        components?.queryItems = try authQueryItems() + extra
        guard let url = components?.url else { throw NavidromeError62.badURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NavidromeError62.http(status: http.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["subsonic-response"] as? [String: Any] else {
            throw NavidromeError62.decoding
        }
        if (body["status"] as? String) == "failed" {
            let error = body["error"] as? [String: Any]
            throw NavidromeError62.api(
                code: (error?["code"] as? NSNumber)?.intValue ?? -1,
                message: (error?["message"] as? String) ?? "未知错误")
        }
        return body
    }

    // MARK: - 业务

    /// 连接测试：真 ping，回显服务器版本与类型。
    func ping() async throws -> String {
        let body = try await request("ping")
        let version = (body["version"] as? String) ?? "?"
        let type = (body["type"] as? String) ?? "subsonic"
        Breadcrumbs.log("navidrome62.ping ok type=\(type) version=\(version)")
        return "\(type) · API \(version)"
    }

    func fetchPlaylists() async throws -> [NavidromePlaylist62] {
        let body = try await request("getPlaylists")
        let container = body["playlists"] as? [String: Any]
        let list = container?["playlist"] as? [[String: Any]] ?? []
        return list.compactMap { raw in
            guard let id = Self.string(raw["id"]), let name = raw["name"] as? String
            else { return nil }
            return NavidromePlaylist62(
                id: id, name: name,
                songCount: (raw["songCount"] as? NSNumber)?.intValue ?? 0,
                coverArtId: Self.string(raw["coverArt"]))
        }
    }

    func fetchAlbumList(size: Int = 60) async throws -> [NavidromeAlbum62] {
        let body = try await request("getAlbumList2", extra: [
            URLQueryItem(name: "type", value: "alphabeticalByName"),
            URLQueryItem(name: "size", value: "\(size)"),
        ])
        let container = body["albumList2"] as? [String: Any]
        let list = container?["album"] as? [[String: Any]] ?? []
        return list.compactMap(Self.album)
    }

    /// 目录（歌单 id / 专辑 id / 歌手 id 通用）：子项分歌曲与子目录。
    func fetchDirectory(id: String) async throws -> NavidromeDirectory62 {
        let body = try await request("getMusicDirectory", extra: [
            URLQueryItem(name: "id", value: id),
        ])
        let dir = body["directory"] as? [String: Any] ?? [:]
        let children = dir["child"] as? [[String: Any]] ?? []
        var tracks: [FoliaTrack] = []
        var albums: [NavidromeAlbum62] = []
        for child in children {
            let isDir = (child["isDir"] as? NSNumber)?.boolValue ?? false
            if isDir {
                if let album = Self.album(child) { albums.append(album) }
            } else if let track = Self.track(child) {
                tracks.append(track)
            }
        }
        return NavidromeDirectory62(
            id: Self.string(dir["id"]) ?? id,
            name: (dir["name"] as? String) ?? "",
            childTracks: tracks, childAlbums: albums)
    }

    /// stream URL 拼装（播放时现拼，含当次盐/令牌；不落盘）。
    func streamURL(songId: String) -> URL? {
        guard isConfigured, SettingsStore.navidromeEnabled62,
              let base = try? baseURL(),
              let password = SecretStore62C.read(account: SecretStore62C.navidromePasswordAccount)
        else { return nil }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var components = URLComponents(
            url: base.appendingPathComponent("rest").appendingPathComponent("stream"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: songId),
            URLQueryItem(name: "u", value: SettingsStore.navidromeUsername62),
            URLQueryItem(name: "t", value: MD5Hex62.of(password + salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Folia"),
        ]
        return components?.url
    }

    func coverArtURL(coverArtId: String, size: Int = 300) -> URL? {
        guard isConfigured,
              let base = try? baseURL(),
              let password = SecretStore62C.read(account: SecretStore62C.navidromePasswordAccount)
        else { return nil }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var components = URLComponents(
            url: base.appendingPathComponent("rest").appendingPathComponent("getCoverArt"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: coverArtId),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "u", value: SettingsStore.navidromeUsername62),
            URLQueryItem(name: "t", value: MD5Hex62.of(password + salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Folia"),
        ]
        return components?.url
    }

    // MARK: - 解析

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func album(_ raw: [String: Any]) -> NavidromeAlbum62? {
        guard let id = string(raw["id"]) else { return nil }
        return NavidromeAlbum62(
            id: id,
            name: (raw["name"] as? String) ?? (raw["title"] as? String) ?? "",
            artist: (raw["artist"] as? String) ?? "",
            songCount: (raw["songCount"] as? NSNumber)?.intValue ?? 0,
            coverArtId: string(raw["coverArt"]))
    }

    private static func track(_ raw: [String: Any]) -> FoliaTrack? {
        guard let id = string(raw["id"]) else { return nil }
        let coverId = string(raw["coverArt"])
        return FoliaTrack(
            id: "navi_\(id)",
            sourceType: .netease,
            title: (raw["title"] as? String) ?? "",
            artist: (raw["artist"] as? String) ?? "未知歌手",
            album: (raw["album"] as? String) ?? "",
            duration: (raw["duration"] as? NSNumber)?.doubleValue ?? 0,
            artworkURL: coverId.flatMap {
                NavidromeClient62.shared.coverArtURL(coverArtId: $0)
            })
    }
}
