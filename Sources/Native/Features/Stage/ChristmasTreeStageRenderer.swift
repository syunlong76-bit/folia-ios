import UIKit
import QuartzCore

// 圣诞树 christmas（(103) 全量重做）：过审网页样板（slug
// sheng-dan-guang-li-zi-yang-ban，新管线 GLB 小镇＋光粒子树）
// 的 Metal 原生移植。路线由 Miller 2026-11-29 拍板「走 Metal」
// （自研 GLB 加载器），DS 对抗评审对账存 folia-deploy/
// ds-review-2026-11-29-christmas-metal.md。
//
// 本类只做宿主协议适配（类名/注册面不变）：
//  - 场景/渲染全部在 ChristmasScene103/（XmasGLB103 加载器、
//    XmasBake103 烘焙、XmasParticles103 池/雪/歌词状态机、
//    XmasMetalEngine103 引擎、XmasShaders103 着色器库）。
//  - 旧 (93)–(100) 的 2D 精灵实现（XmasMetal97）自本版起不再
//    被引用，文件保留备查（任务书口径：可停用、不删）。
// 时钟纪律不变：只消费宿主 frameTick，不自建 CADisplayLink。

final class ChristmasTreeStageRenderer: LyricStageRenderer {

    let view: UIView
    let capabilities = LyricStageCapabilities(
        supportsWordSync: false, requiresSpectrum: false, supportsLineSeek: false)

    private let engine = XmasMetalEngine103()
    private var context: LyricStageContext?
    private var builtTrackId: String? = nil
    private var builtLineCount = -1

    init() {
        view = engine.view
    }

    func mount(context: LyricStageContext) {
        self.context = context
        engine.assemble()
        Breadcrumbs.log("p105 xmas on fp=\(Breadcrumbs.footprintMB97())")
    }

    func applySnapshot(_ snapshot: LyricStageSnapshot) {
        if snapshot.track?.id != builtTrackId || snapshot.lines.count != builtLineCount {
            builtTrackId = snapshot.track?.id
            builtLineCount = snapshot.lines.count
        }
        engine.setSnapshot(lines: snapshot.lines, trackId: snapshot.track?.id)
    }

    func setLifecycle(_ state: LyricStageLifecycleState, active: Bool) {
        engine.setActive(active && state != .destroyed)
    }

    func frameTick(position: TimeInterval) {
        engine.tick(position: position)
    }

    func unmount() {
        engine.teardown()
        context = nil
    }
}
