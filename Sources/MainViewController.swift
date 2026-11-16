import Combine
import SwiftUI
import UIKit
import WebKit

/// 主界面（3.3 全原生浏览）：原生 SwiftUI 浏览面 + 右边缘垂直居中的半透明齿轮。
///
/// 3.3 收口后的结构：主页/歌单/搜索是 NativeBrowseView（SwiftUI），点歌直进
/// QueueManager 原生队列；播放页 = 原生全屏容器 + 特效面 WebView（纯可视化，
/// 由 WebEffectBridge 持有）；迷你条是全 App 唯一播放条。网页只剩特效画布
/// 一处。playerWebView 与 LocalServer 均为旧双表面时代的遗留：LocalServer
/// 不再启动，playerWebView 只在「队列为空的旧桥路径」才可能被创建，正常
/// 流程走不到。
///
/// 沿用 v2 壳行为：全屏沉浸（隐藏状态栏与主指示条、scrollView 不做安全区
/// 内缩）；齿轮无触摸约 3.5 秒淡出且不可点，任意触摸先唤出并重新计时
/// （手势识别器只旁听，不吞页面触摸）。
final class MainViewController: UIViewController, WKNavigationDelegate, UIGestureRecognizerDelegate {

    /// 3.3 起浏览面是原生 SwiftUI（NativeBrowseView 的宿主视图）；
    /// playerWebView 仅保留给「队列为空时旧路径回退」，正常流程不再创建。
    private var browseContainerView: UIView!
    private var playerWebView: WKWebView?
    private var gearButton: UIButton!
    private var gearHideWorkItem: DispatchWorkItem?
    /// 本地服务端口（服务器就绪时记下）与两表面的入口地址：
    /// 内容进程被系统杀掉后靠各自地址重载自愈
    private var serverPort: UInt16 = 0
    // M2 原生播放层：迷你条 + 全屏播放容器（UIHostingController 悬浮挂载）。
    private var miniPlayerHostingController: UIHostingController<MiniPlayerView>?
    private var fullPlayerHostingController: UIHostingController<FullPlayerContainer>?
    private var nativePlayerCancellables = Set<AnyCancellable>()
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
        // Folia 默认主题就是深色（Midnight Default）：全局强制深色外观，
        // 不随系统浅色模式翻白（3.3 真机录屏里白底系统皮的直接原因之一）。
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        // 内容延伸到状态栏/主指示条之下，不给系统栏位留黑带
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        // --- 浏览表面：3.3 起为原生 SwiftUI（主页/歌单/搜索），冷启即挂载 ---
        let browseHost = UIHostingController(rootView: NativeBrowseView())
        browseHost.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(browseHost)
        view.addSubview(browseHost.view)
        browseHost.didMove(toParent: self)
        pinToEdges(browseHost.view)
        self.browseContainerView = browseHost.view

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

        // --- 3.2 原生接管：桥点歌指令改道原生引擎（须在首条指令到达前装好） ---
        NativePlaybackCoordinator.shared.start()

        // --- M2 原生播放层：迷你条悬浮挂载、全屏容器常驻挂载（RenderStateCenter 驱动） ---
        setupNativePlayerUI()

        // 3.3：浏览/播放均已原生化，LocalServer 不再启动（网页浏览面与
        // 网页播放面退役；特效面走本地文件加载，不经本地服务）。
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

