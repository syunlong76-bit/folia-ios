import UIKit
import SwiftUI

// DiaryBookViewController99.swift — (99) 第 7 项入口壳：
// 隐私锁 → 书主页（SwiftUI，DiaryBookViews99）两段。
// (102) 第 2 项：开局动画取消（Miller 2026-11-28 定，
// 覆盖 (99)/(101) 开场视频），打开直接进锁面/书页；
// 锁改三法全上（密码/手势/Face ID＋向导＋首选，见
// DiaryLock102）。
//
// 入口落点（调研）：主页缝四图标行第 3 个「日记本」（Seam85Views book 字形）
// → HomeWallViewController.seam.onDiary93 呈现本类（(99) 改一行类名；
// (100) 歌单墙缝与控制台/拍立得入口亦全部改指本类，旧版无入口）。
final class DiaryBookViewController99: UIViewController {

    private let taggedSong: DiarySong90?
    private var lockHost: UIHostingController<DiaryLockGate102>?
    private var phase: Phase = .lock

    private enum Phase { case lock, book }

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
        Breadcrumbs.log("p102 diary open direct")
        showLock()
    }

    // MARK: - 2. 隐私锁（三法全上，DiaryLock102）

    /// 未配置 → 设置向导（密码→手势→面容→选首选）；
    /// 已配置 → 锁屏只出首选、失败才弹其他方式。进书
    /// 唯一出口是凭据验证成功（旧「直接进入」兜底与试
    /// 用版生物识别口径随 (102) 定版退役）。
    private func showLock() {
        phase = .lock
        let gate = DiaryLockGate102(
            onUnlock: { [weak self] in self?.enterBook() },
            onClose: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: gate)
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
        lockHost = host
    }

    // MARK: - 3. 书主页

    private func enterBook() {
        guard phase == .lock else { return }
        phase = .book
        Breadcrumbs.log("p102 diary lock passed")
        lockHost?.view.removeFromSuperview()
        lockHost?.removeFromParent()
        lockHost = nil
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
