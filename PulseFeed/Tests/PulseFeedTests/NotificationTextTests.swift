import XCTest
@testable import PulseFeed

/// A macOS banner shows title, subtitle and about two lines of body before it truncates. These tests
/// pin the two things that decide whether the visible part is useful: the news leads, and a cut
/// lands on a sentence or a word rather than in the middle of one.
final class NotificationTextTests: XCTestCase {

    // MARK: - clip

    func testTextInsideTheLimitIsUntouched() {
        XCTAssertEqual(NotificationText.clip("Bitcoin fell 3%.", to: 100), "Bitcoin fell 3%.")
    }

    func testCutsOnASentenceEndWhenOneFallsLateEnough() {
        let text = "The Fed cut rates by 25 basis points. Markets rallied through the afternoon and closed higher."
        let clipped = NotificationText.clip(text, to: 60)
        XCTAssertEqual(clipped, "The Fed cut rates by 25 basis points.")
        XCTAssertFalse(clipped.hasSuffix("…"))
    }

    func testCutsOnAWordBoundaryWhenTheSentenceEndIsTooEarly() {
        // The only full stop is 5 characters in — keeping just "U.S." would throw away the room.
        let text = "U.S. lawmakers moved to advance the spending package before the midnight deadline"
        let clipped = NotificationText.clip(text, to: 40)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertLessThanOrEqual(clipped.count, 41)
        XCTAssertTrue(clipped.hasPrefix("U.S. lawmakers moved"))
        // Never mid-word: the character before the ellipsis ends a whole word.
        XCTAssertFalse(clipped.dropLast().hasSuffix("advanc"))
    }

    func testNeverCutsMidWord() {
        let text = "Ronaldo announces retirement from international football after twenty-one years"
        for limit in 10...70 {
            let clipped = NotificationText.clip(text, to: limit)
            let body = clipped.hasSuffix("…") ? String(clipped.dropLast()) : clipped
            guard body.count < text.count else { continue }
            let nextCharacter = text[text.index(text.startIndex, offsetBy: body.count)]
            XCTAssertTrue(nextCharacter == " ", "limit \(limit) cut mid-word: \(clipped)")
        }
    }

    func testASingleUnbrokenWordStillGetsAnEllipsis() {
        let clipped = NotificationText.clip("Supercalifragilisticexpialidocious", to: 10)
        XCTAssertEqual(clipped, "Supercalif…")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(NotificationText.clip("   Markets rallied.   ", to: 100), "Markets rallied.")
    }

    // MARK: - leadLine

    func testLeadLineNamesTheHeadlineFirst() {
        let line = NotificationText.leadLine(headlines: ["Fed cuts rates"], others: ["Weather turns"])
        XCTAssertTrue(line.hasPrefix("Fed cuts rates"))
    }

    func testLeadLineJoinsWhileItFitsAndStopsBeforeOverflowing() {
        let line = NotificationText.leadLine(
            headlines: ["Fed cuts rates"],
            others: ["Lakers trade Davis", "OpenAI ships a new model", "A story that will not fit here"],
            limit: 60)
        // "Fed cuts rates · Lakers trade Davis" is 35; adding the next item would reach 62.
        XCTAssertEqual(line, "Fed cuts rates · Lakers trade Davis")
        XCTAssertLessThanOrEqual(line.count, 60)
    }

    func testLeadLineFallsBackToOthersWhenThereAreNoHeadlines() {
        XCTAssertEqual(NotificationText.leadLine(headlines: [], others: ["Weather turns"]), "Weather turns")
    }

    func testLeadLineIsEmptyOnlyWhenThereIsNothingToSay() {
        XCTAssertEqual(NotificationText.leadLine(headlines: [], others: []), "")
        XCTAssertEqual(NotificationText.leadLine(headlines: ["   "], others: []), "")
    }

    func testLeadLineClipsASingleOversizedHeadline() {
        let long = String(repeating: "news ", count: 60)
        let line = NotificationText.leadLine(headlines: [long], others: [], limit: 40)
        XCTAssertLessThanOrEqual(line.count, 41)
        XCTAssertFalse(line.isEmpty)
    }

    func testLeadLineCollapsesNewlinesSoItStaysOneLine() {
        let line = NotificationText.leadLine(headlines: ["Fed cuts\nrates today"], others: [])
        XCTAssertEqual(line, "Fed cuts rates today")
    }

    // MARK: - urgentSubtitle

    func testUrgentSubtitleLeadsWithTheReasonNotTheOutlet() {
        let subtitle = NotificationText.urgentSubtitle(reason: "Lakers", sourceCount: 4, feedTitle: "ESPN")
        XCTAssertEqual(subtitle, "Lakers · 4 sources · ESPN")
        XCTAssertTrue(subtitle.hasPrefix("Lakers"))
    }

    func testUrgentSubtitleDropsTheCountForASingleSource() {
        XCTAssertEqual(NotificationText.urgentSubtitle(reason: "Breaking", sourceCount: 1, feedTitle: "Reuters"),
                       "Breaking · Reuters")
    }

    func testUrgentSubtitleSkipsEmptyParts() {
        XCTAssertEqual(NotificationText.urgentSubtitle(reason: "Breaking", sourceCount: 1, feedTitle: ""), "Breaking")
    }
}

/// The recap banner as it is actually assembled. The title only ever says how many stories there
/// are, so these pin the two fields that have to carry the news instead.
final class RecapBannerTests: XCTestCase {
    func testThePlainRecapNamesItsHeadlinesInTheSubtitle() throws {
        let summary = try XCTUnwrap(SummaryComposer.plainSummary(
            headlines: ["Fed cuts rates by 25bp"],
            others: ["Lakers trade Davis", "OpenAI ships a model", "Rain in Milan"]))

        XCTAssertEqual(summary.title, "What's new · 4 stories")
        XCTAssertTrue(summary.subtitle.hasPrefix("Fed cuts rates by 25bp"),
                      "the always-visible line must lead with the lead story, got: \(summary.subtitle)")
        XCTAssertTrue(summary.subtitle.contains("Lakers trade Davis"))
        XCTAssertTrue(summary.body.hasPrefix("Fed cuts rates by 25bp"))
    }

    func testTheSubtitleIsNeverEmptyWhenThereIsAStory() throws {
        let summary = try XCTUnwrap(SummaryComposer.plainSummary(headlines: [], others: ["Rain in Milan"]))
        XCTAssertFalse(summary.subtitle.isEmpty)
        XCTAssertEqual(summary.subtitle, "Rain in Milan")
    }

    func testTheSubtitleStaysOnOneLineWhateverTheHeadlinesLookLike() {
        let long = (1...10).map { "A very long headline number \($0) about something that happened" }
        let subtitle = SummaryComposer.subtitle(headlines: long, others: [])
        XCTAssertLessThanOrEqual(subtitle.count, NotificationText.leadLineLimit + 1)
        XCTAssertFalse(subtitle.contains("\n"))
    }

    func testThePromptDemandsAStandaloneFirstSentence() {
        let prompt = SummaryComposer.prompt(headlines: ["A"], others: ["B"])
        XCTAssertTrue(prompt.system.contains("FIRST sentence"),
                      "only the first sentence is visible before the reader opens the banner")
    }
}
