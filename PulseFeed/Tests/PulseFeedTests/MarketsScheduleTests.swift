import XCTest
@testable import PulseFeed

final class MarketsScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_670_400)
    private func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }

    func testNothingChosenFetchesNothing() {
        let d = MarketsSchedule.due(tier: .ac, now: now, lastCrypto: .distantPast, lastQuotes: .distantPast, instruments: [])
        XCTAssertFalse(d.crypto)
        XCTAssertFalse(d.quotes)
        XCTAssertNil(MarketsSchedule.secondsUntilDue(tier: .ac, now: now, lastCrypto: .distantPast, lastQuotes: .distantPast, instruments: []))
    }

    func testCryptoEvery120sOnEveryTier() {
        for tier in [PowerTier.ac, .battery, .critical] {
            XCTAssertFalse(MarketsSchedule.due(tier: tier, now: now, lastCrypto: ago(119), lastQuotes: now, instruments: ["bitcoin"]).crypto, "\(tier)")
            XCTAssertTrue(MarketsSchedule.due(tier: tier, now: now, lastCrypto: ago(120), lastQuotes: now, instruments: ["bitcoin"]).crypto, "\(tier)")
        }
    }

    func testQuotesNeverOnCritical() {
        XCTAssertFalse(MarketsSchedule.due(tier: .critical, now: now, lastCrypto: now, lastQuotes: .distantPast, instruments: ["spy"]).quotes)
    }

    func testQuotesRespectTheACAndBatteryIntervals() {
        XCTAssertFalse(MarketsSchedule.due(tier: .ac, now: now, lastCrypto: now, lastQuotes: ago(299), instruments: ["spy"]).quotes)
        XCTAssertTrue(MarketsSchedule.due(tier: .ac, now: now, lastCrypto: now, lastQuotes: ago(300), instruments: ["spy"]).quotes)
        XCTAssertFalse(MarketsSchedule.due(tier: .battery, now: now, lastCrypto: now, lastQuotes: ago(1799), instruments: ["spy"]).quotes)
        XCTAssertTrue(MarketsSchedule.due(tier: .battery, now: now, lastCrypto: now, lastQuotes: ago(1800), instruments: ["spy"]).quotes)
    }

    func testCryptoOnlyListNeedsNoQuoteCall() {
        let d = MarketsSchedule.due(tier: .ac, now: now, lastCrypto: .distantPast, lastQuotes: .distantPast, instruments: ["bitcoin", "solana"])
        XCTAssertTrue(d.crypto)
        XCTAssertFalse(d.quotes)
    }

    /// The scheduler wakes for prices as it does for a feed, so a person with few feeds still gets fresh numbers.
    func testSecondsUntilDueIsTheSoonerOfTheTwo() {
        XCTAssertEqual(MarketsSchedule.secondsUntilDue(tier: .ac, now: now, lastCrypto: ago(100), lastQuotes: ago(10), instruments: ["bitcoin", "spy"]), 20)
        XCTAssertEqual(MarketsSchedule.secondsUntilDue(tier: .ac, now: now, lastCrypto: ago(500), lastQuotes: now, instruments: ["bitcoin"]), 0)
        XCTAssertEqual(MarketsSchedule.secondsUntilDue(tier: .critical, now: now, lastCrypto: now, lastQuotes: .distantPast, instruments: ["spy"]), nil)
    }
}
