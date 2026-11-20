import Foundation
import UIKit

/// (55) 工作流 G 设置支持层：缓存管理（真删）、内存读数、
/// 配置导出/导入（配置码）、发行说明文本页。与设置页本体
/// （SettingsViewController）同目录，设置页只负责行与动作，
/// 具体读写收在这里。

// MARK: - 缓存管理

/// 原生现有磁盘缓存两类（真实管理面在 LocalServer，本文件
/// 按其既定目录口径做大小统计与逐类清除——删的是
/// LocalServer 实际在用的缓存文件，删后其下一次请求自然
/// 未命中重取，不留假行）：
/// - cover：封面图磁盘缓存，LocalServer 的 Caches/folia-img
///   （LocalServer.swift `cacheDir`，.jpg 落盘）；
/// - api：接口 GET 磁盘缓存，LocalServer 的 Caches/folia-api
///   （LocalServer.swift `apiCacheDir`，.json 落盘）。
/// 歌词缓存（LyricRepository）为纯内存 LRU 且无公开清除/
/// 统计 API、文件不在本工作流域内，不在此立行（见交付报告）。
enum SettingsCacheManager {

    enum Kind: CaseIterable {
        case cover, api
        var directoryName: String {
            switch self {
            case .cover: return "folia-img"
            case .api: return "folia-api"
            }
        }
    }

    static func directory(for kind: Kind) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// 目录内文件总字节数（目录不存在 = 0）。
    static func sizeBytes(for kind: Kind) -> Int {
        let dir = directory(for: kind)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        return files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// 逐类清除：删目录内全部文件，返回实际删掉的字节数。
    @discardableResult
    static func clear(_ kind: Kind) -> Int {
        let dir = directory(for: kind)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var freed = 0
        for url in files {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if (try? fm.removeItem(at: url)) != nil { freed += size }
        }
        Breadcrumbs.log("settings.cache clear kind=\(kind.directoryName) freed=\(freed)")
        return freed
    }

    static func sizeText(_ bytes: Int) -> String {
        if bytes <= 0 { return "0 KB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return "\(max(1, bytes / 1024)) KB"
    }
}

// MARK: - 内存监控（开发者页签）

/// 当前进程常驻内存（mach_task_basic_info.resident_size）。
/// 读不到时返回 nil，设置页如实显示「—」。
enum SettingsMemoryMonitor {
    static func residentBytes() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size)
    }
}

// MARK: - 配置导出 / 导入（配置码）

/// 配置码 = 设置全量 JSON 的 Base64。键白名单 = SettingsStore
/// 全部 settings.* 键 + 速记簿三键；导入只写白名单内的键、
/// 按现值类型校验，写后由设置页 refresh 全量回读刷新 UI。
/// 不含登录态/会话/队列（SettingsStore 既定不入存储口径）。
enum SettingsConfigTransfer {

    static let keys: [String] = [
        SettingsStore.Key.miniPlayerThemeEffectsEnabled,
        SettingsStore.Key.wordEmphasisEnabled,
        SettingsStore.Key.particleFlipEnabled,
        SettingsStore.Key.showPrevButton,
        SettingsStore.Key.showNextButton,
        SettingsStore.Key.showQueueButton,
        SettingsStore.Key.miniPetsEnabled,
        SettingsStore.Key.loopMode,
        SettingsStore.Key.globalLyricTimelineOffsetMs,
        SettingsStore.Key.autoSkipUnplayable,
        SettingsStore.Key.queueDefaultPosition,
        SettingsStore.Key.autoPlayOnLaunch,
        SettingsStore.Key.lyricRenderScale,
        SettingsStore.Key.reduceMotionFollowSystem,
        SettingsStore.SketchbookHandleKey.show,
        SettingsStore.SketchbookHandleKey.position,
        SettingsStore.SketchbookHandleKey.style,
    ]

    static func exportCode() -> String {
        let defaults = UserDefaults.standard
        var payload: [String: Any] = ["foliaSettingsVersion": 1]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                payload[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]) else { return "" }
        return data.base64EncodedString()
    }

    /// 导入配置码：成功返回实际写入的键数，失败返回 nil。
    static func importCode(_ code: String) -> Int? {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleaned),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else { return nil }
        let defaults = UserDefaults.standard
        var applied = 0
        for key in keys {
            guard let value = payload[key] else { continue }
            // 类型护栏：只接受标量（Bool/NSNumber/String），防
            // 异形 JSON 把键写成字典/数组毒化后续读取。
            if value is String || value is NSNumber {
                defaults.set(value, forKey: key)
                applied += 1
            }
        }
        guard applied > 0 else { return nil }
        // 循环模式除镜像键外还要落生效面（与设置页 loopMode
        // 动作同口径：QueueManager.playMode 同步）。
        if let raw = payload[SettingsStore.Key.loopMode] as? String,
           let mode = QueueManager.PlayMode(rawValue: raw) {
            QueueManager.shared.playMode = mode
        }
        Breadcrumbs.log("settings.config import applied=\(applied)")
        return applied
    }
}

// MARK: - 静态文本页（发行说明 / 配置码展示）

/// 设置内静态文本页：近黑底 + 可选中文本 + 完成钮。用于
/// (55) 发行说明与配置码展示（配置码需可长按复制）。
final class SettingsTextPageViewController: UIViewController {

    private let pageTitle: String
    private let bodyText: String
    private let textView = UITextView()

    init(title: String, text: String) {
        pageTitle = title
        bodyText = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel()
        titleLabel.text = pageTitle
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        let copyButton = UIButton(type: .system)
        copyButton.setTitle("复制全文", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        copyButton.addTarget(self, action: #selector(copyAll), for: .touchUpInside)
        let doneButton = UIButton(type: .system)
        doneButton.setTitle("完成", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(copyButton)
        let spacer = UIView()
        spacer.widthAnchor.constraint(equalToConstant: 18).isActive = true
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(doneButton)
        view.addSubview(header)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textColor = UIColor.white.withAlphaComponent(0.88)
        textView.font = .systemFont(ofSize: 13.5)
        textView.isEditable = false
        textView.text = bodyText
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
    }

    @objc private func copyAll() {
        UIPasteboard.general.string = bodyText
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
