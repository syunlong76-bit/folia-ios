import UIKit

/// M1 阶段 3：墙布局（规格 v2.1 §4 + R5）。UICollectionView 只做
/// cell 复用容器；几何全部来自 WallGeometry（已与原版 TS 数值对齐）。
///
/// 索引命名空间（R5 冻结）：indexPath.item 只代表实例槽位（当前窗口
/// 的 instances 数组下标），不代表内容位置；内容由槽位映射到周期
/// 平铺中的实例。numberOfItems = instances.count（≤400）。
///
/// 实例计算不依赖数据源时序：refreshInstances() 由 VC 在输入变化
/// （数据到达/绕回/展开/尺寸变化）时显式调用，prepare() 只在输入
/// 指纹变化时重算——两条路都安全，数据源读到的永远是最新窗口。
///
/// 旋转冻结（3.7 (57) 工作流 A2）：旋转期间 VC 经
/// setRotationFrozen(true) 冻结本布局——shouldInvalidateLayout
/// 恒 false、refreshInstances 直接保留既有实例/属性（首算未完成
/// 时不冻，见彼处守卫）；旋转落地后 VC 解冻并 invalidateLayout
/// 一次收尾。指纹不含 bounds 原始 W/H、只含尺寸类别（见
/// sizeClass），纯旋转（W/H 互换）在转置安全线内不重算 lattice。
///
/// 相机模型：contentSize = 3×3 个单元（cell）的视图空间；初始
/// contentOffset 停在中心单元。worldOrigin 是视口左上角的世界坐标，
/// 属性帧 = (世界坐标 − worldOrigin) × scale + contentOffset——视觉
/// 位置与 contentOffset 相消，滚动时由 VC 的绕回逻辑成对调整
/// contentOffset 与 worldOrigin，画面不跳。
///
/// 滚动平移化（3.7 (58) 定稿③，DS Pro 对账）：(57) 前指纹含
/// worldOrigin，滚动每事件指纹必变 → 全量 layoutLattice 重算＋
/// ≤400 属性重建、间或 reloadData，是滚动卡顿的架构主因。(58)
/// 改为：缓存键剔除 worldOrigin（原点只决定帧平移、不决定实例
/// 集），实例集按（dataVersion=条目身份代指/计数/缩放/尺寸类别/
/// 展开态）缓存于 anchorOrigin；同键下滚动只按帧公式重建属性
/// 帧——全集帧恒为同一刚体平移，与「容器 transform 平移」等价
/// （UICollectionView 无可变换的内容容器，帧算术即其落点），
/// lattice 零重算、实例身份零变化。漂移（worldOrigin 相对锚点）
/// 超过缓存覆盖（cacheOverscan − 安全边距）且未展开时，同帧
/// rebase：以当前原点为新锚全量重算一次（计数落 wall.cache
/// rebase、逐秒入 wall.scroll）。展开态禁 rebase（展开卡须视觉
/// 静止、其相邻 tile 不回收——定稿口径）。缓存 overscan 自适应
/// 放大（2400 起、枚举触顶 400 则降档 1600/900）：实测密度下
/// （pitch=136、单元 9792×5440）周期平铺的真周期是整个单元、
/// 远大于 overscan，逐 tile 回收不成立，覆盖深度即回收上限，
/// 按定稿「按实际 lattice 密度核定、不许静默超限」落此实现；
/// 标准验收 fling（≥1200pt/s×1.5s ≈ 2300 世界单位）全程在
/// 2400 覆盖内、零 rebase。
///
/// 呈现通路纠正（3.7 (59) 工作流一，(58) 真机证伪）：(58) 注释
/// 曾断言「同键只重建 attributesCache、帧算术即平移落点」——
/// 真机录屏证伪：主页墙静止约 4.5s 后一次性瞬移。定案机制：
/// UICollectionView 对已可见 cell 的属性帧只在布局失效
/// （invalidateLayout）或 reloadData 时才重读；同键路径既不
/// 失效也不 reload（身份恒不变），attributesCache 写得再新也
/// 没人读——画面冻结，直到漂移超限触发 rebase＋身份变化＋
/// reloadData 才整屏跳到当前位。(57) 是靠指纹含 worldOrigin、
/// 每事件重算滑窗集、首/尾/计数频繁变化带来的频繁 reloadData
/// 掩盖了这一点（代价是每事件全量 lattice 的卡顿）。(59) 修
/// 法：帧重建照旧（零 lattice），呈现改由 VC 滚动回调在同键
/// 路径显式 invalidateLayout() 承担——CV 本回合布局pass重读
/// 全部可见属性帧、只换帧不重配 cell（无 reloadData、无图
/// 像重载），位移同帧上屏；身份变化路径仍走 reloadData。
final class WallLayout: UICollectionViewLayout {

