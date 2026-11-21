import UIKit

// 群唱 cappella 调参存储与面板（3.7 (57) 工作流 C2）：
// 网页版 folia-major/src/components/visualizer/cappella/
// tuning.ts、src/types.ts 的 CappellaTuning /
// DEFAULT_CAPPELLA_TUNING 与 settingsPanels.tsx 的
// CappellaSettingsPanel 的原生承接。UserDefaults 键前缀
// "folia.tuning.cappella."；缺省与回退逐字对齐网页
// resolveStoredCappellaTuning：avatarSource 取值集
// cover/builtin/color/custom、不认识回缺省 cover；
// emojiPackSource 只有 'custom' 保 custom、余皆 builtin；
// showEmoMessages 布尔直取、缺省 true。
// 数据缺口（如实标注，不假装生效）：网页内置头像包
// （avatar/ 15 图）与表情包（emo/ 9 图）、用户自传图包
// 均不在原生包内且协议无图片下发通道——avatarSource 的
// builtin/custom 两档与 emojiPackSource 当前只存不用，
// 渲染回退到 cover（有封面时）/ color 宫格形态；表情
// 消息因图片池为空恒不生成（网页池为空时 showEmoMessages
// 同样被 buildCappellaMessages 压为 false，口径一致）。
// 渲染器（CappellaStageRenderer）只经本门面读参，逐帧读
// 走 0.25s 缓存（照 StageEffectSettings 先例）。

/// 头像来源（网页 CappellaAvatarSource）。
enum CappellaAvatarSource: String, CaseIterable {
    case cover
    case builtin
    case color
    case custom

    var displayName: String {
        switch self {
        case .cover: return "封面"
        case .builtin: return "内置"
        case .color: return "纯色"
        case .custom: return "自传"
        }
    }
}

/// 表情包来源（网页 CappellaEmojiPackSource）。
enum CappellaEmojiPackSource: String, CaseIterable {
    case builtin
    case custom

    var displayName: String {
        switch self {
        case .builtin: return "内置"
        case .custom: return "自传"
        }
    }
}

/// 一次读全的参数快照（渲染器消费的形状）。
struct CappellaTuningValues: Equatable {
    var showEmoMessages: Bool = true
    var emojiPackSource: CappellaEmojiPackSource = .builtin
    var avatarSource: CappellaAvatarSource = .cover

    static let defaults = CappellaTuningValues()
}

/// 群唱调参存储门面：网页 tuning.ts 每个参数一个属性。
enum CappellaTuningStore {

    private static let prefix = "folia.tuning.cappella."
    private static func key(_ name: String) -> String { prefix + name }
    private static var defaults: UserDefaults { .standard }

    /// 显示表情消息，缺省 true（网页 DEFAULT_CAPPELLA_TUNING）。
    static var showEmoMessages: Bool {
        get { defaults.object(forKey: key("showEmoMessages")) as? Bool ?? true }
        set { defaults.set(newValue, forKey: key("showEmoMessages")) }
    }

    /// 表情包来源：存值 'custom' 才为 custom，余皆 builtin
    /// （网页 resolveStoredCappellaTuning 同义）。
    static var emojiPackSource: CappellaEmojiPackSource {
        get {
            defaults.string(forKey: key("emojiPackSource")) == "custom"
                ? .custom : .builtin
        }
        set { defaults.set(newValue.rawValue, forKey: key("emojiPackSource")) }
    }

    /// 头像来源：取值集外一律回缺省 cover（网页 avatarSource()
    /// 校验同义；网页另有「custom 无图包时面板禁用」的门，
    /// 原生无图包通道，面板以注记明示、存值照常保存）。
    static var avatarSource: CappellaAvatarSource {
        get {
            defaults.string(forKey: key("avatarSource"))
                .flatMap { CappellaAvatarSource(rawValue: $0) } ?? .cover
        }
        set { defaults.set(newValue.rawValue, forKey: key("avatarSource")) }
    }

    /// 一次读全。
    static func values() -> CappellaTuningValues {
        CappellaTuningValues(showEmoMessages: showEmoMessages,
                             emojiPackSource: emojiPackSource,
                             avatarSource: avatarSource)
    }

    /// 写回全量（恢复默认用）。
    static func apply(_ values: CappellaTuningValues) {
        showEmoMessages = values.showEmoMessages
        emojiPackSource = values.emojiPackSource
        avatarSource = values.avatarSource
        cachedValues = nil
        cachedAt = -1
    }

    /// 恢复网页缺省。
    static func resetAll() { apply(.defaults) }

    // MARK: 逐帧读的缓存面（0.25s，照 StageEffectSettings 先例）

