import XCTest
@testable import PulseFeed

/// A tool run (the showcase, the catalog check) must not read the owner's provider keys: a stored
/// Finnhub key would change the labels and cards it draws. Its keys live in a temporary folder of its own
/// run, so a key saved in one dry run never shows as added in the next.
final class ProviderKeyStoreToolRunTests: XCTestCase {
    func testToolRunKeysLiveInATemporaryFolder() {
        let tool = ProviderKeyStore.standard(environment: ["PULSEFEED_RENDER_SHOWCASE": "x"])
        XCTAssertTrue(tool.directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        // One folder per run: the same within it (a key saved is read back), never the shared name.
        XCTAssertEqual(ProviderKeyStore.standard(environment: ["PULSEFEED_DEBUG_WELCOME": "1"]).directory, tool.directory)
        XCTAssertNotEqual(tool.directory.lastPathComponent, "PulseFeed-tool-keys")
        XCTAssertEqual(tool.directory, ProviderKeyStore.toolRunDirectory)
        XCTAssertTrue(ProviderKeyStore.toolRunDirectory.lastPathComponent.hasPrefix("PulseFeed-tool-keys-"))
        let normal = ProviderKeyStore.standard(environment: [:])
        XCTAssertTrue(normal.directory.path.hasSuffix("Application Support/PulseFeed"), normal.directory.path)
    }
}
