import UIKit

// SketchbookHost.swift
//
// 日记本抽屉的自包含安装点（(53) 工作流 D）：把手 + 抽屉整套
// 只依赖宿主的一个 UIView，内部自管命中穿透、旁观点按关闭与
// 数据订阅，宿主不需要任何额外接线。删掉这一处安装调用，
// 日记本即整体摘除（照 folia-major「一个功能的代码放在一起」
// 的收口口径）。
//
// 层级建议（协调者合流时）：装进 HomeWallViewController.view，
// 成为该 view 的最上层子视图即可——抽屉只在 HomeWall 的 view
// 层级内活动；工作流 G 的宠物岛在 window.layer 直属子层
// （zPosition 高位、独立于任何 VC 的 view 层级），两者不在
// 同一层级树，互不遮挡、互不抢命中。
//
// 与书库侧栏共存（(54) 工作流 N，照网页版 is-covered）：
// 本宿主装在工作台宿主之后（墙面最上层），侧栏打开时把手会
// 浮压侧栏——须由 HomeWall 在侧栏可见性变化时把抽屉整层藏
// 起来。接法（HomeWallViewController 合流时补两处）：
//   1. 安装处保留返回值：
//      sketchbookDrawer = SketchbookHost.install(into: view)
//      （把现有的 `_ =` 换成持有到 VC 属性上）
//   2. workbench.onSidebarVisibilityChanged 的闭包里加一行：
//      self?.sketchbookDrawer?.setExternallyCovered(open)
//      （open=true 时整层隐藏，false 时原样恢复；抽屉侧 API
//      已备好：SketchbookDrawerView.setExternallyCovered(_:)）

enum SketchbookHost {

    /// 把日记本（左缘把手 + 滑出抽屉）装进宿主视图，返回抽屉
    /// 视图供调用方按需持有（如需编程式开合时调 setOpen）。
    @discardableResult
    static func install(into host: UIView) -> SketchbookDrawerView {
        let drawer = SketchbookDrawerView(frame: host.bounds)
        drawer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(drawer)
        drawer.observeOutsideTaps(on: host)
        Breadcrumbs.log("sketchbook.install")
        return drawer
    }
}
