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
    /// 输入指纹（变了才重算）：数据量/原点/视口/缩放/展开/offset。
    private var lastFingerprint: String?

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

    /// 实例集的指纹：只含决定「窗口里有哪些实例」的输入（不含
    /// contentOffset——平移只移帧不换集，集不变数据源计数就合法）。
    private func setFingerprint() -> String {
        guard let collectionView else { return "" }
        let b = collectionView.bounds
        return [totalEntries, worldOrigin.x, worldOrigin.y, b.width, b.height,
                cameraScale].map { "\($0)" }.joined(separator: "|")
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
        let fp = setFingerprint()
        if fp != lastFingerprint {
            lastFingerprint = fp
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
        true
    }
}
