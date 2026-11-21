import UIKit

/// 云盘（3.7 (55) 工作流 E，「…」菜单·云盘）。
///
/// 后端查实结论：网页侧 netease.ts 有 getUserCloud →
/// `/user/cloud?limit&offset`（响应 data[]，每条带 simpleSong
/// 歌曲对象）；原生 NativeDataClient 无云盘方法，但其
/// getJSON 是 /api/netease 同源代理的通用入口（LocalServer
/// 任意子路径转发 EdgeOne 网易云函数、统一附 cookie 会话
/// 参数），故本页直接经 getJSON 走同一端点真接列表——与
/// NativeDataClient+Workbench 的电台/专辑扩展同一通路。
/// 点按一行以整列为队列经 QueueManager 起播（与搜索/电台
/// 同一漏斗）。云盘曲目的取流在网页侧带 variant=cloud 标
/// 记：(62) 已在入队侧打标（CloudDriveRegistry62 记云盘曲
/// 目 id 集 + 面包屑 variant=cloud），但原生取流链
/// （EdgeOneAPIClient.fetchSongStreamURL / QueueManager，
/// 非本文件域）尚无 variant 参数与云盘专用端点，取流仍走
/// 标准 /song/url/v1——专用取流请求待 Core 侧补 variant
/// 通路后由注册表消费（D1，真机未验）。点播成败以真机为准。
/// 未登录/接口失败/空列表都给诚实状态文案，不塞占位行。
final class CloudDriveViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateLabel = UILabel()
    private var tracks: [NativeTrack] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        overrideUserInterfaceStyle = .dark

        let titleLabel = UILabel()
        titleLabel.text = "云盘"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
            for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "关闭"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(close)

        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cloudCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        stateLabel.font = .systemFont(ofSize: 13)
        stateLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
        load()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func load() {
        stateLabel.text = "云盘加载中…"
        stateLabel.isHidden = false
        tableView.isHidden = true
        Task { [weak self] in
            guard let self else { return }
            await NativeDataClient.shared.refreshWebSession()
            do {
                let root = try await NativeDataClient.shared.getJSON(
                    "/api/netease/user/cloud",
                    query: ["limit": "200", "offset": "0"])
                let parsed = NativeJSON.array(root["data"]).compactMap(Self.cloudTrack)
                await MainActor.run {
                    self.tracks = parsed
                    Breadcrumbs.log("wall.menu.cloud ok n=\(parsed.count)")
                    if parsed.isEmpty {
                        self.stateLabel.text = "云盘里暂时没有可列出的歌曲。"
                        self.stateLabel.isHidden = false
                        self.tableView.isHidden = true
                    } else {
                        self.stateLabel.isHidden = true
                        self.tableView.isHidden = false
                        self.tableView.reloadData()
                    }
                }
            } catch {
                await MainActor.run {
                    Breadcrumbs.log("wall.menu.cloud failed")
                    self.stateLabel.text = "云盘加载失败：需要登录网易云，或网络暂时不可用。关掉本页后可重试。"
                    self.stateLabel.isHidden = false
                    self.tableView.isHidden = true
                }
            }
        }
    }

    /// /user/cloud 一条 → 曲目：歌曲对象在 simpleSong 里（网
    /// 页侧 getUserCloud 同口径）；缺 simpleSong 时退回条目
    /// 本身的 songId/songName 形状。解析不了就不列（不造假）。
    private static func cloudTrack(_ raw: [String: Any]) -> NativeTrack? {
        if let simple = NativeJSON.dict(raw["simpleSong"]),
           let track = WorkbenchParse.flexibleTrack(simple) {
            return track
        }
        if let track = WorkbenchParse.flexibleTrack(raw) {
            return track
        }
        guard let songId = NativeJSON.string(raw["songId"]) else { return nil }
        return NativeTrack(
            id: songId,
            name: NativeJSON.string(raw["songName"]) ?? "",
            artists: NativeJSON.string(raw["artist"]) ?? "",
            albumName: NativeJSON.string(raw["album"]),
            picUrl: nil,
            durationMs: 0)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cloudCell", for: indexPath)
        let track = tracks[indexPath.row]
        cell.backgroundColor = .clear
        cell.textLabel?.text = track.name
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 14)
        cell.detailTextLabel?.text = track.artists
        // UITableViewCell 默认样式无 detailTextLabel 渲染，副行拼进主行兜底显示歌手。
        if !track.artists.isEmpty {
            cell.textLabel?.text = "\(track.name) · \(track.artists)"
        }
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !tracks.isEmpty else { return }
        let queue = tracks.map(workbenchFoliaTrack)
        // (62) variant=cloud 入队打标：注册云盘曲目 id 集，
        // 面包屑带 variant，取流侧待 Core variant 通路消费。
        CloudDriveRegistry62.mark(queue)
        Breadcrumbs.log("wall.menu.cloud play at=\(indexPath.row) n=\(queue.count) variant=cloud")
        QueueManager.shared.setQueue(queue, startingAt: indexPath.row, source: "cloud-drive")
        dismiss(animated: true)
    }
}

/// (62) 云盘曲目标记注册表：QueueManager/取流链补 variant
/// 通路后按此判定云盘来源（现阶段供面包屑与后续消费读取）。
enum CloudDriveRegistry62 {
    private static var ids: Set<String> = []
    private static let lock = NSLock()

    static func mark(_ tracks: [FoliaTrack]) {
        lock.lock()
        ids.formUnion(tracks.map { $0.id })
        lock.unlock()
    }

    static func isCloudTrack(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }
}
