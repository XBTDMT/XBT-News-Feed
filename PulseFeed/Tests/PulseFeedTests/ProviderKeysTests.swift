import XCTest
@testable import PulseFeed

final class ProviderKeysTests: XCTestCase {
    private var dir: URL!
    private var store: ProviderKeyStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = ProviderKeyStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testKeyIsTrimmedAndEmptyMeansNone() throws {
        try store.set(.finnhub, "  abc123\n")
        XCTAssertEqual(store.get(.finnhub), "abc123")
        try store.set(.balldontlie, "   ")
        XCTAssertNil(store.get(.balldontlie))
    }

    func testKeyFileIsOwnerOnly() throws {
        try store.set(.finnhub, "abc123")
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(".finnhub-key").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRemoveForgetsTheKey() throws {
        try store.set(.balldontlie, "k")
        store.remove(.balldontlie)
        XCTAssertNil(store.get(.balldontlie))
    }

    func testFinnhubRequest() {
        let r = ProviderKeyTest.request(.finnhub, value: "abc123")
        XCTAssertEqual(r.url?.absoluteString, "https://finnhub.io/api/v1/quote?symbol=AAPL&token=abc123")
        XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
    }

    func testBallDontLieRequest() {
        let r = ProviderKeyTest.request(.balldontlie, value: "abc123")
        XCTAssertEqual(r.url?.absoluteString, "https://api.balldontlie.io/v1/teams")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "abc123")
    }

    func testFailedResponsesDoNotPass() {
        func d(_ s: String) -> Data { Data(s.utf8) }
        XCTAssertFalse(ProviderKeyTest.passed(.finnhub, status: 401, body: d(#"{"error":"Invalid API key"}"#)))
        XCTAssertFalse(ProviderKeyTest.passed(.finnhub, status: 200, body: d(#"{"c":0,"d":null}"#)))
        XCTAssertTrue(ProviderKeyTest.passed(.finnhub, status: 200, body: d(#"{"c":348.34,"dp":1.26}"#)))
        XCTAssertFalse(ProviderKeyTest.passed(.balldontlie, status: 401, body: d("Unauthorized")))
        XCTAssertFalse(ProviderKeyTest.passed(.balldontlie, status: 200, body: d(#"{"data":[]}"#)))
        XCTAssertTrue(ProviderKeyTest.passed(.balldontlie, status: 200, body: d(#"{"data":[{"id":1}]}"#)))
    }

    func testCardCopyCoversEveryD13Point() {
        for key in ProviderKey.allCases {
            XCTAssertFalse(ProviderKeyCopy.title(key).isEmpty)
            XCTAssertFalse(ProviderKeyCopy.whatChanges(key).isEmpty)
            XCTAssertTrue(ProviderKeyCopy.cost(key).contains("Free"))
            XCTAssertTrue(ProviderKeyCopy.cost(key).contains("minute"))
            XCTAssertTrue(ProviderKeyCopy.privacy(key).contains("stays on this Mac"))
            XCTAssertTrue(ProviderKeyCopy.privacy(key).contains(key.providerName))
            XCTAssertTrue(ProviderKeyCopy.skip(key).contains("Skipping is fine"))
        }
        XCTAssertEqual(ProviderKeyCopy.signUpURL(.finnhub).absoluteString, "https://finnhub.io/register")
        XCTAssertEqual(ProviderKeyCopy.signUpURL(.balldontlie).absoluteString, "https://app.balldontlie.io/")
    }

    /// Offline, rate-limited or a server error is "couldn't check", never "your key is wrong".
    func testUnreachableIsNotABadKey() {
        let ok = Data(#"{"c":348.34}"#.utf8)
        XCTAssertEqual(ProviderKeyTest.outcome(.finnhub, status: nil, body: Data()), .unreachable)
        XCTAssertEqual(ProviderKeyTest.outcome(.finnhub, status: 429, body: Data()), .unreachable)
        XCTAssertEqual(ProviderKeyTest.outcome(.balldontlie, status: 503, body: Data()), .unreachable)
        XCTAssertEqual(ProviderKeyTest.outcome(.finnhub, status: 401, body: Data()), .rejected)
        XCTAssertEqual(ProviderKeyTest.outcome(.balldontlie, status: 403, body: Data()), .rejected)
        XCTAssertEqual(ProviderKeyTest.outcome(.finnhub, status: 200, body: ok), .passed)
        XCTAssertEqual(ProviderKeyTest.outcome(.finnhub, status: 200, body: Data(#"{"c":0}"#.utf8)), .rejected)
        XCTAssertTrue(ProviderKeyCopy.unreachable(.finnhub).contains("Finnhub"))
    }
}