    private static var cachedValues: CappellaTuningValues?
    private static var cachedAt: CFTimeInterval = -1

    static func valuesCached(now: CFTimeInterval) -> CappellaTuningValues {
        if cachedAt < 0 || now - cachedAt > 0.25 || cachedValues == nil {
            cachedValues = values()
            cachedAt = now
        }
        return cachedValues ?? .defaults
    }
}

/// 群唱调参面板入口（协调者接线点名形状）。
enum CappellaTuning {
    static func makePanel() -> UIViewController {
        CappellaTuningPanelViewController()
    }
}

// MARK: - 调参面板

/// 群唱调参面板：网页 CappellaSettingsPanel 的原生承接。
/// 控件集与网页对应：头像来源四档分段（网页 Segmented）、
/// 表情消息开关（网页 Toggle）、表情包来源二档分段（网页
/// 在开关打开时 Reveal 展开，原生以隐藏行承接）；网页的
/// 图片导入/清空与预览格依赖图包资产通道，原生无此通道，
/// 以注记明示缺口、不摆假按钮。拨动即写 CappellaTuning-
/// Store，渲染器经 0.25s 缓存生效。系统风格：
/// systemBackground / label 语义色适配深色，字号 ≥12pt。
final class CappellaTuningPanelViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var avatarSegment: UISegmentedControl?
    private var emoSwitch: UISwitch?
    private var emoSourceSegment: UISegmentedControl?
    private var emoSourceRow: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "群唱参数"
        view.backgroundColor = .systemBackground
        buildViews()
        refreshFromStore()
    }

    private func buildViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        let avatar = UISegmentedControl(
            items: CappellaAvatarSource.allCases.map { $0.displayName })
        avatar.addTarget(self, action: #selector(avatarChanged), for: .valueChanged)
        avatarSegment = avatar
        stack.addArrangedSubview(makeRow(title: "头像来源", control: avatar))

        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(emoSwitchChanged(_:)), for: .valueChanged)
        emoSwitch = toggle
        stack.addArrangedSubview(makeRow(title: "表情消息", control: toggle))

        let emoSource = UISegmentedControl(
            items: CappellaEmojiPackSource.allCases.map { $0.displayName })
        emoSource.addTarget(self, action: #selector(emoSourceChanged), for: .valueChanged)
        emoSourceSegment = emoSource
        let sourceRow = makeRow(title: "表情包来源", control: emoSource)
        emoSourceRow = sourceRow
        stack.addArrangedSubview(sourceRow)

        let reset = UIButton(type: .system)
        reset.setTitle("恢复默认", for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        reset.backgroundColor = .secondarySystemBackground
        reset.layer.cornerRadius = 8
        reset.heightAnchor.constraint(equalToConstant: 40).isActive = true
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)

        let note = UILabel()
        note.text = "说明：内置/自传头像包与表情图片包尚未进入原生包，当前头像按「封面」宫格裁切或「纯色」宫格渐变呈现；表情消息因图片池为空暂不出现（与网页无图包时的行为一致）。相关设置已保存，图包接入后即生效。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)
    }

    private func makeRow(title: String, control: UIControl) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])
        return container
    }

    private func refreshFromStore() {
        let values = CappellaTuningStore.values()
        if let index = CappellaAvatarSource.allCases.firstIndex(of: values.avatarSource) {
            avatarSegment?.selectedSegmentIndex = index
        }
        emoSwitch?.isOn = values.showEmoMessages
        if let index = CappellaEmojiPackSource.allCases.firstIndex(of: values.emojiPackSource) {
            emoSourceSegment?.selectedSegmentIndex = index
        }
        emoSourceRow?.isHidden = !values.showEmoMessages
    }

    @objc private func avatarChanged() {
        guard let segment = avatarSegment,
              CappellaAvatarSource.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        CappellaTuningStore.avatarSource =
            CappellaAvatarSource.allCases[segment.selectedSegmentIndex]
    }

    @objc private func emoSwitchChanged(_ toggle: UISwitch) {
        CappellaTuningStore.showEmoMessages = toggle.isOn
        emoSourceRow?.isHidden = !toggle.isOn
    }

    @objc private func emoSourceChanged() {
        guard let segment = emoSourceSegment,
              CappellaEmojiPackSource.allCases.indices.contains(segment.selectedSegmentIndex)
        else { return }
        CappellaTuningStore.emojiPackSource =
            CappellaEmojiPackSource.allCases[segment.selectedSegmentIndex]
    }

    @objc private func resetTapped() {
        CappellaTuningStore.resetAll()
        refreshFromStore()
    }
}
