import UIKit

// Settings62ClusterC.swift
//
// 3.7 (62) WC 簇设置行：页签 8 连接与集成（§4.9 全组）、
// 9 存储与备份（§4.10）、10 开发者（§4.11）、11 帮助（§4.12）。
// 契约：build(host:into:reg:) 由基座 build62Tabs 转调；控件一律
// UIAction 闭包接线；每签建组前 host.beginCheckGroup("<页签名>")。
// 行样式与 SettingsViewController 的 FoliaUI 同值（该枚举为其
// 私有，本文件按同值复刻常量，改一处须同步）。

enum Settings62ClusterC {

    private static let primary = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    private static let secondary = UIColor(red: 0.604, green: 0.604, blue: 0.639, alpha: 1)
    private static let accent = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 1)

    static func build(host: SettingsViewController, into stack: UIStackView,
                      reg: (UIView, Int) -> Void) {
        WC62Bootstrap.startIfNeeded()
        buildConnections(host: host, into: stack, reg: reg)
        buildStorage(host: host, into: stack, reg: reg)
        buildDeveloper(host: host, into: stack, reg: reg)
        buildHelp(host: host, into: stack, reg: reg)
    }

    // MARK: - 页签 8：连接与集成

    private static func buildConnections(host: SettingsViewController,
                                         into stack: UIStackView,
                                         reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("连接与集成·62C")

        // Navidrome（组 L）
        let navi = host.makeGroupCard()
        navi.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("Navidrome")))
        navi.addArrangedSubview(switchRow(host: host, title: "Navidrome 连接",
            isOn: SettingsStore.navidromeEnabled62) { on in
            SettingsStore.navidromeEnabled62 = on
            Breadcrumbs.log("settings62c.navidrome enabled=\(on)")
        })
        navi.addArrangedSubview(host.makeHairline())
        navi.addArrangedSubview(textRow(host: host, title: "服务器地址",
            value: { SettingsStore.navidromeBaseURL62.isEmpty ? "未填写" : SettingsStore.navidromeBaseURL62 },
            placeholder: "如 https://music.example.com") { text in
            SettingsStore.navidromeBaseURL62 = text
        })
        navi.addArrangedSubview(host.makeHairline())
        navi.addArrangedSubview(textRow(host: host, title: "用户名",
            value: { SettingsStore.navidromeUsername62.isEmpty ? "未填写" : SettingsStore.navidromeUsername62 },
            placeholder: "Navidrome 用户名") { text in
            SettingsStore.navidromeUsername62 = text
        })
        navi.addArrangedSubview(host.makeHairline())
        navi.addArrangedSubview(secretRow(host: host, title: "密码",
            account: SecretStore62C.navidromePasswordAccount))
        navi.addArrangedSubview(host.makeHairline())
        let naviTestLabel = valueLabel(host: host, text: "未测试")
        navi.addArrangedSubview(actionRow(host: host, title: "连接测试", valueLabel: naviTestLabel) {
            naviTestLabel.text = "测试中…"
            Task { @MainActor in
                do {
                    let info = try await NavidromeClient62.shared.ping()
                    naviTestLabel.text = "已连通 · \(info)"
                } catch {
                    naviTestLabel.text = "失败：\(error.localizedDescription)"
                }
            }
        })
        navi.addArrangedSubview(host.makeHairline())
        navi.addArrangedSubview(host.makeHintRow(
            "Subsonic 协议（Navidrome 兼容）：令牌认证 md5(密码+盐)，密码只存 Keychain。无服务器时测试会如实报失败。"))
        stack.addArrangedSubview(navi)
        reg(navi, 8)

        // 同步服务（组 L）
        let sync = host.makeGroupCard()
        sync.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("同步服务")))
        sync.addArrangedSubview(switchRow(host: host, title: "同步服务",
            isOn: SettingsStore.syncEnabled62) { on in
            SettingsStore.syncEnabled62 = on
            Breadcrumbs.log("settings62c.sync enabled=\(on)")
        })
        sync.addArrangedSubview(host.makeHairline())
        sync.addArrangedSubview(textRow(host: host, title: "同步服务地址",
            value: { SettingsStore.syncBaseURL62.isEmpty ? "未填写" : SettingsStore.syncBaseURL62 },
            placeholder: "如 https://sync.example.com/folia") { text in
            SettingsStore.syncBaseURL62 = text
        })
        sync.addArrangedSubview(host.makeHairline())
        sync.addArrangedSubview(secretRow(host: host, title: "同步令牌",
            account: SecretStore62C.syncTokenAccount))
        sync.addArrangedSubview(host.makeHairline())
        let syncStatus = valueLabel(host: host,
            text: SettingsStore.syncLastStatus62.isEmpty ? "尚未同步" : SettingsStore.syncLastStatus62)
        sync.addArrangedSubview(infoRow(host: host, title: "同步状态", valueLabel: syncStatus))
        sync.addArrangedSubview(host.makeHairline())
        sync.addArrangedSubview(actionRow(host: host, title: "推送（上传本机）", valueLabel: nil) {
            syncStatus.text = "推送中…"
            Task { @MainActor in syncStatus.text = await SyncService62.push() }
        })
        sync.addArrangedSubview(host.makeHairline())
        sync.addArrangedSubview(actionRow(host: host, title: "拉取（覆盖本机）", valueLabel: nil) {
            syncStatus.text = "拉取中…"
            Task { @MainActor in syncStatus.text = await SyncService62.pull() }
        })
        sync.addArrangedSubview(host.makeHairline())
        sync.addArrangedSubview(host.makeHintRow(
            "协议假设：服务端在该地址下提供 PUT/GET <地址>/folia-sync.json（JSON 整体存取，Bearer 令牌鉴权），兼容 R2/S3 预签名或自建服务。同步对象＝设置域（配置白名单，含连接类非密钥项）＋速记簿，不含登录态与任何密钥。拉取覆盖速记簿前会留 .bak62 备份；拉取后速记簿以重启后生效为准。"))
        stack.addArrangedSubview(sync)
        reg(sync, 8)

        // Discord / scrobble / PlayerCap
        let report = host.makeGroupCard()
        report.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("播放上报")))
        report.addArrangedSubview(switchRow(host: host, title: "Discord 播放状态",
            isOn: SettingsStore.discordEnabled62) { on in
            SettingsStore.discordEnabled62 = on
            Breadcrumbs.log("settings62c.discord enabled=\(on)")
        })
        report.addArrangedSubview(host.makeHairline())
        report.addArrangedSubview(secretRow(host: host, title: "Discord Webhook URL",
            account: SecretStore62C.discordWebhookAccount))
        report.addArrangedSubview(host.makeHairline())
        report.addArrangedSubview(switchRow(host: host, title: "上报播放记录（scrobble）",
            isOn: SettingsStore.scrobbleEnabled62) { on in
            SettingsStore.scrobbleEnabled62 = on
            Breadcrumbs.log("settings62c.scrobble enabled=\(on)")
        })
        report.addArrangedSubview(host.makeHairline())
        let scrobbleStatus = valueLabel(host: host, text: Scrobble62.shared.lastResultText)
        report.addArrangedSubview(infoRow(host: host, title: "最近上报", valueLabel: scrobbleStatus))
        report.addArrangedSubview(host.makeHairline())
        report.addArrangedSubview(actionRow(host: host, title: "网易云听歌打卡", valueLabel: nil) {
            scrobbleStatus.text = "打卡中…"
            Task { @MainActor in
                scrobbleStatus.text = await Scrobble62.shared.performCheckIn()
            }
        })
        report.addArrangedSubview(host.makeHairline())
        report.addArrangedSubview(host.makeHintRow(
            "Discord 为桌面 RPC 的移动等价：切歌/暂停时向 Webhook POST 正在播放信息，Webhook URL 按凭据存 Keychain。scrobble 在听满 50%（或 4 分钟）时经自有代理上报；接口可用性待后端核对，失败如实显示。"))
        stack.addArrangedSubview(report)
        reg(report, 8)

        let cap = host.makeGroupCard()
        cap.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("PlayerCap")))
        cap.addArrangedSubview(switchRow(host: host, title: "PlayerCap 上报",
            isOn: SettingsStore.playerCapEnabled62) { on in
            SettingsStore.playerCapEnabled62 = on
            Breadcrumbs.log("settings62c.playercap enabled=\(on)")
        })
        cap.addArrangedSubview(host.makeHairline())
        cap.addArrangedSubview(textRow(host: host, title: "PlayerCap 地址",
            value: { SettingsStore.playerCapBaseURL62.isEmpty ? "未填写" : SettingsStore.playerCapBaseURL62 },
            placeholder: "如 https://example.com/playercap") { text in
            SettingsStore.playerCapBaseURL62 = text
        })
        cap.addArrangedSubview(host.makeHairline())
        cap.addArrangedSubview(textRow(host: host, title: "播放器名",
            value: { SettingsStore.playerCapPlayerName62 },
            placeholder: "Folia iOS") { text in
            SettingsStore.playerCapPlayerName62 = text
        })
        cap.addArrangedSubview(host.makeHairline())
        cap.addArrangedSubview(switchRow(host: host, title: "上报时间轴",
            isOn: SettingsStore.playerCapTimelineEnabled62) { on in
            SettingsStore.playerCapTimelineEnabled62 = on
        })
        cap.addArrangedSubview(host.makeHairline())
        cap.addArrangedSubview(switchRow(host: host, title: "忽略清除（无曲目时不上报）",
            isOn: SettingsStore.playerCapIgnoreClear62) { on in
            SettingsStore.playerCapIgnoreClear62 = on
        })
        cap.addArrangedSubview(host.makeHairline())
        cap.addArrangedSubview(actionRow(host: host, title: "立即上报一次", valueLabel: nil) {
            PlayerCap62.shared.reportNow(reason: "manual")
            NativePlaybackFailureToast.show(message: "PlayerCap 已上报（结果见桥日志）")
        })
        cap.addArrangedSubview(host.makeHairline())
        cap.addArrangedSubview(host.makeHintRow(
            "协议假设：每 20 秒向该地址 POST 一份 JSON（player/title/artist/isPlaying＋可选 position/duration），服务端按通用 JSON 接收。"))
        stack.addArrangedSubview(cap)
        reg(cap, 8)

        // 直播 / OBS
        let live = host.makeGroupCard()
        live.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("直播与 OBS")))
        live.addArrangedSubview(switchRow(host: host, title: "播放页透明背景",
            isOn: SettingsStore.transparentStageBackground62) { on in
            SettingsStore.transparentStageBackground62 = on
            Breadcrumbs.log("settings62c.transparentStage value=\(on)")
        })
        live.addArrangedSubview(host.makeHairline())
        let obsValue = valueLabel(host: host, text: obsAddressText())
        live.addArrangedSubview(actionRow(host: host, title: "OBS 浏览器源（复制地址）",
                                          valueLabel: obsValue) {
            UIPasteboard.general.string = obsAddressText()
            NativePlaybackFailureToast.show(message: "OBS 源地址已复制")
        })
        live.addArrangedSubview(host.makeHairline())
        // (66) OBS 客户端在场状态（后台节流的活动信号面）。
        live.addArrangedSubview(infoRow(host: host, title: "OBS 客户端",
            valueLabel: valueLabel(host: host,
                text: BackgroundThrottle62.obsClientActive ? "在场（近期有拉取）" : "不在场")))
        live.addArrangedSubview(host.makeHairline())
        live.addArrangedSubview(host.makeHintRow(
            "在 OBS 里新建「浏览器源」，地址填上面复制的本机地址，即可显示正在播放的海报与歌词（页面每 5 秒自动刷新）。透明背景开时 OBS 页与舞台背景透明（消费在 LocalServer /obs 页与舞台侧）。歌曲卡在 OBS 页的显示开关在「播放页」页签的舞台歌曲卡组（(66) 已做真）。原「OBS 连接时保持主窗口动画」为桌面概念、iOS 无主窗口对应物，(66) 已摘行摘键，不再留假开关。"))
        stack.addArrangedSubview(live)
        reg(live, 8)
    }

    private static func obsAddressText() -> String {
        let port = LocalServer.shared.port
        return port == 0 ? "本机服务未启动" : "http://127.0.0.1:\(port)/obs"
    }

    // MARK: - 页签 9：存储与备份

    private static func buildStorage(host: SettingsViewController,
                                     into stack: UIStackView,
                                     reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("存储与备份·62C")

        let media = host.makeGroupCard()
        media.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("媒体缓存")))
        media.addArrangedSubview(switchRow(host: host, title: "缓存歌曲（媒体缓存）",
            isOn: SettingsStore.mediaCacheEnabled62) { on in
            SettingsStore.mediaCacheEnabled62 = on
            Breadcrumbs.log("settings62c.mediaCache enabled=\(on)")
        })
        media.addArrangedSubview(host.makeHairline())
        let limitControl = UISegmentedControl(items: ["64", "128", "256", "512"])
        limitControl.selectedSegmentIndex = [64, 128, 256, 512]
            .firstIndex(of: SettingsStore.mediaCacheLimitMB62) ?? 2
        media.addArrangedSubview(segmentedRow(host: host, title: "缓存上限（MB）",
                                              control: limitControl) { index in
            SettingsStore.mediaCacheLimitMB62 = [64, 128, 256, 512][index]
            MediaCache62.shared.enforceLimit()
            Breadcrumbs.log("settings62c.mediaCache limit=\(SettingsStore.mediaCacheLimitMB62)")
        })
        media.addArrangedSubview(host.makeHairline())
        let countLabel = valueLabel(host: host, text: mediaCountText())
        media.addArrangedSubview(infoRow(host: host, title: "已缓存歌曲", valueLabel: countLabel))
        media.addArrangedSubview(host.makeHairline())
        // (66) 缓存歌曲自动回填（切歌订阅回填当前曲＋后续）。
        media.addArrangedSubview(switchRow(host: host, title: "缓存歌曲自动回填",
            isOn: SettingsStore.mediaCacheAutoRefill62) { on in
            SettingsStore.mediaCacheAutoRefill62 = on
            Breadcrumbs.log("settings66.autoRefill=\(on ? 1 : 0)")
        })
        media.addArrangedSubview(host.makeHairline())
        // (66) 缓存目录自选（DS 改判落地）：UIDocumentPicker
        // 选文件夹＋安全作用域书签；失效回退默认并明示。
        let dirLabel = valueLabel(host: host, text: MediaCache62.usingCustomDirectory
            ? "自选目录" : "默认（Caches/folia-media62）")
        media.addArrangedSubview(actionRow(host: host, title: "缓存目录（点按更换）",
                                           valueLabel: dirLabel) {
            MediaCacheDirPicker66.present(from: host) { picked in
                if let picked {
                    MediaCache62.setCustomDirectory(picked)
                    MediaCache62.shared.reloadIndex()
                }
                dirLabel.text = MediaCache62.usingCustomDirectory
                    ? "自选目录" : "默认（Caches/folia-media62）"
            }
        })
        media.addArrangedSubview(host.makeHairline())
        media.addArrangedSubview(actionRow(host: host, title: "恢复默认缓存目录", valueLabel: nil) {
            MediaCache62.clearCustomDirectory()
            MediaCache62.shared.reloadIndex()
            dirLabel.text = "默认（Caches/folia-media62）"
            NativePlaybackFailureToast.show(message: "已恢复默认缓存目录")
        })
        media.addArrangedSubview(host.makeHairline())
        media.addArrangedSubview(actionRow(host: host, title: "预缓存当前队列", valueLabel: nil) {
            Task { @MainActor in
                let done = await MediaCache62.shared.precacheQueue()
                countLabel.text = mediaCountText()
                NativePlaybackFailureToast.show(message: "预缓存完成 \(done) 首")
            }
        })
        media.addArrangedSubview(host.makeHairline())
        media.addArrangedSubview(actionRow(host: host, title: "清除全部媒体缓存", valueLabel: nil) {
            let freed = MediaCache62.shared.clearAll()
            countLabel.text = mediaCountText()
            NativePlaybackFailureToast.show(
                message: "已清除媒体缓存 \(SettingsCacheManager.sizeText(freed))")
        })
        media.addArrangedSubview(host.makeHairline())
        media.addArrangedSubview(host.makeHintRow(
            "媒体缓存为磁盘缓存：预缓存把歌曲文件落盘（上限内按最久未用自动清理）；自动回填开时切歌即回填当前曲与队列后续 3 首（(66) 接入，节流积极且 OBS 在场时推迟）。自选目录切换后原目录缓存不迁移、新目录按其自有索引接管；书签失效时自动回退默认目录并在日志明示。"))
        stack.addArrangedSubview(media)
        reg(media, 9)

        let classify = host.makeGroupCard()
        classify.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("缓存分类清除")))
        let statsLabel = valueLabel(host: host, text: statsText())
        classify.addArrangedSubview(infoRow(host: host, title: "分析数据（听歌统计）",
                                            valueLabel: statsLabel))
        classify.addArrangedSubview(host.makeHairline())
        classify.addArrangedSubview(actionRow(host: host, title: "清除分析数据", valueLabel: nil) {
            ListeningStats62.shared.clearAll()
            statsLabel.text = statsText()
            NativePlaybackFailureToast.show(message: "听歌统计已清除")
        })
        classify.addArrangedSubview(host.makeHairline())
        let balanceLabel = valueLabel(host: host,
            text: "\(VolumeBalanceStore62.shared.count) 首已学习")
        classify.addArrangedSubview(infoRow(host: host, title: "智能平衡数据",
                                            valueLabel: balanceLabel))
        classify.addArrangedSubview(host.makeHairline())
        classify.addArrangedSubview(actionRow(host: host, title: "清除智能平衡数据", valueLabel: nil) {
            VolumeBalanceStore62.shared.clearAll()
            balanceLabel.text = "\(VolumeBalanceStore62.shared.count) 首已学习"
            NativePlaybackFailureToast.show(message: "智能平衡数据已清除")
        })
        classify.addArrangedSubview(host.makeHairline())
        // (66) 歌单数据分仓：API 缓存按类登记（sidecar 清
        // 单），歌单类可单独统计/清除，不动其他 API 缓存。
        let playlistLabel = valueLabel(host: host,
            text: SettingsCacheManager.sizeText(APICacheClass66.sizeBytes(forClass: APICacheClass66.playlistClass)))
        classify.addArrangedSubview(infoRow(host: host, title: "歌单数据（API 缓存）",
                                            valueLabel: playlistLabel))
        classify.addArrangedSubview(host.makeHairline())
        classify.addArrangedSubview(actionRow(host: host, title: "清除歌单数据", valueLabel: nil) {
            let freed = APICacheClass66.clear(cls: APICacheClass66.playlistClass)
            playlistLabel.text = SettingsCacheManager.sizeText(
                APICacheClass66.sizeBytes(forClass: APICacheClass66.playlistClass))
            NativePlaybackFailureToast.show(
                message: "已清除歌单数据 \(SettingsCacheManager.sizeText(freed))")
        })
        classify.addArrangedSubview(host.makeHairline())
        classify.addArrangedSubview(host.makeHintRow(
            "分析数据＝本机听歌统计（播放次数/聆听时长）；智能平衡数据＝逐曲音量学习偏移（供 ReplayGain 消费）；歌单数据＝接口缓存中歌单类响应（按写缓存时的分类清单分仓）。三类清除均为真删；封面与 API 总缓存在本签宿主卡。"))
        stack.addArrangedSubview(classify)
        reg(classify, 9)

        let local = host.makeGroupCard()
        local.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("本地曲库与歌词")))
        local.addArrangedSubview(switchRow(host: host, title: "自动扫描已导入文件夹",
            isOn: SettingsStore.autoScanImportedFolders62) { on in
            SettingsStore.autoScanImportedFolders62 = on
        })
        local.addArrangedSubview(host.makeHairline())
        local.addArrangedSubview(switchRow(host: host, title: "文件夹监视（前台）",
            isOn: SettingsStore.folderWatchEnabled62) { on in
            SettingsStore.folderWatchEnabled62 = on
            // (66) 前台监视做实：开关变更即重挂/撤下目录事件源。
            FolderWatch62.shared.refresh()
            if on { LocalLibrary62.shared.rescanFolders() }
        })
        local.addArrangedSubview(host.makeHairline())
        local.addArrangedSubview(actionRow(host: host, title: "重新扫描已导入文件夹", valueLabel: nil) {
            LocalLibrary62.shared.rescanFolders()
            NativePlaybackFailureToast.show(message: "已触发重扫（结果见本地页）")
        })
        local.addArrangedSubview(host.makeHairline())
        local.addArrangedSubview(actionRow(host: host, title: "歌词导出（当前歌曲）", valueLabel: nil) {
            LyricExport62.exportCurrentTrack(from: host)
        })
        local.addArrangedSubview(host.makeHairline())
        local.addArrangedSubview(host.makeHintRow(
            "文件夹监视为前台监视（(66)）：App 在前台时监听已导入文件夹变化、自动重扫收新文件；切到后台或被杀后不监视（iOS 无常驻后台监视，与桌面语义有此差异，不冒充）。歌词导出生成 .lrc 与 .fia（逐字戳）经系统分享。"))
        stack.addArrangedSubview(local)
        reg(local, 9)
    }

    private static func mediaCountText() -> String {
        "\(MediaCache62.shared.cachedCount) 首 · "
            + SettingsCacheManager.sizeText(MediaCache62.shared.totalBytes)
    }

    private static func statsText() -> String {
        let stats = ListeningStats62.shared
        let minutes = Int(stats.totalListenedSeconds / 60)
        return "\(stats.totalPlays) 次 · \(minutes) 分钟"
    }

    // MARK: - 页签 10：开发者
    //
    // (66) 对齐网页版 DeveloperPage：单组「开发者工具」——
    // 运行日志（采集总开关/写入文件/查看全量）＋内存监控
    // （持续采样/采样间隔/读数）。桥日志入口在宿主老面行。

    private static func buildDeveloper(host: SettingsViewController,
                                       into stack: UIStackView,
                                       reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("开发者·62C")

        let tools = host.makeGroupCard()
        tools.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("开发者工具")))
        // (66) 运行日志采集总开关（网页 consoleLogCapture）：
        // 关时 FoliaBridgeLogStore 完全不记录。
        tools.addArrangedSubview(switchRow(host: host, title: "运行日志采集",
            isOn: SettingsStore.logCaptureEnabled62) { on in
            SettingsStore.logCaptureEnabled62 = on
            if on { Breadcrumbs.log("settings66.logCapture value=1") }
        })
        tools.addArrangedSubview(host.makeHairline())
        tools.addArrangedSubview(switchRow(host: host, title: "写入本地文件",
            isOn: SettingsStore.bridgeLogWriteEnabled62) { on in
            SettingsStore.bridgeLogWriteEnabled62 = on
            Breadcrumbs.log("settings62c.bridgeLogWrite value=\(on)")
        })
        tools.addArrangedSubview(host.makeHairline())
        tools.addArrangedSubview(actionRow(host: host, title: "查看全量日志（分页）", valueLabel: nil) {
            BridgeLog62ViewController.present(from: host)
        })
        tools.addArrangedSubview(host.makeHairline())
        tools.addArrangedSubview(host.makeHintRow(
            "全量日志＝桥日志双轮换文件（2MB×2）的全部行，查看器内可翻页与导出分享。「运行日志采集」关时不再记录（控制台与落盘都停）；「写入本地文件」关时只进系统控制台、不落盘。"))
        tools.addArrangedSubview(host.makeHairline())
        tools.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("内存监控")))
        let sampler = MemorySampler62.shared
        tools.addArrangedSubview(switchRow(host: host, title: "持续采样",
            isOn: sampler.isRunning) { on in
            if on { sampler.start() } else { sampler.stop() }
        })
        tools.addArrangedSubview(host.makeHairline())
        let intervalControl = UISegmentedControl(items: ["2s", "5s", "10s", "30s", "60s"])
        intervalControl.selectedSegmentIndex = [2, 5, 10, 30, 60]
            .firstIndex(of: SettingsStore.memorySampleIntervalSec62) ?? 1
        tools.addArrangedSubview(segmentedRow(host: host, title: "采样间隔",
                                               control: intervalControl) { index in
            SettingsStore.memorySampleIntervalSec62 = [2, 5, 10, 30, 60][index]
            MemorySampler62.shared.restartForIntervalChange()
        })
        tools.addArrangedSubview(host.makeHairline())
        let currentLabel = valueLabel(host: host, text: memoryText())
        tools.addArrangedSubview(infoRow(host: host, title: "当前 / 峰值", valueLabel: currentLabel))
        tools.addArrangedSubview(host.makeHairline())
        let curveLabel = valueLabel(host: host, text: sampler.recentCurveText())
        curveLabel.numberOfLines = 2
        tools.addArrangedSubview(infoRow(host: host, title: "近时曲线（MB）", valueLabel: curveLabel))
        tools.addArrangedSubview(host.makeHairline())
        tools.addArrangedSubview(actionRow(host: host, title: "刷新读数", valueLabel: nil) {
            currentLabel.text = memoryText()
            curveLabel.text = MemorySampler62.shared.recentCurveText()
        })
        tools.addArrangedSubview(host.makeHairline())
        tools.addArrangedSubview(host.makeHintRow(
            "采样器按间隔持续读进程常驻内存并留近 120 个样本；全应用峰值硬线 450MB。"))
        stack.addArrangedSubview(tools)
        reg(tools, 10)
    }

    private static func memoryText() -> String {
        let sampler = MemorySampler62.shared
        let current = sampler.currentBytes.map(SettingsCacheManager.sizeText) ?? "—"
        let peak = sampler.peakBytes > 0 ? SettingsCacheManager.sizeText(sampler.peakBytes) : "—"
        return "\(current) / \(peak)"
    }

    // MARK: - 页签 11：帮助
    //
    // (66) 对齐网页版 HelpPage：快捷键（信息行）→ 支持（AI
    // 帮助/大肥鱼陪伴/社区/思索帮助）→ 关于（发行说明）。

    private static func buildHelp(host: SettingsViewController,
                                  into stack: UIStackView,
                                  reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("帮助·62C")

        let keys = host.makeGroupCard()
        keys.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("键盘快捷键")))
        keys.addArrangedSubview(actionRow(host: host, title: "查看快捷键清单", valueLabel: nil) {
            let page = SettingsTextPageViewController(
                title: "键盘快捷键",
                text: "外接键盘（主页墙/海报墙聚焦时）：\n"
                    + "· S —— 打开命令窗口（设置 → 快捷操作可关）\n"
                    + "· 自定义字母键 —— 执行所绑命令（设置 → 快捷操作 → 命令面板组设置，默认未设置）\n\n"
                    + "触屏等价：\n"
                    + "· 长按缝合工具条 —— 打开命令面板\n"
                    + "· 向左滑动 —— 打开所设目标（命令面板/速记簿/搜索）\n"
                    + "· 舞台三击 —— 洗牌切换下一个歌词特效\n"
                    + "· 点播台封面单击 —— 回播放页；双击台身 —— 进舞台")
            page.modalPresentationStyle = .overFullScreen
            host.present(page, animated: true)
        })
        keys.addArrangedSubview(host.makeHairline())
        keys.addArrangedSubview(host.makeHintRow(
            "iOS 无系统级全局热键：以上均为 App 内绑定（外接键盘或手势），与网页版清单逐项对应、无对应物的不列。"))
        stack.addArrangedSubview(keys)
        reg(keys, 11)

        let support = host.makeGroupCard()
        support.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("支持")))
        support.addArrangedSubview(actionRow(host: host, title: "AI 帮助（本地问答库）", valueLabel: nil) {
            let ai = AIHelp62ViewController()
            ai.modalPresentationStyle = .overFullScreen
            host.present(ai, animated: true)
        })
        support.addArrangedSubview(host.makeHairline())
        support.addArrangedSubview(actionRow(host: host, title: "大肥鱼陪伴", valueLabel: nil) {
            DafeiyuPanel62ViewController.present(from: host)
        })
        support.addArrangedSubview(host.makeHairline())
        support.addArrangedSubview(actionRow(host: host, title: "社区 · Discord（复制）",
            valueLabel: valueLabel(host: host, text: "网页版社区")) {
            UIPasteboard.general.string = "Folia 网页版社区（Discord）"
            NativePlaybackFailureToast.show(message: "已复制社区说明（Discord 为网页版社区渠道）")
            Breadcrumbs.log("settings62c.help discordCopied=1")
        })
        support.addArrangedSubview(host.makeHairline())
        support.addArrangedSubview(actionRow(host: host, title: "思索帮助", valueLabel: nil) {
            Ponder62.presentList(from: host)
        })
        support.addArrangedSubview(host.makeHairline())
        support.addArrangedSubview(actionRow(host: host, title: "直播海报墙", valueLabel: nil) {
            LivePosterWall62ViewController.present(from: host)
        })
        support.addArrangedSubview(host.makeHairline())
        support.addArrangedSubview(host.makeHintRow(
            "AI 帮助为本地 FAQ 关键词检索（离线可用，不冒充在线 AI）。Discord 为网页版登记的社区渠道，App 内以复制说明行承接。思索帮助即教程列表（通用页签可关提示）。"))
        stack.addArrangedSubview(support)
        reg(support, 11)

        let about = host.makeGroupCard()
        about.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle("关于")))
        about.addArrangedSubview(actionRow(host: host,
            title: "发行说明（\(ReleaseNotes62.versionText)）", valueLabel: nil) {
            let page = SettingsTextPageViewController(
                title: "发行说明 · \(ReleaseNotes62.versionText)",
                text: ReleaseNotes62.bodyText)
            page.modalPresentationStyle = .overFullScreen
            host.present(page, animated: true)
        })
        about.addArrangedSubview(host.makeHairline())
        about.addArrangedSubview(host.makeHintRow(
            "版本与构建号以本机实际安装为准（桥日志 app.build 行为准）。"))
        stack.addArrangedSubview(about)
        reg(about, 11)
    }

    // MARK: - 行工厂（UIAction 接线）

    private static func valueLabel(host: SettingsViewController, text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = secondary
        label.textAlignment = .right
        label.numberOfLines = 1
        host.track(label)
        return label
    }

    private static func switchRow(host: SettingsViewController, title: String,
                                  isOn: Bool, onChange: @escaping (Bool) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = FoliaLanguage62.rowTitle(title)
        label.font = .systemFont(ofSize: 15)
        label.textColor = primary
        label.numberOfLines = 0
        host.track(label)
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = accent
        toggle.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        toggle.addAction(UIAction { _ in onChange(toggle.isOn) }, for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(toggle)
        return row
    }

    private static func infoRow(host: SettingsViewController, title: String,
                                valueLabel: UILabel) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let label = UILabel()
        label.text = FoliaLanguage62.rowTitle(title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = secondary
        host.track(label)
        row.addArrangedSubview(label)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(valueLabel)
        return row
    }

    private static func actionRow(host: SettingsViewController, title: String,
                                  valueLabel: UILabel?,
                                  action: @escaping () -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(accent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.contentHorizontalAlignment = .left
        if let titleLabel = button.titleLabel { host.track(titleLabel) }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        row.addArrangedSubview(button)
        if let valueLabel {
            row.addArrangedSubview(UIView())
            row.addArrangedSubview(valueLabel)
        }
        return row
    }

    private static func textRow(host: SettingsViewController, title: String,
                                value: @escaping () -> String, placeholder: String,
                                onSubmit: @escaping (String) -> Void) -> UIStackView {
        let label = valueLabel(host: host, text: value())
        return actionRow(host: host, title: title, valueLabel: label) {
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = placeholder
                field.text = value() == "未填写" ? "" : value()
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
                field.keyboardType = .URL
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
                let text = alert?.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                onSubmit(text)
                label.text = value()
            })
            host.present(alert, animated: true)
        }
    }

    private static func secretRow(host: SettingsViewController, title: String,
                                  account: String) -> UIStackView {
        let label = valueLabel(host: host,
            text: SecretStore62C.read(account: account) != nil ? "已设置" : "未设置")
        return actionRow(host: host, title: title, valueLabel: label) {
            let alert = UIAlertController(
                title: title, message: "只存本机 Keychain，不进设置导出与同步。",
                preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "输入后保存；留空保存即清除"
                field.isSecureTextEntry = true
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
                let text = alert?.textFields?.first?.text ?? ""
                SecretStore62C.write(text, account: account)
                label.text = SecretStore62C.read(account: account) != nil ? "已设置" : "未设置"
                Breadcrumbs.log("settings62c.secret updated account=\(account)")
            })
            host.present(alert, animated: true)
        }
    }

    private static func segmentedRow(host: SettingsViewController, title: String,
                                     control: UISegmentedControl,
                                     onChange: @escaping (Int) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = FoliaLanguage62.rowTitle(title)
        label.font = .systemFont(ofSize: 15)
        label.textColor = primary
        host.track(label)
        control.selectedSegmentTintColor = accent
        control.setTitleTextAttributes(
            [.foregroundColor: primary, .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)],
            for: .selected)
        control.addAction(UIAction { _ in
            if control.selectedSegmentIndex >= 0 { onChange(control.selectedSegmentIndex) }
        }, for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }
}

