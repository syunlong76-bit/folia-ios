import UIKit
import WebKit

/// 主界面：全屏 WKWebView + 右边缘垂直居中的半透明齿轮按钮（打开原生设置页）。
/// WebView 只加载本机回环地址 http://127.0.0.1:<port>/，内容由 LocalServer 提供。
///
/// v2 壳修复（2026-11-14 真机反馈）：
/// - 全屏沉浸：隐藏状态栏与主指示条、WebView scrollView 不做安全区内缩，
///   内容真正铺满刘海屏四边（此前上下大黑边的主因在 Web 侧根布局 + viewport，
///   壳侧把能做的沉浸项一次做满，避免系统栏位再叠一层黑带）。
/// - 齿轮自动隐藏：无触摸约 3.5 秒后淡出且不可点；任意触摸先唤出并重新计时。
///   唤出靠挂在根视图上的手势识别器（cancelsTouchesInView = false、允许与
///   WebView 自身手势同时识别），不拦截、不吞掉页面任何触摸。
final class MainViewController: UIViewController, WKNavigationDelegate, UIGestureRecognizerDelegate {

    private var webView: WKWebView!
    private var statusLabel: UILabel!
    private var gearButton: UIButton!
    private var gearHideWorkItem: DispatchWorkItem?
    /// 本地首页地址（服务器就绪时记下）：内容进程被系统杀掉后靠它重载自愈
    private var homeURL: URL?

    /// 齿轮静止时的不透明度（调柔和后低于 v1 的 0.85，与深色页面融合）
    private let gearRestingAlpha: CGFloat = 0.5
    /// 无触摸多久后淡出齿轮
    private let gearIdleHideDelay: TimeInterval = 3.5

    // MARK: - 沉浸全屏

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // 内容延伸到状态栏/主指示条之下，不给系统栏位留黑带
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        // --- WKWebView ---
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // 音乐播放器：允许自动播放带声媒体，不强制要求用户手势
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 抑制 iOS 网页原生「长按菜单」（拷贝/查询/翻译/共享…）与链接预览：
        // 在文档开始处注入样式——全局关 touch callout；文本选择只对非输入元素关闭，
        // input/textarea/contenteditable 的编辑、选中、粘贴能力保持原样。
        let calloutSuppressScript = WKUserScript(
            source: """
            (function () {
              var css = '* { -webkit-touch-callout: none !important; }'
                + '*:not(input):not(textarea):not([contenteditable]) { -webkit-user-select: none !important; }';
              var style = document.createElement('style');
              style.textContent = css;
              document.documentElement.appendChild(style);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(calloutSuppressScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.underPageBackgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // 关键：禁止 scrollView 按安全区自动内缩内容，否则刘海/底部横条处露黑边
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.webView = webView

        // --- 启动状态提示（服务器就绪后随 WebView 加载自然被覆盖，出错时保留可见）---
        let label = UILabel()
        label.text = "Folia 正在启动本地服务…"
        label.textColor = .lightGray
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        self.statusLabel = label

        // --- 设置齿轮：右边缘、垂直居中；更小、更透，与页面融合 ---
        let gear = UIButton(type: .system)
        gear.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        gear.tintColor = .white
        gear.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        gear.layer.cornerRadius = 17
        gear.alpha = gearRestingAlpha
        gear.accessibilityLabel = "设置"
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
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

        // --- 启动本地服务器，就绪后加载首页 ---
        LocalServer.shared.onReady = { [weak self] port in
            guard let self = self else { return }
            if let url = URL(string: "http://127.0.0.1:\(port)/") {
                self.homeURL = url
                self.webView.load(URLRequest(url: url))
            }
        }
        LocalServer.shared.start()
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

    @objc private func openSettings() {
        wakeGear()
        // 设置页自带 Folia 风格浮层呈现（半透明遮罩 + 底部卡片弹簧滑入），
        // overFullScreen 让底下的播放器页面保持渲染、隐约透出，不整页切换
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .overFullScreen
        present(settings, animated: false)
    }

    // MARK: - WKNavigationDelegate

    /// target=_blank / window.open 的链接在同一个 WebView 内打开，不跳出应用
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel.isHidden = true
    }

    /// 网页内容进程被系统杀掉（内存峰值下 jetsam）后 WKWebView 只剩一块黑屏、不会自己
    /// 恢复：重新加载本地首页自愈。登录态与设置都在页面本地存储里，重载后自行恢复，
    /// 用户最多看到一次页面重开，而不是永久黑屏只能杀 App。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[MainVC] web content process terminated; reloading home")
        statusLabel.isHidden = false
        statusLabel.text = "页面进程被系统回收，正在重新加载…"
        // homeURL 在服务器就绪、首次加载之前赋值，此后不清空；能走到这里（页面曾加载过）
        // 它必然已就位。服务器未就绪时还没有页面可终止，不会进这个回调。
        if let url = homeURL {
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        statusLabel.isHidden = false
        statusLabel.text = "页面加载失败：\(error.localizedDescription)\n可尝试关闭应用后重新打开"
    }
}
