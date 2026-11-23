import UIKit

// 3.7 (62) WD 簇设置行（契约实现）：
//   enum Settings62ClusterD { static func build(host:into:reg:) }
// 基座 SettingsViewController.build62Tabs 已转调本入口。控件一律
// UIAction 闭包接线；组卡用 host.makeGroupCard() 等已去私有化工
// 厂；建组前 host.beginCheckGroup("<页签名>")。
//
// WD 在本簇只落两组行（其余 WD 面不在设置页）：
//  - tab 1 播放页：「每首歌随机歌词动画」开关（§6）
//  - tab 1 播放页：「舞台背景体系」模式选择 + 远程图地址（§6 背景）
// 键见 SettingsStore62D（Key62D）。
// (80) 第 3 项在本簇同组续落：「逐歌记忆特效」开关 + 「逐歌
// 记忆」计数/清除行，键见 SettingsStore80（Key80）。

enum Settings62ClusterD {

    private static let backdropModes: [(raw: String, title: String)] = [
        ("none", "样式自带"),
        ("common", "通用（光晕+几何）"),
        ("latentCover", "隐现 · 封面"),
        ("latentLyric", "隐现 · 歌词"),
        ("latentSpectrum", "隐现 · 频谱"),
        ("monet", "莫奈 wash"),
        ("nomand", "漫游（纸感）"),
        ("sora", "星空"),
        ("url", "远程图 URL"),
    ]

    static func build(host: SettingsViewController, into stack: UIStackView,
                      reg: (UIView, Int) -> Void) {
        host.beginCheckGroup("播放页·62D背景与随机")
        let group = host.makeGroupCard()

        // 每首歌随机歌词动画（§6）：切歌边沿从洗牌袋取下一式。
        let randomSwitch = UISwitch()
        randomSwitch.isOn = SettingsStore.randomPerSongEnabled62
        randomSwitch.addAction(UIAction { action in
            guard let sender = action.sender as? UISwitch else { return }
            SettingsStore.randomPerSongEnabled62 = sender.isOn
        }, for: .valueChanged)
        group.addArrangedSubview(switchRow(host: host,
            title: "每首歌随机歌词动画", toggle: randomSwitch))
        group.addArrangedSubview(host.makeHairline())
        group.addArrangedSubview(host.makeHintRow(
            "开启后每次切歌自动从洗牌袋（与舞台三击轮换同一袋）取下一只歌词样式，一轮内不重复。"))

        group.addArrangedSubview(host.makeHairline())

        // 逐歌记忆特效（3.7 (80) 第 3 项）：在一首歌里手动切
        // 过的样式按 trackId 记住、重播时自动套用；与每首歌
        // 随机同时开时记忆优先（RandomStylePerSong62 让行）。
        let memorySwitch = UISwitch()
        memorySwitch.isOn = SettingsStore.songStyleMemoryEnabled80
        memorySwitch.addAction(UIAction { action in
            guard let sender = action.sender as? UISwitch else { return }
            SettingsStore.songStyleMemoryEnabled80 = sender.isOn
        }, for: .valueChanged)
        group.addArrangedSubview(switchRow(host: host,
            title: "逐歌记忆特效", toggle: memorySwitch))
        group.addArrangedSubview(host.makeHairline())

        let memoryCountLabel = UILabel()
        memoryCountLabel.text = "已记 \(SongStyleMemory80.shared.count) 首"
        let clearMemoryButton = UIButton(type: .system)
        clearMemoryButton.setTitle("清除", for: .normal)
        clearMemoryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        clearMemoryButton.addAction(UIAction { [weak host] _ in
            guard let host else { return }
            presentClearMemoryConfirm(host: host, countLabel: memoryCountLabel)
        }, for: .touchUpInside)
        group.addArrangedSubview(labeledRow(host: host, title: "逐歌记忆",
                                            valueLabel: memoryCountLabel,
                                            button: clearMemoryButton))
        group.addArrangedSubview(host.makeHintRow(
            "在某首歌播放中手动切换的特效会被记住，这首歌再次播放时自动套用，下一首预备时连同预热。关闭开关只停记录与套用，存量保留；清除才删。"))

        group.addArrangedSubview(host.makeHairline())

        // 舞台背景体系（§6 背景）：模式选择走动作表（9 档放不进分段控）。
        let modeValueLabel = UILabel()
        modeValueLabel.text = backdropModes.first {
            $0.raw == SettingsStore.backdropMode62
        }?.title ?? "样式自带"
        let modeButton = UIButton(type: .system)
        modeButton.setTitle("更换", for: .normal)
        modeButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        modeButton.addAction(UIAction { [weak host] _ in
            guard let host else { return }
            presentModePicker(host: host, valueLabel: modeValueLabel)
        }, for: .touchUpInside)
        group.addArrangedSubview(labeledRow(host: host, title: "舞台背景",
                                            valueLabel: modeValueLabel,
                                            button: modeButton))
        group.addArrangedSubview(host.makeHairline())

        let urlButton = UIButton(type: .system)
        urlButton.setTitle("设置远程图地址", for: .normal)
        urlButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        urlButton.addAction(UIAction { [weak host] _ in
            guard let host else { return }
            presentURLEditor(host: host)
        }, for: .touchUpInside)
        let urlRow = UIStackView()
        urlRow.axis = .horizontal
        urlRow.alignment = .center
        urlRow.isLayoutMarginsRelativeArrangement = true
        urlRow.layoutMargins = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        urlRow.addArrangedSubview(urlButton)
        urlRow.addArrangedSubview(UIView())
        group.addArrangedSubview(urlRow)
        group.addArrangedSubview(host.makeHintRow(
            "背景在样式选择器的「背景」段也能改。已设置自定义背景（相册图片/动图/视频）时以自定义背景优先、本体系让位，清除自定义背景后恢复。远程图会先下载到本机缓存再显示，不走网页嵌入。"))

        stack.addArrangedSubview(group)
        reg(group, 1)
    }

