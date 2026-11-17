import UIKit

/// M1 阶段 3：单墙原型（队列墙几何 + 真实歌单数据）。入口：主界面
/// 设置齿轮长按（壳级调试入口，不影响正常使用）。只验证三件事：
/// 自由平移的帧率与手感、封面按档出图、点按展开的同块重排。
/// 不是正式表面：无播放焦点、无详情交接、无标题分区（探索墙的
/// lot 系统与 Bravais 的 rank 系统在阶段 4 各自接入）。
final class WallPrototypeViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {

    struct Entry {
        let id: String
        let title: String
        let picUrl: String?
        /// 副行（如歌单的「歌单 · 285」）；曲目墙不用。
        var subtitle: String? = nil
    }

    private let playlistId: String
    private var entries: [Entry] = []
    private let wallLayout = WallLayout()
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!
    private var didCenterCamera = false
    private var isWrapping = false

    init(playlistId: String = "19723756") {
        self.playlistId = playlistId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: wallLayout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.register(WallPosterCell.self, forCellWithReuseIdentifier: WallPosterCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        statusLabel = UILabel()
        statusLabel.text = "墙原型加载中…"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            statusLabel.heightAnchor.constraint(equalToConstant: 26)
        ])

        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        close.layer.cornerRadius = 13
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 56),
            close.heightAnchor.constraint(equalToConstant: 26)
        ])

        loadEntries()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - 数据

    private func loadEntries() {
        Task { [weak self] in
            guard let self else { return }
            do {
                // 3.7 (6) 渐进加载（真机问题：大歌单全量串行拉完才肯
                // 显示，338 首要等 4 个串行往返）：先取详情拿真实总数
                // 立刻立墙，曲目按页 3 路并发补入、每页落地就上墙。
                // 同时去掉原型期的 400 首上限：总数以详情为准，全量
                // 分页（正式的 id 骨架+按需补页模型在详情 MVP 落）。
                let detail = try await NativeDataClient.shared.fetchPlaylistDetail(id: playlistId)
                let total = detail.trackCount
                await MainActor.run {
                    self.wallLayout.totalEntries = total
                    self.statusLabel.text = "墙原型：共 \(total) 首 · 加载中 0"
                    self.wallLayout.refreshInstances()
                    self.collectionView.reloadData()
                    self.centerCameraIfNeeded()
                }
                let pageSize = 100
                var offset = 0
                while offset < total {
                    // 3 路并发取页；结果按 offset 收齐，只拼连续前缀：
                    // 中间页失败就在缺口处停下，下一轮从缺口重取，
                    // 绝不让序号错位。
                    let batchOffsets = Array(stride(from: offset, to: min(offset + pageSize * 3, total), by: pageSize))
                    var byOffset: [Int: [Entry]] = [:]
                    await withTaskGroup(of: (Int, [Entry]?).self) { group in
                        for pageOffset in batchOffsets {
                            group.addTask {
                                do {
                                    let tracks = try await NativeDataClient.shared.fetchPlaylistTracksPage(
                                        id: self.playlistId, limit: pageSize, offset: pageOffset)
                                    return (pageOffset, tracks.map {
                                        Entry(id: $0.id, title: $0.name, picUrl: $0.picUrl)
                                    })
                                } catch {
                                    return (pageOffset, nil)
                                }
                            }
                        }
                        for await (pageOffset, page) in group { byOffset[pageOffset] = page }
                    }
                    // 失败页不入表（字典赋 nil 即删键）：连续前缀在
                    // 失败页处自然停住，本轮不再前进（重进墙会重拉）。
                    var chunk: [Entry] = []
                    var reachedEnd = false
                    while let page = byOffset[offset] {
                        chunk.append(contentsOf: page)
                        offset += page.count
                        if page.count < pageSize { reachedEnd = true; break }
                    }
                    let progressed = !chunk.isEmpty
                    await MainActor.run {
                        self.entries.append(contentsOf: chunk)
                        self.statusLabel.text = reachedEnd || self.entries.count >= total
                            ? "墙原型：\(total) 首 · 拖动平移 · 点按展开"
                            : "墙原型：共 \(total) 首 · 加载中 \(self.entries.count)"
                        self.collectionView.reloadData()
                    }
                    if reachedEnd || !progressed { break }
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.text = "墙原型加载失败：\(error)"
                }
            }
        }
    }

    // MARK: - 相机

    static func cameraScale(forWidth width: CGFloat) -> Double {
        if width < 640 { return 0.52 }
        if width < 1100 { return 0.64 }
        return 0.76
    }

    private func centerCameraIfNeeded() {
        guard !didCenterCamera, wallLayout.totalEntries > 0 else { return }
        didCenterCamera = true
        wallLayout.cameraScale = Self.cameraScale(forWidth: collectionView.bounds.width)
        let cell = wallLayout.cellViewSize
        collectionView.contentOffset = CGPoint(x: cell.width, y: cell.height)
        wallLayout.invalidateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerCameraIfNeeded()
    }

    /// 相机增量折叠（3.7 (2) 修复）：3.7 (1) 的整格绕回模型有个致命
    /// 错误——属性帧 =（世界 − 原点）× scale + contentOffset，视觉位置
    /// = 帧 − offset 恒等于（世界 − 原点）× scale，与拖动无关：拖动时
    /// 画面纹丝不动，跨过绕回阈值才整格跳一次，真机录屏实证为 PPT。
    /// 改法：offset 恒钉在中心单元，任一滚动增量立即折进 worldOrigin
    /// 并把 offset 拉回中心——相机连续跟手，帧公式不变即成立。
    /// 实例集身份（首/尾 id + 计数）变了才 reloadData，否则只失效布局。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isWrapping, didCenterCamera else { return }
        let cell = wallLayout.cellViewSize
        guard cell.width > 0, cell.height > 0 else { return }
        let center = CGPoint(x: cell.width, y: cell.height)
        let delta = CGPoint(
            x: scrollView.contentOffset.x - center.x,
            y: scrollView.contentOffset.y - center.y)
        guard delta.x != 0 || delta.y != 0 else { return }
        isWrapping = true
        let before = setIdentity()
        wallLayout.worldOrigin = CGPoint(
            x: wallLayout.worldOrigin.x + delta.x / CGFloat(wallLayout.cameraScale),
            y: wallLayout.worldOrigin.y + delta.y / CGFloat(wallLayout.cameraScale))
        scrollView.contentOffset = center
        wallLayout.refreshInstances()
        if setIdentity() != before {
            collectionView.reloadData()
        }
        isWrapping = false
    }

    /// 实例集身份指纹：判断下标→实例的映射是否还成立。
    private func setIdentity() -> String {
        let list = wallLayout.instances
        return "\(list.first?.instanceId ?? "-")/\(list.last?.instanceId ?? "-")/\(list.count)"
    }

    // MARK: - 数据源

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        wallLayout.instances.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WallPosterCell.reuseId, for: indexPath) as! WallPosterCell
        let instance = wallLayout.instances[indexPath.item]
        // 渐进加载期：该序号的曲目可能还没补到，先给空占位（深灰砖），
        // 页落地 reloadData 后自然填上。
        guard instance.queueIndex < entries.count else {
            cell.configure(entry: Entry(id: "", title: "", picUrl: nil), tier: 512)
            return cell
        }
        let entry = entries[instance.queueIndex]
        let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
        let tier = entry.picUrl.map { NativeCoverLoader.wallTier(raw: $0, pixelExtent: pixelExtent) }
            ?? NativeCoverLoader.tier(forPixelExtent: pixelExtent)
        cell.configure(entry: entry, tier: tier)
        return cell
    }

    // MARK: - 预取（拖动闪黑对策：图先进内存缓存，cell 出现时同步上图）

    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard indexPath.item < wallLayout.instances.count else { continue }
            let instance = wallLayout.instances[indexPath.item]
            guard instance.queueIndex < entries.count else { continue }
            let entry = entries[instance.queueIndex]
            guard let pic = entry.picUrl else { continue }
            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
            let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
            let tier = NativeCoverLoader.wallTier(raw: pic, pixelExtent: pixelExtent)
            guard let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else { continue }
            if NativeCoverLoader.shared.cachedImage(for: urlString) != nil { continue }
            Task { _ = await NativeCoverLoader.shared.image(for: urlString, tier: tier) }
        }
    }

    // MARK: - 点按展开

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let instance = wallLayout.instances[indexPath.item]
        let before = setIdentity()
        // 3.7 (3)：不再跳切相机居中（那是生硬感主源）——原地弹簧重排：
        // 被点卡在原地长大、同块卡让位，镜头不动。
        if wallLayout.expandedInstanceId == instance.instanceId {
            wallLayout.expandedInstanceId = nil
        } else {
            wallLayout.expandedInstanceId = instance.instanceId
        }
        wallLayout.refreshInstances()
        if setIdentity() == before {
            let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.86) {
                self.wallLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }
            animator.startAnimation()
        } else {
            collectionView.reloadData()
        }
    }
}

