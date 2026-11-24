import UIKit

/// (85) 第 1 条：世界缝共享等级（网页 bravaisSeamLevel 同
/// 式：全局一个等级、跨面沿用——主页折叠后进歌单，缝仍是
/// 折叠的）。手机档只有 spine（64 书脊）/ hidden 两级；
/// 歌单的展开档（300 完整条）是面内状态、不入本存储。
enum SeamState85 {
    static var levelHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "folia.seam85.hidden") }
        set { UserDefaults.standard.set(newValue, forKey: "folia.seam85.hidden") }
    }

    /// 网页 contentOpacityFor 同式：开口窄于排版宽时内容
    /// 随之淡出（开到 35% 以下不可见）。
    static func contentOpacity(rendered: CGFloat, content: CGFloat) -> CGFloat {
        max(0, min(1, (rendered / max(content, 1) - 0.35) / 0.65))
    }
}

/// 竖排文字（字间换行，与 (84) 侧栏/网页 writing-mode 同
/// 视觉语言）。
enum Seam85Text {
    static func vertical(_ text: String) -> String {
        text.map { String($0) }.joined(separator: "\n")
    }
}

/// 缝宿主侧边竖标签（网页 BRAVAIS_EDGE_TAB）：缝折叠或被
/// 平移挤出视口时出现在屏幕侧边，点它在当前视口重新裂开。
final class SeamEdgeTab85View: UIView {

