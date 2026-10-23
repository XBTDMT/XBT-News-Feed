import XCTest
@testable import PulseFeed

/// `make showcase`'s pure parts: what the picture server answers, the captions' typography, the Stream window's
/// render height, and which rows of the Alerts step the X picture keeps.
@MainActor
final class ShowcaseComposerTests: XCTestCase {
    func testPictureNameIsTheRequestedFileOnly() {
        XCTAssertEqual(ShowcasePictures.pictureName(requestLine: "GET /merrow.jpg HTTP/1.1"), "merrow")
        XCTAssertEqual(ShowcasePictures.pictureName(requestLine: "GET /a/b/../sorrel.jpg?x=1 HTTP/1.1"), "sorrel")
        XCTAssertEqual(ShowcasePictures.pictureName(requestLine: "GET /../../etc/passwd HTTP/1.1"), "passwd")
        XCTAssertEqual(ShowcasePictures.pictureName(requestLine: "garbage"), "")
    }

    func testCaptionsUseTypographicApostrophes() {
        var captions = ShowcaseComposer.stepCaptions.flatMap { [$0.0, $0.1] }
        captions += Array(ShowcaseComposer.designLines.values) + Array(ShowcaseComposer.menuBarLabels.values)
        captions += [ShowcaseComposer.menuBarTitle, ShowcaseComposer.menuBarSubtitle, ShowcaseComposer.alertsTitle,
                     ShowcaseComposer.alertsBody, ShowcaseComposer.socialLine]
        for caption in captions { XCTAssertFalse(caption.contains("'"), caption) }
        XCTAssertTrue(ShowcaseComposer.stepCaptions.contains { $0.0 == "You\u{2019}re set" })
    }

    /// The red dot appears only when the model rates an unread story breaking (no model, no dot): the
    /// captions say so rather than promising a dot for every breaking story.
    func testMenuBarCaptionsSayTheDotIsTheModelsRating() {
        XCTAssertTrue(ShowcaseComposer.menuBarSubtitle.contains("model rates"), ShowcaseComposer.menuBarSubtitle)
        XCTAssertTrue(ShowcaseComposer.menuBarLabels["breaking-dot"]?.contains("rated breaking") ?? false)
    }

    func testStreamWindowRendersTallerSoItsRailEndsInside() {
        for design in AppDesign.allCases {
            let size = ShowcaseRenderer.windowRenderSize(design)
            XCTAssertEqual(size.width, design.mainWindowDefaultSize.width)
            XCTAssertEqual(size.height, design.mainWindowDefaultSize.height + (design == .stream ? ShowcaseRenderer.streamExtraHeight : 0), "\(design)")
            if design == .stream { XCTAssertGreaterThan(size.height, design.mainWindowDefaultSize.height) }
        }
    }

    /// The Alerts step's bands: title, subtitle, the break-through bullets, then each mode's row and banner,
    /// Quiet, the recap interval and the notifications row. The X picture keeps "Breaking + recap" (the band
    /// before the first banner-tall band) down to the recap interval (the band before the last), padded by up to
    /// 40 px but never into the bands it leaves out.
    func testAlertsDetailRowsRunFromTheFirstModeToTheRecapInterval() {
        let bands = [56...97, 113...136, 187...210, 222...241, 254...273, 280...296, 312...331, 364...392, 406...493,
                     524...552, 566...653, 684...709, 730...749, 779...825, 849...895]
        XCTAssertEqual(ShowcaseComposer.alertsDetailRows(bands: bands), 332...848)
        XCTAssertNil(ShowcaseComposer.alertsDetailRows(bands: [56...97, 113...136]))
    }

    func testContentBandsFindRowsOfContent() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 30, y: 100 - 40, width: 50, height: 20))   // rows 20…39 from the top
        ctx.fill(CGRect(x: 30, y: 100 - 80, width: 90, height: 10))   // rows 70…79
        let image = try XCTUnwrap(ctx.makeImage())
        XCTAssertEqual(ShowcaseComposer.contentBands(image, rows: 100), [20...39, 70...79])
    }
}
