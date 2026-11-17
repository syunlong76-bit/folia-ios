import Foundation

/// M1 阶段 3：队列墙几何核心，从 folia-major src/components/wall/
/// layout.ts + blockTemplates.ts 逐函数移植（纯逻辑、无 UIKit）。
/// 槽位/让位数据在 WallTables.swift（脚本生成，勿手改）。
/// 移植纪律：JS 的 Math.imul/>>> 用 UInt32 溢出运算等价实现；
/// 负坐标除法用 floorDiv（Swift 的 / 向零截断，与 JS Math.floor 不同）；
/// Math.round 用 floor(x+0.5) 等价实现（Swift rounded() 对负半数不同）。

struct WallMetrics: Equatable {
    var cellSize: Double = 128
    var gap: Double = 8
    var pitch: Double { cellSize + gap }
}

struct WallRectD: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var left: Double { x }
    var right: Double { x + width }
    var top: Double { y }
    var bottom: Double { y + height }
    func overlaps(_ other: WallRectD) -> Bool {
        left < other.right && right > other.left && top < other.bottom && bottom > other.top
    }
}

/// 一张海报实例：同一内容在周期平铺中有多份拷贝，instanceId 唯一。
struct QueueInstance: Equatable {
    let instanceId: String
    let queueIndex: Int
    let cellSlot: Int
    let repeatX: Int
    let repeatY: Int
    let rect: WallRectD
}

struct LatticeGeometry: Equatable {
    let blocksPerRow: Int
    let blockRows: Int
    let cellSlots: Int
    let cellWidth: Double
    let cellHeight: Double
    let blockWidth: Double
    let blockHeight: Double
}

enum WallGeometry {

    static let blockCols = 12
    static let blockRows = 8
    static let slotsPerBlock = 12
    static let maxRenderedInstances = 400
    /// 单元长宽比偏置（layout.ts FIELD_ASPECT）。
    private static let fieldAspect = 2.2