    var totalEntries: Int = 0
    var metrics = WallMetrics()
    /// 相机 scale（按视口宽断点：<640 → 0.52、<1100 → 0.64、其余 0.76）。
    var cameraScale: Double = 0.52
    /// 视口左上角的世界坐标（CAMERA_HOME 起点 34, 80）。
    var worldOrigin = CGPoint(x: 34, y: 80)
    /// 当前展开的实例 id（nil = 无展开）。
    var expandedInstanceId: String?
    /// 条目身份代指（(58)）：VC 在数据变更点（与 totalEntries
    /// 同批赋值处）递增；实例集缓存键据此失效——条目被替换
    /// （同计数换内容）时实例的 queueIndex→条目映射随之作废。
    var dataVersion: Int = 0

    private(set) var instances: [QueueInstance] = []
    private var attributesCache: [UICollectionViewLayoutAttributes] = []
    /// 实例集缓存键（(58)：不含 worldOrigin，见类头注）。
    private var lastKey: String?
    /// 当前实例集的锚点原点（计算该集时的 worldOrigin）。
    private var anchorOrigin = CGPoint(x: 34, y: 80)
    /// 当前实例集计算时用的 overscan（覆盖深度，世界单位）。
    private var cacheOverscan: Double = 900
    /// layoutLattice 全量重算累计次数（面包屑对账用，只增不减）。
    private(set) var latticeComputeCount = 0
    /// 同帧 rebase 累计次数（(58)：覆盖耗尽时的锚点重置）。
    private(set) var rebaseCount = 0
    /// 最近一次 refreshInstances 的实例身份（instanceId 序列）
    /// 是否变化；prepare() 驱动的变化由 VC 在旋转收尾等点位
    /// 经此旗标补读（滚动路径直接用 refreshInstances 返回值）。
    private(set) var lastIdentityChanged = false
    /// 旋转冻结（(57) A2）：true 时不失效、不重算，保留落定前
    /// 最后一套实例/属性供系统旋转动画变换呈现；(58) 起主页墙
    /// 与曲目墙都在 viewWillTransition 期间置位。
    private var isRotationFrozen = false

    func setRotationFrozen(_ frozen: Bool) {
        isRotationFrozen = frozen
    }

    var geometry: LatticeGeometry {
        WallGeometry.latticeGeometry(totalEntries: totalEntries, metrics: metrics)
    }

    /// 一个单元的视图尺寸（断点/scale 变化时 VC 据此重对齐 offset）。
    var cellViewSize: CGSize {
        CGSize(width: geometry.cellWidth * cameraScale, height: geometry.cellHeight * cameraScale)
    }

    override var collectionViewContentSize: CGSize {
        let cell = cellViewSize
        return CGSize(width: cell.width * 3, height: cell.height * 3)
    }

