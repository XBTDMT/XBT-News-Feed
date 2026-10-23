import XCTest
@testable import PulseFeed

/// Category enablement drives three things: which chips appear (FilterBar order merging), which
/// categories may notify, and which feeds poll (feed.isEnabled, tested through SQL elsewhere).
final class CategorySettingsTests: XCTestCase {
    func testNotificationSettingsDefaultToEveryCategoryOn() {
        let s = NotificationSettings.fromDefaults(UserDefaults(suiteName: "CategorySettingsTests-empty")!)
        XCTAssertTrue(s.isCategoryEnabled("crypto"))
        XCTAssertTrue(s.isCategoryEnabled("travel"))
        XCTAssertTrue(s.isCategoryEnabled("unknown"))
    }
    func testNotificationCategoryCanBeSwitchedOff() {
        let d = UserDefaults(suiteName: "CategorySettingsTests-off")!
        d.set(false, forKey: "notif_music")
        let s = NotificationSettings.fromDefaults(d)
        XCTAssertFalse(s.isCategoryEnabled("music"))
        XCTAssertTrue(s.isCategoryEnabled("crypto"))
        d.removePersistentDomain(forName: "CategorySettingsTests-off")
    }
    func testChipOrderMergesNewCategoriesBeforeStarredAndHidesDisabled() {
        let stored = ["all", "digest", "crypto", "tech", "starred", "saved"]
        let merged = FilterBar.mergedOrder(stored: stored, enabled: ["crypto", "travel", "gaming"])
        XCTAssertEqual(merged, ["all", "digest", "crypto", "travel", "gaming", "starred", "saved"])
    }
    func testChipOrderWithoutStoredOrderIsRegistryOrder() {
        let merged = FilterBar.mergedOrder(stored: nil, enabled: ["world", "ai"])
        XCTAssertEqual(merged, ["all", "digest", "ai", "world", "starred", "saved"])
    }
}
