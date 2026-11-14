import UIKit
import WebKit

/// 主界面（壳 3.0 双表面）：两个全屏 WKWebView + 右边缘垂直居中的半透明齿轮按钮。
///
/// 双表面进程隔离：
/// - 浏览表面（browseWebView）：加载 /browse/?surface=browse，无特效构建，
///   主页/歌单/搜索/收藏/设置都在这里，冷启即加载、常驻最上层。
/// - 播放表面（playerWebView）：加载 /?surface=player、完整特效构建，
///   只在第一次需要播放时才创建；始终留在视图层级内（垫在浏览表面之下），
///   切到浏览表面只是被盖住，音频不间断。
/// 两边用独立的 WKWebViewConfiguration（独立网页进程），但显式共用同一个
/// WKWebsiteDataStore.default()：同源（127.0.0.1 同端口）下登录态、
/// localStorage、IndexedDB 两边一致。任一表面进程被系统杀掉只重载它自己。
///
/// 沿用 v2 壳行为：全屏沉浸（隐藏状态栏与主指示条、scrollView 不做安全区
/// 内缩）；齿轮无触摸约 3.5 秒淡出且不可点，任意触摸先唤出并重新计时
/// （手势识别器只旁听，不吞页面触摸）。
final class MainViewController: UIViewController, WKNavigationDelegate, UIGestureRecognizerDelegate {

    private var browseWebView: WKWebView!
    private var playerWebView: WKWebView?
    private var statusLabel: UILabel!
    private var gearButton: UIButton!
    private var gearHideWorkItem: DispatchWorkItem?
    /// 本地服务端口（服务器就绪时记下）与两表面的入口地址：
    /// 内容进程被系统杀掉后靠各自地址重载自愈
    private var serverPort: UInt16 = 0
    private var browseURL: URL?
    private var playerURL: URL?

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

        // --- 浏览表面 WebView（播放表面在第一次需要时垫到它下面创建）---
        let browse = makeWebView()
        view.addSubview(browse)
        pinToEdges(browse)
        self.browseWebView = browse

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

        // --- 跨表面切换：桥指令（点歌/迷你条/回浏览按钮）经 LocalServer 回调到这里 ---
        BridgeStore.shared.onShowSurface = { [weak self] surface in
            self?.showSurface(surface)
        }

        // --- 启动本地服务器，就绪后加载浏览表面 ---
        LocalServer.shared.onReady = { [weak self] port in
            guard let self = self else { return }
            self.serverPort = port
            let browse = URL(string: "http://127.0.0.1:\(port)/browse/?surface=browse")
            let player = URL(string: "http://127.0.0.1:\(port)/?surface=player")
            self.browseURL = browse
            self.playerURL = player
            if let browse = browse {
                self.browseWebView.load(URLRequest(url: browse))
            }
        }
        LocalServer.shared.start()
    }

    // MARK: - WebView 工厂与表面切换

    /// 两表面共用的 WebView 配置：独立 configuration（独立网页进程）+
    /// 显式共用默认数据存储（同源登录态/本地存储共享）+ 长按抑制脚本。
    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
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
        return webView
    }

    private func pinToEdges(_ webView: WKWebView) {
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// 懒创建播放表面：垫在浏览表面之下（保持在层级内，音频不被系统挂起），
    /// 创建即加载播放构建。此后常驻，切表面只改浏览表面的可见性。
    private func ensurePlayerWebView() -> WKWebView {
        if let existing = playerWebView { return existing }
        let player = makeWebView()
        view.insertSubview(player, belowSubview: browseWebView)
        pinToEdges(player)
        playerWebView = player
        if let url = playerURL {
            player.load(URLRequest(url: url))
        }
        return player
    }

    /// 切换可见表面（主线程）。播放表面从不移出层级、从不 hidden：
    /// 「切到浏览」= 浏览表面盖回来；「切到播放」= 浏览表面隐藏、露出下面的播放表面。
    private func showSurface(_ surface: String) {
        if surface == "player" {
            _ = ensurePlayerWebView()
            browseWebView.isHidden = true
        } else {
            browseWebView.isHidden = false
        }
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
        if webView === browseWebView {
            statusLabel.isHidden = true
        }
    }

    /// 网页内容进程被系统杀掉（内存峰值下 jetsam）后 WKWebView 只剩黑屏、不会自己
    /// 恢复：只重载出事的那个表面，另一个表面（尤其正在放歌的播放表面）不受影响。
    /// 播放表面重载后会从桥的 lastPlay 快照恢复队列与进度到可续播状态。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === playerWebView {
            NSLog("[MainVC] player web content process terminated; reloading player surface")
            if let url = playerURL {
                webView.load(URLRequest(url: url))
            }
            return
        }
        NSLog("[MainVC] browse web content process terminated; reloading browse surface")
        if browseWebView.isHidden == false {
            statusLabel.isHidden = false
            statusLabel.text = "页面进程被系统回收，正在重新加载…"
        }
        if let url = browseURL {
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if webView === browseWebView && browseWebView.isHidden == false {
            statusLabel.isHidden = false
            statusLabel.text = "页面加载失败：\(error.localizedDescription)\n可尝试关闭应用后重新打开"
        }
    }
}