// MARK: - AI 帮助（本地 FAQ 检索，§4.12）

/// 本地问答库关键词检索：内置 ≥15 条真问答，输入关键词按
/// 命中数排序展示；无后端，不冒充在线 AI（页内明示）。
final class AIHelp62ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private struct QA {
        let question: String
        let answer: String
        let keywords: [String]
    }

    private static let library: [QA] = [
        QA(question: "歌词对不上/慢半拍怎么办？",
           answer: "先在设置「歌词」页签用全局时间偏移微调（±2000ms）；仍对不上多为该曲无逐字歌词（YRC），属数据源上限。",
           keywords: ["歌词", "对不上", "慢", "偏移", "同步"]),
        QA(question: "怎么导入本地歌曲？",
           answer: "打开工作台「本地」分区，点「导入文件」选音频文件或文件夹；导入后在本地曲库四视图里点播。",
           keywords: ["本地", "导入", "文件", "mp3", "曲库"]),
        QA(question: "Navidrome 怎么连？",
           answer: "设置「连接与集成」填服务器地址/用户名/密码并打开开关，再点连接测试；歌单在播放面板 Navidrome 页签与工作台本地分区。",
           keywords: ["navidrome", "服务器", "连接", "subsonic"]),
        QA(question: "缓存的歌曲存在哪？占多少空间？",
           answer: "存在沙盒 Caches/folia-media62，设置「存储与备份」可看已缓存首数与占用、上限与全清。",
           keywords: ["缓存", "空间", "目录", "占用"]),
        QA(question: "怎么导出歌词？",
           answer: "设置「存储与备份」的歌词导出行、命令面板「歌词」组、或播放面板歌词页签长按，都能导出当前歌的 .lrc 与 .fia。",
           keywords: ["导出", "歌词", "lrc", "fia"]),
        QA(question: "命令面板怎么打开？",
           answer: "点播台顶排的「命令」键打开；命令涵盖播放/队列/导航/面板/歌词/速记簿/目录/大肥鱼/场景/主题等组。",
           keywords: ["命令", "面板", "快捷"]),
        QA(question: "OBS 直播怎么显示歌词海报？",
           answer: "设置「连接与集成」复制 OBS 浏览器源地址，在 OBS 新建浏览器源粘贴即可；页面每 5 秒刷新当前海报与歌词。",
           keywords: ["obs", "直播", "浏览器源", "海报"]),
        QA(question: "大肥鱼是谁？怎么找她？",
           answer: "大肥鱼是 QQ 机器人（3868261380），在 QQ 加好友或进群 1135730800 @ 她聊天；在线状态以 QQ 端为准。",
           keywords: ["大肥鱼", "机器人", "qq", "陪伴"]),
        QA(question: "同步服务怎么用？",
           answer: "设置「连接与集成」填同步地址与令牌，打开开关后手动推送/拉取；同步对象是设置与速记簿，不含登录态。",
           keywords: ["同步", "r2", "备份", "令牌"]),
        QA(question: "音质怎么切换？",
           answer: "播放面板「音质」页签选档（标准/较高/极高/无损/Hi-Res），下一首取流生效；后端是否给到该档以实际出声为准。",
           keywords: ["音质", "无损", "hires", "码率"]),
        QA(question: "内存占用太高怎么办？",
           answer: "设置「开发者」可开内存持续采样看峰值；全应用峰值硬线 450MB，异常时导出桥日志便于定位。",
           keywords: ["内存", "占用", "卡", "峰值"]),
        QA(question: "日志在哪看？怎么导出？",
           answer: "设置「开发者」的「查看全量日志（分页）」可翻看全部桥日志并导出分享；「写入本地文件」关后不再落盘。",
           keywords: ["日志", "导出", "桥日志", "log"]),
        QA(question: "速记簿是什么？",
           answer: "速记簿是跨来源的歌曲暂存本：搜索行尾按钮收歌，左缘把手拉开抽屉，可分组、看历史、编队列草稿。",
           keywords: ["速记簿", "暂存", "抽屉"]),
        QA(question: "听歌统计在哪清？",
           answer: "设置「存储与备份」的「清除分析数据」会真删本机听歌统计（播放次数/时长）；智能平衡数据在同组清除。",
           keywords: ["统计", "分析", "清除", "平衡"]),
        QA(question: "歌手页/专辑页在哪？",
           answer: "探索与搜索里点歌手进歌手页（热门歌曲＋专辑）；点专辑进专辑页，可播放全部、加入队列与分享信息。",
           keywords: ["歌手", "专辑", "页面"]),
        QA(question: "海报墙怎么开？",
           answer: "命令面板「面板」组的「直播海报墙」，或设置「帮助」的海报墙行；全屏轮播队列封面与当前歌信息。",
           keywords: ["海报墙", "直播", "全屏", "轮播"]),
    ]

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var visible: [QA] = library

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        let title = UILabel()
        title.text = "AI 帮助（本地问答库）"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) },
                       for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(done)
        searchBar.placeholder = "输入关键词，如：缓存 / 歌词 / 同步"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "qa62")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            done.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            searchBar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visible.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "qa62", for: indexPath)
        let qa = visible[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = qa.question
        config.secondaryText = qa.answer
        config.textProperties.color = .white
        config.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.6)
        config.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        cell.selectionStyle = .none
        return cell
    }
}

extension AIHelp62ViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            visible = Self.library
            tableView.reloadData()
            return
        }
        visible = Self.library.map { qa -> (QA, Int) in
            var score = 0
            for keyword in qa.keywords where query.contains(keyword) || keyword.contains(query) {
                score += 2
            }
            if qa.question.lowercased().contains(query) { score += 3 }
            if qa.answer.lowercased().contains(query) { score += 1 }
            return (qa, score)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map { $0.0 }
        tableView.reloadData()
    }
}