    /// 尺寸类别（(57) A2，指纹/失效判定共用口径）：不取 bounds
    /// 原始 W/H，取长/短边的量级分档（128pt 一档，与方向无关的
    /// 规范形）——纯旋转 W/H 互换类别不变；档内小幅尺寸变化的
    /// 世界量差 ≤128/cameraScale，远小于 layoutLattice 的
    /// overscan=900，旧实例集仍完整覆盖新可见域（仅 overscan
    /// 外缘的预取实例可不同、不可见）。转置安全线：长短边世界
    /// 量差 (long−short)/cameraScale ≤ overscan(900) 时转置复用
    /// 成立（14 Pro：(852−393)/0.52≈882 ≤ 900）；超线机型类别
    /// 带方向位，旋转时类别变化、落地重算一次（仍不在旋转
    /// 动画期间算，冻结口径不变）。
    private func sizeClass(for size: CGSize) -> String {
        let shortEdge = Double(min(size.width, size.height))
        let longEdge = Double(max(size.width, size.height))
        let shortBucket = Int(shortEdge / 128)
        let longBucket = Int(longEdge / 128)
        let extentWorld = (longEdge - shortEdge) / max(cameraScale, 0.01)
        if extentWorld <= 900 {
            return "u\(shortBucket)-\(longBucket)"
        }
        let orient = size.width >= size.height ? "L" : "P"
        return "\(orient)\(shortBucket)-\(longBucket)"
    }

    /// 实例集缓存键（(58)）：只含决定「窗口里有哪些实例」的
    /// 输入——条目身份（dataVersion）/计数/缩放/尺寸类别/展开
    /// 态。**不含 worldOrigin**：原点只决定帧平移、不决定集
    /// （(57) 前含原点，滚动每事件必变、全量重算，定稿③主因）。
    private func cacheKey() -> String {
        guard let collectionView else { return "" }
        return [dataVersion, totalEntries].map { "\($0)" }.joined(separator: "|")
            + "|" + "\(cameraScale)"
            + "#" + sizeClass(for: collectionView.bounds.size)
            + "#" + (expandedInstanceId ?? "-")
    }

    private var expandedRects: [String: WallRectD] = [:]

    /// 以给定锚点全量计算实例集（自适应 overscan：2400 起，
    /// 枚举触顶 maxRenderedInstances 时 layoutLattice 按行主序
    /// 截断、覆盖变不对称，降档 1600/900 重试；900 档触顶与
    /// (57) 前行为一致、接受）。每次调用 latticeComputeCount+1。
    private func computeInstanceSet(anchor: CGPoint)
        -> (list: [QueueInstance], rects: [String: WallRectD], overscan: Double) {
        guard let collectionView else { return ([], [:], 900) }
        let viewSize = collectionView.bounds.size
        var overscan = 2400.0
        while true {
            latticeComputeCount += 1
            let worldBounds = WallRectD(
                x: Double(anchor.x), y: Double(anchor.y),
                width: Double(viewSize.width) / cameraScale,
                height: Double(viewSize.height) / cameraScale
            )
            let list = WallGeometry.layoutLattice(
                geometry: geometry, totalEntries: totalEntries,
                bounds: worldBounds, overscan: overscan, metrics: metrics
            )
            if list.count >= WallGeometry.maxRenderedInstances, overscan > 900 {
                overscan = overscan == 2400 ? 1600 : 900
                continue
            }
            var rects: [String: WallRectD] = [:]
            if let expandedId = expandedInstanceId,
               let active = list.first(where: { $0.instanceId == expandedId }) {
                rects = WallGeometry.layoutExpandedBlock(
                    geometry: geometry, totalEntries: totalEntries,
                    active: active, metrics: metrics
                )
            }
            return (list, rects, overscan)
        }
    }

