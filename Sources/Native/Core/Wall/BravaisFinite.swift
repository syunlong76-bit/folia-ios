import Foundation

/// M1 阶段 4：Bravais 有限墙整套纯逻辑，从 folia-major
/// src/components/wall/ 的 blockReservedSlots.ts、wallSlots.ts、
/// rankSlots.ts、wallView.ts、finiteWall.ts 逐函数移植。
/// 有限墙不平铺：条目最多出现一次，rank 之外的槽位是裸墙面。
/// JS 的 Math.imul/>>>/mulberry32 用 UInt32 溢出运算等价实现；
/// Math.round 用 floor(x+0.5)。

// MARK: - 保留槽（blockReservedSlots.ts）

enum ReservedSlots {

    static func clampReservedPerBlock(_ count: Double) -> Int {
        guard count.isFinite else { return 0 }
        return min(6, max(0, Int((count + 0.5).rounded(.down))))
    }

    private static func hashBlock(_ column: Int, _ row: Int) -> UInt32 {
        var value = (UInt32(bitPattern: Int32(truncatingIfNeeded: column)) &* 0x27D4EB2D)
            ^ (UInt32(bitPattern: Int32(truncatingIfNeeded: row)) &* 0x165667B1)
            ^ 0x5BD1E995
        value = (value ^ (value >> 15)) &* 0x85EBCA6B
        value = (value ^ (value >> 13)) &* 0xC2B2AE35
        return value ^ (value >> 16)
    }

    /// mulberry32：state 是 int32 语义，用 UInt32 位模式等价。
    private struct Mulberry32 {
        var state: UInt32
        mutating func next() -> Double {
            state = state &+ 0x6D2B79F5
            var t = (state ^ (state >> 15)) &* (1 | state)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double((t ^ (t >> 14)) ) / 4294967296.0
        }
    }

    /// 块的固定洗牌（与 k 无关；保留槽是它的前缀）。
    static func blockSlotShuffle(_ column: Int, _ row: Int) -> [Int] {
        var order = Array(0..<WallGeometry.slotsPerBlock)
        var random = Mulberry32(state: hashBlock(column, row))
        for index in stride(from: order.count - 1, through: 1, by: -1) {
            let swap = Int((random.next() * Double(index + 1)).rounded(.down))
            order.swapAt(index, swap)
        }
        return order
    }

    static func blockReservedSlots(_ column: Int, _ row: Int, count: Int) -> [Int] {
        Array(blockSlotShuffle(column, row).prefix(clampReservedPerBlock(Double(count))))
    }

    static func blockReservedMask(_ column: Int, _ row: Int, count: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: WallGeometry.slotsPerBlock)
        for slot in blockReservedSlots(column, row, count: count) { mask[slot] = true }
        return mask
    }

    static func blockCapacity(_ count: Int) -> Int {
        WallGeometry.slotsPerBlock - clampReservedPerBlock(Double(count))
    }
}

// MARK: - 固定世界槽位（wallSlots.ts）

struct WallSlot: Equatable {
    let key: String
    let column: Int
    let row: Int
    let slotIndex: Int
    let rect: WallRectD
    let centerX: Double
    let centerY: Double
    /// 占格面积（cols × rows）。
    let area: Int
}

enum WallSlots {

    static func blockSize(metrics: WallMetrics) -> (width: Double, height: Double) {
        (width: Double(WallGeometry.blockCols) * metrics.pitch,
         height: Double(WallGeometry.blockRows) * metrics.pitch)
    }

    static func slotKey(_ column: Int, _ row: Int, _ slotIndex: Int) -> String {
        "\(column),\(row),\(slotIndex)"
    }

    private static func toWallSlot(column: Int, row: Int, slotIndex: Int,
                                   slot: BlockSlot, metrics: WallMetrics) -> WallSlot {
        let pitch = metrics.pitch
        let x = Double(column * WallGeometry.blockCols) * pitch + Double(slot.x) * pitch
        let y = Double(row * WallGeometry.blockRows) * pitch + Double(slot.y) * pitch
        let width = Double(slot.cols) * pitch - metrics.gap
        let height = Double(slot.rows) * pitch - metrics.gap
        return WallSlot(
            key: slotKey(column, row, slotIndex),
            column: column, row: row, slotIndex: slotIndex,
            rect: WallRectD(x: x, y: y, width: width, height: height),
            centerX: x + width / 2, centerY: y + height / 2,
            area: slot.cols * slot.rows
        )
    }

