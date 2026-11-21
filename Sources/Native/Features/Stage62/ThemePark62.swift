import UIKit

/// 主题乐园（(62) §4.1/§8 本体）：预设网格＋当前自动歌曲主题预览＋
/// 自定义三色（色板点选）＋应用/恢复默认。真可操作：点预设即经
/// ThemeSystem62.applyPreset 落盘并全应用刷新；自定义色点选色板
/// 后存为 custom 预设。
final class ThemeParkViewController: UIViewController {

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let songPreview = UIView()
    private let songPreviewLabel = UILabel()
    private var swatchButtons: [UIButton] = []

    private static let customPalette: [String] = [
        "#8B7CF0", "#4C8BF5", "#F58C40", "#66CC80", "#F27399",
        "#5EC8D8", "#F2C94C", "#EB5757", "#BB6BD9", "#F5F5F7",
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = ThemeSystem62.interfaceStyleOverride() == .unspecified
            ? .dark : ThemeSystem62.interfaceStyleOverride()
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        title = "主题乐园"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "恢复默认",
            primaryAction: UIAction { [weak self] _ in
                ThemeSystem62.resetToDefault()
                self?.rebuild()
            })
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        rebuild()
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = UIColor.white.withAlphaComponent(0.6)
        return l
    }

    private func rebuild() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        swatchButtons.removeAll()

        statusLabel.text = "当前生效：\(ThemeSystem62.currentSourceLabel)"
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 0
        stack.addArrangedSubview(statusLabel)

        // 当前自动歌曲主题预览
        stack.addArrangedSubview(sectionTitle("当前歌曲主题（自动生成）"))
        songPreview.layer.cornerRadius = 12
        songPreview.clipsToBounds = true
        songPreview.heightAnchor.constraint(equalToConstant: 64).isActive = true
        if let p = ThemeSystem62.songPalette {
            songPreview.backgroundColor = p.background
            songPreviewLabel.text = "主色 \(FoliaColorHex62.hex(from: p.accent)) · 辅色 \(FoliaColorHex62.hex(from: p.secondary))"
            songPreviewLabel.textColor = p.text
        } else {
            songPreview.backgroundColor = UIColor(white: 0.13, alpha: 1)
            songPreviewLabel.text = "暂无歌曲主题（播放带封面的歌曲后自动生成）"
            songPreviewLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        }
        songPreviewLabel.font = .systemFont(ofSize: 13)
        songPreviewLabel.frame = CGRect(x: 12, y: 22, width: 320, height: 20)
        songPreview.addSubview(songPreviewLabel)
        stack.addArrangedSubview(songPreview)
        let applySong = UIButton(type: .system)
        applySong.setTitle("应用歌曲主题（关闭优先自定义）", for: .normal)
        applySong.setTitleColor(ThemeSystem62.currentAccent, for: .normal)
        applySong.contentHorizontalAlignment = .leading
        applySong.addAction(UIAction { _ in
            SettingsStore.preferCustomTheme = false
            SettingsStore.songThemeAutoSwitch = true
            SettingsStore.songThemeAutoGenerate = true
            NotificationCenter.default.post(name: .foliaTheme62Changed, object: nil)
            Breadcrumbs.log("theme62.park applySongTheme")
        }, for: .touchUpInside)
        stack.addArrangedSubview(applySong)

        // 预设网格（两列）
        stack.addArrangedSubview(sectionTitle("配色预设"))
        let presets = ThemePreset62.all
        var row: UIStackView?
        for (i, preset) in presets.enumerated() {
            if i % 2 == 0 {
                row = UIStackView()
                row!.axis = .horizontal
                row!.spacing = 12
                row!.distribution = .fillEqually
                stack.addArrangedSubview(row!)
            }
            let card = UIButton(type: .system)
            card.backgroundColor = preset.background
            card.layer.cornerRadius = 12
            card.layer.borderWidth = SettingsStore.themePresetId == preset.id ? 2 : 0
            card.layer.borderColor = preset.accent.cgColor
            card.heightAnchor.constraint(equalToConstant: 64).isActive = true
            card.setTitle(preset.name, for: .normal)
            card.setTitleColor(.white, for: .normal)
            card.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            card.addAction(UIAction { [weak self] _ in
                ThemeSystem62.applyPreset(id: preset.id)
                self?.rebuild()
            }, for: .touchUpInside)
            row!.addArrangedSubview(card)
        }
        if presets.count % 2 == 1 { row?.addArrangedSubview(UIView()) }

        // 自定义三色：三行色板（主/辅/背景），点选即存 custom 并应用
        stack.addArrangedSubview(sectionTitle("自定义主题（点选色板）"))
        stack.addArrangedSubview(makeSwatchRow(title: "主色", current: SettingsStore.themeCustomAccentHex) { hex in
            SettingsStore.themeCustomAccentHex = hex
        })
        stack.addArrangedSubview(makeSwatchRow(title: "辅色", current: SettingsStore.themeCustomSecondaryHex) { hex in
            SettingsStore.themeCustomSecondaryHex = hex
        })
        stack.addArrangedSubview(makeSwatchRow(title: "背景调", current: SettingsStore.themeCustomBackgroundHex) { hex in
            SettingsStore.themeCustomBackgroundHex = hex
        })
        let applyCustom = UIButton(type: .system)
        applyCustom.setTitle("应用自定义主题", for: .normal)
        applyCustom.setTitleColor(ThemeSystem62.currentAccent, for: .normal)
        applyCustom.contentHorizontalAlignment = .leading
        applyCustom.addAction(UIAction { [weak self] _ in
            ThemeSystem62.applyPreset(id: "custom")
            self?.rebuild()
        }, for: .touchUpInside)
        stack.addArrangedSubview(applyCustom)
    }

    private func makeSwatchRow(title: String, current: String,
                               onPick: @escaping (String) -> Void) -> UIStackView {
        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.spacing = 8
        rowStack.alignment = .center
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        rowStack.addArrangedSubview(label)
        for hex in Self.customPalette {
            let b = UIButton(type: .system)
            b.backgroundColor = FoliaColorHex62.color(from: hex)
            b.layer.cornerRadius = 11
            b.layer.borderWidth = hex == current ? 2 : 0
            b.layer.borderColor = UIColor.white.cgColor
            b.widthAnchor.constraint(equalToConstant: 22).isActive = true
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
            b.addAction(UIAction { [weak self] _ in
                onPick(hex)
                ThemeSystem62.applyPreset(id: "custom")
                self?.rebuild()
            }, for: .touchUpInside)
            swatchButtons.append(b)
            rowStack.addArrangedSubview(b)
        }
        rowStack.addArrangedSubview(UIView())
        return rowStack
    }

    static func present(from host: UIViewController) {
        let nav = UINavigationController(rootViewController: ThemeParkViewController())
        nav.modalPresentationStyle = .pageSheet
        host.present(nav, animated: true)
        Breadcrumbs.log("theme62.park open")
    }
}

