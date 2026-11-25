// SongInfo87.swift
//
// (87) 功能三件之二：歌曲资料面板。纯本地组装（FoliaTrack 字段
// ＋ ListenStats87 本机播放次数），不发网络请求。行式列出：
// 歌名 / 歌手 / 专辑 / 来源 / 时长 / 歌曲 ID / fee 标记（仅网易云）
// / 本机播放次数。材质与 Comments87 / ConsolePanel82 同口径。

import UIKit

final class SongInfoPanel87ViewController: UIViewController {

    private let track: FoliaTrack
    private let card = UIView()

    init(track: FoliaTrack) {
        self.track = track
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func present(from presenter: UIViewController, track: FoliaTrack) {
        let panel = SongInfoPanel87ViewController(track: track)
        presenter.present(panel, animated: true)
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

        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        for (index, entry) in Self.rows(for: track).enumerated() {
            rows.addArrangedSubview(makeRow(title: entry.0, value: entry.1,
                                            showHairline: index > 0))
        }

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        closeButton.accessibilityLabel = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        card.addSubview(rows)
        card.addSubview(closeButton)
        let cardWidth = card.widthAnchor.constraint(equalToConstant: 380)
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

            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
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

    private func makeRow(title: String, value: String, showHairline: Bool) -> UIView {
        let container = UIView()
        if showHairline {
            let line = UIView()
            line.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            line.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                line.topAnchor.constraint(equalTo: container.topAnchor),
                line.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 14, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.numberOfLines = 0
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            valueLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),
        ])
        return container
    }

    /// 资料行组装（顺序即展示顺序）。fee 行仅网易云出现：
    /// 1=VIP 专享、4=专辑付费、0/8/nil=普通。
    private static func rows(for track: FoliaTrack) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("歌名", track.title.isEmpty ? "—" : track.title))
        rows.append(("歌手", track.artist.isEmpty ? "—" : track.artist))
        rows.append(("专辑", track.album.isEmpty ? "—" : track.album))
        rows.append(("来源", sourceName(of: track.sourceType)))
        let total = max(0, Int(track.duration.rounded()))
        rows.append(("时长", String(format: "%d:%02d", total / 60, total % 60)))
        rows.append(("歌曲 ID", track.id))
        if track.sourceType == .netease {
            let feeText: String
            switch track.fee {
            case 1: feeText = "VIP 专享"
            case 4: feeText = "专辑付费"
            default: feeText = "普通"
            }
            rows.append(("付费标记", feeText))
        }
        rows.append(("本机播放", "\(ListenStats87Store.shared.count(for: track)) 次"))
        return rows
    }

    private static func sourceName(of source: AudioSourceType) -> String {
        switch source {
        case .netease: return "网易云"
        case .qq: return "QQ音乐"
        case .kugou: return "酷狗"
        case .local: return "本地"
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func dimTapped() { dismiss(animated: true) }
}

extension SongInfoPanel87ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        !(touch.view?.isDescendant(of: card) ?? false)
    }
}
