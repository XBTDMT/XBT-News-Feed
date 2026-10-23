import XCTest
@testable import PulseFeed

/// Settings › General › Icon: the master icon (X-Tile) plus the ten sheet icons; "auto" = the master.
final class AppIconStyleTests: XCTestCase {
    func testAutoIsTheMasterForEveryDesign() {
        XCTAssertEqual(AppIconStyle.master, .xTile)
        XCTAssertEqual(AppIconStyle.resolve(stored: nil, design: .nativePro), .xTile)
        XCTAssertEqual(AppIconStyle.resolve(stored: "auto", design: .deck), .xTile)
        XCTAssertEqual(AppIconStyle.resolve(stored: "", design: .stream), .xTile)
    }
    func testStoredChoiceWinsOverTheDesign() {
        XCTAssertEqual(AppIconStyle.resolve(stored: "morningBrief", design: .deck), .morningBrief)
        XCTAssertEqual(AppIconStyle.resolve(stored: "GlassHUD", design: .stream), .glassHUD)
        XCTAssertEqual(AppIconStyle.resolve(stored: "xtile", design: .stream), .xTile)
    }
    func testUnknownFallsBackToTheMaster() {
        XCTAssertEqual(AppIconStyle.resolve(stored: "board", design: .stream), .xTile)
    }
    func testElevenStylesEachHaveANameAndAGlyph() {
        XCTAssertEqual(AppIconStyle.allCases.count, 11)
        XCTAssertEqual(AppIconStyle.allCases.first, .xTile)
        for s in AppIconStyle.allCases {
            XCTAssertFalse(s.displayName.isEmpty)
            XCTAssertFalse(s.glyphSymbolName.isEmpty)
        }
    }
    func testOnlyTheMasterIsBakedIntoTheBundle() {
        XCTAssertTrue(AppIconStyle.xTile.isMaster)
        for s in AppIconStyle.allCases where s != .xTile {
            XCTAssertFalse(s.isMaster, s.rawValue)
        }
    }
}