    /// 按当前实例集与当前 worldOrigin/contentOffset 重建属性
    /// 帧（≤400 个矩形映射，纯算术）。滚动同键路径只走这里：
    /// 全集帧相对上一帧恒为同一刚体平移（帧公式对 worldOrigin
    /// 与 contentOffset 均线性），即定稿③的「平移」步。
    private func rebuildAttributes() {
        guard let collectionView else { attributesCache = []; return }
        let offset = collectionView.contentOffset
        attributesCache = instances.enumerated().map { index, instance in
            let rect = expandedRects[instance.instanceId] ?? instance.rect
            let attrs = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            attrs.frame = CGRect(
                x: (rect.x - Double(worldOrigin.x)) * cameraScale + Double(offset.x),
                y: (rect.y - Double(worldOrigin.y)) * cameraScale + Double(offset.y),
                width: rect.width * cameraScale,
                height: rect.height * cameraScale
            )
            attrs.zIndex = (instance.instanceId == expandedInstanceId) ? 1 : 0
            return attrs
        }
    }

    /// 刷新实例集。返回实例身份（instanceId 序列）本次是否
    /// 变化——VC 据此决定 reloadData（身份不变不许 reload：
    /// 下标→实例映射仍成立、帧已由本方法更新；但帧更新只是
    /// 写进 attributesCache，VC 在同键滚动路径还须
    /// invalidateLayout 让 CV 重读上屏，见类头 (59) 注）。
    /// 三条路径：
    /// 键变 → 全量重算（数据/类别/展开/缩放事件，非滚动期）；
    /// 同键但漂移超覆盖且未展开 → 同帧 rebase（全量重算到新
    /// 锚，rebaseCount+1）；同键其余 → 纯帧平移（零 lattice
    /// 重算、零身份变化）。数据源计数与实例集的同步由 VC 在
    /// 身份变化点调 reloadData 保证。
    @discardableResult
    func refreshInstances() -> Bool {
        guard let collectionView, totalEntries > 0 else {
            let changed = !instances.isEmpty
            instances = []
            attributesCache = []
            expandedRects = [:]
            lastKey = nil
            lastIdentityChanged = changed
            return changed
        }
        // 旋转冻结（(57) A2）：保留既有实例/属性整套不动，等
        // 落地解冻后的一次 invalidate 收尾。首算守卫：lastKey
        // 为 nil（冷启首排/数据清零后）时不冻——首排必算，不许
        // 被冻结误挡成空墙。
        if isRotationFrozen, lastKey != nil {
            lastIdentityChanged = false
            return false
        }
        let key = cacheKey()
        if key != lastKey {
            let oldIds = instances.map(\.instanceId)
            let result = computeInstanceSet(anchor: worldOrigin)
            instances = result.list
            expandedRects = result.rects
            anchorOrigin = worldOrigin
            cacheOverscan = result.overscan
            lastKey = key
            Breadcrumbs.log("wall.cache compute overscan=\(Int(result.overscan)) instances=\(result.list.count)")
            rebuildAttributes()
            let changed = oldIds != instances.map(\.instanceId)
            lastIdentityChanged = changed
            return changed
        }
        // 同键：覆盖检查。漂移 = 当前原点相对锚点的位移；缓存
        // 集覆盖锚点可见窗 ±cacheOverscan，留 120 世界单位安
        // 全边距（布局查询rect 恒为可见域本身，边距只防浮点
        // 与档内尺寸微差）。展开态禁 rebase：展开实例可能已
        // 不在新窗内、重算会让展开块凭空消失（定稿口径）。
        // 呈现位不变式（(59) 代码级保证）：rebase 只换锚点与
        // 实例集，不写 worldOrigin、不写 contentOffset；而属
        // 性帧是（tile 世界矩形, worldOrigin, contentOffset）
        // 的纯函数（见 rebuildAttributes），故 rebase 前后同
        // 时在集内的 tile 帧逐位相同、屏幕位置不动；当前可见
        // tile 恒在新锚可见窗 ±900（最小 overscan 档）之内，
        // 必留集内——rebase 只增删不可见的预取实例，绝不移动
        // 任何可见内容。身份变化引发的 reloadData 因此只是换
        // 数据源映射，不是视觉跳变。
        let driftX = abs(worldOrigin.x - anchorOrigin.x)
        let driftY = abs(worldOrigin.y - anchorOrigin.y)
        let limit = CGFloat(cacheOverscan - 120)
        if expandedInstanceId == nil, driftX > limit || driftY > limit {
            let oldIds = instances.map(\.instanceId)
            let result = computeInstanceSet(anchor: worldOrigin)
            instances = result.list
            expandedRects = result.rects
            anchorOrigin = worldOrigin
            cacheOverscan = result.overscan
            rebaseCount += 1
            Breadcrumbs.log("wall.cache rebase n=\(rebaseCount) overscan=\(Int(result.overscan)) instances=\(result.list.count)")
            rebuildAttributes()
            let changed = oldIds != instances.map(\.instanceId)
            lastIdentityChanged = changed
            return changed
        }
        rebuildAttributes()
        lastIdentityChanged = false
        return false
    }

