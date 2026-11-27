import UIKit
import AVFoundation
import SwiftUI
import LocalAuthentication

// DiaryBookViewController99.swift — (99) 第 7 项入口壳：
// 开场视频 → 隐私锁 → 书主页（SwiftUI，DiaryBookViews99）三段。
//
// 入口落点（调研）：主页缝四图标行第 3 个「日记本」（Seam85Views book 字形）
// → HomeWallViewController.seam.onDiary93 呈现本类（(99) 改一行类名，
// 原 DiaryViewController90 保留供控制台/拍立得旧入口使用）。
// 隐私锁口径（试用版）：LAContext 生物识别；不可用/失败/取消都不锁死人，
// 锁面常驻「直接进入」兜底钮。
final class DiaryBookViewController99: UIViewController {

    private let taggedSong: DiarySong90?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?
    private var phase: Phase = .opening

    private enum Phase { case opening, lock, book }

    init(tagged track: FoliaTrack?) {
        taggedSong = track.map { DiarySong90(track: $0) }
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1)
        Breadcrumbs.log("p99 diary open")
        startOpening()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player?.pause()
    }

    // MARK: - 1. 开场视频（Resources/Diary/diary-opening.mp4，点按跳过）

    private func startOpening() {
        phase = .opening
        let url = Bundle.main.url(forResource: "diary-opening", withExtension: "mp4",
                                  subdirectory: "Diary")
            ?? Bundle.main.url(forResource: "diary-opening", withExtension: "mp4")
        guard let url else {
            // 资源缺失不挡人：直接进锁面（主施工方须把 Resources/Diary
            // 加为 folder reference，见交付报告）。
            Breadcrumbs.log("p99 diary intro")
            showLock()
            return
        }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: avPlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        player = avPlayer
        playerLayer = layer
        let tap = UITapGestureRecognizer(target: self, action: #selector(openingTapped))
        view.addGestureRecognizer(tap)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.finishOpening(skipped: false)
        }
        avPlayer.play()
    }

    @objc private func openingTapped() {
        guard phase == .opening else { return }
        finishOpening(skipped: true)
    }

    private func finishOpening(skipped: Bool) {
        guard phase == .opening else { return }
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        Breadcrumbs.log("p99 diary intro")
        showLock()
    }

    // MARK: - 2. 隐私锁（生物识别 + 直接进入兜底）

    private func showLock() {
        phase = .lock
        let lockView = UIView(frame: view.bounds)
        lockView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        lockView.backgroundColor = UIColor(red: 0.16, green: 0.15, blue: 0.20, alpha: 1)
        view.addSubview(lockView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        lockView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: lockView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: lockView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: lockView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: lockView.trailingAnchor, constant: -32),
        ])

        let icon = UIImageView(image: UIImage(systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)))
        icon.tintColor = UIColor.white.withAlphaComponent(0.9)
        stack.addArrangedSubview(icon)
        let title = UILabel()
        title.text = "音乐日记本"
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        stack.addArrangedSubview(title)
        let sub = UILabel()
        sub.text = "这是只属于你的私密记录"
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = UIColor.white.withAlphaComponent(0.65)
        stack.addArrangedSubview(sub)

        let bioButton = UIButton(type: .system)
        bioButton.setTitle("生物识别解锁", for: .normal)
        bioButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        bioButton.setTitleColor(.white, for: .normal)
        bioButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        bioButton.layer.cornerRadius = 24
        bioButton.contentEdgeInsets = UIEdgeInsets(top: 13, left: 28, bottom: 13, right: 28)
        bioButton.addTarget(self, action: #selector(bioTapped), for: .touchUpInside)
        stack.addArrangedSubview(bioButton)

        let directButton = UIButton(type: .system)
        directButton.setTitle("直接进入", for: .normal)
        directButton.titleLabel?.font = .systemFont(ofSize: 14)
        directButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        directButton.addTarget(self, action: #selector(directTapped), for: .touchUpInside)
        stack.addArrangedSubview(directButton)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        lockView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: lockView.safeAreaLayoutGuide.topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: lockView.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        lockView.tag = 9901
    }

    @objc private func bioTapped() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // 设备无生物识别/未录入：试用版直接放行，不锁死人。
            enterBook()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "解锁你的音乐日记本") { [weak self] success, _ in
            DispatchQueue.main.async {
                if success { self?.enterBook() }
                // 失败/取消：留在锁面，「直接进入」兜底仍在。
            }
        }
    }

    @objc private func directTapped() { enterBook() }

    @objc private func closeTapped() { dismiss(animated: true) }

    // MARK: - 3. 书主页

    private func enterBook() {
        guard phase == .lock else { return }
        phase = .book
        Breadcrumbs.log("p99 diary lock")
        view.viewWithTag(9901)?.removeFromSuperview()
        let root = DiaryBookRootView99(
            store: DiaryStore99.shared,
            initialSong: taggedSong ?? QueueManager.shared.currentTrack.map { DiarySong90(track: $0) },
            onClose: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}