    // MARK: - 行构造（UIAction 口径，不走宿主 Selector 工厂）

    private static func switchRow(host: SettingsViewController,
                                  title: String, toggle: UISwitch) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = .white
        host.track(label)
        toggle.onTintColor = UIColor(red: 0.30, green: 0.62, blue: 0.98, alpha: 1)
        toggle.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        row.addArrangedSubview(label)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(toggle)
        return row
    }

    private static func labeledRow(host: SettingsViewController, title: String,
                                   valueLabel: UILabel, button: UIButton) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = .white
        host.track(titleLabel)
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        valueLabel.textAlignment = .right
        host.track(valueLabel)
        if let buttonTitle = button.titleLabel { host.track(buttonTitle) }
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(button)
        return row
    }

    // MARK: - 选择/编辑呈现

    /// 清除逐歌记忆确认（3.7 (80)）：破坏性动作先确认，清除
    /// 后即时回写计数标签。
    private static func presentClearMemoryConfirm(host: SettingsViewController,
                                                  countLabel: UILabel) {
        let alert = UIAlertController(
            title: "清除逐歌记忆",
            message: "清掉全部 \(SongStyleMemory80.shared.count) 首的记忆样式？清除后各首歌回到跟随当前样式。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            SongStyleMemory80.shared.clearAll()
            countLabel.text = "已记 0 首"
        })
        host.present(alert, animated: true)
    }

    private static func presentModePicker(host: SettingsViewController,
                                          valueLabel: UILabel) {
        let sheet = UIAlertController(title: "舞台背景", message: nil,
                                      preferredStyle: .actionSheet)
        for mode in backdropModes {
            let isCurrent = SettingsStore.backdropMode62 == mode.raw
            sheet.addAction(UIAlertAction(
                title: isCurrent ? "✓ \(mode.title)" : mode.title,
                style: .default) { _ in
                    SettingsStore.backdropMode62 = mode.raw
                    valueLabel.text = mode.title
                    StageBackdrop62.modeDidChange()
                })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        host.present(sheet, animated: true)
    }

    private static func presentURLEditor(host: SettingsViewController) {
        let alert = UIAlertController(
            title: "远程图地址",
            message: "填图片直链地址；下载到本机缓存后作舞台背景显示。",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.text = SettingsStore.backdropRemoteURL62
            field.placeholder = "https://…"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let text = alert.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            SettingsStore.backdropRemoteURL62 = text
            if SettingsStore.backdropMode62 == "url" {
                StageBackdrop62.modeDidChange()
            }
            Breadcrumbs.log("settings62d.backdropURL saved len=\(text.count)")
        })
        host.present(alert, animated: true)
    }
}
