import Foundation

/// 管理本地服务器的静态文件根目录（与安卓版同构）：
/// - app 包内 Resources/Web 为前端 v1 全量文件（folder reference 打包，Bundle 内名为 "Web"）
/// - 首次启动拷贝到 Documents/web/v1
/// - 更新包下载解压后落在 Documents/web/v{n}，记为 pendingWebVersion；
///   下次冷启动时若 pending > active 且目录完整（含 index.html），切换为生效版本
final class WebRootManager {

    static let shared = WebRootManager()

    private let defaults = UserDefaults.standard
    private let fm = FileManager.default

    private enum Keys {
        static let active = "activeWebVersion"
        static let pending = "pendingWebVersion"
    }

    /// 当前生效的前端版本号
    private(set) var activeWebVersion: Int = 1

    /// 已下载、待下次冷启动生效的前端版本号（0 = 无）
    var pendingWebVersion: Int {
        get { defaults.integer(forKey: Keys.pending) }
        set { defaults.set(newValue, forKey: Keys.pending) }
    }

    /// Documents/web 目录
    var webBaseDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("web", isDirectory: true)
    }

    /// 当前生效版本目录（本地服务器的静态根目录）
    var activeWebDir: URL {
        webBaseDir.appendingPathComponent("v\(activeWebVersion)", isDirectory: true)
    }

    func versionDir(_ version: Int) -> URL {
        webBaseDir.appendingPathComponent("v\(version)", isDirectory: true)
    }

    private init() {}

    /// 冷启动时调用：确保 v1 存在；处理 pending 切换；清理无用旧版本目录。
    func prepare() {
        do {
            try fm.createDirectory(at: webBaseDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[WebRoot] create webBaseDir failed: \(error)")
        }

        var active = defaults.integer(forKey: Keys.active)
        if active <= 0 { active = 1 }

        // 首次启动：把包内 Web 拷贝为 v1
        let v1Dir = versionDir(1)
        if !isComplete(dir: v1Dir) {
            if let bundled = Bundle.main.url(forResource: "Web", withExtension: nil) {
                do {
                    if fm.fileExists(atPath: v1Dir.path) {
                        try fm.removeItem(at: v1Dir)
                    }
                    try fm.copyItem(at: bundled, to: v1Dir)
                } catch {
                    NSLog("[WebRoot] copy bundled Web failed: \(error)")
                }
            } else {
                NSLog("[WebRoot] bundled Web folder not found in app bundle")
            }
        }

        // pending 切换：版本更高且目录完整才生效
        let pending = pendingWebVersion
        if pending > active, isComplete(dir: versionDir(pending)) {
            active = pending
            pendingWebVersion = 0
        }

        activeWebVersion = active
        defaults.set(active, forKey: Keys.active)

        cleanupOldVersions(keeping: [active, pendingWebVersion])
    }

    /// 目录完整性判据：存在 index.html 即视为完整（解压成功后写入 pending 前也会用它校验）
    func isComplete(dir: URL) -> Bool {
        fm.fileExists(atPath: dir.appendingPathComponent("index.html").path)
    }

    /// 删除既非生效、亦非待生效的历史版本目录，控制磁盘占用
    private func cleanupOldVersions(keeping: [Int]) {
        let keep = Set(keeping.filter { $0 > 0 }.map { "v\($0)" })
        guard let entries = try? fm.contentsOfDirectory(atPath: webBaseDir.path) else { return }
        for entry in entries where entry.hasPrefix("v") && !keep.contains(entry) {
            try? fm.removeItem(at: webBaseDir.appendingPathComponent(entry))
        }
    }
}