    static func blockSlots(_ column: Int, _ row: Int, metrics: WallMetrics) -> [WallSlot] {
        WallGeometry.blockTemplate(column, row).enumerated().map { slotIndex, slot in
            toWallSlot(column: column, row: row, slotIndex: slotIndex, slot: slot, metrics: metrics)
        }
    }

    /// 块矩形内全部槽位（to 不含），行优先、块内按槽序。
    static func collectBlockRangeSlots(columns: Range<Int>, rows: Range<Int>,
                                       metrics: WallMetrics) -> [WallSlot] {
        var result: [WallSlot] = []
        for row in rows {
            for column in columns {
                result.append(contentsOf: blockSlots(column, row, metrics: metrics))
            }
        }
        return result
    }

    /// 展开 focusedSlot 的整块重排槽位（身份不变、只有 rect 动）。
    static func layoutFocusedBlock(_ column: Int, _ row: Int, focusedSlot: Int,
                                   metrics: WallMetrics) -> [WallSlot]? {
        guard let reflow = WallGeometry.blockReflow(column, row, expandedSlot: focusedSlot) else {
            return nil
        }
        return reflow.enumerated().map { slotIndex, slot in
            toWallSlot(column: column, row: row, slotIndex: slotIndex, slot: slot, metrics: metrics)
        }
    }
}

// MARK: - Rank 占座（rankSlots.ts）

enum RankSlots {

    static let verticalWeight = 0.9
    static let areaWeight = 0.35

    static func score(_ slot: WallSlot, originX: Double, originY: Double, metrics: WallMetrics) -> Double {
        abs(slot.centerX - originX)
            + abs(slot.centerY - originY) * verticalWeight
            - Double(slot.area).squareRoot() * metrics.pitch * areaWeight
    }

    static func withoutReservedSlots(_ slots: [WallSlot], reservedPerBlock: Int) -> [WallSlot] {
        guard reservedPerBlock != 0 else { return slots }
        var masks: [String: [Bool]] = [:]
        return slots.filter { slot in
            let blockKey = "\(slot.column),\(slot.row)"
            if masks[blockKey] == nil {
                masks[blockKey] = ReservedSlots.blockReservedMask(slot.column, slot.row, count: reservedPerBlock)
            }
            return masks[blockKey]![slot.slotIndex] == false
        }
    }

    /// 严格 rank：输出 order[i] 即 rank i 的槽位。
    static func rankSlots(_ candidates: [WallSlot], originX: Double, originY: Double,
                          metrics: WallMetrics, reservedPerBlock: Int = 0,
                          startSlotKey: String? = nil) -> [WallSlot] {
        let open = withoutReservedSlots(candidates, reservedPerBlock: reservedPerBlock)
        var scored = open.map { (slot: $0, score: score($0, originX: originX, originY: originY, metrics: metrics)) }
        scored.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            if a.slot.row != b.slot.row { return a.slot.row < b.slot.row }
            if a.slot.column != b.slot.column { return a.slot.column < b.slot.column }
            return a.slot.slotIndex < b.slot.slotIndex
        }
        var order = scored.map { $0.slot }
        if let startSlotKey, let startIndex = order.firstIndex(where: { $0.key == startSlotKey }), startIndex > 0 {
            let start = order.remove(at: startIndex)
            order.insert(start, at: 0)
        }
        return order
    }

    static func indexRanks(_ order: [WallSlot]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (rank, slot) in order.enumerated() { result[slot.key] = rank }
        return result
    }
}

// MARK: - 视图换算（wallView.ts）

struct WallViewSpec {
    var width: Double
    var height: Double
    var scale: Double
    /// 缝基线的屏幕 x；缺省 = 视口宽一半。
    var lineX: Double?
    var lineXOrDefault: Double { lineX ?? width / 2 }
}

enum WallViewMath {