    override func prepare() {
        super.prepare()
        refreshInstances()
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributesCache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < attributesCache.count else { return nil }
        return attributesCache[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // 旋转冻结期恒不失效（(57) A2）：旋转动画的每一中间
        // bounds 都不许触发 prepare/全量重算，落地由 VC 解冻后
        // 显式 invalidateLayout 一次收尾。
        if isRotationFrozen { return false }
        guard let collectionView else { return true }
        // 仅尺寸类别变化才失效：滚动只改 origin（类别不变）——
        // 滚动路径的属性刷新由 VC 折叠逻辑显式调
        // refreshInstances 承担（offset 恒钉中心单元、帧公式不
        // 依赖 bounds），此处不失效不丢帧；档内尺寸微调同理，
        // 覆盖论证见 sizeClass。
        return sizeClass(for: newBounds.size) != sizeClass(for: collectionView.bounds.size)
    }
}

/// 滚动帧统计（3.7 (58) 定稿③）：逐秒汇总面包屑 wall.scroll——
/// 帧间隔 p95/p99/max、hitch（>16.7ms）占比、scrollViewDidScroll
/// 单次耗时 max、窗口内 lattice 重算/rebase/reloadData 增量、
/// 身份变化旗标。VC 在滚动回调里 noteScrollActivity 喂入（首
/// 次喂入启动 CADisplayLink 与统计窗）；末次活动 2s 后冲刷尾
/// 窗并自停。基线口径：(57) 无此面包屑，其同口径基线为「每滚
/// 动事件 lattice 重算 1 次、reloadData 随身份变化间或」——
/// (58) 真机判读以本行 lattice=0（滚动窗内）/reload ≤1 次每
/// 10s 与 p99 ≤ max(16.7ms, 基线p99/2) 的绝对线为准（见交付
/// 报告判读指南）。
/// 平移连续性采样（3.7 (59) 工作流一）：同窗另落一行
/// wall.pan——窗口内 pan 事件数与折叠位移增量（屏幕点，
/// |dx|/|dy| 分轴累计）。折叠位移即本秒内经帧公式＋
/// invalidateLayout 实际呈现的内容位移：持续拖动时应逐秒
/// 都有 events>0 且位移平滑累积；(58) 的故障形态（事件在
/// 记、画面冻结后瞬移）在本行呈「多秒位移记账正常但
/// wall.scroll 的 max 间隔巨大」之外，更直接的对照是真机
/// 录屏——本行与 wall.scroll 同秒对读，证位移连续非阶梯。
final class WallScrollMetrics: NSObject {

    private let wallName: String
    private weak var layout: WallLayout?
    private var displayLink: CADisplayLink?
    private var lastTickTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var intervalsMs: [Double] = []
    private var didScrollMaxMs: Double = 0
    private var reloadCount = 0
    private var identityChangedInWindow = false
    private var latticeAtWindowStart = 0
    private var rebaseAtWindowStart = 0
    private var lastActivityAt: CFTimeInterval = 0
    private var active = false
    /// 平移采样（(59)）：窗口内 pan 事件数与折叠位移增量
    /// （屏幕点，分轴绝对值累计），随 flush 与 wall.scroll
    /// 同批落 wall.pan 并清零。
    private var panEventCount = 0
    private var panAbsDx: Double = 0
    private var panAbsDy: Double = 0

