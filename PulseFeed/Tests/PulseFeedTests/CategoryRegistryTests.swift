import XCTest
@testable import PulseFeed

/// One registry for every category the app knows: id, label, colour, symbol, and whether it is ON
/// for an install in use by default. Anything not in the registry falls back to a neutral entry.
final class CategoryRegistryTests: XCTestCase {
    func testAnInstallInUseHasItsCategoriesOnByDefaultAndTheGeneralOnesOff() {
        let on = Set(NewsCategory.all.filter(\.defaultEnabled).map(\.id))
        for id in ["crypto", "tech", "ai", "sports", "f1", "finance", "world", "travel", "music", "motors"] {
            XCTAssertTrue(on.contains(id), "\(id) should be on by default")
        }
        for id in ["politics", "science", "health", "gaming", "entertainment"] {
            XCTAssertFalse(on.contains(id), "\(id) should be off by default")
        }
    }
    func testEveryCategoryHasLabelShortColourAndSymbol() {
        for c in NewsCategory.all {
            XCTAssertFalse(c.label.isEmpty); XCTAssertFalse(c.short.isEmpty)
            XCTAssertTrue(c.colorHex.hasPrefix("#") && c.colorHex.count == 7, c.colorHex)
            XCTAssertFalse(c.symbol.isEmpty)
        }
        XCTAssertEqual(Set(NewsCategory.all.map(\.id)).count, NewsCategory.all.count, "ids are unique")
    }
    func testLookupFallsBackToGeneral() {
        XCTAssertEqual(NewsCategory.named("f1").label, "F1")
        XCTAssertEqual(NewsCategory.named("motors").label, "Cars & Bikes")
        XCTAssertEqual(NewsCategory.named("unknown-thing").id, "general")
        XCTAssertEqual(NewsCategory.named("general").short, "News")
    }
    func testDigestBadgeUsesTheShortLabel() {
        XCTAssertEqual(NewsCategory.named("crypto").badge, "BTC")
        XCTAssertEqual(NewsCategory.named("world").badge, "WRLD")
        XCTAssertEqual(NewsCategory.named("ai").badge, "AI")
    }
    func testVisibleOrderKeepsRegistryOrderAndDropsHidden() {
        let visible = NewsCategory.visible(enabledIDs: ["world", "crypto", "gaming"])
        XCTAssertEqual(visible.map(\.id), ["crypto", "world", "gaming"])
    }
}

/// Bar charts have room for about six categories; show the ones with the most unread, in registry
/// order, and let the expanded/rail views list the rest.
final class TopCategoriesTests: XCTestCase {
    func testKeepsTheSixLargestInRegistryOrder() {
        let counts = ["crypto": 1, "tech": 176, "ai": 989, "sports": 148, "f1": 0, "finance": 0, "world": 0, "travel": 55, "music": 144, "motors": 128]
        let top = NewsCategory.top(NewsCategory.visible(enabledIDs: Set(counts.keys)), counts: counts, limit: 6)
        XCTAssertEqual(top.map(\.id), ["tech", "ai", "sports", "travel", "music", "motors"])
    }
    func testFewerThanLimitIsUnchanged() {
        let some = NewsCategory.visible(enabledIDs: ["world", "crypto"])
        XCTAssertEqual(NewsCategory.top(some, counts: [:], limit: 6).map(\.id), ["crypto", "world"])
    }
    func testTiesBreakByRegistryOrder() {
        let all = NewsCategory.visible(enabledIDs: Set(NewsCategory.all.map(\.id)))
        XCTAssertEqual(NewsCategory.top(all, counts: [:], limit: 3).map(\.id), ["crypto", "tech", "ai"])
    }

    /// The catalog's Life group needs chips of its own; both ship off, so no existing chip row changes.
    func testFoodAndLifeExistAndShipOff() {
        XCTAssertEqual(NewsCategory.named("food").label, "Food")
        XCTAssertEqual(NewsCategory.named("life").label, "Life")
        XCTAssertFalse(NewsCategory.named("food").defaultEnabled)
        XCTAssertFalse(NewsCategory.named("life").defaultEnabled)
    }
}
