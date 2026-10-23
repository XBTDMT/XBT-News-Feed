import XCTest
@testable import PulseFeed

/// Stream's picture layout is pure arithmetic and a pure rule, so the popover can size a card
/// before it draws it: the lead's picture is 16:9 of the card width, a row grows only when it
/// carries a thumbnail, and at most `pictureBudget` non-lead stories become picture cards.
final class StreamLayoutTests: XCTestCase {
    // MARK: - Fixtures

    private func story(
        _ id: String, sources: Int = 1, image: Bool = true, priority: String? = nil, read: Bool = false
    ) -> ArticleInfo {
        ArticleInfo(
            articleID: id, feedID: "feed", title: id, url: "https://example.com/\(id)", contentText: nil,
            summary: nil, imageURL: image ? "https://example.com/\(id).jpg" : nil, datePublished: nil,
            dateArrived: "2026-09-07 10:00:00", relevanceScore: nil, priority: priority, isRead: read,
            isStarred: nil, isSaved: nil, isNotified: nil, feedTitle: "Feed", feedCategory: "tech",
            otherSources: sources > 1 ? Array(repeating: "Other", count: sources - 1).joined(separator: ", ") : nil,
            sourceCount: sources)
    }

    private func ids(_ blocks: [StreamBlock]) -> [String] { blocks.map(\.id) }

    // MARK: - Picture height

    func testCategoryLabelIsTheRegistrysLabel() {
        XCTAssertEqual(StreamText.category("ai"), "AI")
        XCTAssertEqual(StreamText.category("f1"), "F1")
        XCTAssertEqual(StreamText.category("motors"), "Cars & Bikes")
        XCTAssertEqual(StreamText.category("finance"), "Finance")
        XCTAssertEqual(StreamText.category("somethingnew"), "Somethingnew")   // not in the registry: capitalised
    }

    func testPictureHeightIsSixteenByNineOfTheWidth() {
        XCTAssertEqual(StreamLayout.pictureHeight(width: 420), 236)
        XCTAssertEqual(StreamLayout.pictureHeight(width: 396), 223)
        XCTAssertEqual(StreamLayout.pictureHeight(width: 480), 270)
        XCTAssertEqual(StreamLayout.pictureAspect, 16.0 / 9.0, accuracy: 0.0001)
    }

    // MARK: - Row height

    func testRowGrowsOnlyForAThumbnail() {
        XCTAssertEqual(StreamLayout.thumbnailSide, 64)
        XCTAssertEqual(StreamLayout.rowHeight(hasThumbnail: false), 34)
        XCTAssertEqual(StreamLayout.rowHeight(hasThumbnail: true), 76)
    }

    func testHasPictureNeedsAParseableURL() {
        XCTAssertTrue(StreamLayout.hasPicture(story("a")))
        XCTAssertFalse(StreamLayout.hasPicture(story("b", image: false)))
        var blank = story("c")
        blank.imageURL = ""
        XCTAssertFalse(StreamLayout.hasPicture(blank))
        var junk = story("d")
        junk.imageURL = "not a url"
        XCTAssertFalse(StreamLayout.hasPicture(junk))
    }

    // MARK: - Picture cards

    func testZeroBudgetKeepsTodaysBlocks() {
        let list = [story("lead"), story("cluster", sources: 3), story("pair", sources: 2), story("solo")]
        let blocks = StreamLayout.blocks(list, heroID: "lead", cardsAllowed: true, pictureBudget: 0)
        XCTAssertEqual(ids(blocks), ["hero-lead", "cluster-cluster", "rows-pair"])
        XCTAssertEqual(StreamLayout.pictureCards(in: blocks), 0)
    }

    func testMultiSourceStoriesWithAnImageBecomePictureCardsWhileTheBudgetLasts() {
        let list = [
            story("lead"), story("p1", sources: 2), story("solo"), story("p2", sources: 3), story("p3", sources: 3),
            story("p4", sources: 2),
        ]
        let blocks = StreamLayout.blocks(list, heroID: "lead", cardsAllowed: true, pictureBudget: 2)
        // p3 is a 3-source story past the budget: the thumbnail cluster card. p4 is 2-source: a row.
        XCTAssertEqual(ids(blocks), ["hero-lead", "picture-p1", "rows-solo", "picture-p2", "cluster-p3", "rows-p4"])
        XCTAssertEqual(StreamLayout.pictureCards(in: blocks), 2)
    }

    func testAStoryWithoutAnImageNeverBecomesAPictureCardAndSpendsNoBudget() {
        let list = [story("lead"), story("bare3", sources: 3, image: false), story("bare2", sources: 2, image: false), story("p1", sources: 2)]
        let blocks = StreamLayout.blocks(list, heroID: "lead", cardsAllowed: true, pictureBudget: 1)
        XCTAssertEqual(ids(blocks), ["hero-lead", "cluster-bare3", "rows-bare2", "picture-p1"])
    }

    func testSingleSourceStoriesStayRowsWhateverTheBudget() {
        let list = [story("lead"), story("a"), story("b")]
        let blocks = StreamLayout.blocks(list, heroID: "lead", cardsAllowed: true, pictureBudget: 5)
        XCTAssertEqual(ids(blocks), ["hero-lead", "rows-a"])
    }

    func testTheLeadIsAlwaysTheHeroAndNeverSpendsTheBudget() {
        let list = [story("lead", sources: 3), story("p1", sources: 2)]
        let blocks = StreamLayout.blocks(list, heroID: "lead", cardsAllowed: true, pictureBudget: 1)
        XCTAssertEqual(ids(blocks), ["hero-lead", "picture-p1"])
        XCTAssertTrue(blocks[0].isHero)
        XCTAssertFalse(blocks[1].isHero)
    }

    func testNoCardsMeansOnlyRows() {
        let list = [story("lead", sources: 3), story("p1", sources: 3), story("solo")]
        let blocks = StreamLayout.blocks(list, heroID: "lead", cardsAllowed: false, pictureBudget: 2)
        XCTAssertEqual(ids(blocks), ["rows-lead"])
        XCTAssertEqual(StreamLayout.pictureCards(in: blocks), 0)
    }

    func testBudgetDefaultsToZeroForExistingCallers() {
        let list = [story("lead"), story("p1", sources: 2)]
        XCTAssertEqual(ids(StreamLayout.blocks(list, heroID: "lead", cardsAllowed: true)), ["hero-lead", "rows-p1"])
    }
}