    var onTap: (() -> Void)?

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.42)
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        label.text = Seam85Text.vertical("书库")
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        addGestureRecognizer(UITapGestureRecognizer(
            target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    @objc private func tapped() { onTap?() }
}

/// (85) 第 1 条：主页缝内容（书脊档 64，网页 BravaisSeam-
/// Home compact 同构成）：书库行 → 折叠钮 → 竖排页签
/// （歌单/电台/专辑/本地）→ 中段直达入口（我喜欢的音乐）
/// → 账户头像 → 底部工具格（搜索/设置／队列/⋯）。
/// 选中态两套（网页 fb3）：一级页签＝填色块；本面无二级
/// 切换（原生分区是独立面、经页签进入），中段直达入口
/// 是普通按钮形态、不冒充页签。
/// 命中纪律同 (84) 侧栏：hitTest 只认按钮本体，缝背景一
/// 律穿透——缝随墙走、不是拖动把手。
final class HomeSeam85View: UIView {

    var onFold: (() -> Void)?
    var onPlaylists: (() -> Void)?
    var onRadio: (() -> Void)?
    var onAlbums: (() -> Void)?
    var onLocal: (() -> Void)?
    var onLiked: (() -> Void)?
    var onAvatar: (() -> Void)?
    var onSearch: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQueue: (() -> Void)?
    var onMore: (() -> Void)?

    /// 内容纵向内边距（宿主按工具条/点播台占位设定）。
    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    /// 内容淡出（宿主按渲染开口逐帧喂，见 SeamState85）。
    var contentOpacity: CGFloat = 1 {
        didSet { contentView.alpha = contentOpacity }
    }

    private let contentView = UIView()
    private let libraryLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private var tabButtons: [UIButton] = []
    private let shortcutSeparator = UIView()
    private let likedButton = UIButton(type: .system)
    private let avatarButton = UIButton(type: .custom)
    private let avatarImageView = UIImageView()
    private let avatarInitialLabel = UILabel()
    private var avatarTask: URLSessionDataTask?
    private var toolButtons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        backgroundColor = UIColor.black.withAlphaComponent(0.34)
        let hairlineL = UIView()
        hairlineL.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        hairlineL.tag = 8501
        addSubview(hairlineL)
        let hairlineR = UIView()
        hairlineR.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        hairlineR.tag = 8502
        addSubview(hairlineR)
        contentView.isUserInteractionEnabled = true
        addSubview(contentView)

        libraryLabel.text = "书库"
        libraryLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        libraryLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        libraryLabel.textAlignment = .center
        contentView.addSubview(libraryLabel)

        foldButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        foldButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        foldButton.layer.cornerRadius = 14
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped), for: .touchUpInside)
        contentView.addSubview(foldButton)

        // 一级页签（竖排）：歌单默认选中（主页墙当前面即
        // 歌单集，与 (84) 侧栏去向表一致）。
        for (index, title) in ["歌单", "电台", "专辑", "本地"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(Seam85Text.vertical(title), for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            button.titleLabel?.textAlignment = .center
            button.layer.cornerRadius = 10
            button.accessibilityLabel = title
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            contentView.addSubview(button)
            tabButtons.append(button)
        }
        refreshTabSelection()

        shortcutSeparator.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        contentView.addSubview(shortcutSeparator)
        likedButton.setTitle(Seam85Text.vertical("我喜欢的音乐"), for: .normal)
        likedButton.titleLabel?.numberOfLines = 0
        likedButton.titleLabel?.font = .systemFont(ofSize: 11)
        likedButton.titleLabel?.textAlignment = .center
        likedButton.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
        likedButton.accessibilityLabel = "我喜欢的音乐"
        likedButton.addTarget(self, action: #selector(likedTapped), for: .touchUpInside)
        contentView.addSubview(likedButton)

        avatarButton.layer.cornerRadius = 16
        avatarButton.clipsToBounds = true
        avatarButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        avatarButton.accessibilityLabel = "定位正在播放"
        avatarButton.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarImageView)
        avatarInitialLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarInitialLabel.textColor = .white
        avatarInitialLabel.textAlignment = .center
        avatarInitialLabel.isUserInteractionEnabled = false
        avatarButton.addSubview(avatarInitialLabel)
        contentView.addSubview(avatarButton)
        setAccount85(nickname: nil, loggedIn: false, avatarURLString: nil)

        for (glyph, label, action) in [
            ("magnifyingglass", "搜索", #selector(searchTapped)),
            ("gearshape", "设置", #selector(settingsTapped)),
            ("list.bullet", "队列", #selector(queueTapped)),
            ("ellipsis", "更多", #selector(moreTapped)),
        ] as [(String, String, Selector)] {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: glyph), for: .normal)
            button.tintColor = UIColor.white.withAlphaComponent(0.88)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            button.layer.cornerRadius = 8
            button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside)
            contentView.addSubview(button)
            toolButtons.append(button)
        }
    }

    private func refreshTabSelection() {
        for (index, button) in tabButtons.enumerated() {
            let selected = index == 0
            button.backgroundColor = selected
                ? UIColor.white.withAlphaComponent(0.13) : .clear
            button.setTitleColor(selected
                ? .white : UIColor.white.withAlphaComponent(0.5), for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        viewWithTag(8501)?.frame = CGRect(x: 0, y: 0, width: 0.5, height: bounds.height)
        viewWithTag(8502)?.frame = CGRect(
            x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height)
        let contentW: CGFloat = 64
        let top = contentTopInset
        let bottom = bounds.height - contentBottomInset
        let contentH = max(0, bottom - top)
        contentView.frame = CGRect(
            x: (bounds.width - contentW) / 2, y: top, width: contentW, height: contentH)
        let cx = contentW / 2
        libraryLabel.frame = CGRect(x: 0, y: 0, width: contentW, height: 18)
        foldButton.frame = CGRect(x: cx - 14, y: 22, width: 28, height: 28)
        // 页签列：每签 54 高、间隔 6。
        var y: CGFloat = 58
        for button in tabButtons {
            button.frame = CGRect(x: 10, y: y, width: contentW - 20, height: 54)
            y += 60
        }
        let tabsBottom = y
        // 工具格（底，两行两列 28×28、间隔 4）。
        let toolsTop = contentH - 60
        for (index, button) in toolButtons.enumerated() {
            let col = CGFloat(index % 2), row = CGFloat(index / 2)
            button.frame = CGRect(
                x: cx - 30 + col * 32, y: toolsTop + row * 32, width: 28, height: 28)
        }
        // 账户位贴工具格正上方（网页 fb4）。
        avatarButton.frame = CGRect(x: cx - 16, y: toolsTop - 42, width: 32, height: 32)
        avatarImageView.frame = avatarButton.bounds
        avatarInitialLabel.frame = avatarButton.bounds
        // 中段：直达入口在页签与账户之间的剩余空间里靠下
        // 居中成组（分隔线＋竖排字，网页 fb11）。
        let midTop = tabsBottom + 8
        let midBottom = toolsTop - 50
        let likedH: CGFloat = 11 * 6 * 1.25 + 8
        let groupH = likedH + 14
        let groupY = midTop + max(0, (midBottom - midTop - groupH) / 2)
        shortcutSeparator.frame = CGRect(x: cx - 10, y: groupY, width: 20, height: 0.5)
        likedButton.frame = CGRect(
            x: cx - 14, y: groupY + 10, width: 28, height: likedH)
        likedButton.isHidden = midBottom - midTop < 60
        shortcutSeparator.isHidden = likedButton.isHidden
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 账户回显（与 HomeSidebar84View.setAccount84 同口径）

    func setAccount85(nickname: String?, loggedIn: Bool, avatarURLString: String?) {
        avatarTask?.cancel()
        avatarTask = nil
        if loggedIn, let nickname, !nickname.isEmpty {
            avatarInitialLabel.text = String(nickname.prefix(1))
            avatarButton.setImage(nil, for: .normal)
        } else {
            avatarInitialLabel.text = nil
            avatarButton.setImage(
                UIImage(systemName: "person.crop.circle"), for: .normal)
            avatarButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        }
        avatarImageView.image = nil
        avatarInitialLabel.isHidden = false
        guard loggedIn, let avatarURLString,
              let url = URL(string: avatarURLString) else { return }
        avatarTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.avatarImageView.image = image
                self?.avatarInitialLabel.isHidden = true
            }
        }
        avatarTask?.resume()
    }

    // MARK: 点按（逐项落痕 sidebar85）

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    @objc private func tabTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0:
            Breadcrumbs.log("sidebar85 tap dest=playlists")
            onPlaylists?()
        case 1:
            Breadcrumbs.log("sidebar85 tap dest=radio")
            onRadio?()
        case 2:
            Breadcrumbs.log("sidebar85 tap dest=albums")
            onAlbums?()
        default:
            Breadcrumbs.log("sidebar85 tap dest=local")
            onLocal?()
        }
    }

    @objc private func likedTapped() {
        Breadcrumbs.log("sidebar85 tap dest=liked")
        onLiked?()
    }

    @objc private func avatarTapped() {
        Breadcrumbs.log("sidebar85 tap dest=avatar")
        onAvatar?()
    }

    @objc private func searchTapped() {
        Breadcrumbs.log("sidebar85 tap dest=search")
        onSearch?()
    }

    @objc private func settingsTapped() {
        Breadcrumbs.log("sidebar85 tap dest=settings")
        onSettings?()
    }

    @objc private func queueTapped() {
        Breadcrumbs.log("sidebar85 tap dest=queue")
        onQueue?()
    }

    @objc private func moreTapped() {
        Breadcrumbs.log("sidebar85 tap dest=more")
        onMore?()
    }
}

