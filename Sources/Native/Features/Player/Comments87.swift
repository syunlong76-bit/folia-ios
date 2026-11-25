// Comments87.swift
//
// (87) 功能三件之一：评论面板。数据走 EdgeOneAPIClient
// .fetchComments87（三家归一化 FoliaComment87）；头像/封面走
// WorkbenchCover（NativeCoverLoader 代理链，不裸直下）。
// 三态：加载中 / 空（暂无评论）/ 失败（评论加载失败＋重试）。
// 本地曲目无评论通路，进面板直接显示「本地歌曲暂无评论」。
// 材质与 ConsolePanel82 同口径：压暗层＋systemUltraThinMaterialDark
// 毛玻璃卡＋白 0.16 描边；入场系统弹簧缩放淡入。

import UIKit

final class CommentsPanel87ViewController: UIViewController {

    private let track: FoliaTrack
    private var comments: [FoliaComment87] = []
    private var loadTask: Task<Void, Never>?

    private let card = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let stateLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    init(track: FoliaTrack) {
        self.track = track
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    static func present(from presenter: UIViewController, track: FoliaTrack) {
        let panel = CommentsPanel87ViewController(track: track)
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

        // 头行：封面＋歌名/歌手＋关闭钮。
        let cover = UIImageView()
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 10
        cover.translatesAutoresizingMaskIntoConstraints = false
        WorkbenchCover.load(raw: track.artworkURL?.absoluteString, into: cover) { true }
        let titleLabel = UILabel()
        titleLabel.text = track.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        let artistLabel = UILabel()
        artistLabel.text = track.artist
        artistLabel.font = .systemFont(ofSize: 13)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        artistLabel.numberOfLines = 1
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        closeButton.accessibilityLabel = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.showsVerticalScrollIndicator = false
        tableView.register(CommentCell87.self, forCellReuseIdentifier: "cmt87")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.font = .systemFont(ofSize: 14)
        stateLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        stateLabel.textAlignment = .center
        stateLabel.numberOfLines = 0
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.isHidden = true
        retryButton.setTitle("重试", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        retryButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        retryButton.layer.cornerRadius = 12
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 24, bottom: 8, right: 24)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        card.addSubview(cover)
        card.addSubview(titleStack)
        card.addSubview(closeButton)
        card.addSubview(tableView)
        card.addSubview(spinner)
        card.addSubview(stateLabel)
        card.addSubview(retryButton)

        let cardMaxWidth = card.widthAnchor.constraint(lessThanOrEqualToConstant: 680)
        cardMaxWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            cardMaxWidth,
            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            blur.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            blur.topAnchor.constraint(equalTo: card.topAnchor),
            blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tint.topAnchor.constraint(equalTo: card.topAnchor),
            tint.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            cover.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            cover.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            cover.widthAnchor.constraint(equalToConstant: 48),
            cover.heightAnchor.constraint(equalToConstant: 48),
            titleStack.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 12),
            titleStack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            tableView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 12),
            tableView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),

            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -32),
            retryButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 14),
        ])

        if track.sourceType == .local {
            showState(text: "本地歌曲暂无评论")
            Breadcrumbs.log("cmt87 src=local n=0")
        } else {
            loadComments()
        }
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

    private func loadComments() {
        loadTask?.cancel()
        spinner.startAnimating()
        stateLabel.isHidden = true
        retryButton.isHidden = true
        tableView.isHidden = true
        let track = self.track
        loadTask = Task { [weak self] in
            do {
                let fetched = try await EdgeOneAPIClient.shared.fetchComments87(track: track)
                await MainActor.run {
                    guard let self else { return }
                    self.spinner.stopAnimating()
                    self.comments = fetched
                    Breadcrumbs.log("cmt87 src=\(track.sourceType.rawValue) n=\(fetched.count)")
                    if fetched.isEmpty {
                        self.showState(text: "暂无评论")
                    } else {
                        self.tableView.isHidden = false
                        self.tableView.reloadData()
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.spinner.stopAnimating()
                    Breadcrumbs.log("cmt87 src=\(track.sourceType.rawValue) n=-1")
                    self.showState(text: "评论加载失败", showRetry: true)
                }
            }
        }
    }

    private func showState(text: String, showRetry: Bool = false) {
        spinner.stopAnimating()
        tableView.isHidden = true
        stateLabel.text = text
        stateLabel.isHidden = false
        retryButton.isHidden = !showRetry
    }

    @objc private func retryTapped() { loadComments() }
    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func dimTapped() { dismiss(animated: true) }
}

extension CommentsPanel87ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // 只认卡外点击关闭，卡内（列表滚动/点按）不触发。
        !(touch.view?.isDescendant(of: card) ?? false)
    }
}

extension CommentsPanel87ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        comments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cmt87", for: indexPath) as! CommentCell87
        cell.configure(with: comments[indexPath.row])
        return cell
    }
}

/// 评论行：圆形头像＋昵称/时间一行＋内容＋点赞数。
private final class CommentCell87: UITableViewCell {

    private let avatarView = UIImageView()
    private let nicknameLabel = UILabel()
    private let timeLabel = UILabel()
    private let contentLabel = UILabel()
    private let likeLabel = UILabel()
    private var representedAvatar: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 18
        avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        nicknameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nicknameLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        nicknameLabel.numberOfLines = 1
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        let headStack = UIStackView(arrangedSubviews: [nicknameLabel, timeLabel])
        headStack.axis = .vertical
        headStack.spacing = 1
        headStack.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.font = .systemFont(ofSize: 14)
        contentLabel.textColor = .white
        contentLabel.numberOfLines = 0
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        likeLabel.font = .systemFont(ofSize: 11)
        likeLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        likeLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatarView)
        contentView.addSubview(headStack)
        contentView.addSubview(contentLabel)
        contentView.addSubview(likeLabel)
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            headStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            headStack.topAnchor.constraint(equalTo: avatarView.topAnchor),
            headStack.trailingAnchor.constraint(lessThanOrEqualTo: likeLabel.leadingAnchor, constant: -8),
            likeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            likeLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            contentLabel.leadingAnchor.constraint(equalTo: headStack.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentLabel.topAnchor.constraint(equalTo: headStack.bottomAnchor, constant: 4),
            contentLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with comment: FoliaComment87) {
        nicknameLabel.text = comment.nickname
        timeLabel.text = comment.timeText
        contentLabel.text = comment.content
        likeLabel.text = comment.likedCount > 0 ? "♥ \(comment.likedCount)" : ""
        let raw = comment.avatarURL?.absoluteString
        representedAvatar = raw
        WorkbenchCover.loadAvatar(url: comment.avatarURL, into: avatarView) { [weak self] in
            self?.representedAvatar == raw
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedAvatar = nil
        avatarView.image = nil
    }
}
