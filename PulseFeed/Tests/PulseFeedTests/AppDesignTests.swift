import XCTest
@testable import PulseFeed

/// The design switch is resolved once at launch: the PULSEFEED_DESIGN environment hook wins,
/// then the stored choice, then Deck.
final class AppDesignTests: XCTestCase {
    func testEnvironmentWinsOverDefaults() {
        XCTAssertEqual(AppDesign.resolve(defaultsValue: "deck", environmentValue: "stream"), .stream)
    }
    func testDefaultsUsedWhenNoEnvironment() {
        XCTAssertEqual(AppDesign.resolve(defaultsValue: "nativePro", environmentValue: nil), .nativePro)
    }
    func testUnknownValuesFallBackToDeck() {
        XCTAssertEqual(AppDesign.resolve(defaultsValue: "board", environmentValue: nil), .deck)
        XCTAssertEqual(AppDesign.resolve(defaultsValue: nil, environmentValue: "PAPER"), .deck)
        XCTAssertEqual(AppDesign.resolve(defaultsValue: nil, environmentValue: nil), .deck)
    }
    func testResolutionIsCaseInsensitive() {
        XCTAssertEqual(AppDesign.resolve(defaultsValue: nil, environmentValue: "NativePro"), .nativePro)
        XCTAssertEqual(AppDesign.resolve(defaultsValue: "STREAM", environmentValue: nil), .stream)
    }
    func testEveryDesignHasNameTaglineAndGlyph() {
        for d in AppDesign.allCases {
            XCTAssertFalse(d.displayName.isEmpty)
            XCTAssertFalse(d.tagline.isEmpty)
            XCTAssertFalse(d.glyphSymbolName.isEmpty)
        }
        XCTAssertEqual(AppDesign.nativePro.displayName, "Native Pro")
    }
}
