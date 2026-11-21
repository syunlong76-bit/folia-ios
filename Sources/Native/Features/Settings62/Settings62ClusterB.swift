import UIKit
import MediaPlayer

/// (62) WB 簇设置行：§4.4 动画与性能（页签 3）/ §4.5 播放
/// 控制（页签 4）/ §4.6 歌词（页签 5）/ §4.7 通用余项（页
/// 签 6）/ §4.8 快捷操作（页签 7）/ §4.9 两项（页签 8）。
///
/// 契约：不改 SettingsViewController 本体；行工厂用宿主已去
/// 私有化的 makeGroupCard/makeSectionHeader/makeHairline/
/// makeHintRow；控件一律 UIAction 闭包接线；每签建组前先
/// host.beginCheckGroup("<页签名>")。键层见 SettingsStore62B，
/// 消费面见 FoliaMotion62 / PlaybackEngine / LyricRepository
/// 等 WB 落点与报告的跨簇交接清单。
enum Settings62ClusterB {

    private static let accent = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 1)
    private static let primary = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    private static let secondary = UIColor(red: 0.604, green: 0.604, blue: 0.639, alpha: 1)
    private static let buttonFill = UIColor.white.withAlphaComponent(0.08)

    static func build(host: SettingsViewController, into stack: UIStackView,
                      reg: (UIView, Int) -> Void) {
        buildMotionTab(host: host, into: stack, reg: reg)
        buildPlaybackTab(host: host, into: stack, reg: reg)
        buildLyricsTab(host: host, into: stack, reg: reg)
        buildGeneralTab(host: host, into: stack, reg: reg)
        buildShortcutsTab(host: host, into: stack, reg: reg)
        buildConnectionsTab(host: host, into: stack, reg: reg)
        applySettingsScrollBehavior(host: host)
    }

    /// 组内分节标题行：宿主 makeSectionHeader 无边距，包一层
    /// 带边距的纵向行再入卡，与开关行左边距对齐。
    private static func sectionHeaderRow(host: SettingsViewController,
                                         title: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 2, right: 14)
        row.addArrangedSubview(host.makeSectionHeader(title))
        return row
    }

    // MARK: - 行工厂（UIAction 版，与宿主行同构造族）

    private static func switchRow(host: SettingsViewController, title: String,
                                  isOn: Bool, onChange: @escaping (Bool) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = primary
        label.numberOfLines = 0
        host.track(label)
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = accent
        toggle.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        toggle.addAction(UIAction { [weak toggle] _ in
            guard let toggle else { return }
            onChange(toggle.isOn)
        }, for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(toggle)
        return row
    }

    private static func segmentedRow(host: SettingsViewController, title: String,
                                     items: [String], selected: Int,
                                     onChange: @escaping (Int) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = primary
        host.track(label)
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selected
        control.selectedSegmentTintColor = accent
        control.setTitleTextAttributes(
            [.foregroundColor: primary, .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor.white,
             .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
        control.addAction(UIAction { [weak control] _ in
            guard let control else { return }
            onChange(control.selectedSegmentIndex)
        }, for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private static func sliderRow(host: SettingsViewController, title: String,
                                  min: Float, max: Float, value: Float,
                                  format: @escaping (Float) -> String,
                                  onChange: @escaping (Float) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let head = UIStackView()
        head.axis = .horizontal
        head.alignment = .center
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = primary
        host.track(label)
        let valueLabel = UILabel()
        valueLabel.text = format(value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = primary
        host.track(valueLabel)
        head.addArrangedSubview(label)
        head.addArrangedSubview(UIView())
        head.addArrangedSubview(valueLabel)
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.minimumTrackTintColor = accent
        slider.addAction(UIAction { [weak slider] _ in
            guard let slider else { return }
            valueLabel.text = format(slider.value)
            onChange(slider.value)
        }, for: .valueChanged)
        row.addArrangedSubview(head)
        row.addArrangedSubview(slider)
        return row
    }

    /// 文本值行：标题 + 当前值 + 「编辑」钮（点开弹窗输入）。
    private static func textRow(host: SettingsViewController, title: String,
                                value: @escaping () -> String,
                                placeholder: String,
                                validate: @escaping (String) -> String?,
                                onSave: @escaping (String) -> Void) -> UIStackView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = primary
        host.track(label)
        let valueLabel = UILabel()
        valueLabel.text = value().isEmpty ? "（未设置）" : value()
        valueLabel.font = .systemFont(ofSize: 12.5)
        valueLabel.textColor = secondary
        valueLabel.numberOfLines = 0
        host.track(valueLabel)
        let button = UIButton(type: .system)
        button.setTitle("编辑", for: .normal)
        button.setTitleColor(accent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = buttonFill
        button.layer.cornerRadius = 10
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        if let titleLabel = button.titleLabel { host.track(titleLabel) }
        button.addAction(UIAction { [weak host] _ in
            guard let host else { return }
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alert.addTextField { field in
                field.text = value()
                field.placeholder = placeholder
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
                let text = alert?.textFields?.first?.text ?? ""
                if let error = validate(text) {
                    let fail = UIAlertController(title: "未保存", message: error,
                                                 preferredStyle: .alert)
                    fail.addAction(UIAlertAction(title: "好", style: .default))
                    host.present(fail, animated: true)
                    return
                }
                onSave(text)
                valueLabel.text = text.isEmpty ? "（未设置）" : text
            })
            host.present(alert, animated: true)
        }, for: .touchUpInside)
        row.addArrangedSubview(label)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(button)
        return row
    }

    private static func buttonRow(host: SettingsViewController, title: String,
                                  action: @escaping () -> Void) -> UIView {
        let wrap = UIView()
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(accent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.backgroundColor = buttonFill
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        if let titleLabel = button.titleLabel { host.track(titleLabel) }
        wrap.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            button.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -12),
            button.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            button.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
        return wrap
    }

    // MARK: - 页签 3：动画与性能（§4.4）

    private static func buildMotionTab(host: SettingsViewController, into stack: UIStackView,
                                       reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("动画与性能·62B")

        let reduceGroup = host.makeGroupCard()
        reduceGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "降低动态（细分）"))
        reduceGroup.addArrangedSubview(switchRow(host: host, title: "队列拼贴",
            isOn: SettingsStore.reduceMotionQueueCollage) {
            SettingsStore.reduceMotionQueueCollage = $0
            Breadcrumbs.log("settings62.reduce queueCollage=\($0)")
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(switchRow(host: host, title: "混音过渡",
            isOn: SettingsStore.reduceMotionMixTransition) {
            SettingsStore.reduceMotionMixTransition = $0
            Breadcrumbs.log("settings62.reduce mixTransition=\($0)")
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(switchRow(host: host, title: "歌单展开转场",
            isOn: SettingsStore.reduceMotionPlaylistExpand) {
            SettingsStore.reduceMotionPlaylistExpand = $0
            Breadcrumbs.log("settings62.reduce playlistExpand=\($0)")
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(switchRow(host: host, title: "Monet 背景漂移",
            isOn: SettingsStore.reduceMotionMonetDrift) {
            SettingsStore.reduceMotionMonetDrift = $0
            Breadcrumbs.log("settings62.reduce monetDrift=\($0)")
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(switchRow(host: host, title: "界面微动效",
            isOn: SettingsStore.reduceMotionMicroEffects) {
            SettingsStore.reduceMotionMicroEffects = $0
            Breadcrumbs.log("settings62.reduce microEffects=\($0)")
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(switchRow(host: host, title: "设置页平滑滚动",
            isOn: SettingsStore.reduceMotionSettingsScroll) {
            SettingsStore.reduceMotionSettingsScroll = $0
            Breadcrumbs.log("settings62.reduce settingsScroll=\($0)")
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(host.makeHintRow(
            "门控口径：上方「降低动态 · 跟随系统」开启时全局跟随系统减弱动态效果、本组细分不参与；关掉跟随后改由本组逐项判定（FoliaMotion62 统一判定面）。"))
        stack.addArrangedSubview(reduceGroup)
        reg(reduceGroup, 3)

        let perfGroup = host.makeGroupCard()
        perfGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "显示与性能"))
        perfGroup.addArrangedSubview(switchRow(host: host, title: "静态模式",
            isOn: SettingsStore.staticModeEnabled) {
            FoliaMotion62.setStaticMode($0)
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(switchRow(host: host, title: "主页动态背景",
            isOn: SettingsStore.homeDynamicBackgroundEnabled) {
            SettingsStore.homeDynamicBackgroundEnabled = $0
            NotificationCenter.default.post(name: .foliaHomeDynamicBackgroundChanged, object: nil)
            Breadcrumbs.log("settings62.homeDynamicBackground=\($0)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(switchRow(host: host, title: "播放页原生毛玻璃背景",
            isOn: SettingsStore.stageBackdropBlurEnabled) {
            SettingsStore.stageBackdropBlurEnabled = $0
            Breadcrumbs.log("settings62.stageBackdropBlur=\($0)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(switchRow(host: host, title: "实验性动画帧率限制",
            isOn: SettingsStore.frameRateLimitEnabled) {
            SettingsStore.frameRateLimitEnabled = $0
            Breadcrumbs.log("settings62.frameRateLimit enabled=\($0)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(segmentedRow(host: host, title: "帧率限制档位",
            items: ["30", "60", "120"],
            selected: [30, 60, 120].firstIndex(of: SettingsStore.frameRateLimitFPS) ?? 1) {
            SettingsStore.frameRateLimitFPS = [30, 60, 120][$0]
            Breadcrumbs.log("settings62.frameRateLimit fps=\(SettingsStore.frameRateLimitFPS)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(switchRow(host: host, title: "歌词画布抗锯齿",
            isOn: SettingsStore.lyricAntialiasEnabled) {
            SettingsStore.lyricAntialiasEnabled = $0
            Breadcrumbs.log("settings62.lyricAntialias=\($0)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(host.makeHintRow(
            "静态模式开启后舞台逐帧动画与墙面动效停住（进度与播放不受影响）。帧率限制对进度驱动即时生效，舞台帧率由舞台侧同键消费。抗锯齿为全局口径：逐样式调参面板里的抗锯齿值优先于本开关。歌词画布分辨率（上方既有行）已扩消费到文本烘焙入口与逐词超采样。"))
        stack.addArrangedSubview(perfGroup)
        reg(perfGroup, 3)

        let bgGroup = host.makeGroupCard()
        bgGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "后台与触摸"))
        bgGroup.addArrangedSubview(segmentedRow(host: host, title: "后台节流",
            items: ["标准", "积极"],
            selected: SettingsStore.backgroundThrottlePolicy == "aggressive" ? 1 : 0) {
            SettingsStore.backgroundThrottlePolicy = $0 == 1 ? "aggressive" : "standard"
            Breadcrumbs.log("settings62.backgroundThrottle=\(SettingsStore.backgroundThrottlePolicy)")
        })
        bgGroup.addArrangedSubview(host.makeHairline())
        bgGroup.addArrangedSubview(switchRow(host: host, title: "播放页触摸光效",
            isOn: SettingsStore.touchGlowEnabled) {
            SettingsStore.touchGlowEnabled = $0
            Breadcrumbs.log("settings62.touchGlow=\($0)")
        })
        bgGroup.addArrangedSubview(host.makeHairline())
        bgGroup.addArrangedSubview(sliderRow(host: host, title: "触摸光效密度",
            min: 0, max: 1, value: Float(SettingsStore.touchGlowDensity),
            format: { "\(Int(($0 * 100).rounded()))%" }) {
            SettingsStore.touchGlowDensity = Double($0)
        })
        bgGroup.addArrangedSubview(host.makeHairline())
        bgGroup.addArrangedSubview(host.makeHintRow(
            "后台节流「积极」时进后台即停进度驱动等逐帧链； iOS 后台任务的调度本身由系统接管，本设置只管应用内动画链。触摸光效在舞台触摸点泛光，密度决定并发光晕与粒子数。"))
        stack.addArrangedSubview(bgGroup)
        reg(bgGroup, 3)
    }

    /// 设置页平滑滚动消费（宿主本体不改）：在本簇构建时找到
    /// 宿主卡片内的滚动视图，按 FoliaMotion62 判定设减速率
    /// ——降低动态命中时用系统普通减速（无平滑惯性加工），
    /// 未命中时用快速减速保持跟手。消费深度如实：仅构建时
    /// 一次性应用，判定变更下次打开设置页生效。
    private static func applySettingsScrollBehavior(host: SettingsViewController) {
        let reduced = FoliaMotion62.reduced(.settingsScroll)
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView {
                scroll.decelerationRate = reduced ? .normal : .fast
            }
            view.subviews.forEach(walk)
        }
        walk(host.view)
        Breadcrumbs.log("settings62.scrollBehavior reduced=\(reduced)")
    }

    // MARK: - 页签 4：播放控制（§4.5）

    private static func buildPlaybackTab(host: SettingsViewController, into stack: UIStackView,
                                         reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("播放控制·62B")

        let transitionGroup = host.makeGroupCard()
        transitionGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "智能过渡"))
        transitionGroup.addArrangedSubview(switchRow(host: host, title: "智能过渡",
            isOn: SettingsStore.smartTransitionEnabled) {
            SettingsStore.smartTransitionEnabled = $0
            Breadcrumbs.log("settings62.smartTransition=\($0)")
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(segmentedRow(host: host, title: "过渡模式",
            items: ["Crossfade", "Automix"],
            selected: SettingsStore.transitionMode == "automix" ? 1 : 0) {
            SettingsStore.transitionMode = $0 == 1 ? "automix" : "crossfade"
            Breadcrumbs.log("settings62.transitionMode=\(SettingsStore.transitionMode)")
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(sliderRow(host: host, title: "过渡最长时长",
            min: 1, max: 12, value: Float(SettingsStore.transitionMaxDurationSec),
            format: { "\(Int($0.rounded())) 秒" }) {
            SettingsStore.transitionMaxDurationSec = Double($0)
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(segmentedRow(host: host, title: "过渡表现模式",
            items: ["等功率", "线性", "缓入缓出"],
            selected: ["equalPower", "linear", "easeInOut"]
                .firstIndex(of: SettingsStore.transitionCurve) ?? 0) {
            SettingsStore.transitionCurve = ["equalPower", "linear", "easeInOut"][$0]
            Breadcrumbs.log("settings62.transitionCurve=\(SettingsStore.transitionCurve)")
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(segmentedRow(host: host, title: "过渡动画",
            items: ["无", "屏幕圆环", "卡片描边"],
            selected: ["none", "ring", "cardStroke"]
                .firstIndex(of: SettingsStore.transitionAnimation) ?? 0) {
            SettingsStore.transitionAnimation = ["none", "ring", "cardStroke"][$0]
            Breadcrumbs.log("settings62.transitionAnimation=\(SettingsStore.transitionAnimation)")
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(host.makeHintRow(
            "下一首会在当前曲尾段预载到 B 轨并按曲线混音切入；Automix 按下一首前奏提前量对齐（无能量数据时以固定提前量近似，日志有标注），失败自动回退硬切。「降低动态 · 混音过渡」开启时过渡动画层停用、只保留音频斜坡。"))
        stack.addArrangedSubview(transitionGroup)
        reg(transitionGroup, 4)

        let gainGroup = host.makeGroupCard()
        gainGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "增益与淡变"))
        gainGroup.addArrangedSubview(switchRow(host: host, title: "ReplayGain",
            isOn: SettingsStore.replayGainEnabled) {
            SettingsStore.replayGainEnabled = $0
            PlaybackEngine.shared.refreshReplayGain()
            Breadcrumbs.log("settings62.replayGain=\($0)")
        })
        gainGroup.addArrangedSubview(host.makeHairline())
        gainGroup.addArrangedSubview(segmentedRow(host: host, title: "暂停 / 播放淡入淡出",
            items: ["无", "100ms", "200ms", "400ms"],
            selected: [0, 100, 200, 400].firstIndex(of: SettingsStore.playPauseFadeMs) ?? 2) {
            SettingsStore.playPauseFadeMs = [0, 100, 200, 400][$0]
            Breadcrumbs.log("settings62.playPauseFadeMs=\(SettingsStore.playPauseFadeMs)")
        })
        gainGroup.addArrangedSubview(host.makeHairline())
        gainGroup.addArrangedSubview(host.makeHintRow(
            "ReplayGain 在引擎音量链上乘增益系数：优先用音量平衡学习到的逐曲偏移，其次曲目元数据增益，都没有时为 1.0（不改音量）。淡入淡出作用于播放与暂停的音量斜坡。"))
        stack.addArrangedSubview(gainGroup)
        reg(gainGroup, 4)

        let deviceGroup = host.makeGroupCard()
        deviceGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "兜底与设备"))
        deviceGroup.addArrangedSubview(switchRow(host: host, title: "自动转换无法播放的音频",
            isOn: SettingsStore.autoTranscodeEnabled) {
            SettingsStore.autoTranscodeEnabled = $0
            Breadcrumbs.log("settings62.autoTranscode=\($0)")
        })
        deviceGroup.addArrangedSubview(host.makeHairline())
        deviceGroup.addArrangedSubview(buttonRow(host: host, title: "声音与设备（音频输出）") { [weak host] in
            guard let host else { return }
            let panel = AudioRoute62ViewController()
            panel.modalPresentationStyle = .pageSheet
            host.present(panel, animated: true)
        })
        deviceGroup.addArrangedSubview(host.makeHairline())
        deviceGroup.addArrangedSubview(switchRow(host: host, title: "播放时阻止休眠",
            isOn: SettingsStore.preventSleepWhilePlaying) {
            SettingsStore.preventSleepWhilePlaying = $0
            PlaybackEngine.shared.refreshIdleTimerGate()
            Breadcrumbs.log("settings62.preventSleep=\($0)")
        })
        deviceGroup.addArrangedSubview(host.makeHairline())
        deviceGroup.addArrangedSubview(switchRow(host: host, title: "语音输入时暂停",
            isOn: SettingsStore.pauseOnVoiceInput) {
            SettingsStore.pauseOnVoiceInput = $0
            Breadcrumbs.log("settings62.pauseOnVoiceInput=\($0)")
        })
        deviceGroup.addArrangedSubview(host.makeHairline())
        deviceGroup.addArrangedSubview(host.makeHintRow(
            "自动转换只对已落盘的本地/缓存音频可行（转 m4a 后播放）；流媒体不可播仍走自动跳过逻辑，服务端转码链不在本机能力内。音频输出路由由 iOS 系统接管，本行打开系统路由选择。阻止休眠为播放期间保持屏幕常亮（桌面端的同名语义在 iOS 上即此）。语音输入时暂停监听音频会话中断（Siri 等），中断后不自动恢复。"))
        stack.addArrangedSubview(deviceGroup)
        reg(deviceGroup, 4)
    }

    // MARK: - 页签 5：歌词（§4.6）

    private static func buildLyricsTab(host: SettingsViewController, into stack: UIStackView,
                                       reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("歌词·62B")

        let strategyGroup = host.makeGroupCard()
        strategyGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "取词策略"))
        strategyGroup.addArrangedSubview(switchRow(host: host, title: "自动使用最佳歌词",
            isOn: SettingsStore.autoBestLyricEnabled) {
            SettingsStore.autoBestLyricEnabled = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.autoBestLyric=\($0)")
        })
        strategyGroup.addArrangedSubview(host.makeHairline())
        strategyGroup.addArrangedSubview(segmentedRow(host: host, title: "最佳歌词策略",
            items: ["YRC 优先", "行级优先", "时长匹配"],
            selected: ["yrcFirst", "lrcFirst", "durationMatch"]
                .firstIndex(of: SettingsStore.bestLyricStrategy) ?? 0) {
            SettingsStore.bestLyricStrategy = ["yrcFirst", "lrcFirst", "durationMatch"][$0]
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.bestLyricStrategy=\(SettingsStore.bestLyricStrategy)")
        })
        strategyGroup.addArrangedSubview(host.makeHairline())
        strategyGroup.addArrangedSubview(segmentedRow(host: host, title: "歌词匹配优先级",
            items: ["精确优先", "折叠优先", "时刻优先"],
            selected: ["exactFirst", "foldedFirst", "timeFirst"]
                .firstIndex(of: SettingsStore.lyricMatchPriority) ?? 0) {
            SettingsStore.lyricMatchPriority = ["exactFirst", "foldedFirst", "timeFirst"][$0]
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.matchPriority=\(SettingsStore.lyricMatchPriority)")
        })
        strategyGroup.addArrangedSubview(host.makeHairline())
        strategyGroup.addArrangedSubview(switchRow(host: host, title: "保留平台自带的逐字歌词",
            isOn: SettingsStore.keepPlatformWordLyrics) {
            SettingsStore.keepPlatformWordLyrics = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.keepWordLyrics=\($0)")
        })
        strategyGroup.addArrangedSubview(host.makeHairline())
        strategyGroup.addArrangedSubview(host.makeHintRow(
            "策略变更会清歌词缓存，下次播放按新策略重新取词。关掉「保留逐字」后合并结果丢弃逐字戳、退回行级扫光。"))
        stack.addArrangedSubview(strategyGroup)
        reg(strategyGroup, 5)

        let localGroup = host.makeGroupCard()
        localGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "本地与过滤"))
        localGroup.addArrangedSubview(segmentedRow(host: host, title: "本地歌曲歌词优先级",
            items: ["平台优先", "本地优先"],
            selected: SettingsStore.localLyricPriority == "localFirst" ? 1 : 0) {
            SettingsStore.localLyricPriority = $0 == 1 ? "localFirst" : "platformFirst"
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.localLyricPriority=\(SettingsStore.localLyricPriority)")
        })
        localGroup.addArrangedSubview(host.makeHairline())
        localGroup.addArrangedSubview(textRow(host: host, title: "本地歌词格式顺序",
            value: { SettingsStore.localLyricFormatOrder },
            placeholder: "lrc,yrc,txt",
            validate: { $0.isEmpty ? "不能为空" : nil }) {
            SettingsStore.localLyricFormatOrder = $0
            Breadcrumbs.log("settings62.localLyricFormatOrder=\($0)")
        })
        localGroup.addArrangedSubview(host.makeHairline())
        localGroup.addArrangedSubview(textRow(host: host, title: "歌词过滤（正则）",
            value: { SettingsStore.lyricFilterRegex },
            placeholder: "如 ^(作词|作曲)",
            validate: { LyricFilter62.validate($0) }) {
            SettingsStore.lyricFilterRegex = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.lyricFilter set len=\($0.count)")
        })
        localGroup.addArrangedSubview(host.makeHairline())
        localGroup.addArrangedSubview(host.makeHintRow(
            "本地歌词经本地曲库注册的歌词源钩子查询（本地曲库未落地前钩子为空、行为不变）。过滤正则在歌词出口按行剔除命中行，非法正则保存时会被拦下、不会落盘。"))
        stack.addArrangedSubview(localGroup)
        reg(localGroup, 5)

        let aiGroup = host.makeGroupCard()
        aiGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "自动 AI 分词"))
        aiGroup.addArrangedSubview(switchRow(host: host, title: "自动 AI 分词",
            isOn: SettingsStore.aiSegmentEnabled) {
            SettingsStore.aiSegmentEnabled = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.aiSegment=\($0)")
        })
        aiGroup.addArrangedSubview(host.makeHairline())
        aiGroup.addArrangedSubview(textRow(host: host, title: "AI 分词服务端点",
            value: { SettingsStore.aiSegmentEndpoint },
            placeholder: "https://…/segment",
            validate: { text in
                if text.isEmpty { return nil }
                return URL(string: text) == nil ? "不是合法 URL" : nil
            }) {
            SettingsStore.aiSegmentEndpoint = $0
            Breadcrumbs.log("settings62.aiSegmentEndpoint set=\(!$0.isEmpty)")
        })
        aiGroup.addArrangedSubview(host.makeHairline())
        aiGroup.addArrangedSubview(host.makeHintRow(
            "开启且端点已配置时，无逐字戳的行会把文本发往该端点换取分词时刻；端点未配置时走本地均分＋跨曲标定估算，日志会如实标注「未配置 AI 服务、走本地估算」，不冒充 AI 分词。"))
        stack.addArrangedSubview(aiGroup)
        reg(aiGroup, 5)
    }

    // MARK: - 页签 6：通用（§4.7 余项）

    private static func buildGeneralTab(host: SettingsViewController, into stack: UIStackView,
                                        reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("通用·62B")

        let launchGroup = host.makeGroupCard()
        launchGroup.addArrangedSubview(sectionHeaderRow(host: host, title: FoliaLanguage62.tabTitle(6)))
        launchGroup.addArrangedSubview(segmentedRow(host: host, title: "界面语言",
            items: ["简体中文", "English"],
            selected: SettingsStore.appLanguage == "en" ? 1 : 0) {
            SettingsStore.appLanguage = $0 == 1 ? "en" : "zh-Hans"
            Breadcrumbs.log("settings62.appLanguage=\(SettingsStore.appLanguage)")
        })
        launchGroup.addArrangedSubview(host.makeHairline())
        launchGroup.addArrangedSubview(switchRow(host: host, title: "启动后直接进入播放界面",
            isOn: SettingsStore.openPlayerOnLaunch) {
            SettingsStore.openPlayerOnLaunch = $0
            Breadcrumbs.log("settings62.openPlayerOnLaunch=\($0)")
        })
        launchGroup.addArrangedSubview(host.makeHairline())
        launchGroup.addArrangedSubview(host.makeHintRow(
            "界面语言目前覆盖设置页签标题、思索面等关键面文案，其余面仍为简体中文（全量本地化未做，不冒充）。直接进入播放界面在入场动画播完或关闭后才直达舞台，不抢入场；无可播放队列时不直达。"))
        stack.addArrangedSubview(launchGroup)
        reg(launchGroup, 6)

        let ponderGroup = host.makeGroupCard()
        ponderGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "思索教程"))
        ponderGroup.addArrangedSubview(switchRow(host: host, title: "思索教程提示",
            isOn: SettingsStore.ponderTipsEnabled) {
            SettingsStore.ponderTipsEnabled = $0
            Breadcrumbs.log("settings62.ponderTips=\($0)")
        })
        ponderGroup.addArrangedSubview(host.makeHairline())
        ponderGroup.addArrangedSubview(switchRow(host: host, title: "触屏思索按钮",
            isOn: SettingsStore.ponderTouchButtonEnabled) {
            SettingsStore.ponderTouchButtonEnabled = $0
            Breadcrumbs.log("settings62.ponderButton=\($0)")
        })
        ponderGroup.addArrangedSubview(host.makeHairline())
        ponderGroup.addArrangedSubview(buttonRow(host: host, title: "打开思索教程列表") { [weak host] in
            guard let host else { return }
            Ponder62.presentList(from: host)
        })
        ponderGroup.addArrangedSubview(host.makeHairline())
        ponderGroup.addArrangedSubview(host.makeHintRow(
            "教程提示在功能面首次使用时出现一次，读过不再弹（列表里可重置已读）。触屏思索按钮是墙面右下的「?」悬浮钮，点开即教程列表；开关变更下次进墙生效。"))
        stack.addArrangedSubview(ponderGroup)
        reg(ponderGroup, 6)
    }

    // MARK: - 页签 7：快捷操作（§4.8）

    private static func buildShortcutsTab(host: SettingsViewController, into stack: UIStackView,
                                          reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("快捷操作·62B")

        let pinGroup = host.makeGroupCard()
        pinGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "快捷命令"))
        pinGroup.addArrangedSubview(buttonRow(host: host,
            title: "编辑固定命令槽位（已固定 \(PinnedCommands62.pinnedIDs.count) 条）") { [weak host] in
            guard let host else { return }
            let editor = PinnedCommandsEditor62ViewController()
            editor.modalPresentationStyle = .pageSheet
            host.present(editor, animated: true)
        })
        pinGroup.addArrangedSubview(host.makeHairline())
        pinGroup.addArrangedSubview(host.makeHintRow(
            "固定槽位是命令面板顶部的置顶区：勾选的命令 id 保存在这里，命令面板打开时按此顺序置顶（面板侧消费）。"))
        stack.addArrangedSubview(pinGroup)
        reg(pinGroup, 7)

        let gestureGroup = host.makeGroupCard()
        gestureGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "手势与键盘"))
        gestureGroup.addArrangedSubview(switchRow(host: host, title: "手势快捷",
            isOn: SettingsStore.gestureShortcutsEnabled) {
            SettingsStore.gestureShortcutsEnabled = $0
            Breadcrumbs.log("settings62.gestureShortcuts=\($0)")
        })
        gestureGroup.addArrangedSubview(host.makeHairline())
        gestureGroup.addArrangedSubview(switchRow(host: host, title: "长按工具条打开命令面板",
            isOn: SettingsStore.longPressToolbarCommandPalette) {
            SettingsStore.longPressToolbarCommandPalette = $0
            Breadcrumbs.log("settings62.longPressToolbarPalette=\($0)")
        })
        gestureGroup.addArrangedSubview(host.makeHairline())
        gestureGroup.addArrangedSubview(segmentedRow(host: host, title: "向左滑动打开",
            items: ["命令面板", "速记簿", "搜索", "无"],
            selected: ["commandPalette", "sketchbook", "search", "none"]
                .firstIndex(of: SettingsStore.swipeLeftTarget) ?? 0) {
            SettingsStore.swipeLeftTarget = ["commandPalette", "sketchbook", "search", "none"][$0]
            Breadcrumbs.log("settings62.swipeLeftTarget=\(SettingsStore.swipeLeftTarget)")
        })
        gestureGroup.addArrangedSubview(host.makeHairline())
        gestureGroup.addArrangedSubview(switchRow(host: host, title: "海报墙 S 键打开命令窗口",
            isOn: SettingsStore.posterWallSHotkeyEnabled) {
            SettingsStore.posterWallSHotkeyEnabled = $0
            Breadcrumbs.log("settings62.posterWallSHotkey=\($0)")
        })
        gestureGroup.addArrangedSubview(host.makeHairline())
        gestureGroup.addArrangedSubview(host.makeHintRow(
            "iOS 无桌面键盘场景：「自定义快捷键」以手势快捷等价实现（左滑目标与长按工具条可绑动作如上）；S 键为外接键盘场景的真绑定（海报墙/主页墙接外接键盘时按 S 打开命令面板）。手势开关变更下次进墙生效。"))
        stack.addArrangedSubview(gestureGroup)
        reg(gestureGroup, 7)
    }

    // MARK: - 页签 8：连接与集成（§4.9 WB 两项）

    private static func buildConnectionsTab(host: SettingsViewController, into stack: UIStackView,
                                            reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("连接与集成·62B")

        let apiGroup = host.makeGroupCard()
        apiGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "歌词接口"))
        apiGroup.addArrangedSubview(textRow(host: host, title: "自定义歌词 API 基址",
            value: { SettingsStore.lyricAPIBaseURL },
            placeholder: "https://…（空 = 自有代理）",
            validate: { text in
                if text.isEmpty { return nil }
                return URL(string: text) == nil ? "不是合法 URL" : nil
            }) {
            SettingsStore.lyricAPIBaseURL = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.lyricAPIBase set=\(!$0.isEmpty)")
        })
        apiGroup.addArrangedSubview(host.makeHairline())
        apiGroup.addArrangedSubview(host.makeHintRow(
            "非空时取词先试该基址的 /lyric 兼容端点，失败自动回落自有 EdgeOne 代理并在日志标注；为空即现行行为。"))
        stack.addArrangedSubview(apiGroup)
        reg(apiGroup, 8)

        let stageGroup = host.makeGroupCard()
        stageGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "舞台模式"))
        stageGroup.addArrangedSubview(switchRow(host: host, title: "舞台模式（外部数据源）",
            isOn: SettingsStore.stageModeEnabled) {
            SettingsStore.stageModeEnabled = $0
            StageDataSource62.shared.restart()
            Breadcrumbs.log("settings62.stageMode=\($0)")
        })
        stageGroup.addArrangedSubview(host.makeHairline())
        stageGroup.addArrangedSubview(textRow(host: host, title: "舞台数据来源",
            value: { SettingsStore.stageDataSourceURL },
            placeholder: "https://…/stage.json",
            validate: { text in
                if text.isEmpty { return nil }
                return URL(string: text) == nil ? "不是合法 URL" : nil
            }) {
            SettingsStore.stageDataSourceURL = $0
            StageDataSource62.shared.restart()
            Breadcrumbs.log("settings62.stageDataSource set=\(!$0.isEmpty)")
        })
        stageGroup.addArrangedSubview(host.makeHairline())
        stageGroup.addArrangedSubview(host.makeHintRow(
            "开启后每 5 秒轮询数据来源，期望 JSON 形状 {title, artist, progress}，映射到舞台信息卡；无源或关闭时舞台行为不变。"))
        stack.addArrangedSubview(stageGroup)
        reg(stageGroup, 8)
    }
}

/// (62) WB §4.5：声音与设备面板——系统路由选择。iOS 的音频
/// 输出由系统接管，本面装 MPVolumeView 的路由钮呈现系统选
/// 择器，并如实标注平台接管范围。
final class AudioRoute62ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)
        let title = UILabel()
        title.text = "声音与设备"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        let volumeView = MPVolumeView()
        volumeView.showsRouteButton = true
        volumeView.showsVolumeSlider = true
        volumeView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(volumeView)
        let hint = UILabel()
        hint.text = "点右侧路由钮选择输出设备（扬声器 / 耳机 / AirPlay）。iOS 的输出路由由系统接管，应用内只能调起系统选择器，不能自建设备列表。"
        hint.font = .systemFont(ofSize: 12.5)
        hint.textColor = UIColor.white.withAlphaComponent(0.6)
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) },
                       for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(done)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            done.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            volumeView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 28),
            volumeView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            volumeView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            volumeView.heightAnchor.constraint(equalToConstant: 44),
            hint.topAnchor.constraint(equalTo: volumeView.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        Breadcrumbs.log("audio62.routePanel opened")
    }
}

/// (62) WB §4.8：固定命令槽位编辑面。命令全集 = 命令面板注
/// 册表的 11 个 id（与 CommandPaletteViewController
/// buildRegistry 同源清单，WC 簇文件）；勾选即写
/// PinnedCommands62，面板置顶区消费。
final class PinnedCommandsEditor62ViewController: UITableViewController {

    private let catalog: [(id: String, title: String)] = [
        ("playback.toggle", "播放 / 暂停"),
        ("playback.prev", "上一首"),
        ("playback.next", "下一首"),
        ("queue.shuffle", "打乱队列"),
        ("queue.open", "打开队列"),
        ("track.like", "喜欢"),
        ("track.star", "星标"),
        ("tool.sleep", "睡眠定时"),
        ("tool.visualizer", "选择可视化"),
        ("tool.volumeUp", "音量 +"),
        ("tool.volumeDown", "音量 −")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        title = "固定命令槽位"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "pin62")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        catalog.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "pin62", for: indexPath)
        let item = catalog[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.id
        cell.accessoryType = PinnedCommands62.isPinned(item.id) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        PinnedCommands62.toggle(catalog[indexPath.row].id)
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}
