import UIKit

/// (62) WB：HomeWall 侧 WB 消费钩子总装。HomeWall 本体只加
/// 两处 hunk（viewDidLoad 末尾一行 install、入场退场落点一
/// 行 entryDidFinish），其余消费全在本文件：
///
/// - 关闭主页动态背景：墙无独立动态背景层本体，消费落在墙
///   视图层树内「无限循环动画」的启停门控——关时把这类图层
///   动画 speed 归零（静态呈现保留），开时恢复。
/// - 向左滑动打开：左滑手势按 swipeLeftTarget 分发到命令面
///   板 / 速记簿 / 搜索（手势快捷总开关关时不装）。
/// - 长按工具条打开命令面板：长按手势挂在墙视图顶部工具条
///   区域（工具条本体由 WA/WC 维护，本钩子只认其帧区域）。
/// - 触屏思索按钮：悬浮「?」钮（ponderTouchButtonEnabled）。
/// - 启动后直达播放界面：entryDidFinish 在入场播完/关闭的
///   落点调用，开关开且引擎已装载时走宿主既有
///   openNativeStageForBackgroundReturn 通路。
final class WB62HomeWallHooks: NSObject, UIGestureRecognizerDelegate {

    private static var instances: [ObjectIdentifier: WB62HomeWallHooks] = [:]

    private weak var host: HomeWallViewController?
    private var ponderButton: UIButton?

    static func install(in host: HomeWallViewController) {
        let key = ObjectIdentifier(host)
        // 地址复用守卫：旧宿主已释放（host 为 weak、已 nil）
        // 时允许新宿主重装，不被陈旧条目挡住。
        if let existing = instances[key], existing.host != nil { return }
        let hooks = WB62HomeWallHooks(host: host)
        instances[key] = hooks
        hooks.installAll()
    }

    /// 入场退场落点消费（HomeWall hunk 调用）：直达播放界面。
    static func entryDidFinish(in host: HomeWallViewController) {
        guard SettingsStore.openPlayerOnLaunch else { return }
        guard PlaybackEngine.shared.currentTrack != nil else {
            Breadcrumbs.log("launch62.openPlayer skipped=no-track")
            return
        }
        Breadcrumbs.log("launch62.openPlayer after-entry=1")
        host.openNativeStageForBackgroundReturn()
    }

    private init(host: HomeWallViewController) {
        self.host = host
        super.init()
    }

    private func installAll() {
        guard let host else { return }
        applyDynamicBackgroundGate()
        NotificationCenter.default.addObserver(
            self, selector: #selector(dynamicBackgroundChanged),
            name: .foliaHomeDynamicBackgroundChanged, object: nil)

        if SettingsStore.gestureShortcutsEnabled {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft(_:)))
            swipe.direction = .left
            swipe.delegate = self
            host.view.addGestureRecognizer(swipe)

            let longPress = UILongPressGestureRecognizer(
                target: self, action: #selector(handleToolbarLongPress(_:)))
            longPress.minimumPressDuration = 0.6
            longPress.delegate = self
            host.view.addGestureRecognizer(longPress)
            Breadcrumbs.log("shortcuts62.gestures installed swipeLeft=\(SettingsStore.swipeLeftTarget) longPressPalette=\(SettingsStore.longPressToolbarCommandPalette)")
        }
        installPonderButtonIfNeeded()
    }

    // MARK: 动态背景门控

    @objc private func dynamicBackgroundChanged() { applyDynamicBackgroundGate() }

    /// 遍历宿主视图层树：repeatCount=∞ 的动画即动态背景类动
    /// 画，关时 speed=0 冻结在当前帧、开时恢复 1。
    private func applyDynamicBackgroundGate() {
        guard let host else { return }
        let enabled = SettingsStore.homeDynamicBackgroundEnabled
        func walk(_ layer: CALayer) {
            for key in layer.animationKeys() ?? [] {
                if let animation = layer.animation(forKey: key),
                   animation.repeatCount == .infinity {
                    layer.speed = enabled ? 1 : 0
                }
            }
            layer.sublayers?.forEach(walk)
        }
        walk(host.view.layer)
        Breadcrumbs.log("wall62.dynamicBackground enabled=\(enabled)")
    }

    // MARK: 手势分发

    @objc private func handleSwipeLeft(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .recognized, let host else { return }
        switch SettingsStore.swipeLeftTarget {
        case "commandPalette":
            host.miniBarPanelCommand()
        case "search":
            SearchHostPresenter.presentSearch(from: host)
        case "sketchbook":
            if let drawer = Self.findDrawer(in: host.view) {
                drawer.setOpen(true, source: "swipeLeft62")
            } else {
                Breadcrumbs.log("shortcuts62.swipeLeft sketchbook-missing")
                return
            }
        default:
            return
        }
        Breadcrumbs.log("shortcuts62.swipeLeft target=\(SettingsStore.swipeLeftTarget)")
    }

    @objc private func handleToolbarLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              SettingsStore.longPressToolbarCommandPalette,
              let host else { return }
        // 只认顶部工具条区域（安全区顶部 64pt 内），避免与墙
        // 面卡片长按（隐藏管理等既有语义）冲突。
        let point = recognizer.location(in: host.view)
        guard point.y < host.view.safeAreaInsets.top + 64 else { return }
        host.miniBarPanelCommand()
        Breadcrumbs.log("shortcuts62.longPressToolbar palette=1")
    }

    private static func findDrawer(in view: UIView) -> SketchbookDrawerView? {
        if let drawer = view as? SketchbookDrawerView { return drawer }
        for subview in view.subviews {
            if let found = findDrawer(in: subview) { return found }
        }
        return nil
    }

    // MARK: 思索按钮

    private func installPonderButtonIfNeeded() {
        guard SettingsStore.ponderTouchButtonEnabled, let host else { return }
        let button = UIButton(type: .system)
        button.setTitle("?", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 0.85)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            guard let host = self?.host else { return }
            Ponder62.presentList(from: host)
        }, for: .touchUpInside)
        host.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
            button.trailingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            button.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor, constant: -96)
        ])
        ponderButton = button
        Breadcrumbs.log("ponder62.button installed")
    }

    // MARK: UIGestureRecognizerDelegate

    /// 不与墙面既有手势抢占：同时识别放行，冲突以既有为准。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