/// 墙海报 cell：封面 + 底部标题。圆角用图层裁切、阴影用 shadowPath
/// 挂在外层容器（规格 §4：禁止默认离屏渲染路径）。
final class WallPosterCell: UICollectionViewCell {

    static let reuseId = "WallPosterCell"

    private let shadowView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var loadTask: Task<Void, Never>?
    private var currentUrl: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.35
        shadowView.layer.shadowRadius = 6
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 2)
        contentView.addSubview(shadowView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        // 未出图占位用深灰而非近黑：拖动中未加载的卡读作灰砖，不读作黑洞。
        imageView.backgroundColor = UIColor(white: 0.13, alpha: 1)
        shadowView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.8
        titleLabel.layer.shadowRadius = 2
        titleLabel.layer.shadowOffset = .zero
        shadowView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        subtitleLabel.numberOfLines = 1
        subtitleLabel.layer.shadowColor = UIColor.black.cgColor
        subtitleLabel.layer.shadowOpacity = 0.8
        subtitleLabel.layer.shadowRadius = 2
        subtitleLabel.layer.shadowOffset = .zero
        shadowView.addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowView.frame = contentView.bounds
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: contentView.bounds, cornerRadius: 8).cgPath
        imageView.frame = shadowView.bounds
        let labelHeight: CGFloat = 16
        let hasSubtitle = !(subtitleLabel.text ?? "").isEmpty
        let titleY = shadowView.bounds.height - labelHeight - 4 - (hasSubtitle ? 13 : 0)
        titleLabel.frame = CGRect(
            x: 6, y: titleY,
            width: shadowView.bounds.width - 12, height: labelHeight)
        subtitleLabel.frame = CGRect(
            x: 6, y: shadowView.bounds.height - 15,
            width: shadowView.bounds.width - 12, height: 12)
        subtitleLabel.isHidden = !hasSubtitle
    }

    /// 按压反馈：轻微缩放（原生点击手感的最低成本件）。
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    func configure(entry: WallPrototypeViewController.Entry, tier: Int) {
        titleLabel.text = entry.title
        subtitleLabel.text = entry.subtitle
        setNeedsLayout()
        loadTask?.cancel()
        guard let pic = entry.picUrl,
              let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else {
            currentUrl = nil
            imageView.image = nil
            return
        }
        currentUrl = urlString
        // 缓存命中同步上图：reloadData/复用重建时不先清空、不异步等一帧，
        // 这是拖动闪黑的主修复。
        if let cached = NativeCoverLoader.shared.cachedImage(for: urlString) {
            imageView.image = cached
            return
        }
        imageView.image = nil
        loadTask = Task { [weak self] in
            let image = await NativeCoverLoader.shared.image(for: urlString, tier: tier)
            guard let self else { return }
            await MainActor.run {
                guard self.currentUrl == urlString else { return }
                self.imageView.image = image
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentUrl = nil
        imageView.image = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
    }
}