    static func viewWorldBounds(centerX: Double, centerY: Double, view: WallViewSpec,
                                seamWidth: Double = 0, seamHeight: Double = 0,
                                overscan: Double = 0) -> WallRectD {
        let lineX = view.lineXOrDefault
        let left = centerX - (lineX + seamWidth) / view.scale - overscan
        let right = centerX + (view.width - lineX + seamWidth) / view.scale + overscan
        let top = centerY - (view.height / 2 + seamHeight) / view.scale - overscan
        let bottom = centerY + (view.height / 2 + seamHeight) / view.scale + overscan
        return WallRectD(x: left, y: top, width: right - left, height: bottom - top)
    }
}

// MARK: - 有限墙规划（finiteWall.ts）

struct FiniteWallPlan {
    let columns: Range<Int>
    let rows: Range<Int>
    /// 整个有限世界（含裸槽）的世界矩形。
    let bounds: WallRectD
    let capacity: Int
    let order: [WallSlot]
    let rankOfSlot: [String: Int]
}

enum FiniteWall {

    static let cameraPad = 60.0
    private static let seamEdgeMargin = 14.0

    private static func jsRound(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    private static func centredRange(center: Double, count: Int) -> Range<Int> {
        let from = jsRound(center - Double(count) / 2)
        return from..<(from + count)
    }

    static func finiteWallBlocks(itemCount: Int, reservedPerBlock: Int = 0,
                                 metrics: WallMetrics, view: WallViewSpec,
                                 originX: Double, originY: Double,
                                 viewCenterX: Double? = nil, viewCenterY: Double? = nil)
        -> (columns: Range<Int>, rows: Range<Int>, bounds: WallRectD, capacity: Int) {
        let perBlock = ReservedSlots.blockCapacity(reservedPerBlock)
        let blocks = max(1, Int(ceil(Double(max(0, itemCount)) / Double(perBlock))))
        let geometry = WallGeometry.latticeGeometry(totalEntries: blocks * WallGeometry.slotsPerBlock, metrics: metrics)
        let block = WallSlots.blockSize(metrics: metrics)
        let screen = WallViewMath.viewWorldBounds(
            centerX: viewCenterX ?? originX, centerY: viewCenterY ?? originY, view: view)
        let screenColumns = Int((screen.left / block.width).rounded(.down))..<(Int((screen.right / block.width).rounded(.down)) + 1)
        let screenRows = Int((screen.top / block.height).rounded(.down))..<(Int((screen.bottom / block.height).rounded(.down)) + 1)
        let contentColumns = centredRange(center: originX / block.width, count: geometry.blocksPerRow)
        let contentRows = centredRange(center: originY / block.height, count: geometry.blockRows)
        let columns = min(contentColumns.lowerBound, screenColumns.lowerBound)..<max(contentColumns.upperBound, screenColumns.upperBound)
        let rows = min(contentRows.lowerBound, screenRows.lowerBound)..<max(contentRows.upperBound, screenRows.upperBound)
        let bounds = WallRectD(
            x: Double(columns.lowerBound) * block.width,
            y: Double(rows.lowerBound) * block.height,
            width: Double(columns.upperBound) * block.width - metrics.gap - Double(columns.lowerBound) * block.width,
            height: Double(rows.upperBound) * block.height - metrics.gap - Double(rows.lowerBound) * block.height
        )
        return (columns, rows, bounds,
                (columns.upperBound - columns.lowerBound) * (rows.upperBound - rows.lowerBound) * perBlock)
    }

    static func plan(itemCount: Int, reservedPerBlock: Int = 0,
                     metrics: WallMetrics, view: WallViewSpec,
                     originX: Double, originY: Double, startSlotKey: String? = nil,
                     viewCenterX: Double? = nil, viewCenterY: Double? = nil) -> FiniteWallPlan {
        let world = finiteWallBlocks(
            itemCount: itemCount, reservedPerBlock: reservedPerBlock, metrics: metrics,
            view: view, originX: originX, originY: originY,
            viewCenterX: viewCenterX, viewCenterY: viewCenterY)
        let candidates = WallSlots.collectBlockRangeSlots(
            columns: world.columns, rows: world.rows, metrics: metrics)
        let order = RankSlots.rankSlots(
            candidates, originX: originX, originY: originY, metrics: metrics,
            reservedPerBlock: reservedPerBlock, startSlotKey: startSlotKey)
        return FiniteWallPlan(
            columns: world.columns, rows: world.rows, bounds: world.bounds,
            capacity: world.capacity, order: order, rankOfSlot: RankSlots.indexRanks(order))
    }

    /// 前 count 个 rank 的包围盒（有内容的那部分世界）。
    static func rankedContentBounds(order: [WallSlot], count: Int) -> WallRectD? {
        let used = order.prefix(max(0, count))
        guard !used.isEmpty else { return nil }
        var left = Double.infinity, right = -Double.infinity
        var top = Double.infinity, bottom = -Double.infinity
        for slot in used {
            left = min(left, slot.rect.x)
            right = max(right, slot.rect.right)
            top = min(top, slot.rect.y)
            bottom = max(bottom, slot.rect.bottom)
        }
        return WallRectD(x: left, y: top, width: right - left, height: bottom - top)
    }

    // MARK: 相机钳制（finiteWall.ts getFiniteCameraRange + seamPlan 的 span）

    private static func cameraSpanOnAxis(anchor: Double, openWidth: Double,
                                         view: WallViewSpec, axis: Character) -> (min: Double, max: Double) {
        let line = axis == "x" ? view.lineXOrDefault : view.height / 2
        let extent = axis == "x" ? view.width : view.height
        let need = openWidth / 2 + seamEdgeMargin
        let minValue = anchor - (extent - need - line) / view.scale
        let maxValue = anchor + (line - need) / view.scale
        if minValue <= maxValue { return (minValue, maxValue) }
        let centred = anchor - (extent / 2 - line) / view.scale
        return (centred, centred)
    }

    struct CameraRange {
        var minX: Double, maxX: Double, minY: Double, maxY: Double
        var lockedX: Bool, lockedY: Bool
    }

    static func finiteCameraRange(contentBounds: WallRectD?,
                                  anchorX: Double, anchorY: Double,
                                  view: WallViewSpec, seamWidth: Double,
                                  seamAxis: Character = "x", pad: Double = cameraPad) -> CameraRange {
        let lineX = view.lineXOrDefault
        let across = seamAxis == "x" ? seamWidth : 0
        let down = seamAxis == "y" ? seamWidth : 0
        let leftSpan = (lineX - across / 2) / view.scale
        let rightSpan = (view.width - lineX - across / 2) / view.scale
        let halfHeight = (view.height / 2 - down / 2) / view.scale
        let content = contentBounds ?? WallRectD(x: anchorX, y: anchorY, width: 0, height: 0)
        var minX = content.left + leftSpan - pad
        var maxX = content.right - rightSpan + pad
        var minY = content.top + halfHeight - pad
        var maxY = content.bottom - halfHeight + pad
        let lockedX = minX > maxX
        let lockedY = minY > maxY
        if lockedX { minX = anchorX; maxX = anchorX }
        if lockedY { minY = anchorY; maxY = anchorY }
        let spanX = seamAxis == "x"
            ? cameraSpanOnAxis(anchor: anchorX, openWidth: seamWidth, view: view, axis: "x")
            : (min: anchorX, max: anchorX)
        let spanY = seamAxis == "y"
            ? cameraSpanOnAxis(anchor: anchorY, openWidth: seamWidth, view: view, axis: "y")
            : (min: anchorY, max: anchorY)
        return CameraRange(
            minX: min(minX, spanX.min), maxX: max(maxX, spanX.max),
            minY: min(minY, spanY.min), maxY: max(maxY, spanY.max),
            lockedX: lockedX, lockedY: lockedY)
    }

    static func clampToCameraRange(centerX: Double, centerY: Double,
                                   range: CameraRange) -> (x: Double, y: Double) {
        (x: min(range.maxX, max(range.minX, centerX)),
         y: min(range.maxY, max(range.minY, centerY)))
    }

    /// 一步拖动：范围内全速、范围外阻尼 0.35。
    static func stepCameraAxis(value: Double, delta: Double, min: Double, max: Double,
                               resistance: Double = 0.35) -> Double {
        let next = value + delta
        return (next < min || next > max) ? value + delta * resistance : next
    }
}
