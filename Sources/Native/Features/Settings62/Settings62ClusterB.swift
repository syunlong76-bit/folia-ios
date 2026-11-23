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
        row.addArrangedSubview(host.makeSectionHeader(FoliaLanguage62.rowTitle(title)))
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
        label.text = FoliaLanguage62.rowTitle(title)
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
        label.text = FoliaLanguage62.rowTitle(title)
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
        label.text = FoliaLanguage62.rowTitle(title)
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
        label.text = FoliaLanguage62.rowTitle(title)
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
    //
    // (66) 对齐网页版 GraphicsPage：性能（静态/动态背景/毛玻璃/
    // 帧率/抗锯齿/触摸光效/后台节流）→ 减少动态（细分六项）。
    // 歌词画布分辨率与「跟随系统」在宿主老面图形卡（归整后居
    // 本签末尾，同属性能/减少动态两组语义）。

    private static func buildMotionTab(host: SettingsViewController, into stack: UIStackView,
                                       reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("动画与性能·62B")

        let perfGroup = host.makeGroupCard()
        perfGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "性能"))
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
        perfGroup.addArrangedSubview(switchRow(host: host, title: "播放页触摸光效",
            isOn: SettingsStore.touchGlowEnabled) {
            SettingsStore.touchGlowEnabled = $0
            Breadcrumbs.log("settings62.touchGlow=\($0)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(sliderRow(host: host, title: "触摸光效密度",
            min: 0, max: 1, value: Float(SettingsStore.touchGlowDensity),
            format: { "\(Int(($0 * 100).rounded()))%" }) {
            SettingsStore.touchGlowDensity = Double($0)
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(segmentedRow(host: host, title: "后台节流",
            items: ["标准", "积极"],
            selected: SettingsStore.backgroundThrottlePolicy == "aggressive" ? 1 : 0) {
            SettingsStore.backgroundThrottlePolicy = $0 == 1 ? "aggressive" : "standard"
            Breadcrumbs.log("settings62.backgroundThrottle=\(SettingsStore.backgroundThrottlePolicy)")
        })
        perfGroup.addArrangedSubview(host.makeHairline())
        perfGroup.addArrangedSubview(host.makeHintRow(
            "静态模式开启后舞台逐帧动画与墙面动效停住（进度与播放不受影响）。帧率限制对进度驱动即时生效，舞台帧率由舞台侧同键消费。抗锯齿为全局口径，逐样式覆盖经 LyricCanvas62 统一解析（(66)）。后台节流「积极」时进后台即停进度驱动等逐帧链，且 OBS 客户端在场时媒体缓存自动回填推迟（BackgroundThrottle62）；iOS 后台任务调度本身由系统接管。触摸光效在舞台触摸点泛光，密度决定并发光晕与粒子数。"))
        stack.addArrangedSubview(perfGroup)
        reg(perfGroup, 3)

        let reduceGroup = host.makeGroupCard()
        reduceGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "减少动态"))
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
            // (66) 即时生效：切换当场重应用滚动减速率，
            // 不再等下次打开设置页（原一次性口径已改）。
            applySettingsScrollBehavior(host: host)
        })
        reduceGroup.addArrangedSubview(host.makeHairline())
        reduceGroup.addArrangedSubview(host.makeHintRow(
            "门控口径：宿主卡「降低动态 · 跟随系统」开启时全局跟随系统减弱动态效果、本组细分不参与；关掉跟随后改由本组逐项判定（FoliaMotion62 统一判定面）。「设置页平滑滚动」切换即时生效（(66)）。"))
        stack.addArrangedSubview(reduceGroup)
        reg(reduceGroup, 3)
    }

    /// 设置页平滑滚动消费：按 FoliaMotion62 判定设宿主滚动
    /// 视图减速率——降低动态命中时用系统普通减速（无平滑惯
    /// 性加工），未命中时用快速减速保持跟手。(66) 起除构建
    /// 时应用外，「设置页平滑滚动」开关切换当场重应用。
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
    //
    // (66) 对齐网页版 PlaybackPage：过渡（启用/模式/最长时长/
    // 激进表现/曲线/过渡动画双开关）→ 声音（输出设备/ReplayGain/
    // 淡入淡出/DSD/自动转换/休眠/语音暂停）；播放行为组（自动
    // 跳过/队列默认位置）在宿主老面控制卡，归整后居本签末尾。

    private static func buildPlaybackTab(host: SettingsViewController, into stack: UIStackView,
                                         reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("播放控制·62B")

        let transitionGroup = host.makeGroupCard()
        transitionGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "过渡"))
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
        // (66) 过渡表现模式·激进表现（网页同名开关做实）：
        // 消费 PlaybackEngine 的触发窗/时长上限/中段增益。
        transitionGroup.addArrangedSubview(switchRow(host: host, title: "过渡表现 · 激进表现",
            isOn: SettingsStore.transitionAggressive62) {
            SettingsStore.transitionAggressive62 = $0
            Breadcrumbs.log("settings66.transitionAggressive=\($0 ? 1 : 0)")
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
        // (66) 过渡动画改双开关（网页为容器动画＋卡片描边两
        // 个独立 bool）：消费 TransitionAnim62.playCurrent，
        // 两者可同时触发；旧三值键保留为导出镜像。
        transitionGroup.addArrangedSubview(switchRow(host: host, title: "过渡动画 · 屏幕圆环",
            isOn: SettingsStore.transitionAnimRing62) {
            SettingsStore.transitionAnimRing62 = $0
            Breadcrumbs.log("settings66.transitionAnimRing=\($0 ? 1 : 0)")
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(switchRow(host: host, title: "过渡动画 · 卡片描边",
            isOn: SettingsStore.transitionAnimCard62) {
            SettingsStore.transitionAnimCard62 = $0
            Breadcrumbs.log("settings66.transitionAnimCard=\($0 ? 1 : 0)")
        })
        transitionGroup.addArrangedSubview(host.makeHairline())
        transitionGroup.addArrangedSubview(host.makeHintRow(
            "下一首会在当前曲尾段预载到 B 轨并按曲线混音切入；Automix 按下一首前奏提前量对齐（无能量数据时以固定提前量近似，日志有标注），失败自动回退硬切。激进表现开时过渡窗口与时长上限放大（×1.5）、双轨中段增益抬升。「降低动态 · 混音过渡」开启时过渡动画层停用、只保留音频斜坡。"))
        stack.addArrangedSubview(transitionGroup)
        reg(transitionGroup, 4)

        let soundGroup = host.makeGroupCard()
        soundGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "声音"))
        soundGroup.addArrangedSubview(buttonRow(host: host, title: "声音与设备（音频输出）") { [weak host] in
            guard let host else { return }
            let panel = AudioRoute62ViewController()
            panel.modalPresentationStyle = .pageSheet
            host.present(panel, animated: true)
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        soundGroup.addArrangedSubview(switchRow(host: host, title: "ReplayGain",
            isOn: SettingsStore.replayGainEnabled) {
            SettingsStore.replayGainEnabled = $0
            PlaybackEngine.shared.refreshReplayGain()
            Breadcrumbs.log("settings62.replayGain=\($0)")
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        soundGroup.addArrangedSubview(segmentedRow(host: host, title: "暂停 / 播放淡入淡出",
            items: ["无", "100ms", "200ms", "400ms"],
            selected: [0, 100, 200, 400].firstIndex(of: SettingsStore.playPauseFadeMs) ?? 2) {
            SettingsStore.playPauseFadeMs = [0, 100, 200, 400][$0]
            Breadcrumbs.log("settings62.playPauseFadeMs=\(SettingsStore.playPauseFadeMs)")
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        // (66) DSD 以 DoP 输出（DS 改判「有条件」落地）：消费
        // DSDPlayback62——本地 .dsf 播放时做能力检测，满足
        // （外接输出＋176.4kHz）走 DoP 封装，不满足明示降级。
        soundGroup.addArrangedSubview(switchRow(host: host, title: "DSD 以 DoP 输出",
            isOn: SettingsStore.dsdDopEnabled62) {
            SettingsStore.dsdDopEnabled62 = $0
            Breadcrumbs.log("settings66.dsdDop=\($0 ? 1 : 0) \(DSDPlayback62.capabilitySummary)")
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        soundGroup.addArrangedSubview(switchRow(host: host, title: "自动转换无法播放的音频",
            isOn: SettingsStore.autoTranscodeEnabled) {
            SettingsStore.autoTranscodeEnabled = $0
            Breadcrumbs.log("settings62.autoTranscode=\($0)")
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        soundGroup.addArrangedSubview(switchRow(host: host, title: "播放时阻止休眠",
            isOn: SettingsStore.preventSleepWhilePlaying) {
            SettingsStore.preventSleepWhilePlaying = $0
            PlaybackEngine.shared.refreshIdleTimerGate()
            Breadcrumbs.log("settings62.preventSleep=\($0)")
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        soundGroup.addArrangedSubview(switchRow(host: host, title: "语音输入时暂停",
            isOn: SettingsStore.pauseOnVoiceInput) {
            SettingsStore.pauseOnVoiceInput = $0
            Breadcrumbs.log("settings62.pauseOnVoiceInput=\($0)")
        })
        soundGroup.addArrangedSubview(host.makeHairline())
        soundGroup.addArrangedSubview(host.makeHintRow(
            "ReplayGain 在引擎音量链上乘增益系数：优先用音量平衡学习到的逐曲偏移，其次曲目元数据增益，都没有时为 1.0（不改音量）。淡入淡出作用于播放与暂停的音量斜坡。DSD DoP：仅本地 DSD 文件；当前输出条件（\(DSDPlayback62.capabilitySummary)）——不满足时以普通 PCM 转换播放并在日志明示，不假装 DoP。自动转换只对已落盘的本地/缓存音频可行（转 m4a 后播放）；流媒体不可播仍走自动跳过逻辑，服务端转码链不在本机能力内。音频输出路由由 iOS 系统接管，本组首行打开系统路由选择。阻止休眠为播放期间保持屏幕常亮。语音输入时暂停监听音频会话中断（Siri 等），中断后不自动恢复。"))
        stack.addArrangedSubview(soundGroup)
        reg(soundGroup, 4)
    }

    // MARK: - 页签 5：歌词（§4.6）
    //
    // (66) 对齐网页版 LyricsPage：歌词来源（自动最佳/匹配优先/
    // 保留逐字/本地优先）→ 歌词调整（过滤：规则卡＋署名块；
    // 全局偏移在宿主老面歌词卡）→ 自动 AI 分词 → 本地歌词格式。

    private static func buildLyricsTab(host: SettingsViewController, into stack: UIStackView,
                                       reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("歌词·62B")

        let strategyGroup = host.makeGroupCard()
        strategyGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "歌词来源"))
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
        strategyGroup.addArrangedSubview(segmentedRow(host: host, title: "本地歌曲歌词优先级",
            items: ["平台优先", "本地优先"],
            selected: SettingsStore.localLyricPriority == "localFirst" ? 1 : 0) {
            SettingsStore.localLyricPriority = $0 == 1 ? "localFirst" : "platformFirst"
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.localLyricPriority=\(SettingsStore.localLyricPriority)")
        })
        strategyGroup.addArrangedSubview(host.makeHairline())
        strategyGroup.addArrangedSubview(host.makeHintRow(
            "策略变更会清歌词缓存，下次播放按新策略重新取词。关掉「保留逐字」后合并结果丢弃逐字戳、退回行级扫光。本地歌词经本地曲库注册的歌词源钩子查询。"))
        stack.addArrangedSubview(strategyGroup)
        reg(strategyGroup, 5)

        // (66) 歌词调整组：过滤规则卡＋开头署名块处理（网页
        // LyricFilterSettingsModal 的逐项落地，消费
        // LyricFilter62.process66 全管线）。
        let filterGroup = host.makeGroupCard()
        filterGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "歌词调整 · 过滤"))
        filterGroup.addArrangedSubview(textRow(host: host, title: "歌词过滤（正则）",
            value: { SettingsStore.lyricFilterRegex },
            placeholder: "如 ^(作词|作曲)",
            validate: { LyricFilter62.validate($0) }) {
            SettingsStore.lyricFilterRegex = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings62.lyricFilter set len=\($0.count)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(switchRow(host: host, title: "过滤规则 · 预置词表",
            isOn: SettingsStore.lyricFilterPresetWords62) {
            SettingsStore.lyricFilterPresetWords62 = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings66.filterPreset=\($0 ? 1 : 0)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(switchRow(host: host, title: "过滤规则 · 冒号形态",
            isOn: SettingsStore.lyricFilterColonForm62) {
            SettingsStore.lyricFilterColonForm62 = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings66.filterColon=\($0 ? 1 : 0)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(switchRow(host: host, title: "过滤规则 · 只作用于开头段",
            isOn: SettingsStore.lyricFilterOpeningOnly62) {
            SettingsStore.lyricFilterOpeningOnly62 = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings66.filterOpeningOnly=\($0 ? 1 : 0)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "开头署名块"))
        filterGroup.addArrangedSubview(segmentedRow(host: host, title: "署名块处理",
            items: ["保留", "删除", "合并成一行"],
            selected: ["keep", "remove", "merge"]
                .firstIndex(of: SettingsStore.lyricCreditsMode62) ?? 0) {
            SettingsStore.lyricCreditsMode62 = ["keep", "remove", "merge"][$0]
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings66.creditsMode=\(SettingsStore.lyricCreditsMode62)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(sliderRow(host: host, title: "署名块最少停留",
            min: 0, max: 10, value: Float(SettingsStore.lyricCreditsMinStay62),
            format: { "\(Int($0.rounded())) 秒" }) {
            SettingsStore.lyricCreditsMinStay62 = Double($0)
            LyricRepository.shared.clearAll()
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(switchRow(host: host, title: "署名块吸收相邻空行",
            isOn: SettingsStore.lyricCreditsAbsorb62) {
            SettingsStore.lyricCreditsAbsorb62 = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings66.creditsAbsorb=\($0 ? 1 : 0)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(textRow(host: host, title: "署名块自定义识别（正则）",
            value: { SettingsStore.lyricCreditsCustom62 },
            placeholder: "命中行视为署名行",
            validate: { LyricFilter62.validate($0) }) {
            SettingsStore.lyricCreditsCustom62 = $0
            LyricRepository.shared.clearAll()
            Breadcrumbs.log("settings66.creditsCustom set len=\($0.count)")
        })
        filterGroup.addArrangedSubview(host.makeHairline())
        filterGroup.addArrangedSubview(host.makeHintRow(
            "规则卡与署名块在歌词出口全管线执行（仓库与舞台同口径）：预置词表认行首制作人员词、冒号形态认「短词：内容」行；署名块指开头连续署名行，删除/合并只处理停留不短于设定值的行。改动会清歌词缓存重新取词。全局歌词偏移在本签宿主卡（逐词强调/粒子换行同卡）。"))
        stack.addArrangedSubview(filterGroup)
        reg(filterGroup, 5)

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

        let formatGroup = host.makeGroupCard()
        formatGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "本地歌词格式"))
        formatGroup.addArrangedSubview(textRow(host: host, title: "本地歌词格式顺序",
            value: { SettingsStore.localLyricFormatOrder },
            placeholder: "lrc,yrc,txt",
            validate: { $0.isEmpty ? "不能为空" : nil }) {
            SettingsStore.localLyricFormatOrder = $0
            Breadcrumbs.log("settings62.localLyricFormatOrder=\($0)")
        })
        formatGroup.addArrangedSubview(host.makeHairline())
        formatGroup.addArrangedSubview(host.makeHintRow(
            "本地曲库按此顺序探每首歌的同名歌词文件，命中即用（本地优先开关在歌词来源组）。"))
        stack.addArrangedSubview(formatGroup)
        reg(formatGroup, 5)
    }

    // MARK: - 页签 6：通用（§4.7 余项）
    //
    // (66) 对齐网页版 GeneralPage：语言 → 启动（启动续播在宿
    // 主老面通用卡）→ 思索。更新组三项按附录 A 口径不迁。

    private static func buildGeneralTab(host: SettingsViewController, into stack: UIStackView,
                                        reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("通用·62B")

        let languageGroup = host.makeGroupCard()
        languageGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "语言"))
        languageGroup.addArrangedSubview(segmentedRow(host: host, title: "界面语言",
            items: ["跟随系统", "简体中文", "繁體中文", "English", "Tiếng Việt"],
            selected: ["system", "zh-Hans", "zh-TW", "en", "vi"]
                .firstIndex(of: SettingsStore.appLanguage) ?? 1) {
            SettingsStore.appLanguage = ["system", "zh-Hans", "zh-TW", "en", "vi"][$0]
            Breadcrumbs.log("settings62.appLanguage=\(SettingsStore.appLanguage)")
        })
        languageGroup.addArrangedSubview(host.makeHairline())
        languageGroup.addArrangedSubview(host.makeHintRow(
            "语言经 FoliaLanguage62 文案表消费：设置行标题已全量入表（(66)），English 时设置面行标题与页签标题切换；繁體/越南语暂无完整译表，未覆盖文案回退简体中文、不冒充全量。变更在重新打开设置后全量生效。"))
        stack.addArrangedSubview(languageGroup)
        reg(languageGroup, 6)

        let launchGroup = host.makeGroupCard()
        launchGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "启动"))
        launchGroup.addArrangedSubview(switchRow(host: host, title: "启动后直接进入播放界面",
            isOn: SettingsStore.openPlayerOnLaunch) {
            SettingsStore.openPlayerOnLaunch = $0
            Breadcrumbs.log("settings62.openPlayerOnLaunch=\($0)")
        })
        launchGroup.addArrangedSubview(host.makeHairline())
        launchGroup.addArrangedSubview(host.makeHintRow(
            "直接进入播放界面在入场动画播完或关闭后才直达舞台，不抢入场；无可播放队列时不直达。启动续播自动播放在本签宿主卡。"))
        stack.addArrangedSubview(launchGroup)
        reg(launchGroup, 6)

        let ponderGroup = host.makeGroupCard()
        ponderGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "思索"))
        ponderGroup.addArrangedSubview(switchRow(host: host, title: "思索教程提示",
            isOn: SettingsStore.ponderTipsEnabled) {
            SettingsStore.ponderTipsEnabled = $0
            Breadcrumbs.log("settings62.ponderTips=\($0)")
        })
        ponderGroup.addArrangedSubview(host.makeHairline())
        ponderGroup.addArrangedSubview(buttonRow(host: host, title: "打开导播台（教程列表）") { [weak host] in
            guard let host else { return }
            Ponder62.presentList(from: host)
        })
        ponderGroup.addArrangedSubview(host.makeHairline())
        ponderGroup.addArrangedSubview(host.makeHintRow(
            "教程提示在功能面首次使用时出现一次，读过不再弹（列表里可重置已读）。导播台入口在工作台顶部控制台底行（灯泡「导播台」），点开即分章教程列表。（73 起原左上角独立浮灯泡撤除、收进控制台；旧「触屏思索按钮」开关已无对应物，一并下线。）"))
        stack.addArrangedSubview(ponderGroup)
        reg(ponderGroup, 6)
    }

    // MARK: - 页签 7：快捷操作（§4.8）
    //
    // (66) 对齐网页版 InteractionPage：命令面板（固定槽位＋
    // 自定义快捷键）→ 网格动作（手势与键盘）。自定义快捷键
    // 为 (66) 做实项：外接键盘 UIKeyCommand 真绑定（消费在
    // HomeWall/WallPrototype 的 keyCommands）。

    private static func buildShortcutsTab(host: SettingsViewController, into stack: UIStackView,
                                          reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("快捷操作·62B")

        let pinGroup = host.makeGroupCard()
        pinGroup.addArrangedSubview(sectionHeaderRow(host: host, title: "命令面板"))
        pinGroup.addArrangedSubview(buttonRow(host: host,
            title: "编辑固定命令槽位（已固定 \(PinnedCommands62.pinnedIDs.count) 条）") { [weak host] in
            guard let host else { return }
            let editor = PinnedCommandsEditor62ViewController()
            editor.modalPresentationStyle = .pageSheet
            host.present(editor, animated: true)
        })
        pinGroup.addArrangedSubview(host.makeHairline())
        // (66) 自定义快捷键：字母（A–Z 单字母，外接键盘）＋
        // 命令（目录同固定槽位 11 条）。网页为 Alt＋字母，
        // iOS UIKeyCommand 无 Alt 语义、以裸字母键绑定并在
        // 发现菜单标注，长按工具条/左滑为触屏等价面。
        pinGroup.addArrangedSubview(textRow(host: host, title: "自定义快捷键 · 字母",
            value: { SettingsStore.customKeyLetter62 },
            placeholder: "如 K（空 = 未设置）",
            validate: { text in
                let t = text.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { return nil }
                return (t.count == 1 && t.first?.isLetter == true) ? nil : "填单个字母"
            }) {
            SettingsStore.customKeyLetter62 = $0
            Breadcrumbs.log("settings66.customKey letter=\(SettingsStore.customKeyLetter62)")
        })
        pinGroup.addArrangedSubview(host.makeHairline())
        // (66) 命令目录与命令面板注册表同源（PinnedCommands62
        // .customKeyCatalog66，只列墙面有直接执行通路者）；
        // 11 条放不进分段控件，改系统动作表点选（iOS 原生）。
        let commandCatalog = PinnedCommands62.customKeyCatalog66
        let currentTitle = commandCatalog
            .first { $0.id == SettingsStore.customKeyCommand62 }?.title ?? "打开播放面板"
        pinGroup.addArrangedSubview(buttonRow(host: host,
            title: "自定义快捷键 · 命令：\(currentTitle)") {
            let sheet = UIAlertController(title: "自定义快捷键 · 命令",
                                          message: "选择按下字母键时执行的命令",
                                          preferredStyle: .actionSheet)
            for entry in commandCatalog {
                sheet.addAction(UIAlertAction(title: entry.title, style: .default) { _ in
                    SettingsStore.customKeyCommand62 = entry.id
                    Breadcrumbs.log("settings66.customKey command=\(entry.id)")
                    NativePlaybackFailureToast.show(message: "已绑定：\(entry.title)（重进设置页刷新显示）")
                })
            }
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
            host.present(sheet, animated: true)
        })
        pinGroup.addArrangedSubview(host.makeHairline())
        pinGroup.addArrangedSubview(host.makeHintRow(
            "固定槽位是命令面板顶部的置顶区：勾选的命令 id 保存在这里，命令面板打开时按此顺序置顶（面板侧消费）。自定义快捷键在主页墙接外接键盘时生效：按下所设字母即执行所选命令（与 S 键同通路）；字母与 S 重复时 S 键优先。"))
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
            "S 键与自定义快捷键均为外接键盘场景的真绑定（海报墙/主页墙接外接键盘时生效）；触屏场景以手势快捷等价（左滑目标与长按工具条可绑动作如上）。手势开关变更下次进墙生效。"))
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
        // (66) 本机歌词接口（网页同名能力）：LocalServer
        // /v1/lyric 开放开关，外部程序读当前曲歌词 JSON。
        apiGroup.addArrangedSubview(switchRow(host: host, title: "开放本机歌词接口（/v1/lyric）",
            isOn: SettingsStore.lyricAPIEnabled62) {
            SettingsStore.lyricAPIEnabled62 = $0
            Breadcrumbs.log("settings66.lyricAPI=\($0 ? 1 : 0)")
        })
        apiGroup.addArrangedSubview(host.makeHairline())
        apiGroup.addArrangedSubview(host.makeHintRow(
            "非空时取词先试该基址的 /lyric 兼容端点，失败自动回落自有 EdgeOne 代理并在日志标注；为空即现行行为。本机歌词接口开启后，本机程序可经 http://127.0.0.1:18765/v1/lyric 读当前曲歌词 JSON（仅回环、无鉴权，关时接口返回未开放明示）。"))
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
