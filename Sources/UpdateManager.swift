import Foundation
import CryptoKit
import ZIPFoundation

/// 更新清单结构（与线上 https://folia-music.netlify.app/app-update.json 对齐，
/// 与安卓版共用同一份清单）：
///
///     {
///       "webVersion": 2,
///       "url": "https://folia-music.netlify.app/bundles/folia-web-2.zip",
///       "sha256": "<zip 文件 SHA-256 十六进制>",
///       "size": 13268768
///     }
///
/// 流程（与安卓一致）：比较版本 → 下载 zip → 校验 size 与 sha256 → 解压 →
/// 完整性校验（index.html 存在）→ 记 pendingWebVersion，下次冷启动由
/// WebRootManager 切换生效。任何一步失败都静默保留旧版，只更新状态字符串。
struct UpdateManifest: Decodable {
    let webVersion: Int
    let url: String
    let sha256: String
    let size: Int64?
}

final class UpdateManager {

    static let shared = UpdateManager()

    static let manifestURL = URL(string: "https://folia-music.netlify.app/app-update.json")!

    private let defaults = UserDefaults.standard
    private let workQueue = DispatchQueue(label: "com.miller.folia.updater")
    private var checking = false

    private enum Keys {
        static let auto = "autoUpdateEnabled"
        static let lastResult = "lastUpdateCheckResult"
    }

    /// 自动更新开关（默认开，UserDefaults 持久化）
    var autoUpdateEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.auto) == nil { return true }
            return defaults.bool(forKey: Keys.auto)
        }
        set { defaults.set(newValue, forKey: Keys.auto) }
    }

    /// 上次检查结果（人类可读字符串，含时间；设置页展示用）
    private(set) var lastCheckResult: String {
        get { defaults.string(forKey: Keys.lastResult) ?? "尚未检查" }
        set { defaults.set(newValue, forKey: Keys.lastResult) }
    }

    private init() {}

    // MARK: - 对外入口

    /// 检查更新（可在任意线程调用；completion 回主线程）
    func checkNow(completion: ((String) -> Void)?) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.checking else {
                self.finish("检查正在进行中", completion: completion)
                return
            }
            self.checking = true
            defer { self.checking = false }
            let result = self.performCheck()
            self.finish(result, completion: completion)
        }
    }

    private func finish(_ result: String, completion: ((String) -> Void)?) {
        let stamped = "\(UpdateManager.timestamp()) \(result)"
        lastCheckResult = stamped
        if let completion = completion {
            DispatchQueue.main.async { completion(stamped) }
        }
    }

    // MARK: - 主流程（在 workQueue 上同步执行）

    private func performCheck() -> String {
        let active = WebRootManager.shared.activeWebVersion

        // 1) 拉清单
        let manifest: UpdateManifest
        switch fetchManifest() {
        case .success(let m): manifest = m
        case .failure(let message): return "检查更新失败：\(message)"
        }

        // 2) 比较版本
        if manifest.webVersion <= active {
            return "已是最新版本（前端 v\(active)）"
        }
        if manifest.webVersion == WebRootManager.shared.pendingWebVersion,
           WebRootManager.shared.isComplete(dir: WebRootManager.shared.versionDir(manifest.webVersion)) {
            return "新版本 v\(manifest.webVersion) 已下载，重启应用后生效"
        }

        // 3) 下载
        guard let zipURL = URL(string: manifest.url) else {
            return "检查更新失败：清单中的下载地址无效"
        }
        let tmpZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("folia-web-\(manifest.webVersion).zip")
        switch download(url: zipURL, to: tmpZip) {
        case .success: break
        case .failure(let message): return "下载新版本失败：\(message)"
        }
        defer { try? FileManager.default.removeItem(at: tmpZip) }

        // 4) 校验 size
        if let expectedSize = manifest.size {
            let attrs = try? FileManager.default.attributesOfItem(atPath: tmpZip.path)
            let actual = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
            if actual != expectedSize {
                return "下载新版本失败：文件大小校验不符（期望 \(expectedSize)，实际 \(actual)）"
            }
        }

        // 5) 校验 sha256
        do {
            let digest = try sha256Hex(of: tmpZip)
            if digest.lowercased() != manifest.sha256.lowercased() {
                return "下载新版本失败：SHA-256 校验不符，已丢弃"
            }
        } catch {
            return "下载新版本失败：计算校验和出错（\(error.localizedDescription)）"
        }

        // 6) 解压到暂存目录 → 完整性校验 → 落位版本目录 → 记 pending
        let fm = FileManager.default
        let staging = WebRootManager.shared.webBaseDir
            .appendingPathComponent(".staging-v\(manifest.webVersion)", isDirectory: true)
        let dest = WebRootManager.shared.versionDir(manifest.webVersion)
        do {
            if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.unzipItem(at: tmpZip, to: staging)
            guard WebRootManager.shared.isComplete(dir: staging) else {
                try? fm.removeItem(at: staging)
                return "下载新版本失败：解压结果不完整（缺 index.html），已丢弃"
            }
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: staging, to: dest)
        } catch {
            return "下载新版本失败：解压出错（\(error.localizedDescription)）"
        }

        WebRootManager.shared.pendingWebVersion = manifest.webVersion
        return "已下载新版本 v\(manifest.webVersion)，重启应用后生效"
    }

    // MARK: - 网络（同步小工具，基于 semaphore；仅在 workQueue 上使用）

    private enum SimpleResult<T> {
        case success(T)
        case failure(String)
    }

    private func fetchManifest() -> SimpleResult<UpdateManifest> {
        var request = URLRequest(url: UpdateManager.manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        var outcome: SimpleResult<UpdateManifest> = .failure("无响应")
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error = error {
                outcome = .failure(error.localizedDescription)
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                outcome = .failure("清单请求返回 \(code)")
                return
            }
            do {
                outcome = .success(try JSONDecoder().decode(UpdateManifest.self, from: data))
            } catch {
                outcome = .failure("清单解析失败（\(error.localizedDescription)）")
            }
        }.resume()
        _ = semaphore.wait(timeout: .now() + 45)
        return outcome
    }

    private func download(url: URL, to destination: URL) -> SimpleResult<Void> {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 300
        var outcome: SimpleResult<Void> = .failure("无响应")
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.downloadTask(with: request) { tmp, response, error in
            defer { semaphore.signal() }
            if let error = error {
                outcome = .failure(error.localizedDescription)
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let tmp = tmp else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                outcome = .failure("下载请求返回 \(code)")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tmp, to: destination)
                outcome = .success(())
            } catch {
                outcome = .failure(error.localizedDescription)
            }
        }.resume()
        _ = semaphore.wait(timeout: .now() + 330)
        return outcome
    }

    // MARK: - 校验和

    /// 流式计算文件 SHA-256（前端更新包十几 MB，分块读不占内存）
    private func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20)
            guard let chunk = chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}
