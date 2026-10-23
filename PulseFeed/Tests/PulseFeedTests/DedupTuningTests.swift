import XCTest
@testable import PulseFeed

/// Measured on 2026-09-06: with stopwords kept, real cross-outlet duplicates scored below the 0.5
/// title threshold and only 33 of 4,690 stories in a week clustered. Stopwords out, threshold 0.4.
final class DedupTuningTests: XCTestCase {
    func testTokenizerDropsStopwordsAndShortTokens() {
        let t = DedupIndex.tokenize("US hits three Iranian oil tankers after saying its warships were targeted")
        XCTAssertFalse(t.contains("after")); XCTAssertFalse(t.contains("its")); XCTAssertFalse(t.contains("us"))
        XCTAssertTrue(t.contains("iranian")); XCTAssertTrue(t.contains("tankers")); XCTAssertTrue(t.contains("warships"))
    }
    func testRealCrossOutletPairClusters() {
        // BBC vs NPR on the same event: 0.73 without stopwords, under 0.5 with them.
        let index = DedupIndex(candidates: [
            DedupCandidate(articleID: "bbc", feedID: "feed-bbc-world", uniqueID: "1", url: "https://bbc/1",
                           title: "US hits three Iranian oil tankers after saying its warships were targeted",
                           contentPrefix: nil, clusterID: nil, dateArrived: "2026-09-07 03:00:00"),
        ])
        let npr = Article(articleID: "npr", feedID: "feed-npr", uniqueID: "2",
                          title: "US military hits 3 Iranian oil tankers after saying Navy warships were targeted",
                          url: "https://npr/2", dateArrived: "2026-09-07 03:05:00")
        XCTAssertEqual(index.decide(npr), .cluster(primaryID: "bbc"))
    }
    func testTopicNeighboursStillDoNotCluster() {
        let index = DedupIndex(candidates: [
            DedupCandidate(articleID: "a", feedID: "feed-sherdog", uniqueID: "1", url: "https://s/1",
                           title: "Valentina Shevchenko vacates flyweight championship; interim title fight set",
                           contentPrefix: nil, clusterID: nil, dateArrived: "2026-09-07 03:00:00"),
        ])
        let other = Article(articleID: "b", feedID: "feed-mmamania", uniqueID: "2",
                            title: "Paulo Costa: UFC refused to book interim light heavyweight title fight",
                            url: "https://m/2", dateArrived: "2026-09-07 03:05:00")
        XCTAssertEqual(index.decide(other), .insert)
    }
}
