import Combine
import UIKit
import WebKit

/// 主界面（3.6 全量前端）：原版 Folia 完整 App 前端整页跑在 WebEffectBridge
/// 的 WebView 里（主页/格子/搜索/命令面板/设置/播放页全是源码本尊），原生
/// 只守底层——音频引擎、队列真源、锁屏、取流、缓存，经桥与前端相连。
///
/// 3.5 及以前的 SwiftUI 仿写浏览面（NativeBrowseView）、原生迷你条与全屏
/// 播放容器就此退役（文件保留在工程内，不再挂载）。壳侧只剩：全屏沉浸、
/// 右缘设置齿轮（壳级设置/更新）、桥致命错误时的重试浮层。
final class MainViewController: UIViewController, UIGestureRecognizerDelegate {

    private var gearButton: UIButton!
    private var gearHideWorkItem: DispatchWorkItem?
    private var fatalErrorView: UIView?
    private var openStageNoticeView: UIView?
    private var openStageNoticeLabel: UILabel?
    private var openStageRetryButton: UIButton?
    private var openStageRetryLeading: NSLayoutConstraint?
    private var openStageRetryTrailing: NSLayoutConstraint?
    private var openStageLabelTrailing: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()

    /// 齿轮静止时的不透明度（与深色页面融合）
    private let gearRestingAlpha: CGFloat = 0.5
    /// 无触摸多久后淡出齿轮
    private let gearIdleHideDelay: TimeInterval = 3.5

