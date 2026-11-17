import UIKit

/// M1 阶段 3：单墙原型（队列墙几何 + 真实歌单数据）。入口：主界面
/// 设置齿轮长按（壳级调试入口，不影响正常使用）。只验证三件事：
/// 自由平移的帧率与手感、封面按档出图、点按展开的同块重排。
/// 不是正式表面：无播放焦点、无详情交接、无标题分区（探索墙的
/// lot 系统与 Bravais 的 rank 系统在阶段 4 各自接入）。
final class WallPrototypeViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate {

    struct Entry {
        let id: String
        let title: String
        let picUrl: String?
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
                let tracks = try await NativeDataClient.shared.fetchPlaylistTracksPage(
                    id: playlistId, limit: 400, offset: 0)
                let loaded = tracks.map { Entry(id: $0.id, title: $0.name, picUrl: $0.picUrl) }
                await MainActor.run {
                    self.entries = loaded
                    self.wallLayout.totalEntries = loaded.count
                    self.statusLabel.text = "墙原型：\(loaded.count) 首 · 拖动平移 · 点按展开"
                    self.wallLayout.refreshInstances()
                    self.collectionView.reloadData()
                    self.centerCameraIfNeeded()
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

    /// 绕回（WallLayout 相机模型）：offset 偏出中心单元时成对调整
    /// offset 与 worldOrigin，视觉位置不变（周期平铺的拷贝接棒）。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isWrapping, didCenterCamera else { return }
        let cell = wallLayout.cellViewSize
        guard cell.width > 0, cell.height > 0 else { return }
        var offset = scrollView.contentOffset
        var origin = wallLayout.worldOrigin
        var changed = false
        if offset.x < cell.width * 0.5 {
            offset.x += cell.width
            origin.x -= CGFloat(wallLayout.geometry.cellWidth)
            changed = true
        } else if offset.x > cell.width * 1.5 {
            offset.x -= cell.width
            origin.x += CGFloat(wallLayout.geometry.cellWidth)
            changed = true
        }
        if offset.y < cell.height * 0.5 {
            offset.y += cell.height
            origin.y -= CGFloat(wallLayout.geometry.cellHeight)
            changed = true
        } else if offset.y > cell.height * 1.5 {
            offset.y -= cell.height
            origin.y += CGFloat(wallLayout.geometry.cellHeight)
            changed = true
        }
        if changed {
            isWrapping = true
            wallLayout.worldOrigin = origin
            scrollView.contentOffset = offset
            // 实例集随窗口换了一批：刷新集并同步数据源计数。
            wallLayout.refreshInstances()
            collectionView.reloadData()
            isWrapping = false
        }
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
        let entry = entries[instance.queueIndex]
        let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        let pixelExtent = Double(max(frame.width, frame.height)) * Double(UIScreen.main.scale)
        let tier = NativeCoverLoader.tier(forPixelExtent: pixelExtent)
        cell.configure(entry: entry, tier: tier)
        return cell
    }

    // MARK: - 点按展开

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let instance = wallLayout.instances[indexPath.item]
        if wallLayout.expandedInstanceId == instance.instanceId {
            wallLayout.expandedInstanceId = nil
        } else {
            wallLayout.expandedInstanceId = instance.instanceId
            // 相机飞到该卡居中：只改 worldOrigin（视觉公式与 offset 相消）。
            let viewSize = collectionView.bounds.size
            let centerX = instance.rect.x + instance.rect.width / 2
            let centerY = instance.rect.y + instance.rect.height / 2
            wallLayout.worldOrigin = CGPoint(
                x: centerX - Double(viewSize.width) / wallLayout.cameraScale / 2,
                y: centerY - Double(viewSize.height) / wallLayout.cameraScale / 2
            )
        }
        // 原型阶段先跳变不做帧动画（阶段 4 接正式表面时补动画器）。
        wallLayout.refreshInstances()
        collectionView.reloadData()
    }
}

/// 墙海报 cell：封面 + 底部标题。圆角用图层裁切、阴影用 shadowPath
/// 挂在外层容器（规格 §4：禁止默认离屏渲染路径）。
final class WallPosterCell: UICollectionViewCell {

    static let reuseId = "WallPosterCell"

    private let shadowView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
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
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        shadowView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.8
        titleLabel.layer.shadowRadius = 2
        titleLabel.layer.shadowOffset = .zero
        shadowView.addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowView.frame = contentView.bounds
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: contentView.bounds, cornerRadius: 8).cgPath
        imageView.frame = shadowView.bounds
        let labelHeight: CGFloat = 16
        titleLabel.frame = CGRect(
            x: 6, y: shadowView.bounds.height - labelHeight - 4,
            width: shadowView.bounds.width - 12, height: labelHeight)
    }

    func configure(entry: WallPrototypeViewController.Entry, tier: Int) {
        titleLabel.text = entry.title
        loadTask?.cancel()
        imageView.image = nil
        guard let pic = entry.picUrl,
              let urlString = NativeCoverLoader.shared.proxiedURLString(pic, tier: tier) else {
            currentUrl = nil
            return
        }
        currentUrl = urlString
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
    }
}
