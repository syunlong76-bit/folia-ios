import Foundation
import QuartzCore
import UIKit

/// (62) WB 簇：降低动态统一判定层（§4.4 六项 + 假生效 C1 做真）。
///
/// 门控语义（任务定死）：
/// - `SettingsStore.reduceMotionFollowSystem`（基座既有键）开
///   （默认）＝全局跟随系统 `UIAccessibility.isReduceMotionEnabled`，
///   各细分开关不参与判定；
/// - 关＝改读各细分开关（Key62B 六键），系统值不参与判定。
/// 此前 C1 假生效的病根是墙/舞台各点直读系统值、本开关无门
/// 控语义；本层是唯一判定面，消费点一律走 `reduced(_:)`。
enum FoliaMotion62 {

    enum Feature: String {
        case queueCollage      // 队列拼贴
        case mixTransition     // 混音过渡
        case playlistExpand    // 歌单展开转场
        case monetDrift        // Monet 背景漂移
        case microEffects      // 界面微动效
        case settingsScroll    // 设置页平滑滚动
    }

    /// 统一判定：该 feature 当前是否应降低动态。
    static func reduced(_ feature: Feature) -> Bool {
        if SettingsStore.reduceMotionFollowSystem {
            return UIAccessibility.isReduceMotionEnabled
        }
        switch feature {
        case .queueCollage: return SettingsStore.reduceMotionQueueCollage
        case .mixTransition: return SettingsStore.reduceMotionMixTransition
        case .playlistExpand: return SettingsStore.reduceMotionPlaylistExpand
        case .monetDrift: return SettingsStore.reduceMotionMonetDrift
        case .microEffects: return SettingsStore.reduceMotionMicroEffects
        case .settingsScroll: return SettingsStore.reduceMotionSettingsScroll
        }
    }

    /// 帧率限制的 DisplayLink 口径：未开限制返回 nil（系统
    /// 默认全速）；开时按档位给 preferredFrameRateRange（下限
    /// 取档位的一半留弹性、上限与 preferred 钉档位）。
    static func frameRateRange() -> CAFrameRateRange? {
        guard SettingsStore.frameRateLimitEnabled else { return nil }
        let fps = Float(SettingsStore.frameRateLimitFPS)
        return CAFrameRateRange(minimum: max(fps / 2, 10), maximum: fps, preferred: fps)
    }

    /// 给任意 CADisplayLink 套当前帧率口径（开/关都可调，关
    /// 时恢复系统默认范围）。StageVC 的 DisplayLink 归 WA，
    /// WA 可直接调本函数或读 SettingsStore 两访问器自设。
    static func applyFrameRate(to link: CADisplayLink) {
        if let range = frameRateRange() {
            link.preferredFrameRateRange = range
        } else {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 10, maximum: 120, preferred: 120)
        }
    }

    /// 静态模式总判定（§4.4）：协议层统一标志——渲染器/驱动
    /// 读本值决定是否停逐帧推进；开关变更经通知
    /// .foliaStaticModeChanged 广播，StageVC（WA）订阅停其
    /// DisplayLink，StageProgressDriver 在 WB 内直读停链。
    static var isStaticModeEnabled: Bool { SettingsStore.staticModeEnabled }

    static func setStaticMode(_ enabled: Bool) {
        SettingsStore.staticModeEnabled = enabled
        Breadcrumbs.log("motion62.staticMode value=\(enabled)")
        NotificationCenter.default.post(name: .foliaStaticModeChanged, object: nil)
    }
}

extension Notification.Name {
    /// 静态模式变更（62 WB）：StageProgressDriver 已直读消费；
    /// StageVC（WA 文件域）订阅后停/启其舞台 DisplayLink。
    static let foliaStaticModeChanged = Notification.Name("foliaStaticModeChanged")
    /// 后台节流策略变更（62 WB）：aggressive 时驱动/引擎进
    /// 后台即停逐帧链，standard 时仅生命周期代偿。
    static let foliaBackgroundThrottleChanged =
        Notification.Name("foliaBackgroundThrottleChanged")
    /// 主页动态背景开关变更（62 WB）：HomeWall 钩子消费。
    static let foliaHomeDynamicBackgroundChanged =
        Notification.Name("foliaHomeDynamicBackgroundChanged")
    /// 外部舞台数据到达（62 WB）：StageDataSource62 发出，
    /// userInfo = ["title": String, "artist": String,
    /// "progress": Double]，舞台信息卡数据源（WA）可订阅。
    static let foliaExternalStageData = Notification.Name("foliaExternalStageData")
}

/// (62) WB：后台节流的用户可控层（§4.4）。生命周期代偿（失
/// 活停 DisplayLink）是既有行为；本层补策略：aggressive 时进
/// 后台即广播停链（StageProgressDriver 订阅后停链、回前台按
/// 宿主 start 节奏恢复），standard 时不额外干预。iOS 后台任
/// 务本身由系统接管的部分不在本层能力内（设置行 hint 标注）。
enum BackgroundThrottle62 {

