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
final class WallLayout: UICollectionViewLayout {

    var totalEntries: Int = 0
    var metrics = WallMetrics()
    /// 相机 scale（按视口宽断点：<640 → 0.52、<1100 → 0.64、其余 0.76）。
    var cameraScale: Double = 0.52
    /// 视口左上角的世界坐标（CAMERA_HOME 起点 34, 80）。
    var worldOrigin = CGPoint(x: 34, y: 80)
    /// 当前展开的实例 id（nil = 无展开）。
    var expandedInstanceId: String?

    private(set) var instances: [QueueInstance] = []
    private var attributesCache: [UICollectionViewLayoutAttributes] = []
    /// 输入指纹（变了才重算）：数据量/原点/尺寸类别/缩放/展开。
    private var lastFingerprint: String?
    /// layoutLattice 全量重算累计次数（面包屑对账用，只增不减）。
    private(set) var latticeComputeCount = 0
    /// 旋转冻结（(57) A2）：true 时不失效、不重算，保留落定前
    /// 最后一套实例/属性供系统旋转动画变换呈现；仅主页墙在
    /// viewWillTransition 期间置位，曲目墙从不置位、恒 false。
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

    /// 实例集的指纹：只含决定「窗口里有哪些实例」的输入（不含
    /// contentOffset——平移只移帧不换集，集不变数据源计数就合法；
    /// 不含 bounds 原始 W/H——只含尺寸类别，见 sizeClass：指纹
    /// 只决定「何时重算」，实例/帧的计算函数本身不因类别改变，
    /// 同类别内复用的实例集覆盖新可见域、逐帧公式不变）。
    private func setFingerprint() -> String {
        guard let collectionView else { return "" }
        return [totalEntries, worldOrigin.x, worldOrigin.y,
                cameraScale].map { "\($0)" }.joined(separator: "|")
            + "#" + sizeClass(for: collectionView.bounds.size)
            + "#" + (expandedInstanceId ?? "-")
    }

    private var expandedRects: [String: WallRectD] = [:]

    /// 重算实例集（指纹变了才算）并重建属性帧（每帧都建，成本是
    /// ≤400 个矩形映射）。数据源计数与实例集的同步由 VC 在集变化
    /// 的事件点（绕回/展开/数据到达）调 reloadData 保证。
    func refreshInstances() {
        guard let collectionView, totalEntries > 0 else {
            instances = []
            attributesCache = []
            expandedRects = [:]
            lastFingerprint = nil
            return
        }
        // 旋转冻结（(57) A2）：保留既有实例/属性整套不动，等
        // 落地解冻后的一次 invalidate 收尾。首算守卫：lastFingerprint
        // 为 nil（冷启首排/数据清零后）时不冻——首排必算，不许
        // 被冻结误挡成空墙。
        if isRotationFrozen, lastFingerprint != nil { return }
        let fp = setFingerprint()
        if fp != lastFingerprint {
            lastFingerprint = fp
            latticeComputeCount += 1
            let viewSize = collectionView.bounds.size
            let worldBounds = WallRectD(
                x: Double(worldOrigin.x), y: Double(worldOrigin.y),
                width: Double(viewSize.width) / cameraScale,
                height: Double(viewSize.height) / cameraScale
            )
            let list = WallGeometry.layoutLattice(
                geometry: geometry, totalEntries: totalEntries,
                bounds: worldBounds, overscan: 900, metrics: metrics
            )
            var rects: [String: WallRectD] = [:]
            if let expandedId = expandedInstanceId,
               let active = list.first(where: { $0.instanceId == expandedId }) {
                rects = WallGeometry.layoutExpandedBlock(
                    geometry: geometry, totalEntries: totalEntries,
                    active: active, metrics: metrics
                )
            }
            instances = list
            expandedRects = rects
        }
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
