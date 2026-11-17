import Foundation

/// M1 阶段 4：Bravais 无限拼贴的起点/周期取项，从 folia-major
/// src/components/wall/startTile.ts 逐函数移植（纯逻辑）。
/// 内容在整块周期上重复：块内按槽序占非保留槽；wrapOffset 旋转
/// 序列，使起点 slot 显示第 0 项。默认实色外观档 reservedPerBlock=0，
/// 此时退化为周期内顺序取项（与 Lattice 单元序列一致）。
enum StartTile {

    struct WrapPeriod: Equatable {
        let blocksPerRow: Int
        let blockRows: Int
        /// 扣保留槽后每块的内容槽数。
        let perBlock: Int
    }

    private static func mod(_ value: Int, _ size: Int) -> Int {
        ((value % size) + size) % size
    }

    /// 周期形状（getWrapPeriod）：块数按 perBlock 折算，阵列形状
    /// 复用 Lattice 的 FIELD_ASPECT 规则（只取块数、与度量无关）。
    static func wrapPeriod(itemCount: Int, reservedPerBlock: Int = 0) -> WrapPeriod {
        let perBlock = ReservedSlots.blockCapacity(reservedPerBlock)
        let blocks = max(1, Int(ceil(Double(max(0, itemCount)) / Double(perBlock))))
        let geometry = WallGeometry.latticeGeometry(
            totalEntries: blocks * WallGeometry.slotsPerBlock,
            metrics: WallMetrics(cellSize: 1, gap: 0))
        return WrapPeriod(
            blocksPerRow: geometry.blocksPerRow,
            blockRows: geometry.blockRows,
            perBlock: perBlock)
    }

    /// slot 在重复序列中的位置（未加 wrapOffset）；保留槽/空层为 nil。
    static func wrapIndex(column: Int, row: Int, slotIndex: Int,
                          itemCount: Int, reservedPerBlock: Int = 0) -> Int? {
        guard itemCount > 0 else { return nil }
        let mask = ReservedSlots.blockReservedMask(column, row, count: reservedPerBlock)
        guard slotIndex >= 0, slotIndex < mask.count, !mask[slotIndex] else { return nil }
        var within = 0
        for index in 0..<slotIndex where !mask[index] { within += 1 }
        let period = wrapPeriod(itemCount: itemCount, reservedPerBlock: reservedPerBlock)
        let blockInPeriod = mod(row, period.blockRows) * period.blocksPerRow
            + mod(column, period.blocksPerRow)
        return (blockInPeriod * period.perBlock + within) % itemCount
    }

    /// 使 startSlot 显示第 0 项的偏移；无可用起点时 0。
    static func startWrapOffset(startColumn: Int?, startRow: Int?, startSlotIndex: Int?,
                                itemCount: Int, reservedPerBlock: Int = 0) -> Int {
        guard let column = startColumn, let row = startRow, let slotIndex = startSlotIndex,
              let index = wrapIndex(column: column, row: row, slotIndex: slotIndex,
                                    itemCount: itemCount, reservedPerBlock: reservedPerBlock)
        else { return 0 }
        return mod(-index, itemCount)
    }

    /// 无限模式下 slot 显示的条目序号；保留槽/空层为 nil。
    static func infiniteSlotItem(column: Int, row: Int, slotIndex: Int,
                                 itemCount: Int, wrapOffset: Int,
                                 reservedPerBlock: Int = 0) -> Int? {
        guard let index = wrapIndex(column: column, row: row, slotIndex: slotIndex,
                                    itemCount: itemCount, reservedPerBlock: reservedPerBlock)
        else { return nil }
        return mod(index + wrapOffset, itemCount)
    }
}
