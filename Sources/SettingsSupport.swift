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

// MARK: - 内存监控采样器（3.7 (62) WC 簇 §4.11 做真）

/// 持续采样器：按设置间隔（SettingsStore.memorySampleIntervalSec62）
/// 定时读 residentBytes，存环形历史（最近 120 个样本），提供当前
/// 值/峰值/近时序列供设置页显示。设置页开发者行负责启停。
final class MemorySampler62 {

    static let shared = MemorySampler62()

    private(set) var samples: [Int] = []
    private(set) var peakBytes: Int = 0
    private(set) var isRunning = false
    private var timer: Timer?
    private static let capacity = 120

    private init() {}

    var currentBytes: Int? { samples.last ?? SettingsMemoryMonitor.residentBytes() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        sampleNow()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(SettingsStore.memorySampleIntervalSec62),
            repeats: true) { [weak self] _ in self?.sampleNow() }
        Breadcrumbs.log("memorysampler62.start interval=\(SettingsStore.memorySampleIntervalSec62)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        Breadcrumbs.log("memorysampler62.stop samples=\(samples.count)")
    }

    /// 间隔变更后重启计时（采样值保留）。
    func restartForIntervalChange() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(SettingsStore.memorySampleIntervalSec62),
            repeats: true) { [weak self] _ in self?.sampleNow() }
    }

    private func sampleNow() {
        guard let bytes = SettingsMemoryMonitor.residentBytes() else { return }
        samples.append(bytes)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
        peakBytes = max(peakBytes, bytes)
    }

    /// 近时曲线文本（最近 12 个样本的 MB 值，供设置行展示）。
    func recentCurveText() -> String {
        let tail = samples.suffix(12)
        guard !tail.isEmpty else { return "暂无样本" }
        return tail.map { String(format: "%.0f", Double($0) / 1_048_576) }
            .joined(separator: " · ") + " MB"
    }
}

// MARK: - (62) 发行说明（§4.12 动态化：版本从 Bundle 读）

