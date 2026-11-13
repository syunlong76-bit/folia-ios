import UIKit
import WebKit

/// 主界面：全屏 WKWebView + 右边缘垂直居中的半透明齿轮按钮（打开原生设置页）。
/// WebView 只加载本机回环地址 http://127.0.0.1:<port>/，内容由 LocalServer 提供。
final class MainViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // --- WKWebView ---
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // 音乐播放器：允许自动播放带声媒体，不强制要求用户手势
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
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

        // --- 设置齿轮：右边缘、垂直居中、半透明 ---
        let gear = UIButton(type: .system)
        gear.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        gear.tintColor = .white
        gear.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        gear.layer.cornerRadius = 20
        gear.alpha = 0.85
        gear.accessibilityLabel = "设置"
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(gear)
        NSLayoutConstraint.activate([
            gear.widthAnchor.constraint(equalToConstant: 40),
            gear.heightAnchor.constraint(equalToConstant: 40),
            gear.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            gear.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // --- 启动本地服务器，就绪后加载首页 ---
        LocalServer.shared.onReady = { [weak self] port in
            guard let self = self else { return }
            if let url = URL(string: "http://127.0.0.1:\(port)/") {
                self.webView.load(URLRequest(url: url))
            }
        }
        LocalServer.shared.start()
    }

    @objc private func openSettings() {
        let settings = SettingsViewController()
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true)
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

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        statusLabel.isHidden = false
        statusLabel.text = "页面加载失败：\(error.localizedDescription)\n可尝试关闭应用后重新打开"
    }
}
