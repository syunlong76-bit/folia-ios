import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// 3.7 (62) WA 簇设置行：页签 0 外观 / 1 播放页 / 2 主页与歌单。
/// 行控件一律 UIAction 闭包接线；写盘经 SettingsStore62A，写后发
/// .foliaSettings62AChanged（userInfo["key"]）供各消费面即时重读。
/// 开关 onTintColor 用 ThemeSystem62.currentAccent——主题系统在
/// 设置页强调色的真消费点。
enum Settings62ClusterA {

    static func build(host: SettingsViewController, into stack: UIStackView,
                      reg: (UIView, Int) -> Void) {
        buildAppearance(host: host, into: stack, reg: reg)
        buildPlayer(host: host, into: stack, reg: reg)
        buildHome(host: host, into: stack, reg: reg)
    }

    private static func post(_ key: String) {
        NotificationCenter.default.post(
            name: .foliaSettings62AChanged, object: nil, userInfo: ["key": key])
    }

    // MARK: - 行工厂（本簇自有，样式与宿主既有行同族）

    /// (63) 第 1 条修：(62) 版 header 直挂 cardStack、从不随卡
    /// 注册页签——13 个 header 是全栈唯一无卡包裹的裸标签，
    /// 压缩时最先塌零、且修好压缩后会在 12 页签同时冒头。
    /// 改照 62B 的 sectionHeaderRow 模式：header 包边距行入
    /// 卡作首行，随卡注册/显隐。各组首行 addRow 均显式
    /// hairline:false，header 入卡不会多出一条发丝线。
    private static func group(_ host: SettingsViewController, into stack: UIStackView,
                              tab: Int, header: String,
                              reg: (UIView, Int) -> Void) -> UIStackView {
        let card = host.makeGroupCard()
        card.addArrangedSubview(sectionHeaderRow(host, header))
        stack.addArrangedSubview(card)
        reg(card, tab)
        return card
    }

