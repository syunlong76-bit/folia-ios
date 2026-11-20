import UIKit

// 字幕调节面板（3.7 (55) 工作流 D）：网页版 SubtitleSettingsSurfaceView
// 的原生承接。入口 = 舞台点播台「字幕」钮发出的
// Notification.Name("FoliaMiniBarSubtitle")（工作流 C 定名），由
// StageViewController 订阅后 present 本面板（pageSheet）。
//
// 每一项都直连 SubtitleSettingsStore 并即时被 SubtitleOverlayView
// 消费（消费点逐项写在各行注释与 Store/Overlay 头注）：改任一项，
// 舞台底部字幕层当场变化，不需要重开舞台。面板自身订阅
// SubtitleSettingsStore.changedNotification 回显最新值（命令面板等
// 其他入口改了设置时面板不显示旧值）。
//
// 数据缺口如实标注（面板底部说明行）：译文/罗马音行在原生歌词数据
// 里没有字段（LyricLine / LyricLineData 均无），选了也不会显示，
// 本面板不造假数据；布局与副字幕内容的选项仍按网页全集提供。
final class SubtitleSettingsPanelViewController: UIViewController {

    static func present(from presenter: UIViewController) {
        let panel = SubtitleSettingsPanelViewController()
        panel.modalPresentationStyle = .pageSheet
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        Breadcrumbs.log("stage.subtitle.panel open")
        presenter.present(panel, animated: true)
    }

    private let store = SubtitleSettingsStore.shared
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let hiddenSwitch = UISwitch()
    private let rowCountSegment = UISegmentedControl(items: ["1 行", "2 行", "3 行"])
    private var rowSourceSegments: [UISegmentedControl] = []
    private var rowContainers: [UIView] = []
    private let previewSwitch = UISwitch()
    private let opacitySlider = UISlider()
    private let opacityValueLabel = UILabel()
    private let backgroundSwitch = UISwitch()
    private let blurSwitch = UISwitch()
    private let scaleSlider = UISlider()
    private let scaleValueLabel = UILabel()
    private let contentModeSegment = UISegmentedControl(
        items: SubtitleContentMode.allCases.map { $0.displayName })
    /// 隐藏开关打开时整组布局/外观行禁用（网页 Reveal 同语义）。
    private var gatedControls: [UIControl] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildViews()
        refreshFromStore()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: SubtitleSettingsStore.changedNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 搭建