    private func pinToEdges(_ pinnedView: UIView) {
        NSLayoutConstraint.activate([
            pinnedView.topAnchor.constraint(equalTo: view.topAnchor),
            pinnedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pinnedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pinnedView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// 懒创建播放表面：垫在浏览表面之下（保持在层级内，音频不被系统挂起），
    /// 创建即加载播放构建。此后常驻，切表面只改浏览表面的可见性。
    private func ensurePlayerWebView() -> WKWebView {
        if let existing = playerWebView { return existing }
        let player = makeWebView()
        view.insertSubview(player, belowSubview: browseContainerView)
        pinToEdges(player)
        playerWebView = player
        if let url = playerURL {
            player.load(URLRequest(url: url))
        }
        return player
    }

    /// 切换可见表面（主线程）。播放表面从不移出层级、从不 hidden：
    /// 「切到浏览」= 浏览表面盖回来；「切到播放」= 浏览表面隐藏、露出下面的播放表面。
    /// 3.2：原生队列已有曲目时，「切到播放」改开原生全屏播放器（特效面），
    /// 网页播放表面不再创建；队列为空（旧路径）才回退网页播放表面。
    private func showSurface(_ surface: String) {
        if surface == "player" {
            if QueueManager.shared.currentTrack != nil {
                RenderStateCenter.shared.setFullPlayerOpen(true)
                return
            }
            _ = ensurePlayerWebView()
            browseContainerView.isHidden = true
        } else {
            browseContainerView.isHidden = false
        }
    }

    // MARK: - M2 原生播放层

    /// 原生迷你条（UIHostingController 悬浮于浏览表面之上）+ 全屏播放容器
    ///（UIHostingController 常驻挂载，位移切换）。双表面壳（LocalServer 与
    /// /__bridge/* 表面切换）原样保留，不拆。
    /// 展开 / 收起唯一来源：RenderStateCenter.isFullPlayerOpen。
    private func setupNativePlayerUI() {
        let renderCenter = RenderStateCenter.shared

        // --- 迷你条：底部悬浮，安全区之上 ---
        let miniView = MiniPlayerView {
            RenderStateCenter.shared.setFullPlayerOpen(true)
        }
        let miniHC = UIHostingController(rootView: miniView)
        miniHC.view.backgroundColor = .clear
        miniHC.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(miniHC)
        view.addSubview(miniHC.view)
        miniHC.didMove(toParent: self)
        NSLayoutConstraint.activate([
            miniHC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            miniHC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            miniHC.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            miniHC.view.heightAnchor.constraint(equalToConstant: 64),
        ])
        miniHC.view.isHidden = true // 无曲目时隐藏
        self.miniPlayerHostingController = miniHC

        // --- 全屏播放容器：常驻挂载，收起时位移出屏 + 宿主隐藏 ---
        let fullView = FullPlayerContainer {
            RenderStateCenter.shared.setFullPlayerOpen(false)
        }
        let fullHC = UIHostingController(rootView: fullView)
        fullHC.view.backgroundColor = .clear
        fullHC.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(fullHC)
        view.addSubview(fullHC.view)
        fullHC.didMove(toParent: self)
        NSLayoutConstraint.activate([
            fullHC.view.topAnchor.constraint(equalTo: view.topAnchor),
            fullHC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fullHC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fullHC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        fullHC.view.isHidden = true
        self.fullPlayerHostingController = fullHC

        // 桥的收起请求（网页 minimize 动作）-> 收起播放页。
        WebEffectBridge.shared.onMinimizeRequested = {
            RenderStateCenter.shared.setFullPlayerOpen(false)
        }

        // 迷你条可见性：3.3 起浏览面原生化，网页播放条已不存在，原生迷你条
        // 是全 App 唯一播放条：有曲目且全屏播放器未展开时显示。
        Publishers.CombineLatest(PlaybackEngine.shared.$currentTrack, renderCenter.$isFullPlayerOpen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track, fullOpen in
                self?.miniPlayerHostingController?.view.isHidden = track == nil || fullOpen
            }
            .store(in: &nativePlayerCancellables)

        // 全屏容器宿主可见性：展开立即显示；收起等 spring 动画（0.35s）后再隐藏。
        renderCenter.$isFullPlayerOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in
                guard let self, let hostView = self.fullPlayerHostingController?.view else { return }
                if open {
                    hostView.isHidden = false
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if !RenderStateCenter.shared.isFullPlayerOpen {
                            hostView.isHidden = true
                        }
                    }
                }
            }
            .store(in: &nativePlayerCancellables)
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

    /// 网页内容进程被系统杀掉后重载出事的表面（3.3 后只剩旧路径的播放表面
    /// 还可能存在；特效面 WebView 由 WebEffectBridge 自己管自愈）。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === playerWebView {
            NSLog("[MainVC] player web content process terminated; reloading player surface")
            if let url = playerURL {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("[MainVC] navigation failed: \(error.localizedDescription)")
    }
}
