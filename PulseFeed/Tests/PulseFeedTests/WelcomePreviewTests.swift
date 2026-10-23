import XCTest
@testable import PulseFeed

/// Answers every request with HTTP 500.
final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("oops".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WelcomePreviewTests: XCTestCase {
    private var catalog: Catalog!
    private var draft = WelcomeDraft()

    override func setUpWithError() throws {
        catalog = try Catalog.load(from: CatalogTests.catalogURL).forBuild(providers: ["balldontlie"])
    }

    func testSamplesTwoSourcesPerTopicFromSixTopics() {
        draft.topics = ["tech", "ai", "nba", "world", "music", "travel", "golf", "pets"]
        let sample = WelcomePreview.sourcesToSample(draft, catalog: catalog, region: "us")
        XCTAssertLessThanOrEqual(sample.count, 12)
        XCTAssertEqual(Set(sample.map(\.1.id)), Set(draft.topics.prefix(6)))
        for t in draft.topics.prefix(6) { XCTAssertLessThanOrEqual(sample.filter { $0.1.id == t }.count, 2) }
    }

    func testSkipsSwitchedOffAndJSONSources() throws {
        draft.topics = ["nba"]
        let all = draft.sources(catalog: catalog, region: "us").first!.sources.filter { $0.type == "rss" }
        let first = try XCTUnwrap(all.first)
        draft.sourceSwitches[first.url] = false
        let sample = WelcomePreview.sourcesToSample(draft, catalog: catalog, region: "us")
        XCTAssertFalse(sample.contains { $0.0.url == first.url })
        XCTAssertTrue(sample.allSatisfy { $0.0.type == "rss" })
    }

    func testMergeNewestFirstUniqueAndCapped() {
        func h(_ t: String, _ s: TimeInterval?) -> PreviewHeadline {
            PreviewHeadline(title: t, source: "S", topicLabel: "T", date: s.map { Date(timeIntervalSince1970: $0) })
        }
        let merged = WelcomePreview.merge([h("Old", 1), h("New", 3), h("new", 2), h("Undated", nil), h("Mid", 2)], limit: 3)
        XCTAssertEqual(merged.map(\.title), ["New", "Mid", "Old"])
        XCTAssertEqual(WelcomePreview.merge([h("A", nil), h("B", 1)], limit: 8).map(\.title), ["B", "A"])
    }

    func testFailingFetchYieldsNoHeadlinesNotAnError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        let preview = WelcomePreview(session: URLSession(configuration: config))
        draft.topics = ["tech"]
        let headlines = await preview.headlines(for: draft, catalog: catalog, region: "us")
        XCTAssertEqual(headlines, [])
    }
}
