import Foundation

/// M1 阶段 4：探索墙平面布局，从 folia-major src/components/app/
/// lattice/exploreLayout.ts 逐函数移植（纯逻辑）。
/// 一份分区 = 一块地（lot，12×8，容量 13）；分区按页序连成 strip，
/// 平面无边周期平铺：(列, 行) 处的地 = wrap(行 + 列×stride)。
/// Bravais 的 explore 形状共用同一实现。

/// 条目在墙条目表中的位置 + 类型（rank 决定 lot 内占座顺序：
/// album 0、playlist/mix 1、artist 2、song 3）。
struct WallEntryRef: Equatable {
    let index: Int
    let kindRank: Int

    static func rank(ofKind kind: String) -> Int {
        switch kind {
        case "album": return 0
        case "playlist", "mix": return 1
        case "artist": return 2
        default: return 3 // song
        }
    }
}

struct WallSectionData {
    let key: String
    let entries: [WallEntryRef]
}

struct Lot: Equatable {
    let section: Int
    let part: Int
    let parts: Int
    /// tiles[i] 是站在 seats[i] 上的条目（墙条目表下标）。
    let tiles: [Int]
    let seats: [BlockSlot]
    let heading: BlockSlot
    let mirrors: Int
}

struct WallHeadingInstance: Equatable {
    let instanceId: String
    let section: Int
    let part: Int
    let parts: Int
    let rect: WallRectD
}

struct ExploreLayout {

    let sections: [WallSectionData]
    let lots: [Lot]
    let metrics: WallMetrics
    /// 一块地的视图内尺寸（不含街道）。
    let lotSize: (width: Double, height: Double)

    private let seatOf: [Int: (lot: Int, seat: Int)]
    private let firstLotOf: [Int]

    private var pitch: Double { metrics.pitch }
    private var street: Double { metrics.cellSize / 2 }
    private var pitchX: Double { Double(LotGeometry.lotCols) * pitch + street }
    private var pitchY: Double { Double(LotGeometry.lotRows) * pitch + street }
    var lotCount: Int { lots.count }

    init(pageSections: [WallSectionData], metrics: WallMetrics) {
        self.metrics = metrics
        let filtered = pageSections.filter { !$0.entries.isEmpty }
        sections = filtered
        lots = Self.buildStrip(sections: filtered)
        lotSize = (width: Double(LotGeometry.lotCols) * metrics.pitch - metrics.gap,
                   height: Double(LotGeometry.lotRows) * metrics.pitch - metrics.gap)
        var seatMap: [Int: (lot: Int, seat: Int)] = [:]
        for (lotIndex, lot) in lots.enumerated() {
            for (seat, tile) in lot.tiles.enumerated() {
                seatMap[tile] = (lot: lotIndex, seat: seat)
            }
        }
        seatOf = seatMap
        firstLotOf = filtered.indices.map { section in
            lots.firstIndex { $0.section == section } ?? -1
        }
    }

    // MARK: - strip 构建（exploreLayout.ts buildStrip）

    static func buildStrip(sections: [WallSectionData]) -> [Lot] {
        var result: [Lot] = []
        for (index, section) in sections.enumerated() {
            let total = section.entries.count
            guard total > 0 else { continue }
            let parts = Int(ceil(Double(total) / Double(LotGeometry.lotCapacity)))
            var from = 0
            for part in 0..<parts {
                let size = total / parts + (part < total % parts ? 1 : 0)
                let slice = section.entries[from..<(from + size)]
                    .sorted { $0.kindRank < $1.kindRank } // 稳定排序（Swift sorted 稳定）
                from += size
                let mirrors = LotGeometry.mirrorsOf(sectionKey: section.key, part: part)
                let cut = LotGeometry.cutLot(count: size, mirrors: mirrors)
                result.append(Lot(
                    section: index, part: part, parts: parts,
                    tiles: slice.map { $0.index }, seats: cut.seats,
                    heading: cut.heading, mirrors: mirrors
                ))
            }
        }
        return result
    }

    static func strideOf(_ lotCount: Int) -> Int {
        lotCount >= 7 ? 3 : (lotCount >= 4 ? 2 : 1)
    }

    private static func wrap(_ value: Int, _ count: Int) -> Int {
        ((value % count) + count) % count
    }

    static func lotIndexAt(column: Int, row: Int, lotCount: Int) -> Int {
        wrap(row + column * strideOf(lotCount), lotCount)
    }

    // MARK: - 位置换算

    private func lotAt(column: Int, row: Int) -> Lot {
        lots[Self.lotIndexAt(column: column, row: row, lotCount: lotCount)]
    }

    private func rectOf(slot: BlockSlot, column: Int, row: Int) -> WallRectD {
        WallRectD(
            x: Double(column) * pitchX + Double(slot.x) * pitch,
            y: Double(row) * pitchY + Double(slot.y) * pitch,
            width: Double(slot.cols) * pitch - metrics.gap,
            height: Double(slot.rows) * pitch - metrics.gap
        )
    }

    private func posterAt(column: Int, row: Int, seat: Int) -> QueueInstance {
        let lot = lotAt(column: column, row: row)
        let rect = rectOf(slot: lot.seats[seat], column: column, row: row)
        return QueueInstance(
            instanceId: "\(seat):\(column):\(row)",
            queueIndex: lot.tiles[seat],
            cellSlot: seat,
            repeatX: column, repeatY: row,
            rect: rect
        )
    }

    // MARK: - 视口实例（exploreLayout.ts near）

