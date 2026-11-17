import Foundation

/// M1 阶段 4：探索墙 lot 系统，从 folia-major src/components/app/
/// lattice/lotSeats.ts + lotTables.ts 逐函数移植（纯逻辑）。
/// 表数据在 LotTables.swift（脚本生成）。Bravais 的 explore 形状
/// 与 Lattice 探索墙共用同一套 lot 代码，原生侧也只实现一份。
enum LotGeometry {

    static let lotCols = 12
    static let lotRows = 8
    /// 一块地最多装 13 条，再多分下一块。
    static let lotCapacity = 13

    /// 右条座数（lotTables.ts stripSeatsOf）。
    static func stripSeatsOf(_ count: Int) -> Int {
        count <= 3 ? 1 : (count == lotCapacity ? 3 : 2)
    }

    /// 展开时右条座数（lotTables.ts grownStripSeatsOf）。
    static func grownStripSeatsOf(_ others: Int) -> Int {
        min(3, max(others - 9, others > 2 ? 2 : 1))
    }

    /// 分区镜像位（lotSeats.ts mirrorsOf）：FNV-1a 变体哈希，
    /// bit0/1 = 左方块左右/上下翻，bit2/3 = 右方块；右条永不镜像。
    static func mirrorsOf(sectionKey: String, part: Int) -> Int {
        var hash: UInt32 = 0x811C9DC5
        for scalar in "\(sectionKey)#\(part)".unicodeScalars {
            hash = (hash ^ scalar.value) &* 0x01000193
        }
        hash = (hash ^ (hash >> 15)) &* 0x2C1B3C6D
        hash ^= hash >> 12
        return Int(hash % 16)
    }

    /// 表内座位落进 field 并按 mirror 翻转（mirror: 1 左右、2 上下）。
    private static func seatsIn(field: BlockSlot, table: [BlockSlot], mirror: Int) -> [BlockSlot] {
        table.map { seat in
            BlockSlot(
                x: field.x + (mirror & 1 != 0 ? field.cols - seat.x - seat.cols : seat.x),
                y: field.y + (mirror & 2 != 0 ? field.rows - seat.y - seat.rows : seat.y),
                cols: seat.cols, rows: seat.rows
            )
        }
    }

    /// 座位序：面积降序 → y → x（JS sort 稳定，Swift sort 同样稳定）。
    private static func bySeatOrder(_ a: BlockSlot, _ b: BlockSlot) -> Bool {
        let areaA = a.cols * a.rows, areaB = b.cols * b.rows
        if areaA != areaB { return areaA > areaB }
        if a.y != b.y { return a.y < b.y }
        return a.x < b.x
    }

    /// 一块地的标题座 + count 条的座位（第 i 条坐第 i 座）。
    static func cutLot(count: Int, mirrors: Int) -> (heading: BlockSlot, seats: [BlockSlot]) {
        if count <= 2 {
            return (LotTables.heading_half, LotTables.right_half_seats[max(0, count)])
        }
        let strip = stripSeatsOf(count)
        let left = (count - strip) / 2
        let seats = (
            seatsIn(field: LotTables.left_square, table: LotTables.square_seats[left], mirror: mirrors & 3)
            + seatsIn(field: LotTables.right_square, table: LotTables.square_seats[count - strip - left], mirror: (mirrors >> 2) & 3)
            + seatsIn(field: LotTables.right_strip, table: LotTables.strip_seats[strip], mirror: 0)
        ).sorted(by: bySeatOrder)
        return (LotTables.heading_strip, seats)
    }

    /// 最小总移动分配（lotSeats.ts seatWithLeastTravel）：中心距
    /// 平方和最小的双射，同代价取先找到者；位掩码 DP。
    private static func seatWithLeastTravel(from: [BlockSlot], to: [BlockSlot]) -> [Int] {
        let count = from.count
        guard count > 0 else { return [] }
        // 中心坐标 ×2 取整，代价全程整数。
        let travel: [[Int]] = from.map { tile in
            to.map { seat in
                let dx = 2 * tile.x + tile.cols - 2 * seat.x - seat.cols
                let dy = 2 * tile.y + tile.rows - 2 * seat.y - seat.rows
                return dx * dx + dy * dy
            }
        }
        let size = 1 << count
        var best = [Double](repeating: .infinity, count: size)
        var lastSeat = [Int](repeating: 0, count: size)
        best[0] = 0
        for mask in 0..<size {
            let tile = mask.nonzeroBitCount
            if tile >= count { continue }
            for seat in 0..<count where mask & (1 << seat) == 0 {
                let sum = best[mask] + Double(travel[tile][seat])
                let next = mask | (1 << seat)
                if sum < best[next] {
                    best[next] = sum
                    lastSeat[next] = seat
                }
            }
        }
        var taken = [Int](repeating: 0, count: count)
        var mask = size - 1
        for tile in stride(from: count - 1, through: 0, by: -1) {
            taken[tile] = lastSeat[mask]
            mask &= ~(1 << lastSeat[mask])
        }
        return taken
    }

    /// 展开 grownSeat 时整块地的座位（第 i 个 = 第 i 张卡的新位置）。
    /// 展开卡占其中心所在方块的整块（右条的卡判归右方块）；其余卡
    /// 分另一方块 + 右条，按最小移动分配。count ≤ 2 走特例。
    static func cutGrownLot(count: Int, mirrors: Int, grownSeat: Int) -> [BlockSlot] {
        let base = cutLot(count: count, mirrors: mirrors).seats
        guard grownSeat >= 0, grownSeat < base.count else { return base }
        let grown = base[grownSeat]
        if count <= 2 {
            return base.indices.map { $0 == grownSeat ? LotTables.right_square : LotTables.right_strip }
        }
        let leftSquare = LotTables.left_square
        let isInLeft = Double(grown.x) + Double(grown.cols) / 2 < Double(leftSquare.x + leftSquare.cols)
        let others = count - 1
        let strip = grownStripSeatsOf(others)
        let free = seatsIn(
                field: isInLeft ? LotTables.right_square : LotTables.left_square,
                table: LotTables.square_seats[others - strip],
                mirror: isInLeft ? (mirrors >> 2) & 3 : mirrors & 3)
            + seatsIn(field: LotTables.right_strip, table: LotTables.strip_seats[strip], mirror: 0)
        let movers = base.indices.filter { $0 != grownSeat }
        let taken = seatWithLeastTravel(from: movers.map { base[$0] }, to: free)
        var result = base
        result[grownSeat] = isInLeft ? LotTables.left_square : LotTables.right_square
        for (index, seat) in movers.enumerated() {
            result[seat] = free[taken[index]]
        }
        return result
    }
}