    init(wallName: String) {
        self.wallName = wallName
        super.init()
    }

    /// 滚动回调每次调：登记活动与本次回调耗时；首次调启动
    /// 统计窗（快照 lattice/rebase 计数为窗口基线）。panDelta
    /// 是本次回调折叠的位移（屏幕点，offset 复位前的值）——
    /// (59) 起计入 wall.pan 采样（窗口未启动时也先累计，首
    /// 次喂入启动窗口后不清零、本窗一并落账）。
    func noteScrollActivity(layout: WallLayout, didScrollMs: Double, panDelta: CGPoint) {
        let now = CACurrentMediaTime()
        lastActivityAt = now
        if didScrollMs > didScrollMaxMs { didScrollMaxMs = didScrollMs }
        panEventCount += 1
        panAbsDx += abs(Double(panDelta.x))
        panAbsDy += abs(Double(panDelta.y))
        guard !active else { return }
        active = true
        self.layout = layout
        windowStart = now
        latticeAtWindowStart = layout.latticeComputeCount
        rebaseAtWindowStart = layout.rebaseCount
        intervalsMs = []
        lastTickTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// 滚动路径上的 reloadData 计数（数据到达等非滚动期
    /// reload 不经此口、不计）。
    func noteReloadData() {
        if active { reloadCount += 1 }
    }

    /// 滚动窗内发生过实例身份变化（refreshInstances 返回 true）。
    func noteIdentityChanged() {
        if active { identityChangedInWindow = true }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastTickTimestamp > 0 {
            intervalsMs.append((now - lastTickTimestamp) * 1000)
        }
        lastTickTimestamp = now
        if now - windowStart >= 1.0 {
            flush()
        }
        if now - lastActivityAt > 2.0 {
            if now - windowStart >= 0.5, !intervalsMs.isEmpty {
                flush()
            }
            displayLink?.invalidate()
            displayLink = nil
            active = false
        }
    }

    private func flush() {
        guard let layout else { return }
        let sorted = intervalsMs.sorted()
        func pct(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let idx = min(sorted.count - 1, Int((p * Double(sorted.count)).rounded(.up)))
            return sorted[idx]
        }
        let hitch = intervalsMs.isEmpty
            ? 0
            : Double(intervalsMs.filter { $0 > 16.7 }.count) / Double(intervalsMs.count) * 100
        Breadcrumbs.log("wall.scroll wall=\(wallName)"
            + " didScrollMax=\(Self.fmt(didScrollMaxMs))ms"
            + " p95=\(Self.fmt(pct(0.95)))ms p99=\(Self.fmt(pct(0.99)))ms"
            + " max=\(Self.fmt(sorted.last ?? 0))ms"
            + " hitch=\(Self.fmt(hitch))%"
            + " lattice=\(layout.latticeComputeCount - latticeAtWindowStart)"
            + " rebase=\(layout.rebaseCount - rebaseAtWindowStart)"
            + " reload=\(reloadCount)"
            + " identityChanged=\(identityChangedInWindow ? 1 : 0)")
        Breadcrumbs.log("wall.pan wall=\(wallName)"
            + " events=\(panEventCount)"
            + " dx=\(Self.fmt(panAbsDx))"
            + " dy=\(Self.fmt(panAbsDy))")
        windowStart = CACurrentMediaTime()
        intervalsMs = []
        didScrollMaxMs = 0
        reloadCount = 0
        identityChangedInWindow = false
        latticeAtWindowStart = layout.latticeComputeCount
        rebaseAtWindowStart = layout.rebaseCount
        panEventCount = 0
        panAbsDx = 0
        panAbsDy = 0
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}
