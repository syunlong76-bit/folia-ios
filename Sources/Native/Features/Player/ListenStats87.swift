// ListenStats87.swift
//
// (87) 功能三件之三：听歌统计。纯本地计数，UserDefaults 持久化
// （key 前缀 "stats87."）：累计播放次数 / 累计收听秒数 / 每曲
// 计数 / 每日计数 / 标题映射（Top 列表展示用）。recordPlay 的
// 接线点（播放引擎起播回调）不在本包允许改动范围内，由主线
// 在起播处调 ListenStats87Store.shared.recordPlay(track:) 一行
// 接入；addListening(seconds:) 同理由进度回调按增量调用。

import UIKit

final class ListenStats87Store {

    static let shared = ListenStats87Store()

    private enum Key {
        static let totalPlays = "stats87.totalPlays"
        static let totalSeconds = "stats87.totalSeconds"
        static let perTrack = "stats87.perTrack"
        static let perDay = "stats87.perDay"
        static let titles = "stats87.titles"
    }

    private let defaults = UserDefaults.standard
    /// 串行队列守全部读写（调用方多在主线程，队列兜底跨线程安全）。
    private let queue = DispatchQueue(label: "folia.stats87.store")

    private init() {}

    private static func trackKey(for track: FoliaTrack) -> String {
        "\(track.sourceType.rawValue):\(track.id)"
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - 写入

    /// 记一次播放：总数＋每曲＋今日各 +1，并登记标题映射供
    /// Top 列表展示。落面包屑 stats87（≤15 字节口径）。
    func recordPlay(track: FoliaTrack) {
        queue.sync {
            let total = defaults.integer(forKey: Key.totalPlays) + 1
            defaults.set(total, forKey: Key.totalPlays)

            let key = Self.trackKey(for: track)
            var perTrack = defaults.dictionary(forKey: Key.perTrack) as? [String: Int] ?? [:]
            perTrack[key] = (perTrack[key] ?? 0) + 1
            defaults.set(perTrack, forKey: Key.perTrack)

            var perDay = defaults.dictionary(forKey: Key.perDay) as? [String: Int] ?? [:]
            let today = Self.todayKey()
            perDay[today] = (perDay[today] ?? 0) + 1
            defaults.set(perDay, forKey: Key.perDay)

            var titles = defaults.dictionary(forKey: Key.titles) as? [String: String] ?? [:]
            titles[key] = track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
            defaults.set(titles, forKey: Key.titles)

            Breadcrumbs.log("stats87 plays=\(total)")
        }
    }

    /// 累加收听秒数（进度回调按增量喂）：单次 clamp 到 0~3600，
    /// 防 seek/异常增量把总数打爆。
    func addListening(seconds: Double) {
        let clamped = min(max(seconds, 0), 3600)
        guard clamped > 0 else { return }
        queue.sync {
            let total = defaults.double(forKey: Key.totalSeconds) + clamped
            defaults.set(total, forKey: Key.totalSeconds)
        }
    }

    // MARK: - 读取

    var totalPlays: Int {
        queue.sync { defaults.integer(forKey: Key.totalPlays) }
    }

    var totalSeconds: Double {
        queue.sync { defaults.double(forKey: Key.totalSeconds) }
    }

    func count(for track: FoliaTrack) -> Int {
        let key = Self.trackKey(for: track)
        return queue.sync {
            (defaults.dictionary(forKey: Key.perTrack) as? [String: Int])?[key] ?? 0
        }
    }

    /// 最常听（计数降序，同数按 key 字典序保稳定）。
    func topTracks(limit: Int) -> [(key: String, count: Int)] {
        queue.sync {
            let perTrack = defaults.dictionary(forKey: Key.perTrack) as? [String: Int] ?? [:]
            return perTrack
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(limit)
                .map { (key: $0.key, count: $0.value) }
        }
    }

    func todayPlays() -> Int {
        let today = Self.todayKey()
        return queue.sync {
            (defaults.dictionary(forKey: Key.perDay) as? [String: Int])?[today] ?? 0
        }
    }

    /// Top 列表展示标题（recordPlay 时登记的「歌名 — 歌手」）；
    /// 无登记时回退展示原始 key。
    func title(forKey key: String) -> String {
        queue.sync {
            (defaults.dictionary(forKey: Key.titles) as? [String: String])?[key] ?? key
        }
    }

    /// 累计收听时长文案：「12 小时 34 分」/「34 分」/「不足 1 分」。
    static func durationText(seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        if minutes > 0 { return "\(minutes) 分" }
        return "不足 1 分"
    }
}

// MARK: - 统计面板

final class ListenStats87ViewController: UIViewController {

    private let card = UIView()
    private let contentStack = UIStackView()

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func present(from presenter: UIViewController) {
        presenter.present(ListenStats87ViewController(), animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let dimTap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimTap.delegate = self
        view.addGestureRecognizer(dimTap)

        card.backgroundColor = .clear
        card.layer.cornerRadius = 28
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96).translatedBy(x: 0, y: 12)
        view.addSubview(card)

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(blur)
        let tint = UIView()
        tint.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        tint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tint)

        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        closeButton.accessibilityLabel = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)

        let cardWidth = card.widthAnchor.constraint(equalToConstant: 400)
        cardWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            cardWidth,
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            blur.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            blur.topAnchor.constraint(equalTo: card.topAnchor),
            blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tint.topAnchor.constraint(equalTo: card.topAnchor),
            tint.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        rebuildContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.45, delay: 0,
                       usingSpringWithDamping: 0.86, initialSpringVelocity: 0.4,
                       options: [.curveEaseOut]) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let store = ListenStats87Store.shared

        let heading = UILabel()
        heading.text = "听歌统计"
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.textColor = .white
        contentStack.addArrangedSubview(heading)

        if store.totalPlays == 0 {
            let empty = UILabel()
            empty.text = "还没有收听记录"
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = UIColor.white.withAlphaComponent(0.6)
            contentStack.addArrangedSubview(empty)
            return
        }

        contentStack.addArrangedSubview(summaryRow(title: "累计播放",
            value: "\(store.totalPlays) 次"))
        contentStack.addArrangedSubview(summaryRow(title: "累计收听",
            value: ListenStats87Store.durationText(seconds: store.totalSeconds)))
        contentStack.addArrangedSubview(summaryRow(title: "今日播放",
            value: "\(store.todayPlays()) 次"))

        let top = store.topTracks(limit: 10)
        if !top.isEmpty {
            let topHeading = UILabel()
            topHeading.text = "最常听"
            topHeading.font = .systemFont(ofSize: 14, weight: .semibold)
            topHeading.textColor = UIColor.white.withAlphaComponent(0.85)
            contentStack.addArrangedSubview(topHeading)
            for (index, entry) in top.enumerated() {
                contentStack.addArrangedSubview(summaryRow(
                    title: "\(index + 1). \(store.title(forKey: entry.key))",
                    value: "\(entry.count) 次"))
            }
        }
    }

    private func summaryRow(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 14, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fill
        return stack
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func dimTapped() { dismiss(animated: true) }
}

extension ListenStats87ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        !(touch.view?.isDescendant(of: card) ?? false)
    }
}
