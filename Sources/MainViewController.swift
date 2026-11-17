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
        let prototype = WallPrototypeViewController()
        prototype.modalPresentationStyle = .fullScreen
        present(prototype, animated: true)
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
