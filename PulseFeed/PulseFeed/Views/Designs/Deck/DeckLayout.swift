import Foundation

/// Pure sizing and copy for the Deck popover. No SwiftUI here so it stays unit-testable.
enum DeckLayout {
    /// Collapsed height of the four big tiles (Breaking, Markets, Brief, Unread).
    static let tileHeight: CGFloat = 200
    /// Collapsed height of the three small tiles (Starred, Saved, Search).
    static let smallTileHeight: CGFloat = 66
    /// Height of a row-mate drawn as a header-only strip under an expanded tile.
    static let stripHeight: CGFloat = 44
    /// Ceiling for any expanded tile; past it the tile scrolls inside itself and the popover scrolls
    /// as a whole, so the 400×600 frame never grows.
    static let expandedCap: CGFloat = 420
    /// Gap between tiles and between grid rows.
    static let gap: CGFloat = 10

    /// Height of an expanded tile: the collapsed height plus one `rowHeight` per content row,
    /// never past `cap`. Negative row counts count as zero.
    static func expandedHeight(collapsed: CGFloat, contentRows: Int, rowHeight: CGFloat, cap: CGFloat) -> CGFloat {
        let rows = CGFloat(max(0, contentRows))
        return min(collapsed + rows * rowHeight, cap)
    }

    // MARK: - Grid arrangement

    /// How one grid row draws given the tile that is expanded (if any). A row whose tile is expanded
    /// draws that tile full width with its row-mates as strips beneath it; any other row is untouched.
    struct RowLayout: Equatable {
        /// The tile drawn full width, or nil when the row is side by side.
        let expanded: DeckTileID?
        /// Row-mates drawn as `stripHeight` strips under the expanded tile, in row order. Empty when
        /// the row is side by side.
        let strips: [DeckTileID]

        var isStacked: Bool { expanded != nil }
    }

    /// `row` is the tiles of one grid row in display order; `expanded` is the popover's single
    /// expanded tile. A tile from another row leaves this row side by side.
    static func rowLayout(_ row: [DeckTileID], expanded: DeckTileID?) -> RowLayout {
        guard let expanded, row.contains(expanded) else { return RowLayout(expanded: nil, strips: []) }
        return RowLayout(expanded: expanded, strips: row.filter { $0 != expanded })
    }

    /// "4 new since 14:02" (24-hour local time); "4 new" when the user has never looked;
    /// "Nothing new since 14:02" for zero.
    static func newSinceText(newCount: Int, lastLooked: Date?, timeZone: TimeZone = .current) -> String {
        let head = newCount == 0 ? "Nothing new" : "\(newCount) new"
        guard let lastLooked else { return head }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return "\(head) since \(f.string(from: lastLooked))"
    }

    /// "Since last looked · 4 new" — the divider inside an expanded tile (the sheet's copy, no time:
    /// the tile's own "N new since HH:mm" line already carries it).
    static func sinceDividerText(newCount: Int) -> String {
        "Since last looked · \(newCount) new"
    }

    /// Bar heights for the Unread tile: proportional to the largest count, with `floor` as the
    /// minimum so an empty category still draws a short track.
    static func barHeights(counts: [Int], maxHeight: CGFloat, floor: CGFloat) -> [CGFloat] {
        guard let top = counts.max(), top > 0 else { return counts.map { _ in floor } }
        return counts.map { count in
            guard count > 0 else { return floor }
            return max(floor, (maxHeight * CGFloat(count) / CGFloat(top)).rounded())
        }
    }

    // MARK: - Categories

    /// Every category in the registry, in display order, with its swatch colour. The Unread tile
    /// and the Overview draw `visible(_:)`, the ones that are switched on.
    static let categories: [DeckCategory] = NewsCategory.all.map {
        DeckCategory(tag: $0.id, label: $0.label, colorHex: $0.colorHex)
    }

    static func visible(_ enabled: Set<String>) -> [DeckCategory] {
        categories.filter { enabled.contains($0.tag) }
    }

    /// The bars: at most `limit` categories, the ones with the most unread, in registry order.
    static func top(_ cats: [DeckCategory], counts: [String: Int], limit: Int = 6) -> [DeckCategory] {
        let keep = Set(NewsCategory.top(cats.map { NewsCategory.named($0.tag) }, counts: counts, limit: limit).map(\.id))
        return cats.filter { keep.contains($0.tag) }
    }

    /// "f1" → "F1", "crypto" → "Crypto"; an unknown tag is capitalised.
    static func label(for tag: String) -> String {
        categories.first { $0.tag == tag }?.label ?? tag.capitalized
    }

    /// The category's swatch colour; grey for an unknown tag.
    static func colorHex(for tag: String) -> String {
        categories.first { $0.tag == tag }?.colorHex ?? "#8E8E93"
    }

    /// Groups items by category for the Overview list, keeping the input order inside each group.
    /// Groups follow `categories` order; unknown categories come after, alphabetically.
    static func groupedByCategory<T>(_ items: [T], category: (T) -> String) -> [DeckCategoryGroup<T>] {
        var buckets: [String: [T]] = [:]
        var seen: [String] = []
        for item in items {
            let tag = category(item)
            if buckets[tag] == nil { seen.append(tag) }
            buckets[tag, default: []].append(item)
        }
        let known = categories.map(\.tag)
        let ordered = seen.sorted { a, b in
            let ia = known.firstIndex(of: a) ?? known.count
            let ib = known.firstIndex(of: b) ?? known.count
            return ia != ib ? ia < ib : a < b
        }
        return ordered.map { DeckCategoryGroup(category: $0, items: buckets[$0] ?? []) }
    }
}

struct DeckCategory: Identifiable, Sendable {
    let tag: String
    let label: String
    let colorHex: String
    var id: String { tag }
}

struct DeckCategoryGroup<T>: Identifiable {
    let category: String
    let items: [T]
    var id: String { category }
}