/// 样式工作台 VisPlayground（(62) §4.1/§8 本体）：样式列表＋实时
/// 预览区（真渲染器小舞台）＋调参面板入口一体。
/// 预览渲染器经 LyricStageRegistry 工厂装配；预览歌词＝当前播放
/// 行（有队列且歌词已缓存时经 LyricRepository 现取）＋内置示例行
/// 兜底；预览快照 palette 走当前主题/封面 palette 近似（中性＋
/// 当前主题 accent 覆写）。
final class VisPlaygroundViewController: UIViewController {

    private let listStack = UIStackView()
    private let previewContainer = UIView()
    private var renderer: LyricStageRenderer?
    private var selectedStyleId: String = StageStyleStore.currentStyleId
    private var previewLines: [LyricLine] = VisPlaygroundViewController.sampleLines
    private var context: LyricStageContext!

    static var sampleLines: [LyricLine] {
        let texts = ["示例歌词 · 预览行一", "VisPlayground sample line two",
                     "第三行示例 · 扫光与排版预览", "末行示例 · sample outro"]
        return texts.enumerated().map { i, text in
            LyricLine(id: i, start: Double(i) * 3.2, end: Double(i + 1) * 3.2,
                      text: text, words: nil)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        title = "样式工作台"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })

        previewContainer.backgroundColor = .black
        previewContainer.layer.cornerRadius = 12
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        listStack.axis = .vertical
        listStack.spacing = 6
        listStack.isLayoutMarginsRelativeArrangement = true
        listStack.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 16, right: 14)
        listStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(listStack)
        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            previewContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.38),
            scroll.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            listStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            listStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        context = LyricStageContext(
            sendCommand: { _ in },
            currentAnchor: {
                PlaybackAnchor(trackId: "visplayground", positionAtAnchor: 0,
                               wallTimeAtAnchor: CACurrentMediaTime(), rate: 0, anchorSeq: 0)
            })
        buildList()
        mountPreview(styleId: selectedStyleId)
        loadCurrentTrackLines()
        Breadcrumbs.log("visplayground.open style=\(selectedStyleId)")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        renderer?.view.frame = previewContainer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        renderer?.setLifecycle(.destroyed, active: false)
        renderer?.unmount()
        renderer = nil
    }

    private func buildList() {
        for v in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        for info in LyricStageRegistry.allStyles {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.alignment = .center
            let pick = UIButton(type: .system)
            pick.setTitle((info.id == selectedStyleId ? "● " : "○ ") + info.displayName,
                          for: .normal)
            pick.setTitleColor(info.isLocked ? UIColor.white.withAlphaComponent(0.35)
                               : .white, for: .normal)
            pick.titleLabel?.font = .systemFont(ofSize: 15,
                                                 weight: info.id == selectedStyleId ? .semibold : .regular)
            pick.contentHorizontalAlignment = .leading
            pick.isEnabled = !info.isLocked && info.factory != nil
            pick.addAction(UIAction { [weak self] _ in
                self?.selectedStyleId = info.id
                self?.buildList()
                self?.mountPreview(styleId: info.id)
            }, for: .touchUpInside)
            row.addArrangedSubview(pick)
            row.addArrangedSubview(UIView())
            if let tuningFactory = info.tuningPanelFactory, !info.isLocked {
                let tune = UIButton(type: .system)
                tune.setTitle("调参", for: .normal)
                tune.setTitleColor(ThemeSystem62.currentAccent, for: .normal)
                tune.addAction(UIAction { [weak self] _ in
                    self?.present(tuningFactory(), animated: true)
                }, for: .touchUpInside)
                row.addArrangedSubview(tune)
            }
            let apply = UIButton(type: .system)
            apply.setTitle("应用到舞台", for: .normal)
            apply.setTitleColor(ThemeSystem62.currentAccent, for: .normal)
            apply.isEnabled = !info.isLocked && info.factory != nil
            apply.addAction(UIAction { [weak self] _ in
                StageStyleStore.currentStyleId = info.id
                Breadcrumbs.log("visplayground.apply style=\(info.id)")
                self?.dismiss(animated: true)
            }, for: .touchUpInside)
            row.addArrangedSubview(apply)
            listStack.addArrangedSubview(row)
        }
    }

    private func mountPreview(styleId: String) {
        renderer?.setLifecycle(.destroyed, active: false)
        renderer?.unmount()
        renderer?.view.removeFromSuperview()
        renderer = nil
        guard let info = LyricStageRegistry.info(for: styleId),
              let factory = info.factory else { return }
        let next = factory()
        next.mount(context: context)
        previewContainer.addSubview(next.view)
        next.view.frame = previewContainer.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        renderer = next
        pushPreviewSnapshot()
        next.setLifecycle(.paused, active: true)
        Breadcrumbs.log("visplayground.preview style=\(styleId)")
    }

    private func pushPreviewSnapshot() {
        guard let renderer else { return }
        var palette = ThemeSystem62.songPalette ?? PaletteTokens.neutralDark
        palette.accent = ThemeSystem62.currentAccent
        let track = PlaybackEngine.shared.currentTrack
        let snapshot = LyricStageSnapshot(
            protocolVersion: LyricStageProtocolInfo.version,
            track: track.map { TrackMeta(track: $0) },
            lines: previewLines,
            palette: palette,
            styleId: selectedStyleId,
            styleVersion: LyricStageRegistry.info(for: selectedStyleId)?.styleVersion ?? 1,
            viewport: LyricStageViewport(size: previewContainer.bounds.size,
                                          safeAreaInsets: .zero,
                                          dynamicTypeScale: 1),
            anchor: PlaybackAnchor(trackId: track?.id ?? "visplayground",
                                   positionAtAnchor: 1.2,
                                   wallTimeAtAnchor: CACurrentMediaTime(),
                                   rate: 0, anchorSeq: 0),
            hostCapabilities: LyricStageProtocolInfo.hostCapabilities,
            ext: ["entry": "visplayground"])
        renderer.applySnapshot(snapshot)
    }

    /// 有当前曲目时用其真实歌词行替换示例行（仓库现取；失败保留示例）。
    private func loadCurrentTrackLines() {
        guard let track = PlaybackEngine.shared.currentTrack else { return }
        Task { [weak self] in
            let entry = await LyricRepository.shared.entry(for: track.id)
            let lines = LyricParser.stageLines(from: entry.lines,
                                               trackDuration: track.duration,
                                               singingRatio: entry.singingRatio)
            guard let self, !lines.isEmpty else { return }
            await MainActor.run {
                self.previewLines = lines
                self.pushPreviewSnapshot()
                Breadcrumbs.log("visplayground.lines src=current-track n=\(lines.count)")
            }
        }
    }

    static func present(from host: UIViewController) {
        let nav = UINavigationController(rootViewController: VisPlaygroundViewController())
        nav.modalPresentationStyle = .pageSheet
        host.present(nav, animated: true)
    }
}