    static func install() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { _ in
                let policy = SettingsStore.backgroundThrottlePolicy
                Breadcrumbs.log("throttle62.background policy=\(policy)")
                if policy == "aggressive" {
                    NotificationCenter.default.post(
                        name: .foliaBackgroundThrottleChanged,
                        object: nil, userInfo: ["state": "background-aggressive"])
                }
            }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { _ in
                if SettingsStore.backgroundThrottlePolicy == "aggressive" {
                    NotificationCenter.default.post(
                        name: .foliaBackgroundThrottleChanged,
                        object: nil, userInfo: ["state": "foreground"])
                }
            }
    }
}

/// (66) 后台节流的活动信号面：OBS 浏览器源客户端在场判
/// 据——LocalServer 每次服务 /obs 请求时登记时刻，「最近
/// 12 秒内有拉取」判在场（OBS 页 5 秒自动刷新，两轮未到
/// 即离场）。消费：MediaCache62 自动回填在节流 aggressive
/// 且 OBS 在场时推迟；设置行（直播与 OBS 组）状态回显。
/// （(66) 初版曾另建同名文件致重复声明，已并回本枚举。）
extension BackgroundThrottle62 {

    private static var lastOBSActivity: Date? {
        get { UserDefaults.standard.object(forKey: "folia.obs.lastActivity") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "folia.obs.lastActivity") }
    }

    /// LocalServer /obs 路由调用。
    static func noteOBSActivity() {
        lastOBSActivity = Date()
    }

    /// OBS 客户端是否在场（最近 12 秒内拉过 /obs）。
    static var obsClientActive: Bool {
        guard let last = lastOBSActivity else { return false }
        return Date().timeIntervalSince(last) < 12
    }

    /// 后台工作是否可执行：策略 standard → 恒可；
    /// aggressive 且 OBS 在场 → 不可（推迟）。
    static var allowsBackgroundWork: Bool {
        guard SettingsStore.backgroundThrottlePolicy == "aggressive" else { return true }
        return !obsClientActive
    }
}

/// (62) WB：歌词画布统一口径（§4.4 分辨率做全 + 抗锯齿）。
///
/// - 分辨率：全局键 lyricRenderScale（基座既有）的消费汇聚
///   点。Monet 已在自己的烘焙处乘本键（MonetStageRenderer 两
///   处 bakeScale）；本层供其余文本烘焙入口统一取倍率——
///   StageTextKit 的 bitmapImage 是全渲染器共用的栅格入口，
///   WB 在该入口按「调用方未叠加全局键时」口径不可判，故采
///   用显式面：`effectiveScale(base:)` 由烘焙调用点取倍率，
///   GlowWordEngine 的超采样推导已叠加本键（见其 init hunk）。
/// - 抗锯齿：全局键 lyricAntialiasEnabled；关时烘焙上下文关
///   闭抗锯齿（shouldAntialias=false）。逐样式调参面板的
///   antialias 值仍优先（调用点自带值时不覆盖）。
enum LyricCanvas62 {

    /// 全局分辨率倍率（0.5...2，基座键吸附档位）。
    static var globalScale: CGFloat { CGFloat(SettingsStore.lyricRenderScale) }

    /// 烘焙有效倍率 = 调用方基础倍率 × 全局档位。
    static func effectiveScale(base: CGFloat) -> CGFloat {
        base * globalScale
    }

    /// 全局抗锯齿口径：供 CGContext 烘焙入口设置
    /// shouldAntialias。逐样式 antialias 优先的调用点不走此面。
    static var edgeAntialiasingEnabled: Bool { SettingsStore.lyricAntialiasEnabled }

    static func applyAntialias(to context: CGContext) {
        context.setShouldAntialias(edgeAntialiasingEnabled)
        context.setAllowsAntialiasing(edgeAntialiasingEnabled)
    }

    // MARK: - (66) 统一读取口径（逐样式覆盖 × 全局键）

    /// 分辨率统一解析：逐样式覆盖为数值串（"0.75"/"1"/"1.5"
    /// 等）时覆盖全局档；"global"/nil/不可解析时回全局档
    /// lyricRenderScale。此前各渲染器各行其是（Nebbia 的
    /// "global" 曾落成 ×1 忽略全局档），(66) 起一律经此面。
    static func resolvedScale(styleOverride raw: String?) -> CGFloat {
        guard let raw, raw != "global", let value = Double(raw) else {
            return globalScale
        }
        return CGFloat(value)
    }

    /// 抗锯齿统一解析：逐样式覆盖 "off" 关 / "on" 开优先；
    /// "global"/nil/余值回全局键 lyricAntialiasEnabled。
    /// 此前 Cadenza/Diorama 以 `!= "off"` 判定，全局键关闭
    /// 时样式 "global" 仍开抗锯齿——(66) 修正。
    static func resolvedAntialias(styleOverride raw: String?) -> Bool {
        switch raw {
        case "off": return false
        case "on": return true
        default: return edgeAntialiasingEnabled
        }
    }
}
