import Foundation

/// Pure sizing for the Native Pro Inbox window (the N2 window option, chosen on 2026-09-07):
/// the top bar's split between the markets strip and the search field, the two panes' widths, and
/// the footer's feed-health tally. No SwiftUI here so it stays unit-testable.
enum NativeProInboxLayout {
    // MARK: - Top bar (strip + search + three glyphs)

    /// The sheet's top bar is 56pt tall.
    static let topBarHeight: CGFloat = 56
    /// Left padding that clears the traffic lights (the sheet's 92).
    static let lightsInset: CGFloat = 92
    /// Right inset, and the chip rail's horizontal inset.
    static let inset: CGFloat = 16
    /// Gap between the top bar's pieces (strip · search · glyph · glyph · glyph).
    static let topBarGap: CGFloat = 14
    /// Width of each of the three glyphs after the search field (refresh, mark read, settings).
    static let glyphWidth: CGFloat = 16
    /// The strip at the sheet's width, while the search field keeps its minimum.
    static let stripWidth: CGFloat = 640
    /// The strip never gives way past this while the bar can hold it.
    static let stripMinWidth: CGFloat = 420
    /// The search field's floor: the strip shrinks before the search does.
    static let searchMinWidth: CGFloat = 180

    /// What the bar has left for the strip and the search after the insets, the gaps and the glyphs.
    static func topBarAvailable(barWidth: CGFloat) -> CGFloat {
        max(0, barWidth - lightsInset - inset - 4 * topBarGap - 3 * glyphWidth)
    }

    /// The strip's width for a bar of `barWidth`: 640 while the search keeps 180; then the strip gives
    /// way down to 420; below that the strip is whatever the bar has and the search collapses.
    static func stripWidth(barWidth: CGFloat) -> CGFloat {
        let available = topBarAvailable(barWidth: barWidth)
        if available >= stripWidth + searchMinWidth { return stripWidth }
        return min(available, max(stripMinWidth, available - searchMinWidth))
    }

    /// The price credit's x in the bar: the search field's text (its 10pt inner inset), after the
    /// lights inset and, when prices show, the strip and a gap. It sits `creditBottomInset` above the
    /// bar's bottom edge, in the slack under the field.
    static func creditLeading(barWidth: CGFloat, hasStrip: Bool) -> CGFloat {
        lightsInset + (hasStrip ? stripWidth(barWidth: barWidth) + topBarGap : 0) + 10
    }
    static let creditBottomInset: CGFloat = 2

    /// The search field's width: the bar's remainder after the strip, never negative.
    static func searchWidth(barWidth: CGFloat) -> CGFloat {
        max(0, topBarAvailable(barWidth: barWidth) - stripWidth(barWidth: barWidth))
    }

    // MARK: - Chip rail, panes, footer

    /// The chip rail is 38pt tall with a rule beneath it.
    static let chipRailHeight: CGFloat = 38
    /// The list column: the sheet's 460, which is also the narrowest the split divider allows (an
    /// HSplitView hands a flexible neighbour the slack, so the floor is what the window opens at);
    /// draggable wider, up to 620.
    static let listWidth: CGFloat = 460
    static let listMaxWidth: CGFloat = 620
    /// The reader pane never drops under this; the reading column inside it is capped at 760.
    static let readerMinWidth: CGFloat = 420
    static let readerColumnMaxWidth: CGFloat = 760
    /// The status footer is 32pt tall.
    static let footerHeight: CGFloat = 32

    /// The footer's right-hand count: "69 sources · 66 ok · 2 stale · 1 failing".
    struct HealthTally: Equatable, Sendable {
        var total = 0
        var ok = 0
        var stale = 0
        var failing = 0

        init(total: Int, ok: Int, stale: Int, failing: Int) {
            self.total = total; self.ok = ok; self.stale = stale; self.failing = failing
        }

        init(healths: [FeedHealth]) {
            total = healths.count
            for health in healths {
                switch health {
                case .ok: ok += 1
                case .stale: stale += 1
                case .failing: failing += 1
                }
            }
        }
    }
}
