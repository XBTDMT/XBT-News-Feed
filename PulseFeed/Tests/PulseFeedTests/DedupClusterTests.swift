import XCTest
@testable import PulseFeed

/// DedupIndex replaces destructive dedup with cluster-or-drop decisions:
/// exact URL / same-feed near-duplicates are dropped; cross-feed matches are kept
/// and pointed at the primary article via `clusterID`.
final class DedupClusterTests: XCTestCase {

    private func candidate(
        id: String, feed: String, url: String? = nil, title: String?,
        content: String? = nil, cluster: String? = nil, arrived: String = "2026-09-05 10:00:00"
    ) -> DedupCandidate {
        DedupCandidate(
            articleID: id, feedID: feed, url: url, title: title,
            contentPrefix: content, clusterID: cluster, dateArrived: arrived)
    }

    private func article(
        id: String, feed: String, url: String? = nil, title: String?,
        content: String? = nil, arrived: String = "2026-09-05 10:05:00"
    ) -> Article {
        Article(
            articleID: id, feedID: feed, uniqueID: id, title: title, url: url,
            contentText: content, dateArrived: arrived, priority: "fyi")
    }

    func testExactURLMatchIsDroppedEvenAcrossFeeds() {
        let index = DedupIndex(candidates: [
            candidate(id: "e1", feed: "feed-a", url: "https://x.com/story?utm=1", title: "Anything")
        ])
        let new = article(id: "n1", feed: "feed-b", url: "https://x.com/story", title: "Different title entirely")
        XCTAssertEqual(index.decide(new), .drop)
    }

    func testSameFeedNearIdenticalTitleIsDropped() {
        let index = DedupIndex(candidates: [
            candidate(id: "e1", feed: "feed-a", title: "Verstappen wins Monza after late safety car drama")
        ])
        let new = article(id: "n1", feed: "feed-a", title: "Verstappen wins Monza after late safety car drama!")
        XCTAssertEqual(index.decide(new), .drop)
    }

    func testCrossFeedSimilarTitleClustersToExistingPrimary() {
        let index = DedupIndex(candidates: [
            candidate(id: "e1", feed: "feed-a", title: "Verstappen wins Monza after late safety car drama")
        ])
        let new = article(id: "n1", feed: "feed-b", title: "Verstappen wins Monza following late safety car drama")
        XCTAssertEqual(index.decide(new), .cluster(primaryID: "e1"))
    }

    func testCrossFeedMatchAgainstSecondaryResolvesToItsPrimary() {
        // e2 is already a secondary of e1; a new match against e2 must point at e1.
        let index = DedupIndex(candidates: [
            candidate(id: "e1", feed: "feed-a", title: "Fed holds rates steady, signals two cuts this year"),
            candidate(id: "e2", feed: "feed-b", title: "Fed holds rates steady and signals two cuts this year", cluster: "e1"),
        ])
        let new = article(id: "n1", feed: "feed-c", title: "Fed holds rates steady and signals two cuts this year")
        XCTAssertEqual(index.decide(new), .cluster(primaryID: "e1"))
    }

    func testUnrelatedArticleIsInserted() {
        let index = DedupIndex(candidates: [
            candidate(id: "e1", feed: "feed-a", title: "Lakers beat Celtics in overtime thriller")
        ])
        let new = article(id: "n1", feed: "feed-b", title: "Bitcoin ETF inflows hit record as price nears 100k")
        XCTAssertEqual(index.decide(new), .insert)
    }

    func testApplySetsClusterIDOnClusteredArticlesAndCountsDrops() {
        let index = DedupIndex(candidates: [
            candidate(id: "e1", feed: "feed-a", url: "https://a.com/1", title: "Apple unveils new M5 MacBook Pro lineup"),
        ])
        let dup = article(id: "n1", feed: "feed-a", url: "https://a.com/1", title: "whatever")
        let cross = article(id: "n2", feed: "feed-b", title: "Apple unveils the new M5 MacBook Pro lineup")
        let fresh = article(id: "n3", feed: "feed-b", title: "SEC approves spot Solana ETF applications")

        let result = index.apply([dup, cross, fresh])

        XCTAssertEqual(result.dropped, 1)
        XCTAssertEqual(result.clustered, 1)
        XCTAssertEqual(result.toInsert.map(\.articleID), ["n2", "n3"])
        XCTAssertEqual(result.toInsert[0].clusterID, "e1")
        XCTAssertNil(result.toInsert[1].clusterID)
    }

    func testClusterAmongBatchPointsLaterCrossFeedCopiesAtEarliest() {
        let first = article(id: "b1", feed: "feed-a", title: "Nvidia posts record quarterly revenue on AI demand", arrived: "2026-09-05 10:00:00")
        let second = article(id: "b2", feed: "feed-b", title: "Nvidia posts record quarterly revenue amid AI demand", arrived: "2026-09-05 10:00:03")
        let sameFeedNear = article(id: "b3", feed: "feed-a", title: "Nvidia posts record quarterly revenue on AI demand today", arrived: "2026-09-05 10:00:05")
        let unrelated = article(id: "b4", feed: "feed-c", title: "UFC 320 main card results and highlights", arrived: "2026-09-05 10:00:07")

        let clustered = DedupIndex.clusterAmong([second, unrelated, first, sameFeedNear])
        let byID = Dictionary(uniqueKeysWithValues: clustered.map { ($0.articleID, $0.clusterID) })

        XCTAssertEqual(clustered.count, 4, "clusterAmong must not drop anything")
        XCTAssertNil(byID["b1"] ?? nil)
        XCTAssertEqual(byID["b2"] ?? nil, "b1")
        XCTAssertNil(byID["b3"] ?? nil, "same-feed near-duplicates within a batch are left alone")
        XCTAssertNil(byID["b4"] ?? nil)
    }
}
