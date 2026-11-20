import UIKit
import WebKit

/// 【3.7 (51) 起非根、仅存量引用】原主界面（3.6 全量前端）：原版 Folia
/// 完整 App 前端整页跑在 WebEffectBridge 的 WebView 里。本包换根后根控
/// 制器已是原生主页墙（SceneDelegate 直建 HomeWallViewController），本
/// 类不在冷启路径、不再被任何代码呈现（全仓引用只剩注释），本包按
/// (51) 分工保留本体不删，待 (52) 删桥时一并退役。本包已摘除其作为根时的三处职责接线：
/// 回程票恢复（handleStageClosed，随回程票链整链删除）、桥开页提示条
/// 与桥致命错误浮层（安装点随换根摘除；网页舞台兜底通道的提示改由
/// WebStageHostViewController 在其宿主内承载）。
///
/// 3.5 及以前的 SwiftUI 仿写浏览面（NativeBrowseView）、原生迷你条与全屏
/// 播放容器就此退役（文件保留在工程内，不再挂载）。壳侧只剩：全屏沉浸、
/// 右缘设置齿轮（壳级设置/更新）。
final class MainViewController: UIViewController, UIGestureRecognizerDelegate {

    private var gearButton: UIButton!
    private var gearHideWorkItem: DispatchWorkItem?

    /// 齿轮静止时的不透明度（与深色页面融合）
    private let gearRestingAlpha: CGFloat = 0.5
    /// 无触摸多久后淡出齿轮
    private let gearIdleHideDelay: TimeInterval = 3.5

    // MARK: - 沉浸全屏

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    /// dismiss 统一拦截（3.7 (46)）：根控制器 dismiss 会带下整
    /// 条呈现链（含 canonical 舞台）——未登记且 RouteGuard 在
    /// 期时由 StageExitGate veto。
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if StageExitGate.shared.shouldVetoDismiss(from: self) { return }
        super.dismiss(animated: flag, completion: completion)
    }

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

    @objc private func openSettings() {
        wakeGear()
        // 设置页自带 Folia 风格浮层呈现（半透明遮罩 + 底部卡片弹簧滑入），
        // overFullScreen 让底下的页面保持渲染、隐约透出，不整页切换
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .overFullScreen
        present(settings, animated: false)
    }
}
