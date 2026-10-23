import Foundation
import GRDB

/// The welcome flow's writes (spec §6): a fresh install starts with nothing on, and Finish applies the
/// choices through the paths Settings uses.
extension AppDatabase {
    /// A fresh install, before the engine's first tick: every source off and unchosen, and none of the seed
    /// interest keywords (they were the owner's, spec C2). The flow's Finish chooses what comes back on. Only
    /// `WelcomeGate.launchPlan` asks for this, and never for a database with stories.
    func prepareFreshInstall() throws {
        try dbPool.write { db in
            // The same check as the caller's, inside the write: a database with stories is never reset.
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM article)") == false else {
                print("PulseFeed: [Welcome] fresh-install reset refused: the database has stories")
                return
            }
            try db.execute(sql: "UPDATE feed SET isEnabled = 0, catalogAdded = 1, updatedAt = datetime('now')")
            try db.execute(sql: "DELETE FROM userInterest")
        }
    }
}

extension AppDatabase {
    /// Every source's enabled state by URL, for a re-run of the flow (`WelcomeDraft.current`).
    func sourceStates() async throws -> [String: Bool] {
        try await dbPool.read { db in
            var out: [String: Bool] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT url, isEnabled FROM feed") { out[row["url"]] = row["isEnabled"] }
            return out
        }
    }

    /// Finish: writes the draft through `applyInterests`, `addSource`, `addInterest` and the stored settings
    /// keys, sets each catalog row of a picked topic in one UPDATE (on = chosen; off keeps the unchosen mark it
    /// had), and marks the flow done. Returns true when the
    /// picked design differs from the running one, so the caller relaunches to apply it.
    func applyWelcome(_ draft: WelcomeDraft, catalog: Catalog, region: String, runningDesign: AppDesign,
                      defaults d: UserDefaults) async throws -> Bool {
        let picked = Set(draft.matchesToApply().compactMap { if case .topic(let id) = $0 { return id } else { return nil } })
        let urls = catalog.sources.filter { picked.contains($0.topic) }.map(\.url)
        // Each row's "nobody chose this" mark (v11 catalogAdded) before topics switch on: setTopicEnabled clears
        // it for the whole topic, and a row Finish leaves off must stay unchosen, or a later category tick
        // would switch it on (arXiv, a never-offered feed, a source switched off in the flow).
        let marks: [String: Bool] = try await dbPool.read { db in
            var out: [String: Bool] = [:]
            for url in urls {
                if let mark = try Bool.fetchOne(db, sql: "SELECT catalogAdded FROM feed WHERE url = ?", arguments: [url]) { out[url] = mark }
            }
            return out
        }

        try await applyInterests(draft.matchesToApply(), catalog: catalog, region: region, defaults: d)

        // A topic switched on all its sources; set each back to what the Sources step showed. A source the flow
        // never offers keeps the state it had (off on a fresh install; as the person left it on a re-run). A row
        // turned on is chosen; a row left off gets its mark back.
        for source in catalog.sources where picked.contains(source.topic) {
            let want = source.isOffered ? draft.isOn(source) : (draft.current[source.url] ?? false)
            try await dbPool.write { db in
                if want {
                    try db.execute(sql: "UPDATE feed SET isEnabled = 1, catalogAdded = 0, updatedAt = datetime('now') WHERE url = ?",
                                   arguments: [source.url])
                } else {
                    try db.execute(sql: "UPDATE feed SET isEnabled = 0, catalogAdded = ?, updatedAt = datetime('now') WHERE url = ?",
                                   arguments: [marks[source.url] ?? false, source.url])
                }
            }
        }
        for site in draft.addedSites {
            _ = try await addSource(title: site.title, url: site.url, category: site.category)
        }
        // The relevance keywords a fresh install had none of (spec C2): one per followed name.
        for m in draft.matchesToApply() {
            guard case .follow(let name, let topicID) = m else { continue }
            let category = topicID.flatMap { catalog.topic($0)?.category } ?? NewsCategory.general.id
            try await addInterest(keyword: name, weight: 2.0, category: category)
        }

        d.set(draft.alertMode.rawValue, forKey: AlertMode.defaultsKey)
        d.set(Double(draft.recapInterval), forKey: SummaryComposer.intervalKey)
        d.set(draft.appearance.rawValue, forKey: AppAppearance.defaultsKey)
        MarketInstrument.store(draft.instruments, d)
        d.set(draft.pricesInMenuBar, forKey: WelcomeDraft.capsuleKey)
        let relaunch = draft.design != runningDesign
        if relaunch { d.set(draft.design.rawValue, forKey: AppDesign.defaultsKey) }
        WelcomeGate.markCompleted(d)
        return relaunch
    }
}
