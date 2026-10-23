import SwiftUI
import GRDB

/// Settings › Intelligence › Learning week: the running counts, and after seven days the
/// proposals — each waits for Accept. Rules are printed so the reader can hold the app to them.
struct LearningWeekSection: View {
    let appDB: AppDatabase
    /// nil while the week is off: reading it must not start the clock.
    @State private var study: EngagementStudy? = EngagementStudy.isEnabled(.standard) ? EngagementStudy.current() : nil
    @State private var report: EngagementReport?
    @State private var decisions: [String: String] =
        UserDefaults.standard.dictionary(forKey: LearningWeekSection.decisionsKey) as? [String: String] ?? [:]

    static let decisionsKey = "engagement_decisions"

    var body: some View {
        Section("Learning week") {
            if let study {
                running(study)
            } else {
                Text("A learning week records what you open, read and skip for seven days, on this Mac only, then proposes changes you accept or reject.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Start a learning week") {
                    EngagementStudy.setEnabled(true, .standard)
                    study = EngagementStudy.current()
                    Task { await load() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func running(_ study: EngagementStudy) -> some View {
            let progress = study.progress()
            let unlocked = progress.ready || DebugOpen.wants("study")
            Text(progress.ready
                 ? "Week complete · started \(study.startedAt.formatted(date: .abbreviated, time: .omitted))"
                 : "Day \(progress.day) of 7 · proposals unlock \(study.endsAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.headline)
            Text("The app only watches this week: what it showed you, what you opened, how long you read, what you starred, saved or marked not interested. Nothing about sources or ranking changes until you accept a proposal below.")
                .font(.caption).foregroundStyle(.secondary)

            if let report {
                Text("\(report.totals.shown) shown · \(report.totals.opened) opened · \(report.totals.starred) starred · \(report.totals.saved) saved · \(report.totals.dismissed) not interested · \(Int(report.totals.dwellSeconds / 60)) min reading")
                    .font(.caption)
                if !report.categories.isEmpty {
                    ForEach(report.categories.prefix(8)) { c in
                        LabeledContent(NewsCategory.named(c.category).label, value: "\(c.opens) of \(c.shown) opened")
                    }
                }
                if !report.topics.isEmpty {
                    Text("Topics you open most: " + report.topics.filter { $0.opens > 0 }.prefix(6).map { "\($0.topic) (\($0.opens))" }.joined(separator: ", "))
                        .font(.caption)
                }
                if unlocked {
                    if report.proposals.isEmpty {
                        Text("No changes proposed: nothing crossed the rules.").font(.callout)
                    }
                    ForEach(report.proposals) { proposal in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(proposal.title).fontWeight(.semibold)
                                Text(proposal.evidence).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let decision = decisions[proposal.id] {
                                Text(decision.capitalized).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Accept") { Task { await accept(proposal) } }.controlSize(.small)
                                Button("Reject") { decide(proposal.id, "rejected") }.controlSize(.small)
                            }
                        }
                    }
                } else {
                    Text("Proposals appear when the week is over.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }

            Text("Rules, written before the week began: a source is proposed off after 50 or more impressions with 2% or fewer opened, or after 5 “not interested” and no open; a category that is off is proposed on after 5 opened stories about it. Urgent alerts and the full lists are never touched.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Stop") {
                    EngagementStudy.setEnabled(false, .standard)
                    self.study = nil
                }.font(.caption)
                Spacer()
                Button("Refresh") { Task { await load() } }.font(.caption)
            }
    }

    private func load() async {
        guard let study else { return }
        EngagementLog.shared.flush()
        let rows = (try? await appDB.fetchEngagement(since: study.startedAt)) ?? []
        let enabled = (try? await appDB.dbPool.read { Set(try String.fetchAll($0, sql: "SELECT DISTINCT category FROM feed WHERE isEnabled = 1")) }) ?? []
        let off = NewsCategory.all.map(\.id).filter { !enabled.contains($0) }
        report = EngagementReport.build(events: rows, enabledCategories: enabled, categoriesOff: off)
    }

    private func accept(_ proposal: EngagementReport.Proposal) async {
        switch proposal.kind {
        case .disableSource(let feedID): try? await appDB.updateFeedEnabled(feedID: feedID, isEnabled: false)
        case .enableCategory(let id): try? await appDB.setCategoryEnabled(id, true)
        }
        decide(proposal.id, "accepted")
    }

    private func decide(_ id: String, _ decision: String) {
        decisions[id] = decision
        UserDefaults.standard.set(decisions, forKey: Self.decisionsKey)
    }
}