enum ReleaseNotes62 {

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var bodyText: String {
        """
        \(versionText) 发行说明（62 全量迁移 · WC 簇部分）

        · 连接与集成：Navidrome 客户端（Subsonic 协议）落地——设置、连接测试、歌单/专辑浏览与点播、播放面板 Navidrome 页签。
        · 同步服务：通用 REST 同步（设置域＋速记簿），手动推送/拉取，令牌存 Keychain。
        · Discord 播放状态以 Webhook 形式上报（桌面 RPC 的移动等价）；PlayerCap 按地址周期上报播放状态。
        · scrobble 上报与网易云打卡：真发请求、结果诚实回显（接口可用性待后端核对）。
        · OBS 浏览器源：本机 /obs 页输出正在播放海报＋歌词；播放页透明背景与 OBS 保持动画两项设置落地。
        · 播放面板新增音质/本地/Navidrome 三页签；音质档位真接取流参数。
        · 存储：媒体缓存子系统（预缓存/上限 LRU/计数/全清）、听歌统计与智能平衡数据两类可清、本地曲库（文件/文件夹导入、四视图、重扫）。
        · 歌词导出：.lrc 与 .fia（逐字戳 JSON）三入口真达。
        · 探索页补每日推荐歌曲/歌单货架；歌手页落地；歌单页补导出/换封面/重扫。
        · 命令面板扩到全集（导航/面板/歌词/速记簿/目录/大肥鱼/场景/主题）。
        · 开发者：桥日志全量分页查看＋导出、写入本地文件开关、内存持续采样。
        · 帮助：AI 帮助（本地 FAQ 库）、思索帮助页、Discord 社区行、大肥鱼陪伴面板、直播海报墙。
        """
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
        // (62) WC 簇键并入白名单：同步服务（SyncService62）的
        // 设置域即经此导出/导入。凭据类键不在此列（Keychain，
        // 永不进配置码/同步）；sync.lastStatus 为状态非设置，
        // 不并入。
        SettingsStore.Key62C.navidromeEnabled,
        SettingsStore.Key62C.navidromeBaseURL,
        SettingsStore.Key62C.navidromeUsername,
        SettingsStore.Key62C.syncEnabled,
        SettingsStore.Key62C.syncBaseURL,
        SettingsStore.Key62C.discordEnabled,
        SettingsStore.Key62C.scrobbleEnabled,
        SettingsStore.Key62C.playerCapEnabled,
        SettingsStore.Key62C.playerCapBaseURL,
        SettingsStore.Key62C.playerCapPlayerName,
        SettingsStore.Key62C.playerCapTimelineEnabled,
        SettingsStore.Key62C.playerCapIgnoreClear,
        SettingsStore.Key62C.transparentStageBackground,
        SettingsStore.Key62C.streamQuality,
        SettingsStore.Key62C.mediaCacheEnabled,
        SettingsStore.Key62C.mediaCacheLimitMB,
        SettingsStore.Key62C.autoScanImportedFolders,
        SettingsStore.Key62C.folderWatchEnabled,
        SettingsStore.Key62C.bridgeLogWriteEnabled,
        SettingsStore.Key62C.memorySampleIntervalSec,
        SettingsStore.Key62C.localLyricFormatOrder,
        SettingsStore.Key62C.localLyricPriority,
        // (62) INT-4：WA/WB 簇键并入白名单（配置码与 R2 同步
        // 共用）。状态类键不并入（wallScrollOriginY 滚动位、
        // ponderSeenIDs 已读态）。
        "settings.appearance.daylightMode",
        "settings.appearance.sceneOverrides62",
        "settings.home.playlistCardStyle62",
        "settings.home.wallCamera62",
        "settings.appearance.preferCustomTheme",
        "settings.appearance.scenePreset",
        "settings.appearance.songThemeAutoGenerate",
        "settings.appearance.songThemeAutoSwitch",
        "settings.appearance.soundTracingEnabled",
        "settings.appearance.themeCustomAccentHex",
        "settings.appearance.themeCustomBackgroundHex",
        "settings.appearance.themeCustomSecondaryHex",
        "settings.appearance.themePresetId",
        "settings.appearance.themeSource",
        "settings.general.appLanguage",
        "settings.general.openPlayerOnLaunch",
        "settings.general.ponderTipsEnabled",
        "settings.general.ponderTouchButtonEnabled",
        "settings.graphics.backgroundThrottlePolicy",
        "settings.graphics.frameRateLimitEnabled",
        "settings.graphics.frameRateLimitFPS",
        "settings.graphics.homeDynamicBackgroundEnabled",
        "settings.graphics.lyricAntialiasEnabled",
        "settings.graphics.reduceMotionMicroEffects",
        "settings.graphics.reduceMotionMixTransition",
        "settings.graphics.reduceMotionMonetDrift",
        "settings.graphics.reduceMotionPlaylistExpand",
        "settings.graphics.reduceMotionQueueCollage",
        "settings.graphics.reduceMotionSettingsScroll",
        "settings.graphics.stageBackdropBlurEnabled",
        "settings.graphics.staticMode",
        "settings.graphics.touchGlowDensity",
        "settings.graphics.touchGlowEnabled",
        "settings.home.grid3DCardStyle",
        "settings.home.gridCardMinOpacity",
        "settings.home.gridCardMinSize",
        "settings.home.gridFullBleedCover",
        "settings.home.gridSquareCards",
        "settings.home.homeTabsEnabled",
        "settings.home.librarySuiteChoice",
        "settings.home.rememberCardPositions",
        "settings.home.showHomeTabAlbums",
        "settings.home.showHomeTabExplore",
        "settings.home.showHomeTabLocal",
        "settings.home.showHomeTabPlaylists",
        "settings.home.showHomeTabRecommend",
        "settings.home.wallCardOrder",
        "settings.integration.lyricAPIBaseURL",
        "settings.integration.lyricAPIEnabled",
        "settings.dev.logCaptureEnabled",
        "settings.integration.stageDataSourceURL",
        "settings.integration.stageModeEnabled",
        "settings.lyrics.aiSegmentEnabled",
        "settings.lyrics.aiSegmentEndpoint",
        "settings.lyrics.autoBestLyricEnabled",
        "settings.lyrics.bestLyricStrategy",
        "settings.lyrics.filterRegex",
        "settings.lyrics.filterPresetWords",
        "settings.lyrics.filterColonForm",
        "settings.lyrics.filterOpeningOnly",
        "settings.lyrics.creditsMode",
        "settings.lyrics.creditsMinStay",
        "settings.lyrics.creditsAbsorb",
        "settings.lyrics.creditsCustom",
        "settings.lyrics.keepPlatformWordLyrics",
        "settings.lyrics.matchPriority",
        "settings.playback.autoTranscodeEnabled",
        "settings.playback.pauseOnVoiceInput",
        "settings.playback.playPauseFadeMs",
        "settings.playback.preventSleepWhilePlaying",
        "settings.playback.replayGainEnabled",
        "settings.playback.smartTransitionEnabled",
        "settings.playback.transitionAnimation",
        "settings.playback.transitionAggressive",
        "settings.playback.transitionAnimRing",
        "settings.playback.transitionAnimCard",
        "settings.playback.dsdDopEnabled",
        "settings.playback.transitionCurve",
        "settings.playback.transitionMaxDurationSec",
        "settings.playback.transitionMode",
        "settings.player.alwaysShowBackButton",
        "settings.player.alwaysShowSkipButtons",
        "settings.player.barSlots62",
        "settings.player.bottomBarHeight",
        "settings.player.headerAutoHideEnabled",
        "settings.player.headerBlurEnabled",
        "settings.player.hideBottomBar",
        "settings.player.hideRightButtons",
        "settings.player.latticeBadgeCurrentOnly",
        "settings.player.latticePosterTintColorHex",
        "settings.player.latticePosterTintEnabled",
        "settings.player.latticePosterTintForceCustom",
        "settings.player.latticePosterTintStrength",
        "settings.player.latticeVignetteEnabled",
        "settings.player.latticeVignetteStrength",
        "settings.player.playbackEntryView",
        "settings.player.showPanelCloseButton",
        "settings.player.trackPillDisplayMode",
        "settings.player.trackPillDurationSeconds",
        "settings.player.trackPillOBSEnabled",
        "settings.player.barSlotLeft62",
        "settings.player.barSlotRight62",
        "settings.player.trackPillPosition",
        "settings.player.trackPillShowOnHome",
        "settings.player.videoLayerEnabled",
        "settings.player.videoLayerFillMode",
        "settings.player.videoLayerOpacity",
        "settings.player.videoLayerURL",
        "settings.shortcuts.gestureShortcutsEnabled",
        "settings.shortcuts.longPressToolbarCommandPalette",
        "settings.shortcuts.pinnedCommandIDs",
        "settings.shortcuts.posterWallSHotkeyEnabled",
        "settings.shortcuts.customKeyLetter",
        "settings.shortcuts.customKeyCommand",
        "settings.shortcuts.swipeLeftTarget",
        "settings.wall.backdropBlurAmount",
        "settings.wall.backdropLyricsEnabled",
        "settings.wall.stackEdgesEnabled",
        "settings.wall.stripAlwaysTransparent",
        "settings.wall.stripDirection",
        "settings.wall.stripStyle",
        "settings.wall.transparency",
        "settings.wall.windowsPerPane",
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
