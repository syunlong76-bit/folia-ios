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
/// - 触屏思索按钮：左上角悬浮小灯泡钮（ponderTouchButtonEnabled；
///   (70) C 组由右下角「?」钮改版，见 installPonderButtonIfNeeded）。
/// - 启动后直达播放界面：entryDidFinish 在入场播完/关闭的
///   落点调用，开关开且引擎已装载时走宿主既有
///   openNativeStageForBackgroundReturn 通路。
final class WB62HomeWallHooks: NSObject, UIGestureRecognizerDelegate {

    private static var instances: [ObjectIdentifier: WB62HomeWallHooks] = [:]

    private weak var host: HomeWallViewController?
    private var ponderButton: UIButton?
    /// 思索钮变淡计时（3.7 (70) C 组）：出现/交互后 3 秒无
    /// 操作自动变淡，任一交互取消重排。
    private var ponderDimWorkItem: DispatchWorkItem?

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

    // MARK: 思索按钮（(70) C 组改版：小灯泡·左上角·3 秒变淡）
    //
    // Miller 定版规格：原右下角紫色「?」圆钮改为小灯泡图
    // 标（Lucide bulb 形态——包内无 Lucide 字体资产，以 SF
    // Symbol lightbulb 的同形线框字形落，报告已注明）、移
    // 左上角安全区内（右下角让给 (70) 全局宠物召唤钮）；
    // tap 功能不变，仍走 Ponder62.presentList 导览入口。
    // 显隐：出现/任一交互后全透明度，3 秒无操作自动变淡
    // 到 0.25（仍可见、仍可点，不是隐藏/移除）；交互＝钮
    // 自身点按＋墙面任意点按（不消费触摸的观察识别器），
    // 每次交互恢复全透明并重新计时。动效守 iOS 口径：
    // 恢复 0.2s、变淡 0.5s easeOut 缓动。

    private static let ponderDimDelay: TimeInterval = 3
    private static let ponderDimmedAlpha: CGFloat = 0.25

    private func installPonderButtonIfNeeded() {
        guard SettingsStore.ponderTouchButtonEnabled, let host else { return }
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        button.setImage(UIImage(systemName: "lightbulb", withConfiguration: config),
                        for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(red: 0.545, green: 0.486, blue: 0.941, alpha: 0.85)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            guard let self, let host = self.host else { return }
            self.pokePonderButton()
            Ponder62.presentList(from: host)
        }, for: .touchUpInside)
        host.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
            button.leadingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            button.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
        ponderButton = button
        // 墙面任意点按＝交互：不消费触摸的观察识别器，只
        // 负责给变淡计时续命，不拦任何既有手势链。
        let pokeTap = UITapGestureRecognizer(target: self, action: #selector(handlePonderPokeTap))
        pokeTap.cancelsTouchesInView = false
        pokeTap.delegate = self
        host.view.addGestureRecognizer(pokeTap)
        pokePonderButton()
        Breadcrumbs.log("ponder62.button installed")
    }

    @objc private func handlePonderPokeTap() {
        pokePonderButton()
    }

    /// 交互落点：立即恢复全透明（已全透明时只续计时），
    /// 并重排 3 秒变淡。
    private func pokePonderButton() {
        guard let button = ponderButton else { return }
        ponderDimWorkItem?.cancel()
        if button.alpha < 1 {
            UIView.animate(withDuration: 0.2, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                button.alpha = 1
            }
        }
        let work = DispatchWorkItem { [weak button] in
            guard let button, button.window != nil else { return }
            UIView.animate(withDuration: 0.5, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                button.alpha = Self.ponderDimmedAlpha
            }
        }
        ponderDimWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ponderDimDelay,
                                      execute: work)
    }

    // MARK: UIGestureRecognizerDelegate

    /// 不与墙面既有手势抢占：同时识别放行，冲突以既有为准。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
