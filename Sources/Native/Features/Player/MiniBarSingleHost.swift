import Foundation

/// 迷你台单宿主仲裁（3.7 (72)）。
///
/// 病灶（(71) 真机桥日志实证）：主页墙（host=homewall）与
/// 曲目墙（host=wallproto）各有一套完整的迷你台实现，两页
/// 同窗叠放时同活——日志里同一秒两套台一起 expand、一起
/// collapse idle，形态各行其是；被盖住的那套的手势识别器
/// 与计时器仍在跑，与在前者抢响应，疑为「细条时灵时不灵」
/// 的机制根源（诊断档 forensics/log-diagnosis-2026-11-22）。
///
/// 本仲裁只管辖一件事：**同一时刻只有最前宿主能动形态**。
/// - 宿主在 viewWillAppear 认领（claim）、viewWillDisappear
///   让位（release）；后入窗的 presented 页天然后认领。
/// - 形态漏斗 collapseMiniBarIdle / expandMiniBar 在非认领
///   方直接短路（闲置计时到点也无动作），杜绝双宿主同动。
/// - 收起态经 sharedCollapsed 共享：任一宿主经
///   setMiniBarForm 写形态时同步共享旗标；新认领方露面时
///   若自身形态与共享旗标不一致，无动画对齐一次，交接不
///   跳变、不出现「这页细条那页全台」。
/// 播放状态、封面、进度等内容面不归本仲裁（各宿主自有订
/// 阅且只读，无写冲突）。
final class MiniBarSingleHost {

    static let shared = MiniBarSingleHost()

    private init() {}

    /// 当前认领宿主名（"homewall" / "wallproto"）；无宿主
    /// 在场时为 nil（两漏斗都短路，与双宿主同动的旧患无涉：
    /// 无页面在场时本就无人点按）。
    private(set) var activeHost: String?

    /// 跨宿主共享的收起态（初始展开，与两宿主各自初值同）。
    var sharedCollapsed = false

    func claim(_ host: String) {
        activeHost = host
    }

    func release(_ host: String) {
        if activeHost == host { activeHost = nil }
    }

    func isActive(_ host: String) -> Bool {
        activeHost == host
    }
}