    // MARK: - 整数工具（JS 语义）

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
    }

    private static func jsRound(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    // MARK: - 定向（blockTemplates.ts）

    /// Integer hash（与 JS Math.imul/>>> 逐位等价）。
    static func mixBlockCoords(_ blockColumn: Int, _ blockRow: Int) -> UInt32 {
        let a = UInt32(bitPattern: Int32(truncatingIfNeeded: blockColumn))
        let b = UInt32(bitPattern: Int32(truncatingIfNeeded: blockRow))
        var value = (a &* 0x9E3779B1) ^ (b &* 0x85EBCA6B)
        value = (value ^ (value >> 15)) &* 0x2C1B3C6D
        value ^= value >> 12
        return value
    }

    /// 定向号 = 模板号 * 4 + 反射号（反射序：恒等、翻 X、翻 Y、双翻）。
    static func blockOrientation(_ blockColumn: Int, _ blockRow: Int) -> Int {
        let count = WallTables.templates.count
        let template = ((blockColumn + blockRow * 2) % count + count) % count
        return template * 4 + Int(mixBlockCoords(blockColumn, blockRow) % 4)
    }

    private static func reflect(_ slot: BlockSlot, reflection: Int) -> BlockSlot {
        var result = slot
        if reflection == 1 || reflection == 3 {
            result = BlockSlot(x: blockCols - result.x - result.cols, y: result.y, cols: result.cols, rows: result.rows)
        }
        if reflection == 2 || reflection == 3 {
            result = BlockSlot(x: result.x, y: blockRows - result.y - result.rows, cols: result.cols, rows: result.rows)
        }
        return result
    }

    /// 某块的 12 槽位（已定向）。
    static func blockTemplate(_ blockColumn: Int, _ blockRow: Int) -> [BlockSlot] {
        let orientation = blockOrientation(blockColumn, blockRow)
        let template = WallTables.templates[orientation / 4]
        let reflection = orientation % 4
        return template.map { reflect($0, reflection: reflection) }
    }

    /// 展开某槽位时整块的让位布局（已定向）；槽位越界返回 nil。
    static func blockReflow(_ blockColumn: Int, _ blockRow: Int, expandedSlot: Int) -> [BlockSlot]? {
        guard expandedSlot >= 0, expandedSlot < slotsPerBlock else { return nil }
        let orientation = blockOrientation(blockColumn, blockRow)
        let table = WallTables.reflows[orientation / 4][expandedSlot]
        let reflection = orientation % 4
        return table.map { reflect($0, reflection: reflection) }
    }

    // MARK: - 单元几何（layout.ts getLatticeGeometry）

    static func latticeGeometry(totalEntries: Int, metrics: WallMetrics) -> LatticeGeometry {
        let pitch = metrics.pitch
        let blockWidth = Double(blockCols) * pitch
        let blockHeight = Double(blockRows) * pitch
        let blocks = max(1, Int(ceil(Double(max(0, totalEntries)) / Double(slotsPerBlock))))
        let blocksPerRow: Int
        if blocks <= 1 {
            blocksPerRow = 1
        } else {
            let raw = (fieldAspect * Double(blocks) * Double(blockRows) / Double(blockCols)).squareRoot()
            blocksPerRow = max(1, jsRound(raw))
        }
        let blockRowsCount = Int(ceil(Double(blocks) / Double(blocksPerRow)))
        return LatticeGeometry(
            blocksPerRow: blocksPerRow,
            blockRows: blockRowsCount,
            cellSlots: blocksPerRow * blockRowsCount * slotsPerBlock,
            cellWidth: Double(blocksPerRow) * blockWidth,
            cellHeight: Double(blockRowsCount) * blockHeight,
            blockWidth: blockWidth,
            blockHeight: blockHeight
        )
    }

    // MARK: - 实例构建（layout.ts buildInstance）

    static func buildInstance(geometry: LatticeGeometry, totalEntries: Int,
                              absoluteColumn: Int, absoluteRow: Int, slotIndex: Int,
                              metrics: WallMetrics) -> QueueInstance {
        let repeatX = floorDiv(absoluteColumn, geometry.blocksPerRow)
        let repeatY = floorDiv(absoluteRow, geometry.blockRows)
        let localColumn = absoluteColumn - repeatX * geometry.blocksPerRow
        let localRow = absoluteRow - repeatY * geometry.blockRows
        let cellSlot = (localRow * geometry.blocksPerRow + localColumn) * slotsPerBlock + slotIndex
        let slot = blockTemplate(localColumn, localRow)[slotIndex]
        let pitch = metrics.pitch
        let rect = WallRectD(
            x: Double(repeatX) * geometry.cellWidth + Double(localColumn) * geometry.blockWidth + Double(slot.x) * pitch,
            y: Double(repeatY) * geometry.cellHeight + Double(localRow) * geometry.blockHeight + Double(slot.y) * pitch,
            width: Double(slot.cols) * pitch - metrics.gap,
            height: Double(slot.rows) * pitch - metrics.gap
        )
        return QueueInstance(
            instanceId: "\(cellSlot):\(repeatX):\(repeatY)",
            queueIndex: totalEntries > 0 ? cellSlot % totalEntries : 0,
            cellSlot: cellSlot,
            repeatX: repeatX,
            repeatY: repeatY,
            rect: rect
        )
    }

    static func instanceBlock(geometry: LatticeGeometry, instance: QueueInstance) -> (column: Int, row: Int, slotIndex: Int) {
        let blockInCell = instance.cellSlot / slotsPerBlock
        return (
            column: instance.repeatX * geometry.blocksPerRow + (blockInCell % geometry.blocksPerRow),
            row: instance.repeatY * geometry.blockRows + blockInCell / geometry.blocksPerRow,
            slotIndex: instance.cellSlot % slotsPerBlock
        )
    }

    // MARK: - 视口布局（layout.ts layoutLattice）

    static func layoutLattice(geometry: LatticeGeometry, totalEntries: Int,
                              bounds: WallRectD, overscan: Double,
                              metrics: WallMetrics) -> [QueueInstance] {
        guard totalEntries > 0, geometry.blockWidth > 0, geometry.blockHeight > 0 else { return [] }
        let view = WallRectD(x: bounds.x - overscan, y: bounds.y - overscan,
                             width: bounds.width + overscan * 2, height: bounds.height + overscan * 2)
        let fromColumn = Int((view.left / geometry.blockWidth).rounded(.down))
        let toColumn = Int((view.right / geometry.blockWidth).rounded(.down))
        let fromRow = Int((view.top / geometry.blockHeight).rounded(.down))
        let toRow = Int((view.bottom / geometry.blockHeight).rounded(.down))
        var result: [QueueInstance] = []
        guard fromRow <= toRow, fromColumn <= toColumn else { return [] }
        for row in fromRow...toRow {
            for column in fromColumn...toColumn {
                for slotIndex in 0..<slotsPerBlock {
                    let instance = buildInstance(geometry: geometry, totalEntries: totalEntries,
                                                 absoluteColumn: column, absoluteRow: row,
                                                 slotIndex: slotIndex, metrics: metrics)
                    if !instance.rect.overlaps(view) { continue }
                    result.append(instance)
                    if result.count >= maxRenderedInstances { return result }
                }
            }
        }
        return result
    }

    // MARK: - 展开重排（layout.ts layoutExpandedBlock）

    /// 展开 active 所在块的 12 张卡的新位置（instanceId → rect）。
    static func layoutExpandedBlock(geometry: LatticeGeometry, totalEntries: Int,
                                    active: QueueInstance, metrics: WallMetrics) -> [String: WallRectD] {
        var result: [String: WallRectD] = [:]
        guard totalEntries > 0 else { return result }
        let block = instanceBlock(geometry: geometry, instance: active)
        let localColumn = block.column - active.repeatX * geometry.blocksPerRow
        let localRow = block.row - active.repeatY * geometry.blockRows
        guard let reflow = blockReflow(localColumn, localRow, expandedSlot: block.slotIndex) else { return result }
        let pitch = metrics.pitch
        let originX = Double(active.repeatX) * geometry.cellWidth + Double(localColumn) * geometry.blockWidth
        let originY = Double(active.repeatY) * geometry.cellHeight + Double(localRow) * geometry.blockHeight
        let blockInCell = localRow * geometry.blocksPerRow + localColumn
        for slotIndex in 0..<slotsPerBlock {
            let slot = reflow[slotIndex]
            let cellSlot = blockInCell * slotsPerBlock + slotIndex
            result["\(cellSlot):\(active.repeatX):\(active.repeatY)"] = WallRectD(
                x: originX + Double(slot.x) * pitch,
                y: originY + Double(slot.y) * pitch,
                width: Double(slot.cols) * pitch - metrics.gap,
                height: Double(slot.rows) * pitch - metrics.gap
            )
        }
        return result
    }

    // MARK: - 最近拷贝（layout.ts locateNearestInstance）

    static func locateNearestInstance(geometry: LatticeGeometry, totalEntries: Int,
                                      queueIndex: Int, pointX: Double, pointY: Double,
                                      metrics: WallMetrics) -> QueueInstance? {
        guard totalEntries > 0, queueIndex >= 0, queueIndex < totalEntries else { return nil }
        var best: QueueInstance?
        var bestDistance = Double.infinity
        var cellSlot = queueIndex
        while cellSlot < geometry.cellSlots {
            let blockInCell = cellSlot / slotsPerBlock
            let localColumn = blockInCell % geometry.blocksPerRow
            let localRow = blockInCell / geometry.blocksPerRow
            let slotIndex = cellSlot % slotsPerBlock
            let base = buildInstance(geometry: geometry, totalEntries: totalEntries,
                                     absoluteColumn: localColumn, absoluteRow: localRow,
                                     slotIndex: slotIndex, metrics: metrics)
            let repeatX = jsRound((pointX - base.rect.x - base.rect.width / 2) / geometry.cellWidth)
            let repeatY = jsRound((pointY - base.rect.y - base.rect.height / 2) / geometry.cellHeight)
            let candidate = buildInstance(geometry: geometry, totalEntries: totalEntries,
                                          absoluteColumn: repeatX * geometry.blocksPerRow + localColumn,
                                          absoluteRow: repeatY * geometry.blocksPerRow + localRow,
                                          slotIndex: slotIndex, metrics: metrics)
            let dx = candidate.rect.x + candidate.rect.width / 2 - pointX
            let dy = candidate.rect.y + candidate.rect.height / 2 - pointY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
            cellSlot += totalEntries
        }
        return best
    }
}