    /// 组内分节标题行（与 62B sectionHeaderRow 同构造）：宿主
    /// makeSectionHeader 无边距，包一层带边距的纵向行再入卡，
    /// 与开关行左边距对齐。
    private static func sectionHeaderRow(_ host: SettingsViewController,
                                         _ title: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 2, right: 14)
        row.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle(title)))
        return row
    }

    private static func addRow(_ host: SettingsViewController, to card: UIStackView,
                               _ row: UIView, hairline: Bool = true) {
        if hairline, card.arrangedSubviews.count > 0 {
            card.addArrangedSubview(host.makeHairline())
        }
        card.addArrangedSubview(row)
    }

    private static func titleLabel(_ host: SettingsViewController, _ text: String) -> UILabel {
        let label = UILabel()
        // (66) 行标题过语言表（界面语言 en 时显英文）。
        label.text = FoliaLanguage62.rowTitle(text)
        label.font = .systemFont(ofSize: 15)
        label.textColor = .white
        label.numberOfLines = 0
        host.track(label)
        return label
    }

    private static func switchRow(_ host: SettingsViewController, _ title: String,
                                  isOn: Bool, onChange: @escaping (Bool) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = ThemeSystem62.currentAccent
        toggle.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        toggle.addAction(UIAction { _ in onChange(toggle.isOn) }, for: .valueChanged)
        row.addArrangedSubview(titleLabel(host, title))
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(toggle)
        return row
    }

    private static func segmentedRow(_ host: SettingsViewController, _ title: String,
                                     items: [String], selected: Int,
                                     onChange: @escaping (Int) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selected
        control.addAction(UIAction { _ in
            if control.selectedSegmentIndex >= 0 { onChange(control.selectedSegmentIndex) }
        }, for: .valueChanged)
        row.addArrangedSubview(titleLabel(host, title))
        row.addArrangedSubview(control)
        return row
    }

    private static func sliderRow(_ host: SettingsViewController, _ title: String,
                                  value: Double, min lo: Double, max hi: Double,
                                  format: @escaping (Double) -> String,
                                  onChange: @escaping (Double) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 6
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let head = UIStackView()
        head.axis = .horizontal
        let valueLabel = UILabel()
        valueLabel.text = format(value)
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        host.track(valueLabel)
        head.addArrangedSubview(titleLabel(host, title))
        head.addArrangedSubview(UIView())
        head.addArrangedSubview(valueLabel)
        let slider = UISlider()
        slider.minimumValue = Float(lo)
        slider.maximumValue = Float(hi)
        slider.value = Float(value)
        slider.minimumTrackTintColor = ThemeSystem62.currentAccent
        slider.addAction(UIAction { _ in
            let v = Double(slider.value)
            valueLabel.text = format(v)
            onChange(v)
        }, for: .valueChanged)
        row.addArrangedSubview(head)
        row.addArrangedSubview(slider)
        return row
    }

    private static func buttonRow(_ host: SettingsViewController, _ title: String,
                                  detail: String? = nil,
                                  action: @escaping () -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(ThemeSystem62.currentAccent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        row.addArrangedSubview(button)
        row.addArrangedSubview(UIView())
        if let detail {
            let label = UILabel()
            label.text = detail
            label.font = .systemFont(ofSize: 12)
            label.textColor = UIColor.white.withAlphaComponent(0.55)
            host.track(label)
            row.addArrangedSubview(label)
        }
        return row
    }

    // MARK: - 页签 0 外观
    //
    // (66) 分组构成/顺序/命名对齐网页版 AppearancePage：
    // 歌词渲染器（动画调整/场景/声线追踪）→ 主题（明暗/预设/
    // 主题乐园）→ 歌曲主题（自动切换/自动生成/来源/优先自定义）。

    private static func buildAppearance(host: SettingsViewController, into stack: UIStackView,
                                        reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("外观·62A")

        let lyrics = group(host, into: stack, tab: 0, header: "歌词渲染器", reg: reg)
        addRow(host, to: lyrics, buttonRow(host, "歌词动画调整",
            detail: "样式工作台") {
            VisPlaygroundViewController.present(from: host)
        }, hairline: false)
        addRow(host, to: lyrics, segmentedRow(host, "场景",
            items: ["无", "影厅", "现场", "书房"], selected: SettingsStore.scenePreset) { idx in
            SettingsStore.scenePreset = idx
            post(SettingsStore.Key62A.scenePreset)
        })
        addRow(host, to: lyrics, switchRow(host, "声线追踪",
            isOn: SettingsStore.soundTracingEnabled) { on in
            SettingsStore.soundTracingEnabled = on
            post(SettingsStore.Key62A.soundTracingEnabled)
        })
        // (66) 逐场景设置面：调参场景选择＋三滑杆（暗角/氛围
        // /氛围色调），写 sceneOverrides62，SceneSystem62 在
        // 注册表基值上叠加消费；未覆盖的场景用内置参数。
        let editor = SceneOverrideEditor62()
        addRow(host, to: lyrics, segmentedRow(host, "逐场景调参 · 场景",
            items: ["影厅", "现场", "书房"], selected: editor.targetScene - 1) { idx in
            editor.targetScene = idx + 1
            Breadcrumbs.log("settings66.sceneEdit target=\(idx + 1)")
        })
        let sceneNames = ["影厅", "现场", "书房"]
        addRow(host, to: lyrics, sliderRow(host, "逐场景调参 · 暗角",
            value: editor.value(at: 0), min: 0, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            editor.setValue(at: 0, v)
            post(SettingsStore.Key62A.sceneOverrides62)
        })
        addRow(host, to: lyrics, sliderRow(host, "逐场景调参 · 氛围浓度",
            value: editor.value(at: 1), min: 0, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            editor.setValue(at: 1, v)
            post(SettingsStore.Key62A.sceneOverrides62)
        })
        addRow(host, to: lyrics, sliderRow(host, "逐场景调参 · 氛围色调",
            value: editor.value(at: 2), min: 0, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            editor.setValue(at: 2, v)
            post(SettingsStore.Key62A.sceneOverrides62)
        })
        addRow(host, to: lyrics, host.makeHintRow(
            "场景影响舞台氛围层（暗角/氛围/对比基线）；逐场景调参写入覆盖值、切到该场景即生效，滑杆初值为当前调参场景（默认 \(sceneNames[editor.targetScene - 1])）的有效值。声线追踪在舞台右上画电平近似轨迹线——原生暂无真实频谱数据源，视图内已标注「非频谱」。浅色模式下舞台/墙面等深色设计面仍以深色呈现（见交付报告适配清单）。"))

        let theme = group(host, into: stack, tab: 0, header: "主题", reg: reg)
        addRow(host, to: theme, segmentedRow(host, "明暗模式",
            items: ["浅色", "深色", "跟随系统"],
            selected: [2, 1, 0][SettingsStore.daylightMode]) { idx in
            // 网页序为 浅色/深色/跟随系统；存储口径 0 跟随/1 恒深/2 恒浅。
            SettingsStore.daylightMode = [2, 1, 0][idx]
            post(SettingsStore.Key62A.daylightMode)
            Breadcrumbs.log("settings62.daylightMode=\(SettingsStore.daylightMode)")
        }, hairline: false)
        addRow(host, to: theme, buttonRow(host, "切换配色预设",
            detail: ThemeSystem62.selectedPreset.name) {
            let ids = ThemePreset62.all.map { $0.id } + ["custom"]
            let current = ids.firstIndex(of: SettingsStore.themePresetId) ?? 0
            ThemeSystem62.applyPreset(id: ids[(current + 1) % ids.count])
        })
        addRow(host, to: theme, buttonRow(host, "主题乐园",
            detail: "当前：\(ThemeSystem62.currentSourceLabel)") {
            ThemeParkViewController.present(from: host)
        })
        addRow(host, to: theme, host.makeHintRow(
            "主题乐园里可预览当前歌曲主题、应用预设与自定义三色。"))

        let songTheme = group(host, into: stack, tab: 0, header: "歌曲主题", reg: reg)
        addRow(host, to: songTheme, switchRow(host, "歌曲主题自动切换",
            isOn: SettingsStore.songThemeAutoSwitch) { on in
            SettingsStore.songThemeAutoSwitch = on
            post(SettingsStore.Key62A.songThemeAutoSwitch)
            Breadcrumbs.log("settings62.songThemeAutoSwitch=\(on ? 1 : 0)")
        }, hairline: false)
        addRow(host, to: songTheme, switchRow(host, "自动生成歌曲主题",
            isOn: SettingsStore.songThemeAutoGenerate) { on in
            SettingsStore.songThemeAutoGenerate = on
            post(SettingsStore.Key62A.songThemeAutoGenerate)
        })
        addRow(host, to: songTheme, segmentedRow(host, "主题生成来源",
            items: ["封面", "专辑", "艺术家"], selected: SettingsStore.themeSource) { idx in
            SettingsStore.themeSource = idx
            post(SettingsStore.Key62A.themeSource)
        })
        addRow(host, to: songTheme, switchRow(host, "优先使用自定义主题",
            isOn: SettingsStore.preferCustomTheme) { on in
            SettingsStore.preferCustomTheme = on
            post(SettingsStore.Key62A.preferCustomTheme)
        })
        addRow(host, to: songTheme, host.makeHintRow(
            "歌曲主题由封面主色生成（来源为艺术家时原生无艺术家图源，回退封面并落面包屑标注）。"))
    }

    // MARK: - 页签 1 播放页
    //
    // (66) 对齐网页版 PlayerPage：进入视图（进入视图＋Lattice
    // 全行）→ 控制栏（自动隐藏/高度/拖动定位/两槽指派）→
    // 舞台歌曲卡 → 视频层 → 播放页实验（显隐类＋点播台槽位集）。

    private static func buildPlayer(host: SettingsViewController, into stack: UIStackView,
                                    reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("播放页·62A")

        let entry = group(host, into: stack, tab: 1, header: "进入视图", reg: reg)
        addRow(host, to: entry, segmentedRow(host, "播放后进入的视图",
            items: ["舞台", "播放详情", "留在当前页"],
            selected: SettingsStore.playbackEntryView) { idx in
            SettingsStore.playbackEntryView = idx
            post(SettingsStore.Key62A.playbackEntryView)
        }, hairline: false)
        addRow(host, to: entry, switchRow(host, "Lattice 边缘暗角",
            isOn: SettingsStore.latticeVignetteEnabled) { on in
            SettingsStore.latticeVignetteEnabled = on
            post(SettingsStore.Key62A.latticeVignetteEnabled)
        })
        addRow(host, to: entry, sliderRow(host, "暗角强度",
            value: SettingsStore.latticeVignetteStrength, min: 0, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            SettingsStore.latticeVignetteStrength = v
            post(SettingsStore.Key62A.latticeVignetteStrength)
        })
        addRow(host, to: entry, switchRow(host, "海报聚焦叠色",
            isOn: SettingsStore.latticePosterTintEnabled) { on in
            SettingsStore.latticePosterTintEnabled = on
            post(SettingsStore.Key62A.latticePosterTintEnabled)
        })
        addRow(host, to: entry, switchRow(host, "叠色强制自定义颜色",
            isOn: SettingsStore.latticePosterTintForceCustom) { on in
            SettingsStore.latticePosterTintForceCustom = on
            post(SettingsStore.Key62A.latticePosterTintForceCustom)
        })
        addRow(host, to: entry, buttonRow(host, "叠层颜色",
            detail: SettingsStore.latticePosterTintColorHex) {
            let palette = ["#8B7CF0", "#4C8BF5", "#F58C40", "#66CC80",
                           "#F27399", "#5EC8D8", "#F2C94C", "#EB5757"]
            let current = palette.firstIndex(of: SettingsStore.latticePosterTintColorHex) ?? -1
            SettingsStore.latticePosterTintColorHex = palette[(current + 1) % palette.count]
            post(SettingsStore.Key62A.latticePosterTintColorHex)
        })
        addRow(host, to: entry, sliderRow(host, "叠色强度",
            value: SettingsStore.latticePosterTintStrength, min: 0, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            SettingsStore.latticePosterTintStrength = v
            post(SettingsStore.Key62A.latticePosterTintStrength)
        })
        addRow(host, to: entry, switchRow(host, "只显示正在播放的序号",
            isOn: SettingsStore.latticeBadgeCurrentOnly) { on in
            SettingsStore.latticeBadgeCurrentOnly = on
            post(SettingsStore.Key62A.latticeBadgeCurrentOnly)
        })

        let bar = group(host, into: stack, tab: 1, header: "控制栏", reg: reg)
        addRow(host, to: bar, switchRow(host, "自动隐藏控制栏",
            isOn: SettingsStore.headerAutoHideEnabled) { on in
            SettingsStore.headerAutoHideEnabled = on
            post(SettingsStore.Key62A.headerAutoHideEnabled)
        }, hairline: false)
        addRow(host, to: bar, sliderRow(host, "底部组件高度",
            value: SettingsStore.bottomBarHeight, min: 48, max: 110,
            format: { "\(Int($0.rounded())) pt" }) { v in
            SettingsStore.bottomBarHeight = v
            post(SettingsStore.Key62A.bottomBarHeight)
        })
        addRow(host, to: bar, buttonRow(host, "在播放页拖动调整",
            detail: "拖点播台顶缘") {
            // (66) 网页「底部组件重定位」原生落点：关设置回
            // 舞台后，舞台点播台顶缘拖高柄会脉冲提示一次，
            // 拖动与上方滑杆同键（bottomBarHeight）落盘。
            NotificationCenter.default.post(name: .foliaStageBarLocate66, object: nil)
            Breadcrumbs.log("settings66.barLocate posted=1")
            host.dismiss(animated: true)
        })
        let slotNames = ["无", "上一首", "下一首", "播放列表", "喜欢", "播放模式", "睡眠定时"]
        addRow(host, to: bar, segmentedRow(host, "进度条左槽功能",
            items: slotNames,
            selected: SettingsStore.barSlotFunctions62.firstIndex(of: SettingsStore.barSlotLeft62) ?? 5) { idx in
            SettingsStore.barSlotLeft62 = SettingsStore.barSlotFunctions62[idx]
            post(SettingsStore.Key62A.barSlotLeft62)
            Breadcrumbs.log("settings66.barSlotL=\(SettingsStore.barSlotLeft62)")
        })
        addRow(host, to: bar, segmentedRow(host, "进度条右槽功能",
            items: slotNames,
            selected: SettingsStore.barSlotFunctions62.firstIndex(of: SettingsStore.barSlotRight62) ?? 3) { idx in
            SettingsStore.barSlotRight62 = SettingsStore.barSlotFunctions62[idx]
            post(SettingsStore.Key62A.barSlotRight62)
            Breadcrumbs.log("settings66.barSlotR=\(SettingsStore.barSlotRight62)")
        })
        addRow(host, to: bar, host.makeHintRow(
            "两槽位于播放页进度条左右两端（网页同位），点按执行所指派功能；网页右槽默认的「歌词时间轴」原生无对应功能面，默认置为播放列表。"))

        let pill = group(host, into: stack, tab: 1, header: "舞台歌曲卡", reg: reg)
        addRow(host, to: pill, segmentedRow(host, "显示方式",
            items: ["切歌时显", "常显", "关"],
            selected: SettingsStore.trackPillDisplayMode) { idx in
            SettingsStore.trackPillDisplayMode = idx
            post(SettingsStore.Key62A.trackPillDisplayMode)
        }, hairline: false)
        addRow(host, to: pill, sliderRow(host, "显示时长",
            value: SettingsStore.trackPillDurationSeconds, min: 1, max: 15,
            format: { "\(Int($0.rounded())) 秒" }) { v in
            SettingsStore.trackPillDurationSeconds = v
            post(SettingsStore.Key62A.trackPillDurationSeconds)
        })
        addRow(host, to: pill, segmentedRow(host, "调整位置",
            items: ["左上", "右上", "左下", "右下"],
            selected: SettingsStore.trackPillPosition) { idx in
            SettingsStore.trackPillPosition = idx
            post(SettingsStore.Key62A.trackPillPosition)
        })
        addRow(host, to: pill, switchRow(host, "在首页显示",
            isOn: SettingsStore.trackPillShowOnHome) { on in
            SettingsStore.trackPillShowOnHome = on
            post(SettingsStore.Key62A.trackPillShowOnHome)
        })
        // (66) 假生效做真：原按钮行＋「通路未就绪」弹窗摘除，
        // 改真开关——消费在 LocalServer /obs 页（开启时页面
        // 渲染歌曲卡区块，见 LocalServer.obsPageHTML）。
        addRow(host, to: pill, switchRow(host, "在浏览器源启用",
            isOn: SettingsStore.trackPillOBSEnabled) { on in
            SettingsStore.trackPillOBSEnabled = on
            post(SettingsStore.Key62A.trackPillOBSEnabled)
            Breadcrumbs.log("settings66.pillOBS=\(on ? 1 : 0)")
        })
        addRow(host, to: pill, switchRow(host, "显示信息卡片关闭按钮",
            isOn: SettingsStore.showPanelCloseButton) { on in
            SettingsStore.showPanelCloseButton = on
            post(SettingsStore.Key62A.showPanelCloseButton)
        })

        let video = group(host, into: stack, tab: 1, header: "视频层", reg: reg)
        addRow(host, to: video, switchRow(host, "视频层开关",
            isOn: SettingsStore.videoLayerEnabled) { on in
            SettingsStore.videoLayerEnabled = on
            post(SettingsStore.Key62A.videoLayerEnabled)
        }, hairline: false)
        addRow(host, to: video, buttonRow(host, "本地视频 / 图片",
            detail: CustomBackgroundStore.currentVideoLayer != nil ? "已装入" : "未装入") {
            VideoLayerPicker62.present(from: host)
        })
        addRow(host, to: video, buttonRow(host, "视频 URL",
            detail: SettingsStore.videoLayerURL.isEmpty ? "未设置" : "已设置") {
            let alert = UIAlertController(
                title: "视频层 URL",
                message: "填远程图片/GIF/视频 URL：下载到本地缓存后走原生播放（不用 WebView）。",
                preferredStyle: .alert)
            alert.addTextField { field in
                field.text = SettingsStore.videoLayerURL
                field.placeholder = "https://…"
                field.keyboardType = .URL
                field.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "下载并启用", style: .default) { _ in
                let text = alert.textFields?.first?.text ?? ""
                VideoLayerURLInstaller62.install(from: text)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            host.present(alert, animated: true)
        })
        addRow(host, to: video, sliderRow(host, "视频层不透明度",
            value: SettingsStore.videoLayerOpacity, min: 0.1, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            SettingsStore.videoLayerOpacity = v
            post(SettingsStore.Key62A.videoLayerOpacity)
        })
        addRow(host, to: video, segmentedRow(host, "填充方式",
            items: ["填充", "适应"], selected: SettingsStore.videoLayerFillMode) { idx in
            SettingsStore.videoLayerFillMode = idx
            post(SettingsStore.Key62A.videoLayerFillMode)
        })

        let lab = group(host, into: stack, tab: 1, header: "播放页实验", reg: reg)
        addRow(host, to: lab, switchRow(host, "隐藏底部控制条",
            isOn: SettingsStore.hideBottomBar) { on in
            SettingsStore.hideBottomBar = on
            post(SettingsStore.Key62A.hideBottomBar)
        }, hairline: false)
        addRow(host, to: lab, switchRow(host, "隐藏右侧按钮",
            isOn: SettingsStore.hideRightButtons) { on in
            SettingsStore.hideRightButtons = on
            post(SettingsStore.Key62A.hideRightButtons)
        })
        addRow(host, to: lab, switchRow(host, "始终显示切歌按钮",
            isOn: SettingsStore.alwaysShowSkipButtons) { on in
            SettingsStore.alwaysShowSkipButtons = on
            post(SettingsStore.Key62A.alwaysShowSkipButtons)
        })
        addRow(host, to: lab, switchRow(host, "始终显示播放页返回按钮",
            isOn: SettingsStore.alwaysShowBackButton) { on in
            SettingsStore.alwaysShowBackButton = on
            post(SettingsStore.Key62A.alwaysShowBackButton)
        })
        addRow(host, to: lab, switchRow(host, "播放页顶栏模糊背景",
            isOn: SettingsStore.headerBlurEnabled) { on in
            SettingsStore.headerBlurEnabled = on
            post(SettingsStore.Key62A.headerBlurEnabled)
        })
        addRow(host, to: lab, sectionHeaderRow(host, "点播台按钮槽位集"))
        let slotDefs: [(String, String)] = [
            ("prev", "上一首"), ("next", "下一首"), ("queue", "播放列表"),
            ("like", "喜欢"), ("mode", "播放模式"), ("sleep", "睡眠定时"),
        ]
        for def in slotDefs {
            addRow(host, to: lab, switchRow(host, def.1,
                isOn: SettingsStore.barSlots62.contains(def.0)) { on in
                var current = SettingsStore.barSlots62
                if on, !current.contains(def.0) { current.append(def.0) }
                if !on { current.removeAll { $0 == def.0 } }
                SettingsStore.barSlots62 = slotDefs.map { $0.0 }.filter { current.contains($0) }
                post(SettingsStore.Key62A.barSlots62)
                Breadcrumbs.log("settings62.barSlots=\(SettingsStore.barSlots62.joined(separator: ","))")
            })
        }
        addRow(host, to: lab, host.makeHintRow(
            "槽位集为点播台进度条右侧的按钮集合（(50) 三键自定义的扩展面），舞台与点播台同键消费；上方「控制栏」两槽为播放页进度条两端的单钮指派，两者不同面。"))
    }

    // MARK: - 页签 2 主页与歌单
    //
    // (66) 对齐网页版 HomePage：资料库 → 主页（胶囊入口）→
    // 网格 → 墙面（BravaisWallGroup）；速记簿组为宿主老面卡，
    // 归整后随老面卡在本签末尾（网页同为末组）。

    private static func buildHome(host: SettingsViewController, into stack: UIStackView,
                                  reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("主页与歌单·62A")

        let suite = group(host, into: stack, tab: 2, header: "资料库", reg: reg)
        addRow(host, to: suite, segmentedRow(host, "资料库界面",
            items: ["Bravais 墙", "网格"],
            selected: SettingsStore.librarySuiteChoice) { idx in
            SettingsStore.librarySuiteChoice = idx
            post(SettingsStore.Key62A.librarySuiteChoice)
            Breadcrumbs.log("settings62.librarySuite=\(idx)")
        }, hairline: false)
        addRow(host, to: suite, host.makeHintRow(
            "与墙面工具条布局钮同一状态源：在这里改，回墙即生效；在墙上切，设置页同步。"))

        let tabs = group(host, into: stack, tab: 2, header: "主页", reg: reg)
        addRow(host, to: tabs, switchRow(host, "顶部胶囊入口总开关",
            isOn: SettingsStore.homeTabsEnabled) { on in
            SettingsStore.homeTabsEnabled = on
            post(SettingsStore.Key62A.homeTabsEnabled)
        }, hairline: false)
        addRow(host, to: tabs, switchRow(host, "显示歌单页签",
            isOn: SettingsStore.showHomeTabPlaylists) { on in
            SettingsStore.showHomeTabPlaylists = on
            post(SettingsStore.Key62A.showHomeTabPlaylists)
        })
        addRow(host, to: tabs, switchRow(host, "显示推荐页签",
            isOn: SettingsStore.showHomeTabRecommend) { on in
            SettingsStore.showHomeTabRecommend = on
            post(SettingsStore.Key62A.showHomeTabRecommend)
        })
        addRow(host, to: tabs, switchRow(host, "显示探索页签",
            isOn: SettingsStore.showHomeTabExplore) { on in
            SettingsStore.showHomeTabExplore = on
            post(SettingsStore.Key62A.showHomeTabExplore)
        })
        addRow(host, to: tabs, switchRow(host, "显示专辑页签",
            isOn: SettingsStore.showHomeTabAlbums) { on in
            SettingsStore.showHomeTabAlbums = on
            post(SettingsStore.Key62A.showHomeTabAlbums)
        })
        addRow(host, to: tabs, switchRow(host, "显示本地页签",
            isOn: SettingsStore.showHomeTabLocal) { on in
            SettingsStore.showHomeTabLocal = on
            post(SettingsStore.Key62A.showHomeTabLocal)
        })
        addRow(host, to: tabs, host.makeHintRow(
            "消费点为工作台侧栏分区行：原生侧栏分区为歌单/电台/搜索/专辑/本地，推荐→电台行、探索→搜索行。关掉的分区不渲染。"))

        let grid = group(host, into: stack, tab: 2, header: "网格", reg: reg)
        // (66) 歌单卡片样式做实：拍立得卡片（默认）/纯图片
        // 封面，消费 CollectionView 拍立得网格 cell。
        addRow(host, to: grid, segmentedRow(host, "歌单卡片样式",
            items: ["拍立得卡片", "纯图片封面"],
            selected: SettingsStore.playlistCardStyle62 == "image" ? 1 : 0) { idx in
            SettingsStore.playlistCardStyle62 = idx == 1 ? "image" : "card"
            post(SettingsStore.Key62A.playlistCardStyle62)
            Breadcrumbs.log("settings66.plistStyle=\(SettingsStore.playlistCardStyle62)")
        }, hairline: false)
        addRow(host, to: grid, switchRow(host, "3D 卡片",
            isOn: SettingsStore.grid3DCardStyle) { on in
            SettingsStore.grid3DCardStyle = on
            post(SettingsStore.Key62A.grid3DCardStyle)
        })
        addRow(host, to: grid, switchRow(host, "全画幅封面",
            isOn: SettingsStore.gridFullBleedCover) { on in
            SettingsStore.gridFullBleedCover = on
            post(SettingsStore.Key62A.gridFullBleedCover)
        })
        addRow(host, to: grid, switchRow(host, "正方形卡片",
            isOn: SettingsStore.gridSquareCards) { on in
            SettingsStore.gridSquareCards = on
            post(SettingsStore.Key62A.gridSquareCards)
        })
        addRow(host, to: grid, sliderRow(host, "卡片最小尺寸",
            value: SettingsStore.gridCardMinSize, min: 60, max: 180,
            format: { "\(Int($0.rounded())) pt" }) { v in
            SettingsStore.gridCardMinSize = v
            post(SettingsStore.Key62A.gridCardMinSize)
        })
        addRow(host, to: grid, sliderRow(host, "卡片最小透明度",
            value: SettingsStore.gridCardMinOpacity, min: 0.3, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            SettingsStore.gridCardMinOpacity = v
            post(SettingsStore.Key62A.gridCardMinOpacity)
        })
        addRow(host, to: grid, host.makeHintRow(
            "3D 卡片为透视倾斜＋高光近似（非真 3D 渲染）。纯图片封面只影响歌单网格的卡片外观（去白框与标题条）。"))

        let wall = group(host, into: stack, tab: 2, header: "墙面", reg: reg)
        addRow(host, to: wall, switchRow(host, "记住主页卡片位置",
            isOn: SettingsStore.rememberCardPositions) { on in
            SettingsStore.rememberCardPositions = on
            post(SettingsStore.Key62A.rememberCardPositions)
        }, hairline: false)
        addRow(host, to: wall, sliderRow(host, "墙面透光",
            value: SettingsStore.wallTransparency, min: 0, max: 1,
            format: { "\(Int(($0 * 100).rounded()))%" }) { v in
            SettingsStore.wallTransparency = v
            post(SettingsStore.Key62A.wallTransparency)
        })
        addRow(host, to: wall, sliderRow(host, "每块窗数",
            value: Double(SettingsStore.wallWindowsPerPane), min: 1, max: 12,
            format: { "\(Int($0.rounded()))" }) { v in
            SettingsStore.wallWindowsPerPane = Int(v.rounded())
            post(SettingsStore.Key62A.wallWindowsPerPane)
        })
        addRow(host, to: wall, switchRow(host, "集合叠页边",
            isOn: SettingsStore.stackEdgesEnabled) { on in
            SettingsStore.stackEdgesEnabled = on
            post(SettingsStore.Key62A.stackEdgesEnabled)
        })
        // (63) 第 4 条：信息条本体（StripSurface62）已按 Miller
        // 令摘除，其三行设置（方向/始终透明/样式）唯一消费者
        // 就是本体，随本体一并撤下防假生效；存储键保留不读。
        addRow(host, to: wall, switchRow(host, "墙后画面显示歌词",
            isOn: SettingsStore.backdropLyricsEnabled) { on in
            SettingsStore.backdropLyricsEnabled = on
            post(SettingsStore.Key62A.backdropLyricsEnabled)
        })
        addRow(host, to: wall, sliderRow(host, "墙后画面模糊",
            value: SettingsStore.backdropBlurAmount, min: 0, max: 30,
            format: { "\(Int($0.rounded()))" }) { v in
            SettingsStore.backdropBlurAmount = v
            post(SettingsStore.Key62A.backdropBlurAmount)
        })
        addRow(host, to: wall, host.makeHintRow(
            "记住卡片位置开启后，卡片顺序与墙面相机位置（平移原点/网格滚动偏移）一并落盘，下次进墙恢复（(66) 几何面做实）。"))
    }
}

/// (66) 逐场景调参编辑器：持有当前调参场景（三滑杆共用），
/// 读 SceneSystem62 有效参数、写 sceneOverrides62 覆盖。
final class SceneOverrideEditor62 {
    var targetScene: Int
    init() { targetScene = min(max(SettingsStore.scenePreset, 1), 3) }
    func value(at index: Int) -> Double {
        SceneSystem62.effectiveParams(forScene: targetScene).tuple[index]
    }
    func setValue(at index: Int, _ v: Double) {
        var all = SettingsStore.sceneOverrides62
        var arr = all["\(targetScene)"]
            ?? SceneSystem62.registeredParams(forScene: targetScene).tuple
        arr[index] = v
        all["\(targetScene)"] = arr
        SettingsStore.sceneOverrides62 = all
        Breadcrumbs.log("settings66.sceneOverride scene=\(targetScene) idx=\(index)")
    }
}

extension Notification.Name {
    /// (66) 设置行「在播放页拖动调整」→ 舞台点播台拖高柄脉冲。
    static let foliaStageBarLocate66 = Notification.Name("foliaStageBarLocate66")
}

/// (62) 视频层本地媒体选入：PHPicker 选图片/动图/视频 → 装进
/// 视频层独立槽（installVideoLayer）→ 开视频层开关 → 发变更通知。
final class VideoLayerPicker62: NSObject, PHPickerViewControllerDelegate {
    private static var retained: VideoLayerPicker62?

    static func present(from host: UIViewController) {
        let picker62 = VideoLayerPicker62()
        retained = picker62
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = picker62
        host.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController,
                didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        Self.retained = nil
        guard let provider = results.first?.itemProvider else { return }
        let isMovie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let typeId = isMovie ? UTType.movie.identifier : UTType.image.identifier
        provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
            guard let url else {
                Breadcrumbs.log("videolayer62.local fail=no-file")
                return
            }
            let kind: CustomBackgroundKind = isMovie
                ? .video
                : (CustomBackgroundStore.imageFrameCount(at: url) > 1 ? .animated : .image)
            do {
                let bytes = try CustomBackgroundStore.installVideoLayer(
                    sourceURL: url, kind: kind)
                SettingsStore.videoLayerEnabled = true
                Breadcrumbs.log("videolayer62.local ok kind=\(kind.rawValue) bytes=\(bytes)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .foliaSettings62AChanged, object: nil,
                        userInfo: ["key": SettingsStore.Key62A.videoLayerEnabled])
                }
            } catch {
                Breadcrumbs.log("videolayer62.local fail=install")
            }
        }
    }
}