/// (85) 第 1 条：歌单页缝（网页 BravaisSeamCollection 同
/// 骨架）：书脊档（64）＝返回 ‹ → 折叠 → 竖排歌单名（点
/// 它展开）→ 竖排计数 → 播放钮 → 展开钮；展开档（300）
/// ＝返回＋横排标题＋计数＋播放全部/加入队列＋收起。
/// 构成与主页缝不同（集合的身份与动作）、骨架同。
final class PlaylistSeam85View: UIView {

    var onBack: (() -> Void)?
    var onFold: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onAppendQueue: (() -> Void)?
    var onExpandChange: ((Bool) -> Void)?

    var contentTopInset: CGFloat = 108
    var contentBottomInset: CGFloat = 132
    var contentOpacity: CGFloat = 1 {
        didSet {
            spineContent.alpha = contentOpacity
            fullContent.alpha = contentOpacity
        }
    }

    private(set) var expanded = false
    private let spineContent = UIView()
    private let fullContent = UIView()
    private let backButton = UIButton(type: .system)
    private let foldButton = UIButton(type: .system)
    private let titleButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    // 展开档
    private let fullBackButton = UIButton(type: .system)
    private let fullTitleLabel = UILabel()
    private let fullMetaLabel = UILabel()
    private let fullPlayButton = UIButton(type: .system)
    private let fullAppendButton = UIButton(type: .system)
    private let fullFoldButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func build() {
        backgroundColor = UIColor.black.withAlphaComponent(0.34)
        let hairlineL = UIView()
        hairlineL.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        hairlineL.tag = 8501
        addSubview(hairlineL)
        let hairlineR = UIView()
        hairlineR.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        hairlineR.tag = 8502
        addSubview(hairlineR)
        addSubview(spineContent)
        addSubview(fullContent)
        fullContent.isHidden = true

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = "返回"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        spineContent.addSubview(backButton)
        foldButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        foldButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        foldButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        foldButton.layer.cornerRadius = 14
        foldButton.accessibilityLabel = "折叠"
        foldButton.addTarget(self, action: #selector(foldTapped), for: .touchUpInside)
        spineContent.addSubview(foldButton)
        titleButton.titleLabel?.numberOfLines = 0
        titleButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        titleButton.titleLabel?.textAlignment = .center
        titleButton.setTitleColor(.white, for: .normal)
        titleButton.accessibilityLabel = "展开信息条"
        titleButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        spineContent.addSubview(titleButton)
        countLabel.numberOfLines = 0
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        countLabel.textAlignment = .center
        spineContent.addSubview(countLabel)
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        playButton.layer.cornerRadius = 18
        playButton.accessibilityLabel = "播放全部"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        spineContent.addSubview(playButton)
        expandButton.setImage(
            UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expandButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        expandButton.accessibilityLabel = "展开信息条"
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        spineContent.addSubview(expandButton)

        fullBackButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        fullBackButton.tintColor = .white
        fullBackButton.accessibilityLabel = "返回"
        fullBackButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        fullContent.addSubview(fullBackButton)
        fullTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        fullTitleLabel.textColor = .white
        fullTitleLabel.numberOfLines = 2
        fullContent.addSubview(fullTitleLabel)
        fullMetaLabel.font = .systemFont(ofSize: 12)
        fullMetaLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        fullContent.addSubview(fullMetaLabel)
        for (button, title, glyph, action) in [
            (fullPlayButton, "播放全部", "play.fill", #selector(playTapped)),
            (fullAppendButton, "加入队列", "text.badge.plus", #selector(appendTapped)),
        ] as [(UIButton, String, String, Selector)] {
            button.setImage(UIImage(systemName: glyph), for: .normal)
            button.setTitle("  " + title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.tintColor = .white
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            button.layer.cornerRadius = 12
            button.contentHorizontalAlignment = .left
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 0)
            button.accessibilityLabel = title
            button.addTarget(self, action: action, for: .touchUpInside)
            fullContent.addSubview(button)
        }
        fullFoldButton.setTitle("收起", for: .normal)
        fullFoldButton.titleLabel?.font = .systemFont(ofSize: 13)
        fullFoldButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        fullFoldButton.accessibilityLabel = "收起信息条"
        fullFoldButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        fullContent.addSubview(fullFoldButton)
    }

    /// 数据回填（标题/计数）：宿主在种子落地与条目变化时调。
    func setPlaylist85(title: String, count: Int) {
        titleButton.setTitle(Seam85Text.vertical(title), for: .normal)
        countLabel.text = Seam85Text.vertical("\(count) 首")
        fullTitleLabel.text = title
        fullMetaLabel.text = "\(count) 首"
    }

    func setExpanded85(_ expanded: Bool) {
        self.expanded = expanded
        spineContent.isHidden = expanded
        fullContent.isHidden = !expanded
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        viewWithTag(8501)?.frame = CGRect(x: 0, y: 0, width: 0.5, height: bounds.height)
        viewWithTag(8502)?.frame = CGRect(
            x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height)
        let top = contentTopInset
        let contentH = max(0, bounds.height - contentTopInset - contentBottomInset)
        // 书脊内容（64 宽居中）。
        spineContent.frame = CGRect(
            x: (bounds.width - 64) / 2, y: top, width: 64, height: contentH)
        let cx: CGFloat = 32
        backButton.frame = CGRect(x: cx - 14, y: 0, width: 28, height: 28)
        foldButton.frame = CGRect(x: cx - 14, y: 34, width: 28, height: 28)
        // 播放钮/展开钮贴底（网页书脊几何 play 0.84/expand 0.905）。
        expandButton.frame = CGRect(x: cx - 14, y: contentH - 34, width: 28, height: 28)
        playButton.frame = CGRect(x: cx - 18, y: contentH - 82, width: 36, height: 36)
        // 竖排标题占中段上部、计数紧随其后。
        let titleTop: CGFloat = 74
        let titleH = max(60, contentH - 74 - 100 - 44)
        titleButton.frame = CGRect(x: 8, y: titleTop, width: 48, height: titleH)
        let countH: CGFloat = 44
        countLabel.frame = CGRect(
            x: 8, y: titleTop + titleH + 6, width: 48, height: countH)
        // 展开档内容（300 宽居中、左对齐排版）。
        fullContent.frame = CGRect(
            x: (bounds.width - 300) / 2, y: top, width: 300, height: contentH)
        fullBackButton.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        fullTitleLabel.frame = CGRect(x: 36, y: 2, width: 264, height: 44)
        fullMetaLabel.frame = CGRect(x: 36, y: 48, width: 264, height: 18)
        fullPlayButton.frame = CGRect(x: 16, y: 84, width: 268, height: 44)
        fullAppendButton.frame = CGRect(x: 16, y: 136, width: 268, height: 44)
        fullFoldButton.frame = CGRect(x: 16, y: 188, width: 60, height: 28)
    }

    // MARK: 命中纪律（只认按钮本体，其余穿透给墙面）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let view = node {
            if view is UIControl { return hit }
            if view === self { break }
            node = view.superview
        }
        return nil
    }

    // MARK: 点按（逐项落痕 sidebar85）

    @objc private func backTapped() {
        Breadcrumbs.log("sidebar85 tap dest=back")
        onBack?()
    }

    @objc private func foldTapped() {
        Breadcrumbs.log("sidebar85 tap dest=fold")
        onFold?()
    }

    @objc private func playTapped() {
        Breadcrumbs.log("sidebar85 tap dest=playall")
        onPlayAll?()
    }

    @objc private func appendTapped() {
        Breadcrumbs.log("sidebar85 tap dest=append")
        onAppendQueue?()
    }

    @objc private func expandTapped() {
        Breadcrumbs.log("sidebar85 tap dest=\(expanded ? "spine" : "expand")")
        onExpandChange?(!expanded)
    }
}
