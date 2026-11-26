import Foundation

// SyncService62.swift
//
// 3.7 (62) WC 簇 §4.9 组 L：同步服务（R2 口径的通用 REST 同步）。
// 协议假设（设置页 hint 与报告同文）：服务端在 base URL 下提供
//   PUT  <base>/folia-sync.json   （整体写入 JSON）
//   GET  <base>/folia-sync.json   （读回同一 JSON）
// 鉴权：Authorization: Bearer <令牌>（令牌存 Keychain）。
// 同步对象：设置域（SettingsConfigTransfer 白名单导出）＋日记本
// 数据（Documents/folia-sketchbook.json 原文）。不含登录态/队列。
// 服务端形态未定（R2/S3/自建皆可，只要满足上面两条 REST 约定），
// 无服务端可测时以请求真发＋状态诚实回显为准。

enum SyncService62 {

    struct Payload: Codable {
        var version: Int = 1
        var syncedAt: TimeInterval = Date().timeIntervalSince1970
        /// 设置域：SettingsConfigTransfer 配置码原文（Base64），
        /// 拉回时原样走 importCode（白名单＋类型护栏不另写一套）。
        var settingsCode: String? = nil
        /// 日记本文件原文（Base64），避免嵌套 JSON 转义歧义。
        var sketchbookBase64: String? = nil
    }

    enum SyncError: Error, LocalizedError {
        case notConfigured
        case http(status: Int)
        case decoding
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "同步地址或令牌未配置"
            case .http(let s): return "同步服务返回 HTTP \(s)"
            case .decoding: return "同步数据无法解析"
            }
        }
    }

    private static var endpointURL: URL? {
        let raw = SettingsStore.syncBaseURL62
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard let base = URL(string: withScheme) else { return nil }
        return base.appendingPathComponent("folia-sync.json")
    }

    private static var token: String? {
        SecretStore62C.read(account: SecretStore62C.syncTokenAccount)
    }

    static var isConfigured: Bool { endpointURL != nil && token != nil }

    private static var sketchbookFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-sketchbook.json")
    }

    static func makePayload() -> Payload {
        var payload = Payload()
        payload.syncedAt = Date().timeIntervalSince1970
        payload.settingsCode = SettingsConfigTransfer.exportCode()
        if let data = try? Data(contentsOf: sketchbookFileURL) {
            payload.sketchbookBase64 = data.base64EncodedString()
        }
        return payload
    }

    /// 推送（PUT 整体写入）。返回人类可读结果并落 lastStatus。
    @discardableResult
    static func push() async -> String {
        guard SettingsStore.syncEnabled62 else { return finish("同步未开启") }
        guard let url = endpointURL, let token else {
            return finish("推送失败：\(SyncError.notConfigured.localizedDescription)")
        }
        do {
            let data = try JSONEncoder().encode(makePayload())
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status) else {
                throw SyncError.http(status: status)
            }
            Breadcrumbs.log("sync62.push ok bytes=\(data.count)")
            return finish("推送成功 · \(Self.timeText())")
        } catch {
            Breadcrumbs.log("sync62.push fail err=\(error.localizedDescription)")
            return finish("推送失败：\(error.localizedDescription)")
        }
    }

    /// 拉取（GET 读回并应用：设置经配置码通路导入，日记本文件
    /// 覆盖前先备份为 .bak62）。返回人类可读结果。
    @discardableResult
    static func pull() async -> String {
        guard SettingsStore.syncEnabled62 else { return finish("同步未开启") }
        guard let url = endpointURL, let token else {
            return finish("拉取失败：\(SyncError.notConfigured.localizedDescription)")
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status) else {
                throw SyncError.http(status: status)
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            var applied = 0
            if let code = payload.settingsCode {
                applied = SettingsConfigTransfer.importCode(code) ?? 0
            }
            if let base64 = payload.sketchbookBase64,
               let sketchData = Data(base64Encoded: base64) {
                let backup = sketchbookFileURL.appendingPathExtension("bak62")
                try? FileManager.default.copyItem(at: sketchbookFileURL, to: backup)
                try sketchData.write(to: sketchbookFileURL, options: .atomic)
            }
            Breadcrumbs.log("sync62.pull ok applied=\(applied)")
            return finish("拉取成功 · 应用设置 \(applied) 项 · \(Self.timeText())")
        } catch {
            Breadcrumbs.log("sync62.pull fail err=\(error.localizedDescription)")
            return finish("拉取失败：\(error.localizedDescription)")
        }
    }

    private static func finish(_ text: String) -> String {
        SettingsStore.syncLastStatus62 = text
        return text
    }

    private static func timeText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}
