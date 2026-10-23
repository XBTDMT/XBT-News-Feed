import XCTest
import GRDB
import CryptoKit
@testable import PulseFeed

/// What the migrations seed. The private flavour's v1 runs exactly the SQL it always ran (GRDB records
/// only the identifier, so a changed text would never reach an existing database, but a new private
/// install must still match the old ones); the public flavour seeds no personal interests and no row for
/// a private-only provider (ESPN's site API, Binance's stream, Yahoo Finance).
final class MigrationSeedTests: XCTestCase {


    func testPublicSeedHasNoPersonalInterests() throws {
        let q = try migrated()
        let interests = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userInterest") }
        XCTAssertEqual(interests, 0)
    }

    /// The hosts are matched loosely (ESPN's site API path, any Binance or Yahoo URL) so this file spells out
    /// none of the hosts the public copy must not carry.
    func testPublicSeedHasNoPrivateProviderFeeds() throws {
        let q = try migrated()
        let (ids, hosts) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE id IN ('feed-espn-nba', 'feed-binance-ws')"),
             try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM feed WHERE url LIKE '%espn.com/apis%' OR url LIKE '%binance%'
                    OR url LIKE '%yahoo%'
                """))
        }
        XCTAssertEqual(ids, 0)
        XCTAssertEqual(hosts, 0)
    }

    // MARK: - Helpers

    private func migrated() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try AppDatabase.migrator.migrate(q)
        return q
    }

    /// The statements v1 runs: everything between the migrator's BEGIN and its record of the identifier.
    private func v1Statements() throws -> [String] {
        nonisolated(unsafe) var traced: [String] = []
        var config = Configuration()
        config.prepareDatabase { db in
            db.trace(options: .statement) { event in
                if case let .statement(statement) = event { traced.append(statement.sql) }
            }
        }
        let q = try DatabaseQueue(configuration: config)
        try AppDatabase.migrator.migrate(q, upTo: "v1_initial")
        let start = try XCTUnwrap(traced.firstIndex { $0.hasPrefix("BEGIN") })
        let end = try XCTUnwrap(traced.firstIndex { $0.hasPrefix("INSERT INTO grdb_migrations") })
        return Array(traced[(start + 1)..<end])
    }
}
