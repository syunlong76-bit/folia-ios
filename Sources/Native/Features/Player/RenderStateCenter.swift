import Combine
import Foundation
import UIKit

/// 渲染激活状态的 app 级唯一事实源（M2，native-arch.md §10）。
///
/// 汇总三条件，缺一不可：
///   1. 前台（App 处于活跃状态）
///   2. 播放页展开（原生 FullPlayerContainer 打开）
///   3. 未休眠（睡眠定时器未触发）
///
/// `WebEffectBridge` 与未来原生特效层（Metal / 粒子 / 城市场景）同源订阅
/// 本中心，不再各自私自判断 renderState。
/// 前后台信号默认取 UIApplication 通知；SwiftUI 侧如有 scenePhase，
/// 可再调 `setForeground(_:)` 显式喂入（以后者为准，两者都写同一字段）。
final class RenderStateCenter: ObservableObject {
    static let shared = RenderStateCenter()

    /// 当前是否允许特效面渲染（rAF / CSS 动画可跑）。
    @Published private(set) var isActive: Bool = false

    /// 播放页是否展开。由 MainViewController（迷你条点按 / 容器收起）写入。
    @Published private(set) var isFullPlayerOpen: Bool = false

    /// App 是否在前台活跃。
    @Published private(set) var isForeground: Bool = true

    /// 是否处于休眠（睡眠定时器触发后为 true）。M2 默认 false，睡眠定时器在 M3 接入。
    @Published private(set) var isSleeping: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // 前后台：默认走 UIApplication 通知；初始值按当前 state 取一次，
        // 避免冷启动时在后台态误判为前台。
        isForeground = UIApplication.shared.applicationState == .active

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.setForeground(true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.setForeground(false) }
            .store(in: &cancellables)

        recompute()
    }

    /// 播放页展开 / 收起。唯一写入入口（MainViewController 调用）。
    func setFullPlayerOpen(_ open: Bool) {
        guard isFullPlayerOpen != open else { return }
        isFullPlayerOpen = open
        recompute()
    }

    /// 前台 / 后台。SwiftUI scenePhase 侧可显式喂入。
    func setForeground(_ foreground: Bool) {
        guard isForeground != foreground else { return }
        isForeground = foreground
        recompute()
    }

    /// 休眠 / 唤醒。睡眠定时器（M3）调用；M2 保持 false。
    func setSleeping(_ sleeping: Bool) {
        guard isSleeping != sleeping else { return }
        isSleeping = sleeping
        recompute()
    }

    private func recompute() {
        let next = isForeground && isFullPlayerOpen && !isSleeping
        if isActive != next {
            isActive = next
        }
    }
}