    func near(bounds: WallRectD, overscan: Double) -> (posters: [QueueInstance], headings: [WallHeadingInstance]) {
        var posters: [QueueInstance] = []
        var headings: [WallHeadingInstance] = []
        guard lotCount > 0 else { return (posters, headings) }
        let view = WallRectD(
            x: bounds.x - overscan, y: bounds.y - overscan,
            width: bounds.width + overscan * 2, height: bounds.height + overscan * 2
        )
        let isFull = { posters.count + headings.count >= WallGeometry.maxRenderedInstances }
        let fromRow = Int((view.top / pitchY).rounded(.down))
        let toRow = Int((view.bottom / pitchY).rounded(.down))
        let fromCol = Int((view.left / pitchX).rounded(.down))
        let toCol = Int((view.right / pitchX).rounded(.down))
        guard fromRow <= toRow, fromCol <= toCol else { return (posters, headings) }
        for row in fromRow...toRow {
            for column in fromCol...toCol {
                let lot = lotAt(column: column, row: row)
                let headingRect = rectOf(slot: lot.heading, column: column, row: row)
                if headingRect.overlaps(view) {
                    headings.append(WallHeadingInstance(
                        instanceId: "heading:\(column):\(row)",
                        section: lot.section, part: lot.part, parts: lot.parts,
                        rect: headingRect
                    ))
                    if isFull() { return (posters, headings) }
                }
                for seat in 0..<lot.seats.count {
                    let poster = posterAt(column: column, row: row, seat: seat)
                    if !poster.rect.overlaps(view) { continue }
                    posters.append(poster)
                    if isFull() { return (posters, headings) }
                }
            }
        }
        return (posters, headings)
    }

    // MARK: - 最近拷贝（nearestPlace / nearest）

    private static func jsRound(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    private func nearestPlace(index: Int, offsetX: Double, offsetY: Double,
                              pointX: Double, pointY: Double) -> (column: Int, row: Int) {
        let column = (pointX - offsetX) / pitchX
        let row = (pointY - offsetY) / pitchY
        let middle = Self.jsRound(column)
        let reach = Int(ceil(Double(lotCount) * pitchY / (2 * pitchX))) + 1
        var best = (column: middle, row: 0)
        var bestDistance = Double.infinity
        for candidate in (middle - reach)...(middle + reach) {
            let first = Self.wrap(index - candidate * Self.strideOf(lotCount), lotCount)
            let candidateRow = first + lotCount * Self.jsRound((row - Double(first)) / Double(lotCount))
            let dx = (Double(candidate) - column) * pitchX
            let dy = (Double(candidateRow) - row) * pitchY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = (column: candidate, row: candidateRow)
            }
        }
        return best
    }

    func nearest(queueIndex: Int, pointX: Double, pointY: Double) -> QueueInstance? {
        guard let stands = seatOf[queueIndex] else { return nil }
        let slot = lots[stands.lot].seats[stands.seat]
        let place = nearestPlace(
            index: stands.lot,
            offsetX: Double(slot.x) * pitch + (Double(slot.cols) * pitch - metrics.gap) / 2,
            offsetY: Double(slot.y) * pitch + (Double(slot.rows) * pitch - metrics.gap) / 2,
            pointX: pointX, pointY: pointY
        )
        return posterAt(column: place.column, row: place.row, seat: stands.seat)
    }

    // MARK: - 展开（grown）

    func grownRects(active: QueueInstance) -> [String: WallRectD] {
        var result: [String: WallRectD] = [:]
        guard lotCount > 0 else { return result }
        let column = active.repeatX, row = active.repeatY, seat = active.cellSlot
        let lot = lotAt(column: column, row: row)
        guard seat >= 0, seat < lot.seats.count else { return result }
        let slots = LotGeometry.cutGrownLot(count: lot.seats.count, mirrors: lot.mirrors, grownSeat: seat)
        for (index, slot) in slots.enumerated() {
            result["\(index):\(column):\(row)"] = rectOf(slot: slot, column: column, row: row)
        }
        return result
    }

    // MARK: - 步进候选 / 分区定位

    func stepCandidates(from: QueueInstance) -> [QueueInstance] {
        var candidates: [QueueInstance] = []
        guard lotCount > 0 else { return candidates }
        for row in (from.repeatY - 1)...(from.repeatY + 1) {
            for column in (from.repeatX - 1)...(from.repeatX + 1) {
                let seats = lotAt(column: column, row: row).seats.count
                for seat in 0..<seats {
                    candidates.append(posterAt(column: column, row: row, seat: seat))
                }
            }
        }
        return candidates
    }

    func sectionAt(pointX: Double, pointY: Double) -> Int? {
        guard lotCount > 0 else { return nil }
        let column = Int((pointX / pitchX).rounded(.down))
        let row = Int((pointY / pitchY).rounded(.down))
        if pointX - Double(column) * pitchX > lotSize.width
            || pointY - Double(row) * pitchY > lotSize.height {
            return nil // 落在街道上
        }
        return lotAt(column: column, row: row).section
    }

    func sectionStart(section: Int, pointX: Double, pointY: Double) -> (x: Double, y: Double)? {
        guard section >= 0, section < firstLotOf.count else { return nil }
        let index = firstLotOf[section]
        guard index >= 0 else { return nil }
        let place = nearestPlace(index: index, offsetX: 0, offsetY: 0, pointX: pointX, pointY: pointY)
        return (x: Double(place.column) * pitchX, y: Double(place.row) * pitchY)
    }
}
