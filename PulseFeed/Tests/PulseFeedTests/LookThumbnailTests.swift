import XCTest
@testable import PulseFeed

/// The welcome flow's Look step shows a picture of each design (`Contents/Resources/Welcome/look-<design>.png`,
/// copied by `make bundle`); without one it keeps the design's symbol.
final class LookThumbnailTests: XCTestCase {
    private func makeBundleFolder(with files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LookThumbnailTests-\(UUID().uuidString)", isDirectory: true)
        let welcome = root.appendingPathComponent("Welcome", isDirectory: true)
        try FileManager.default.createDirectory(at: welcome, withIntermediateDirectories: true)
        for name in files {
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: welcome.appendingPathComponent(name))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testThumbnailResourceName() throws {
        let folder = try makeBundleFolder(with: ["look-deck.png"])
        let bundle = try XCTUnwrap(Bundle(url: folder))
        let url = try XCTUnwrap(LookThumbnail.url(for: .deck, in: bundle))
        XCTAssertTrue(url.path.hasSuffix("Welcome/look-deck.png"), url.path)
    }

    /// The three pictures `make public-images` writes are committed, so every build's Look step has them.
    func testEveryDesignHasACommittedThumbnail() {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PulseFeed/Resources/Welcome", isDirectory: true)
        for design in AppDesign.allCases {
            let file = folder.appendingPathComponent(LookThumbnail.resourceName(for: design) + ".png")
            let head = (try? Data(contentsOf: file))?.prefix(4)
            XCTAssertEqual(head.map(Array.init), [0x89, 0x50, 0x4E, 0x47], "\(file.path) is missing or not a PNG")
        }
    }

    func testMissingThumbnailIsNil() throws {
        let folder = try makeBundleFolder(with: ["look-deck.png"])
        let bundle = try XCTUnwrap(Bundle(url: folder))
        XCTAssertNil(LookThumbnail.url(for: .stream, in: bundle))
    }
}