    // MARK: - 沉浸全屏

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 回程票（3.7 (13) #6）：前端 stageClosed 过桥后按票恢复墙。
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleStageClosed),
            name: .foliaStageClosed, object: nil)
        // Folia 默认主题就是深色（Midnight Default）：全局强制深色外观，
        // 不随系统浅色模式翻白。
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        // --- 唯一界面：全量前端 WebView（桥持有，本地文件加载 index.html，
        // 不带 ?surface=browse——误落 browse 表面会让起播走不存在的 HTTP
        // 桥、点了没反应，审计 P17）。---
        let webView = WebEffectBridge.shared.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // 禁止 scrollView 按安全区自动内缩内容，否则刘海/底部横条处露黑边。
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // --- 设置齿轮：右边缘、垂直居中；壳级设置（更新等）入口 ---
        let gear = UIButton(type: .system)
        gear.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        gear.tintColor = .white
        gear.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        gear.layer.cornerRadius = 17
        gear.alpha = gearRestingAlpha
        gear.accessibilityLabel = "设置"
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        // M1 阶段 3 调试入口：长按齿轮打开单墙原型（正式表面接入后移除）。
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(openWallPrototype))
        longPress.minimumPressDuration = 0.8
        gear.addGestureRecognizer(longPress)
        view.addSubview(gear)
        NSLayoutConstraint.activate([
            gear.widthAnchor.constraint(equalToConstant: 34),
            gear.heightAnchor.constraint(equalToConstant: 34),
            gear.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            gear.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        self.gearButton = gear

        // --- 触摸唤出：点按/拖动识别器只旁听，不取消 WebView 的触摸 ---
        let tapWake = UITapGestureRecognizer(target: self, action: #selector(handleScreenTouch))
        tapWake.cancelsTouchesInView = false
        tapWake.delegate = self
        view.addGestureRecognizer(tapWake)
        let panWake = UIPanGestureRecognizer(target: self, action: #selector(handleScreenTouch))
        panWake.cancelsTouchesInView = false
        panWake.delegate = self
        view.addGestureRecognizer(panWake)
        scheduleGearHide()

        // --- 开页提示条（3.7 (13.5)，DS38 Q7）：收墙后还没落地
        // 时亮「正在打开」，闭环跑满仍失败亮「没打开 + 重试」。 ---
        WebEffectBridge.shared.onOpenStageNotice = { [weak self] notice in
            self?.updateOpenStageNotice(notice)
        }

        // --- 桥致命错误（网页进程反复被杀、自动重载已停）：浮层 + 人工重试 ---
        WebEffectBridge.shared.$lastFatalError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if error != nil {
                    self?.showFatalErrorOverlay()
                } else {
                    self?.hideFatalErrorOverlay()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 开页提示条

    private func updateOpenStageNotice(_ notice: WebEffectBridge.OpenStageNotice?) {
        guard let notice else {
            openStageNoticeView?.removeFromSuperview()
            openStageNoticeView = nil
            return
        }
        if openStageNoticeView == nil {
            let pill = UIView()
            pill.backgroundColor = UIColor.black.withAlphaComponent(0.78)
            pill.layer.cornerRadius = 16
            pill.layer.borderWidth = 0.5
            pill.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            pill.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false

            let retry = UIButton(type: .system)
            retry.setTitle("重试", for: .normal)
            retry.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            retry.tintColor = .white
            retry.translatesAutoresizingMaskIntoConstraints = false
            retry.addTarget(self, action: #selector(retryOpenStage), for: .touchUpInside)

            pill.addSubview(label)
            pill.addSubview(retry)
            view.addSubview(pill)
            // opening 态没有重试按钮：按钮隐藏时改走 label 直达
            // 右缘的约束，免得胶囊被隐藏按钮的宽度撑长（13.5
            // 审查低-3）。
            let retryLeading = retry.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10)
            let retryTrailing = retry.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12)
            let labelTrailing = label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14)
            labelTrailing.isActive = false
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                pill.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
                pill.heightAnchor.constraint(equalToConstant: 32),
                label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
                retryLeading,
                retryTrailing,
                retry.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
            ])
            openStageRetryLeading = retryLeading
            openStageRetryTrailing = retryTrailing
            openStageLabelTrailing = labelTrailing
            openStageNoticeView = pill
            openStageNoticeLabel = label
            openStageRetryButton = retry
        }
        switch notice {
        case .opening:
            openStageNoticeLabel?.text = "正在打开播放页…"
            openStageRetryButton?.isHidden = true
            openStageRetryLeading?.isActive = false
            openStageRetryTrailing?.isActive = false
            openStageLabelTrailing?.isActive = true
        case .failed:
            openStageNoticeLabel?.text = "播放页没打开"
            openStageRetryButton?.isHidden = false
            openStageLabelTrailing?.isActive = false
            openStageRetryLeading?.isActive = true
            openStageRetryTrailing?.isActive = true
        }
        if let pill = openStageNoticeView {
            view.bringSubviewToFront(pill)
        }
    }

    @objc private func retryOpenStage() {
        WebEffectBridge.shared.retryOpenStage()
    }

    // MARK: - 致命错误浮层

    private func showFatalErrorOverlay() {
        guard fatalErrorView == nil else { return }
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "页面进程反复中断，已停止自动恢复"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let retry = UIButton(type: .system)
        retry.setTitle("重新加载", for: .normal)
        retry.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        retry.addTarget(self, action: #selector(retryWebContent), for: .touchUpInside)
        retry.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(retry)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),
            retry.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            retry.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16)
        ])
        fatalErrorView = container
    }

    private func hideFatalErrorOverlay() {
        fatalErrorView?.removeFromSuperview()
        fatalErrorView = nil
    }

    @objc private func retryWebContent() {
        WebEffectBridge.shared.retryAfterFatalError()
    }

    // MARK: - 齿轮自动隐藏

    @objc private func handleScreenTouch() {
        wakeGear()
    }

    /// 唤出齿轮并重置隐藏计时
    private func wakeGear() {
        gearHideWorkItem?.cancel()
        if gearButton.alpha < gearRestingAlpha || !gearButton.isUserInteractionEnabled {
            gearButton.isUserInteractionEnabled = true
            UIView.animate(withDuration: 0.25) {
                self.gearButton.alpha = self.gearRestingAlpha
            }
        }
        scheduleGearHide()
    }

    private func scheduleGearHide() {
        gearHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.45, animations: {
                self.gearButton.alpha = 0
            }, completion: { _ in
                // 淡出后彻底不可点，避免透明按钮误触挡住页面右缘操作；
                // 若期间已被新触摸唤出（alpha 已回复），不要误关
                if self.gearButton.alpha == 0 {
                    self.gearButton.isUserInteractionEnabled = false
                }
            })
        }
        gearHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gearIdleHideDelay, execute: work)
    }

    /// 与 WebView 内部手势（滚动、点击、横竖屏手势）同时识别，互不抢占
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func openWallPrototype() {
        // 阶段 4 起长按入口改开 Bravais 主页墙（歌单墙）；点歌单进其
        // 曲目墙。单墙原型本身已在 3.7 (3) 验收关门。
        let home = HomeWallViewController()
        home.modalPresentationStyle = .fullScreen
        present(home, animated: true)
    }

    /// 回程恢复（3.7 (13) #6）：播放页关闭且有票时，重呈主页墙
    /// 并直达原曲目墙；无票（用户自己进的播放页）什么都不做。
    @objc private func handleStageClosed() {
        // 先确认能呈现再消费票据：主 VC 上还压着别的浮层（如设置
        // 页）时票不能销毁，留待下一次机会（新票会覆盖旧票）。
        guard presentedViewController == nil,
              let ticket = WallReturnTicketStore.pending else { return }
        WallReturnTicketStore.pending = nil
        Breadcrumbs.log("stage closed, restoring kind=\(ticket.kind) playlist=\(ticket.playlistId)")
        // 主页票（13.4）：从主页墙台面进的播放页，关页只回主页墙。
        if ticket.kind == .home {
            let home = HomeWallViewController()
            home.modalPresentationStyle = .fullScreen
            present(home, animated: true)
            return
        }
        let home = HomeWallViewController()
        home.modalPresentationStyle = .fullScreen
        present(home, animated: true) {
            home.presentRestoredWall(ticket: ticket)
        }
    }

    @objc private func openSettings() {
        wakeGear()
        // 设置页自带 Folia 风格浮层呈现（半透明遮罩 + 底部卡片弹簧滑入），
        // overFullScreen 让底下的页面保持渲染、隐约透出，不整页切换
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .overFullScreen
        present(settings, animated: false)
    }
}
