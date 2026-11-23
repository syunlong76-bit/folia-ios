import UIKit

/// (62) WB：HomeWall 侧 WB 消费钩子总装。HomeWall 本体只加
/// 两处 hunk（viewDidLoad 末尾一行 install、入场退场落点一
/// 行 entryDidFinish），其余消费全在本文件：
///
/// - 关闭主页动态背景：墙无独立动态背景层本体，消费落在墙
///   视图层树内「无限循环动画」的启停门控——关时把这类图层
///   动画 speed 归零（静态呈现保留），开时恢复。
/// - 向左滑动打开：(75) 摘除（Miller 2026-11-23 20:17 真
///   机实报：主页墙上左滑本应平移墙面，却被本手势抢去弹
///   出命令面板、还自动聚焦搜索框拉起键盘）。墙面水平滑
///   动自此归墙平移所有；命令面板只许从工具条明确入口
///   （「…」/命令键）或长按工具条（自有开关）打开。
///   swipeLeftTarget 存储键保留备查、自此无任何消费者，
///   设置页「向左滑动打开」行已同步摘除（防假生效）。
/// - 长按工具条打开命令面板：长按手势挂在墙视图顶部工具条
///   区域（工具条本体由 WA/WC 维护，本钩子只认其帧区域）。
/// - 触屏思索按钮：(73) 撤除——独立浮灯泡收进工作台顶部
///   控制台作「导播台」入口（WorkbenchOverlayHostView 的
///   .guide 行 → Ponder62.presentList），本文件不再安装。
/// - 启动后直达播放界面：entryDidFinish 在入场播完/关闭的
///   落点调用，开关开且引擎已装载时走宿主既有
///   openNativeStageForBackgroundReturn 通路。
final class WB62HomeWallHooks: NSObject, UIGestureRecognizerDelegate {

    private static var instances: [ObjectIdentifier: WB62HomeWallHooks] = [:]

    private weak var host: HomeWallViewController?

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
            let longPress = UILongPressGestureRecognizer(
                target: self, action: #selector(handleToolbarLongPress(_:)))
            longPress.minimumPressDuration = 0.6
            longPress.delegate = self
            host.view.addGestureRecognizer(longPress)
            Breadcrumbs.log("shortcuts62.gestures installed longPressPalette=\(SettingsStore.longPressToolbarCommandPalette)")
        }
        // (75) 左滑触发摘除自证：本钩子不再安装任何滑动识
        // 别器——真机日志有此行即证明在跑的包里墙面左滑只
        // 余墙体平移、无面板触发源。与「wall.menu.panel
        // present kind=command62」对位：该行自此只许由工
        // 具条入口/长按工具条/S 键触发。
        Breadcrumbs.log("swipe75.off host=homewall")
        // (73) 独立浮灯泡已撤除（收进工作台控制台「导播
        // 台」行），此处不再安装任何悬浮钮。
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

    // (75) handleSwipeLeft 已整段摘除（见文件头）：连同其
    // 独占的 findDrawer 递归查找一并删除，速记簿改走搜索
    // 行尾按钮等既有明确入口，不再占墙面滑动。

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

    // MARK: UIGestureRecognizerDelegate

    /// 不与墙面既有手势抢占：同时识别放行，冲突以既有为准。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