    private func buildViews() {
        let titleLabel = UILabel()
        titleLabel.text = "字幕调节"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        // 隐藏底部字幕层（网页 hidePlayerTranslationSubtitle）。
        hiddenSwitch.addTarget(self, action: #selector(hiddenToggled), for: .valueChanged)
        stack.addArrangedSubview(makeRow(
            title: "隐藏底部字幕层", note: "关掉后舞台底部不再显示字幕",
            control: hiddenSwitch))

        // 字幕行数（布局行数 1–3）。
        rowCountSegment.addTarget(self, action: #selector(rowCountChanged), for: .valueChanged)
        stack.addArrangedSubview(makeRow(
            title: "字幕行数", note: nil, control: rowCountSegment))
        gatedControls.append(rowCountSegment)

        // 各行内容：第 1 行可选 当前句/译文/罗马音；第 2、3 行可选
        // 下一句/译文/罗马音（网页 SubtitleOverlayRowsSetting 同集）。
        let rowTitles = ["第一行", "第二行", "第三行"]
        for index in 0..<3 {
            let options = index == 0
                ? SubtitleRowSource.singleRowOptions : SubtitleRowSource.followRowOptions
            let segment = UISegmentedControl(items: options.map { $0.displayName })
            segment.tag = index
            segment.addTarget(self, action: #selector(rowSourceChanged(_:)), for: .valueChanged)
            rowSourceSegments.append(segment)
            let row = makeRow(title: rowTitles[index], note: nil, control: segment)
            rowContainers.append(row)
            stack.addArrangedSubview(row)
            gatedControls.append(segment)
        }

        // 预览后续歌词（布局行无内容时改显后续句；网页 |only 的反面）。
        previewSwitch.addTarget(self, action: #selector(previewToggled), for: .valueChanged)
        stack.addArrangedSubview(makeRow(
            title: "预览后续歌词",
            note: "当前行在所选行里没内容时，先显示后面的歌词",
            control: previewSwitch))
        gatedControls.append(previewSwitch)

        // 字幕透明度（0.2–1，步进 0.05，网页同范围同歩进）。
        opacitySlider.minimumValue = 0.2
        opacitySlider.maximumValue = 1
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        opacityValueLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        stack.addArrangedSubview(makeSliderRow(
            title: "字幕透明度", slider: opacitySlider, valueLabel: opacityValueLabel))
        gatedControls.append(opacitySlider)

        // 字幕背景（辉光底）。
        backgroundSwitch.addTarget(self, action: #selector(backgroundToggled), for: .valueChanged)
        stack.addArrangedSubview(makeRow(
            title: "字幕背景", note: "字幕后加一层暗色辉光垫底",
            control: backgroundSwitch))
        gatedControls.append(backgroundSwitch)

        // 下二句模糊（后续预览行模糊；原生为近似呈现，见 Overlay 头注）。
        blurSwitch.addTarget(self, action: #selector(blurToggled), for: .valueChanged)
        stack.addArrangedSubview(makeRow(
            title: "后续歌词模糊", note: "预览的后续歌词行虚化呈现",
            control: blurSwitch))
        gatedControls.append(blurSwitch)

        // 字幕缩放（0.85–1.4，步进 0.05，网页同范围同歩进）。
        scaleSlider.minimumValue = 0.85
        scaleSlider.maximumValue = 1.4
        scaleSlider.addTarget(self, action: #selector(scaleChanged), for: .valueChanged)
        scaleValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        scaleValueLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        stack.addArrangedSubview(makeSliderRow(
            title: "字幕缩放", slider: scaleSlider, valueLabel: scaleValueLabel))
        gatedControls.append(scaleSlider)

        // 副字幕内容（译文/罗马音/两者/无）。
        contentModeSegment.addTarget(self, action: #selector(contentModeChanged), for: .valueChanged)
        stack.addArrangedSubview(makeRow(
            title: "副字幕内容", note: "布局里译文/罗马音行显示哪种副文本",
            control: contentModeSegment))
        gatedControls.append(contentModeSegment)

        // 数据缺口说明（如实标注，不造假数据）。
        let gapNote = UILabel()
        gapNote.text = "说明：原生歌词数据暂无译文/罗马音字段，布局或副字幕选到译文/罗马音时对应行不会显示；当前句与下一句可正常显示。数据补齐后自动生效。"
        gapNote.font = .systemFont(ofSize: 12)
        gapNote.textColor = UIColor.white.withAlphaComponent(0.5)
        gapNote.numberOfLines = 0
        stack.addArrangedSubview(gapNote)
    }

    private func makeRow(title: String, note: String?,
                         control: UIControl) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        var constraints: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            container.heightAnchor.constraint(equalToConstant: note == nil ? 48 : 56),
        ]
        if let note {
            let noteLabel = UILabel()
            noteLabel.text = note
            noteLabel.font = .systemFont(ofSize: 11)
            noteLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            noteLabel.numberOfLines = 1
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(noteLabel)
            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                noteLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            ])
        } else {
            constraints.append(
                titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func makeSliderRow(title: String, slider: UISlider,
                               valueLabel: UILabel) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 44),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - 回显

    @objc private func storeChanged() {
        refreshFromStore()
    }

    private func refreshFromStore() {
        hiddenSwitch.isOn = store.isHidden
        rowCountSegment.selectedSegmentIndex = store.rowCount - 1
        for (index, segment) in rowSourceSegments.enumerated() {
            let container = rowContainers[index]
            container.isHidden = index >= store.rowCount
            guard index < store.rowCount else { continue }
            let options = index == 0
                ? SubtitleRowSource.singleRowOptions : SubtitleRowSource.followRowOptions
            if let optionIndex = options.firstIndex(of: store.rows[index]) {
                segment.selectedSegmentIndex = optionIndex
            }
        }
        previewSwitch.isOn = store.previewsUpcoming
        opacitySlider.value = Float(store.opacity)
        opacityValueLabel.text = "\(Int((store.opacity * 100).rounded()))%"
        backgroundSwitch.isOn = store.hasBackground
        blurSwitch.isOn = store.blurUpcoming
        scaleSlider.value = Float(store.fontScale)
        scaleValueLabel.text = "\(Int((store.fontScale * 100).rounded()))%"
        if let modeIndex = SubtitleContentMode.allCases.firstIndex(of: store.contentMode) {
            contentModeSegment.selectedSegmentIndex = modeIndex
        }
        for control in gatedControls {
            control.isEnabled = !store.isHidden
            control.alpha = store.isHidden ? 0.4 : 1
        }
    }

    // MARK: - 动作（全部直写 Store，字幕层订阅即时消费）

    @objc private func hiddenToggled() {
        store.isHidden = hiddenSwitch.isOn
        Breadcrumbs.log("stage.subtitle.panel hidden=\(hiddenSwitch.isOn)")
    }

    @objc private func rowCountChanged() {
        store.setRowCount(rowCountSegment.selectedSegmentIndex + 1)
        Breadcrumbs.log("stage.subtitle.panel rowCount=\(rowCountSegment.selectedSegmentIndex + 1)")
    }

    @objc private func rowSourceChanged(_ segment: UISegmentedControl) {
        let options = segment.tag == 0
            ? SubtitleRowSource.singleRowOptions : SubtitleRowSource.followRowOptions
        guard options.indices.contains(segment.selectedSegmentIndex) else { return }
        store.setRow(at: segment.tag, source: options[segment.selectedSegmentIndex])
        Breadcrumbs.log("stage.subtitle.panel row\(segment.tag)="
            + "\(options[segment.selectedSegmentIndex].rawValue)")
    }

    @objc private func previewToggled() {
        store.setPreviewsUpcoming(previewSwitch.isOn)
        Breadcrumbs.log("stage.subtitle.panel preview=\(previewSwitch.isOn)")
    }

    @objc private func opacityChanged() {
        // 步进 0.05（网页同歩进）：吸附到最近档再写 Store。
        let stepped = (Double(opacitySlider.value) / 0.05).rounded() * 0.05
        store.opacity = stepped
        opacityValueLabel.text = "\(Int((stepped * 100).rounded()))%"
    }

    @objc private func backgroundToggled() {
        store.hasBackground = backgroundSwitch.isOn
        Breadcrumbs.log("stage.subtitle.panel background=\(backgroundSwitch.isOn)")
    }

    @objc private func blurToggled() {
        store.blurUpcoming = blurSwitch.isOn
        Breadcrumbs.log("stage.subtitle.panel blur=\(blurSwitch.isOn)")
    }

    @objc private func scaleChanged() {
        let stepped = (Double(scaleSlider.value) / 0.05).rounded() * 0.05
        store.fontScale = stepped
        scaleValueLabel.text = "\(Int((stepped * 100).rounded()))%"
    }

    @objc private func contentModeChanged() {
        guard SubtitleContentMode.allCases.indices.contains(
            contentModeSegment.selectedSegmentIndex) else { return }
        store.contentMode = SubtitleContentMode.allCases[
            contentModeSegment.selectedSegmentIndex]
        Breadcrumbs.log("stage.subtitle.panel contentMode=\(store.contentMode.rawValue)")
    }
}
