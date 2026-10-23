import XCTest
import AppKit
@testable import PulseFeed

/// The master icon's letter: Archivo Black's "X" outlined to points, placed as on the design sheet.
final class XTileGlyphTests: XCTestCase {
    func testOutlineIsFourteenStraightSegments() {
        XCTAssertEqual(XTileGlyph.points.count, 14)
    }
    func testLetterSitsInsideTheIconGridAndIsCentredAcross() {
        let b = XTileGlyph.bounds
        // Apple's 1024 grid keeps art inside the central 824 square (100…924); the sheet's X spans ~165…862 × ~211…830.
        XCTAssertGreaterThanOrEqual(b.minX, 100); XCTAssertLessThanOrEqual(b.maxX, 924)
        XCTAssertGreaterThanOrEqual(b.minY, 100); XCTAssertLessThanOrEqual(b.maxY, 924)
        XCTAssertEqual(b.midX, 512, accuracy: 3)
        XCTAssertEqual(b.width, 696.6, accuracy: 1)
        XCTAssertEqual(b.height, 619.2, accuracy: 1)
    }
    func testPathScalesWithTheTile() {
        let small = XTileGlyph.path(in: 64).boundingRect
        let full = XTileGlyph.bounds
        XCTAssertEqual(small.width, full.width / 16, accuracy: 0.01)
        XCTAssertEqual(small.minX, full.minX / 16, accuracy: 0.01)
    }
    @MainActor
    func testMenuBarGlyphIsAnEighteenPointTemplate() {
        let image = XTileGlyph.menuBarImage
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(AppIconStyle.xTile.menuBarImage, image)
        XCTAssertNil(AppIconStyle.tileDeck.menuBarImage)
    }
}
