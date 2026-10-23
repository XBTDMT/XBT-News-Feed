import SwiftUI
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

    /// Settings › General › Icon: every tile shows its icon. The 1024-point art used to be scaled about a corner that
    /// sat outside the 48-point frame, so `.clipped()` cut every icon away and the grid showed empty tiles.
    @MainActor func testThumbnailDrawsItsIconInsideTheTile() throws {
        for style in AppIconStyle.allCases {
            let renderer = ImageRenderer(content: AppIconThumbnail(style: style, size: 48))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage, "\(style) did not render")
            XCTAssertEqual(image.width, 48)
            XCTAssertGreaterThan(Self.alpha(of: image, x: 24, y: 24), 0.5, "\(style): the tile's centre is empty")
        }
    }

    private static func alpha(of image: CGImage, x: Int, y: Int) -> CGFloat {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return CGFloat(px[(y * image.width + x) * 4 + 3]) / 255
    }
}
