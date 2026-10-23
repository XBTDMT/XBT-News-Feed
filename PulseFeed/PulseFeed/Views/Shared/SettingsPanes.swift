import SwiftUI
import ServiceManagement
import UserNotifications
import GRDB
import AppKit
import Sparkle

// Pane CONTENT shared by every design; the chrome around them lives in SettingsChromes.swift.

// MARK: - Sources

extension DebugOpen {
    /// `PULSEFEED_DEBUG_ADD_SOURCE=theverge.com` opens Settings › Sources › Add source with that typed
    /// and runs Find, so the sheet can be screenshotted without a mouse. Nothing is added.
    static let addSourceInput: String? = ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_ADD_SOURCE"].flatMap { $0.isEmpty ? nil : $0 }
}

struct SourcesSettingsTab: View {
    let appDB: AppDatabase
    @Environment(\.designTokens) private var tokens
    @State private var feeds: [Feed] = []
    @State private var showAddSheet = false
    @State private var addSheetInput = ""
    @State private var message: String?
    /// The debug hook opens the sheet once per launch, not on every visit to the pane.
    @MainActor private static var debugAddSourceShown = false

    private let pollIntervals = [
        (60, "1 min"), (180, "3 min"), (300, "5 min"),
        (900, "15 min"), (1800, "30 min"), (3600, "1 hr"),
    ]

    private var tally: (ok: Int, stale: Int, failing: Int) {
        var ok = 0, stale = 0, failing = 0
        for feed in feeds {
            switch feed.health() {
            case .ok: ok += 1
            case .stale: stale += 1
            case .failing: failing += 1
            }
        }
        return (ok, stale, failing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Sources").font(.system(size: 20, weight: .bold))
                let t = tally
                (Text("\(feeds.count) · ")
                    + Text("\(t.ok) ok").foregroundColor(Color(hex: "#1E8E3E")).bold()
                    + Text(" · ")
                    + Text("\(t.stale) stale").foregroundColor(Color(hex: "#B25E00")).bold()
                    + Text(" · ")
                    + Text("\(t.failing) failing").foregroundColor(Color(hex: "#D93025")).bold())
                    .font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
            }

            if let catalog = Catalog.bundled {
                InterestBox(appDB: appDB, catalog: catalog) { outcome in
                    message = outcome
                    await loadFeeds()
                }
            }

            categoriesGrid

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(groupedFeeds.enumerated()), id: \.element.category.id) { gIndex, group in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: group.category.colorHex)).frame(width: 8, height: 8)
                            Text(group.category.label.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.6)
                            Spacer()
                            Text("\(group.feeds.count)").font(.system(size: 10)).monospacedDigit()
                        }
                        .foregroundStyle(tokens.secondaryText)
                        .padding(EdgeInsets(top: gIndex == 0 ? 8 : 12, leading: 12, bottom: 4, trailing: 12))
                        ForEach(Array(group.feeds.enumerated()), id: \.element.id) { index, feed in
                            FeedRow(feed: feed, appDB: appDB, pollIntervals: pollIntervals, onDelete: loadFeeds)
                            if index < group.feeds.count - 1 { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
                        }
                    }
                }
                .background(tokens.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tokens.cardBorder, lineWidth: 1))
            }

            HStack(spacing: 8) {
                Button("Add source…") {
                    addSheetInput = ""
                    showAddSheet = true
                }
                Button("Import OPML") { importOPML() }
                Button("Export OPML") { exportOPML() }
                Spacer()
                if let msg = message {
                    Text(msg).font(.caption).foregroundStyle(tokens.secondaryText).lineLimit(1).truncationMode(.middle)
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .sheet(isPresented: $showAddSheet) {
            AddSourceSheet(appDB: appDB, initialInput: addSheetInput) { outcome in
                message = outcome
                await loadFeeds()
            }
            .environment(\.designTokens, tokens)
        }
        .task {
            await loadFeeds()
            if let input = DebugOpen.addSourceInput, !Self.debugAddSourceShown {
                Self.debugAddSourceShown = true
                addSheetInput = input
                showAddSheet = true
            }
        }
    }

    private func loadFeeds() async {
        feeds = (try? await appDB.fetchAllFeeds()) ?? []
    }

    private struct FeedGroup { let category: NewsCategory; let feeds: [Feed] }

    /// Registry order; "general" and unknown categories last.
    private var groupedFeeds: [FeedGroup] {
        let known = NewsCategory.all + [NewsCategory.general]
        var groups: [FeedGroup] = []
        for category in known {
            let members = feeds.filter { $0.category == category.id }
            if !members.isEmpty { groups.append(FeedGroup(category: category, feeds: members)) }
        }
        let knownIDs = Set(known.map(\.id))
        for other in Set(feeds.map(\.category)).subtracting(knownIDs).sorted() {
            groups.append(FeedGroup(category: NewsCategory(id: other, label: other.capitalized, short: other.capitalized, badge: "NEWS", colorHex: "#8E8E93", symbol: "newspaper", defaultEnabled: true), feeds: feeds.filter { $0.category == other }))
        }
        return groups
    }

    /// Tick a category on or off (`setCategoryEnabled`: on brings back the sources the install had or chose).
    /// A category with no feeds is not shown.
    private var categoriesGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 128), spacing: 6)]
        return VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORIES").font(.system(size: 10, weight: .bold)).kerning(0.6).foregroundStyle(tokens.secondaryText)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(NewsCategory.all + [NewsCategory.general]) { category in
                    let members = feeds.filter { $0.category == category.id }
                    if !members.isEmpty {
                        let isOn = members.contains { $0.isEnabled }
                        Toggle(isOn: Binding(
                            get: { isOn },
                            set: { on in
                                Task {
                                    try? await appDB.setCategoryEnabled(category.id, on)
                                    await loadFeeds()
                                }
                            })) {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(hex: category.colorHex)).frame(width: 8, height: 8)
                                Text(category.label).font(.system(size: 12)).lineLimit(1)
                                Text("\(members.count)").font(.system(size: 10)).foregroundStyle(tokens.secondaryText).monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                    }
                }
            }
            Text("Off means its sources stop polling and its stories leave the lists and counts.")
                .font(.system(size: 10)).foregroundStyle(tokens.secondaryText)
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            guard let data = try? Data(contentsOf: url) else {
                message = "Failed to read file"
                return
            }
            let opmlFeeds = OPMLService().parseOPML(data: data)
            let added = (try? await appDB.importFeeds(opmlFeeds, ownExport: OPMLService.isOwnExport(data))) ?? 0
            message = "\(added) of \(opmlFeeds.count) sources added or switched on"
            await loadFeeds()
        }
    }

    private func exportOPML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "PulseFeed.opml"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let allFeeds = (try? await appDB.fetchAllFeeds()) ?? []
            let xml = OPMLService().exportOPML(feeds: allFeeds)
            try? xml.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct FeedRow: View {
    let feed: Feed
    let appDB: AppDatabase
    let pollIntervals: [(Int, String)]
    let onDelete: () async -> Void
    @Environment(\.designTokens) private var tokens

    @State private var isEnabled: Bool
    @State private var pollInterval: Int
    @State private var isHovering = false
    /// Remove asks once, in the row — no alert.
    @State private var confirmingRemove = false
    @State private var storyCount: Int?

    init(feed: Feed, appDB: AppDatabase, pollIntervals: [(Int, String)], onDelete: @escaping () async -> Void) {
        self.feed = feed
        self.appDB = appDB
        self.pollIntervals = pollIntervals
        self.onDelete = onDelete
        _isEnabled = State(initialValue: feed.isEnabled)
        _pollInterval = State(initialValue: feed.pollInterval)
    }

    private var health: FeedHealth { feed.health() }

    private var healthColor: Color {
        switch health {
        case .ok: return Color(hex: "#34C759")
        case .stale: return Color(hex: "#FF9F0A")
        case .failing: return Color(hex: "#FF3B30")
        }
    }

    /// "F1 · 4m", or the problem in the sheet's amber / red.
    private var meta: (text: String, color: Color) {
        switch health {
        case .failing(let errors):
            return ("\(errors) errors" + (feed.lastFetchError.map { " · \($0)" } ?? ""), Color(hex: "#D93025"))
        case .stale(let days):
            return ("\(feed.category.capitalized) · no article in \(days)d", Color(hex: "#B25E00"))
        case .ok:
            return ("\(feed.category.capitalized) · \(feed.lastArticleAt?.relativeTime ?? "–")", tokens.secondaryText)
        }
    }

    /// "Remove? 312 stories go too" once the count is in; plain until then.
    private var removePrompt: String {
        switch storyCount {
        case .some(let n) where n > 0: return "Remove? \(n) \(n == 1 ? "story goes" : "stories go") too"
        default: return "Remove this source?"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(isEnabled ? healthColor : Color.secondary.opacity(0.3)).frame(width: 8, height: 8)
            Text(feed.title).font(.system(size: 12)).lineLimit(1).foregroundStyle(isEnabled ? .primary : .secondary)
            Spacer(minLength: 6)
            if confirmingRemove {
                Text(removePrompt).font(.system(size: 11)).foregroundStyle(Color(hex: "#D93025")).lineLimit(1)
                Button("Keep") { confirmingRemove = false }
                    .controlSize(.mini)
                Button("Remove", role: .destructive) {
                    Task {
                        try? await appDB.deleteFeed(feedID: feed.id)
                        await onDelete()
                    }
                }
                .buttonStyle(.borderedProminent).tint(Color(hex: "#D93025")).controlSize(.mini)
            } else {
                Text(meta.text).font(.system(size: 11)).foregroundStyle(meta.color).lineLimit(1)
                if isHovering {
                    if feed.type == "rss" || feed.type == "json_api" {
                        Picker("", selection: $pollInterval) {
                            ForEach(pollIntervals, id: \.0) { interval in Text(interval.1).tag(interval.0) }
                        }
                        .labelsHidden().controlSize(.mini).frame(width: 70)
                        .onChange(of: pollInterval) { _, newValue in
                            Task { try? await appDB.updateFeedPollInterval(feedID: feed.id, pollInterval: newValue) }
                        }
                    }
                    Toggle("", isOn: $isEnabled).labelsHidden().controlSize(.mini).toggleStyle(.switch)
                        .onChange(of: isEnabled) { _, newValue in
                            Task { try? await appDB.updateFeedEnabled(feedID: feed.id, isEnabled: newValue) }
                        }
                    Button {
                        confirmingRemove = true
                        Task { storyCount = try? await appDB.articleCount(feedID: feed.id) }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this source and its stories")
                }
            }
        }
        .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Add source

/// Settings › Sources › Add source…: type a site or a feed address, Find shows what was detected
/// (title editable, address, item count) or a plain error, Add stores it enabled in the chosen category.
struct AddSourceSheet: View {
    let appDB: AppDatabase
    var initialInput: String = ""
    /// Called with a one-line outcome for the pane's message slot before the sheet closes.
    let onDone: (String) async -> Void
    /// The welcome flow: the found feed is handed back instead of added (Finish adds it).
    var onFound: ((AddedSite) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var tokens
    @State private var input: String
    @State private var category = NewsCategory.general.id
    @State private var title = ""
    @State private var found: DiscoveredFeed?
    @State private var errorText: String?
    @State private var isFinding = false
    @State private var isAdding = false
    @State private var findTask: Task<Void, Never>?

    init(appDB: AppDatabase, initialInput: String = "", onDone: @escaping (String) async -> Void,
         onFound: ((AddedSite) -> Void)? = nil) {
        self.appDB = appDB
        self.initialInput = initialInput
        self.onDone = onDone
        self.onFound = onFound
        _input = State(initialValue: initialInput)
    }

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add source").font(.system(size: 15, weight: .bold))
                Text("Paste a feed address, or just the site — the feed is found for you.")
                    .font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
            }

            HStack(spacing: 8) {
                TextField("theverge.com or https://example.com/feed", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { find() }
                    .disabled(isFinding || isAdding)
                Button(isFinding ? "Finding…" : "Find") { find() }
                    .disabled(trimmedInput.isEmpty || isFinding || isAdding)
            }

            HStack(spacing: 8) {
                Text("Category").font(.system(size: 12))
                Picker("", selection: $category) {
                    ForEach(NewsCategory.pickerIDs, id: \.self) { id in
                        Text(NewsCategory.named(id).label).tag(id)
                    }
                }
                .labelsHidden().frame(width: 170)
                Spacer()
            }

            Group {
                if isFinding {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for a feed…").font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let found {
                    resultCard(found)
                } else if let errorText {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Color(hex: "#D93025"))
                        Text(errorText).font(.system(size: 11)).foregroundStyle(Color(hex: "#D93025"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Nothing is added until you press Add.").font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
                }
            }
            .frame(minHeight: 72, alignment: .top)

            HStack {
                Button("Cancel") {
                    findTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isAdding ? "Adding…" : "Add") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(found == nil || title.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(width: 480)
        .task {
            if !trimmedInput.isEmpty { find() }
        }
    }

    private func resultCard(_ feed: DiscoveredFeed) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color(hex: "#1E8E3E")).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                TextField("Title", text: $title).textFieldStyle(.roundedBorder).font(.system(size: 12))
                Text(feed.url.absoluteString)
                    .font(.system(size: 11)).foregroundStyle(tokens.secondaryText).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Text("\(feed.format.rawValue) · \(feed.itemCount) \(feed.itemCount == 1 ? "item" : "items") right now")
                    .font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tokens.cardBorder, lineWidth: 1))
    }

    private func find() {
        let text = trimmedInput
        guard !text.isEmpty, !isFinding else { return }
        findTask?.cancel()
        found = nil
        errorText = nil
        isFinding = true
        findTask = Task {
            let result = await FeedDiscovery.resolve(text)
            guard !Task.isCancelled else { return }
            isFinding = false
            switch result {
            case .success(let feed):
                found = feed
                title = feed.title
            case .failure(let error):
                errorText = error.errorDescription
            }
        }
    }

    private func add() {
        guard let found, !isAdding else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let onFound {
            onFound(AddedSite(title: name, url: found.url.absoluteString, category: category))
            dismiss()
            return
        }
        isAdding = true
        Task {
            let outcome: String
            do {
                switch try await appDB.addSource(title: name, url: found.url.absoluteString, category: category) {
                case .added(let feed):
                    outcome = "Added \(feed.title) to \(NewsCategory.named(feed.category).label)"
                case .alreadyPresent(let feed):
                    outcome = "\(feed.title) was already a source — switched on"
                }
            } catch {
                outcome = "Could not add: \(error.localizedDescription)"
            }
            isAdding = false
            await onDone(outcome)
            dismiss()
        }
    }
}

// MARK: - AI

struct AISettingsTab: View {
    let appDB: AppDatabase
    @AppStorage("ai_enabled") private var aiEnabled = true
    @AppStorage("ai_prefer_on_device") private var preferOnDevice = true
    @State private var gateStatus: AIGateStatus?
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var testStatus: String?
    @State private var isTesting = false
    @State private var interests: [UserInterest] = []
    @State private var newKeyword = ""
    @State private var newWeight = 2.0
    @State private var newCategory = "general"

    private let categories = NewsCategory.pickerIDs

    var body: some View {
        Form {
            Section("AI Pipeline") {
                Toggle("Enable AI Summaries & Scoring", isOn: $aiEnabled)
                Text("Two-pass pipeline: keyword scoring (local), then the on-device Apple model (or Claude) for top candidates and multi-source stories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Prefer on-device Apple model for summaries", isOn: $preferOnDevice)
                Text("Uses Apple's on-device model when available (no API key, no network). Claude is still used for the daily brief when a key is set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LearningWeekSection(appDB: appDB)

            Section("Status") {
                if let status = gateStatus {
                    LabeledContent("Engine", value: status.engine)
                    LabeledContent("On-device available", value: status.onDeviceAvailable ? "Yes" : "No")
                    LabeledContent("Claude key", value: status.hasClaudeKey ? "Yes" : "No")
                    LabeledContent("Calls today", value: "\(status.callsToday) / \(status.dailyCap)")
                    if let until = status.cooldownUntil, until > Date() {
                        Text("Backing off after API errors until \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Refresh") {
                        Task { await loadGateStatus() }
                    }
                    .font(.caption)
                }
            }

            Section("Claude API Key") {
                HStack {
                    SecureField(hasKey ? "API key saved" : "sk-ant-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button(apiKey.isEmpty ? "Clear" : "Save") {
                        if apiKey.isEmpty {
                            AIService.removeAPIKey()
                            hasKey = false
                            testStatus = nil
                        } else {
                            AIService.setAPIKey(apiKey)
                            hasKey = true
                            apiKey = ""
                            testStatus = "Key saved"
                        }
                    }
                    .disabled(apiKey.isEmpty && !hasKey)
                }
                Text("Optional. Enables AI-powered article summaries and smarter relevance scoring. Get a key at console.anthropic.com (~$2/month at typical volume).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if hasKey {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("API key stored in Application Support")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Test") {
                            Task { await testConnection() }
                        }
                        .disabled(isTesting)
                        .font(.caption)
                    }
                }
                if let status = testStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("Success") ? .green : .orange)
                }
            }

            Section("Interest Keywords") {
                ForEach(interests) { interest in
                    HStack {
                        Text(interest.keyword)
                        Text(interest.category ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", interest.weight))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 30)
                        Slider(value: Binding(
                            get: { interest.weight },
                            set: { newVal in
                                Task {
                                    try? await appDB.updateInterestWeight(id: interest.id, weight: newVal)
                                    await loadInterests()
                                }
                            }
                        ), in: 0.5...5.0, step: 0.5)
                        .frame(width: 80)
                        Button(role: .destructive) {
                            Task {
                                try? await appDB.removeInterest(id: interest.id)
                                await loadInterests()
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Keyword", text: $newKeyword)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $newCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 90)
                    Button("Add") {
                        guard !newKeyword.isEmpty else { return }
                        Task {
                            try? await appDB.addInterest(
                                keyword: newKeyword, weight: newWeight, category: newCategory)
                            newKeyword = ""
                            await loadInterests()
                        }
                    }
                    .disabled(newKeyword.isEmpty)
                }
            }

            Section("Model Info") {
                LabeledContent("Model", value: "claude-haiku-4-5-20251001")
                LabeledContent("Scoring threshold", value: "> 3.0 keyword score, or 2+ sources")
                LabeledContent("Est. cost", value: "~$2/month (100 articles/day)")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasKey = AIService.getAPIKey() != nil
        }
        .task { await loadInterests() }
        .task { await loadGateStatus() }
    }

    private func loadInterests() async {
        interests = (try? await appDB.fetchAllInterests()) ?? []
    }

    private func loadGateStatus() async {
        gateStatus = await AIGate.shared.status()
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        guard let key = AIService.getAPIKey() else {
            testStatus = "No API key found"
            return
        }
        let service = AIService()
        let testArticle = Article(
            articleID: "test", feedID: "test", uniqueID: "test",
            title: "Bitcoin reaches new all-time high of $100,000",
            contentText: "Bitcoin surged past $100,000 for the first time in history.",
            dateArrived: "2026-01-01")
        if let result = await service.enrichWithClaude(article: testArticle, apiKey: key) {
            testStatus = "Success: \"\(result.tldr)\" (relevance: \(result.relevance))"
        } else {
            testStatus = "Failed — check API key or network"
        }
    }
}

// MARK: - Notifications

struct NotificationsSettingsTab: View {
    @AppStorage("notif_quietHoursEnabled") private var quietHoursEnabled = false
    @AppStorage("notif_quietHoursStart") private var quietHoursStart = 23
    @AppStorage("notif_quietHoursEnd") private var quietHoursEnd = 7
    @AppStorage("notif_relevanceThreshold") private var relevanceThreshold = 0.0
    @AppStorage(SummaryComposer.intervalKey) private var summaryInterval: Double = SummaryComposer.defaultInterval
    @AppStorage(AlertMode.defaultsKey) private var alertMode: String = AlertMode.breakingAndRecap.rawValue
    @AppStorage(MarketShock.enabledKey) private var marketShocks = true
    @AppStorage(UrgencyRules.defaultsKey) private var rulesText: String = ""
    @State private var rulesDraft: String = ""

    private let intervals: [(Double, String)] = [(0, "Off"), (300, "5 min"), (900, "15 min"), (1800, "30 min"), (3600, "1 hour")]

    var body: some View {
        Form {
            Section("How you are notified") {
                Picker("Alerts", selection: $alertMode) {
                    ForEach(AlertMode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle("Alert on big market moves (SPY, QQQ, MAG7 ±2.5 % on the day; coins ±7 % in 24 h)", isOn: $marketShocks)
                Picker("Recap of everything new", selection: $summaryInterval) {
                    ForEach(intervals, id: \.0) { Text($0.1).tag($0.0) }
                }
                Text("One notification written by the on-device model from the stories that arrived since the last recap. Nothing new, nothing sent. On critical battery it is a plain list of the top three.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Urgent stories always get their own alert at once: a war breaking out or a ceasefire, a market shock, a marquee trade, a frontier model launch, tour dates from an artist you follow. Everything else waits for the recap; \"headline\" stories lead it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Urgency rules") {
                TextEditor(text: $rulesDraft)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 180)
                HStack {
                    Button("Reset to defaults") { rulesDraft = UrgencyRules.defaults.asText; rulesText = "" }
                    Spacer()
                    Button("Save rules") { rulesText = rulesDraft }
                        .buttonStyle(.borderedProminent)
                        .disabled(rulesDraft == (rulesText.isEmpty ? UrgencyRules.defaults.asText : rulesText))
                }
                Text("Lowercase substrings, one per line; \"a&b\" needs both. Followed names interrupt when paired with an event word (trade, signing, launch, tour…). Never-urgent lines demote a match one tier. Market moves are numbers, not words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Category Notifications") {
                ForEach(NewsCategory.all) { category in
                    CategoryNotificationToggle(category: category)
                }
            }

            Section("Quiet Hours") {
                Toggle("Enable Quiet Hours", isOn: $quietHoursEnabled)
                if quietHoursEnabled {
                    Picker("Start", selection: $quietHoursStart) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    Picker("End", selection: $quietHoursEnd) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    Text("Notifications are suppressed from \(formatHour(quietHoursStart)) to \(formatHour(quietHoursEnd))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Relevance") {
                HStack {
                    Text("Min Score")
                    Slider(value: $relevanceThreshold, in: 0...10, step: 0.5)
                    Text(String(format: "%.1f", relevanceThreshold))
                        .monospacedDigit()
                        .frame(width: 30)
                }
                Text("Articles scored below this threshold won't trigger notifications. Leave at 0 to notify for all articles. Requires AI enabled (on-device model or a Claude key).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Urgent alert budget") {
                LabeledContent("Per hour", value: "\(UrgencyRules.stored().perHour)")
                LabeledContent("Per day", value: "\(UrgencyRules.stored().perDay)")
                Text("Set in the rules above. Over budget, an urgent story leads the next recap instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { rulesDraft = rulesText.isEmpty ? UrgencyRules.defaults.asText : rulesText }
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h) \(ampm)"
    }
}

/// One `notif_<category>` toggle (default on).
private struct CategoryNotificationToggle: View {
    let category: NewsCategory
    @AppStorage private var enabled: Bool

    init(category: NewsCategory) {
        self.category = category
        _enabled = AppStorage(wrappedValue: true, NotificationSettings.notificationKey(for: category.id))
    }

    var body: some View {
        Toggle(category.label, isOn: $enabled)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    let appDB: AppDatabase
    let updaterController: SPUStandardUpdaterController
    @State private var stats: AppDatabase.DatabaseStats?
    @State private var feedStatuses: [Feed] = []
    @State private var cleanupMessage: String?
    @State private var isCleaning = false
    @AppStorage("crashRecoveryEnabled") private var crashRecoveryEnabled = false
    @AppStorage("unread_window_days") private var unreadWindowDays = 2
    /// Stream's tabbed chrome has no Power pane, so it embeds the power sections here.
    var includePower = false
    @AppStorage(AppAppearance.defaultsKey) private var appearanceRaw: String = AppAppearance.light.rawValue

    var body: some View {
        Form {
            Section("Welcome") {
                HStack {
                    Text("Pick topics, sources, follows, alerts and the look again. Sources you already set stay as they are unless you switch them.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Run the welcome again") { WelcomeWindowController.shared.open(appDB: appDB, rerun: true) }
                }
            }
            Section("Design") {
                DesignPicker()
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { a in
                        Text(a.title).tag(a.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceRaw) { _, raw in
                    AppAppearance.apply(AppAppearance.resolve(raw))
                }
                Text("The three designs were drawn light. System follows the Mac's setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Icon") {
                AppIconPicker()
            }

            if includePower {
                PowerSections()
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { LoginItemService.isEnabled },
                    set: { LoginItemService.setEnabled($0) }
                ))
                if LoginItemService.isEnabled {
                    Text("The app will start automatically when you log in. No terminal needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Install to /Applications") {
                    let source = Bundle.main.bundleURL
                    let dest = AppInfo.installURL(displayName: AppInfo.displayName)
                    do {
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.copyItem(at: source, to: dest)
                        print("PulseFeed: Installed to /Applications")
                    } catch {
                        print("PulseFeed: Install failed: \(error)")
                    }
                }
                .buttonStyle(.bordered)
            }

            Section("Crash Recovery") {
                Toggle("Auto-restart on crash", isOn: $crashRecoveryEnabled)
                    .onChange(of: crashRecoveryEnabled) { _, enabled in
                        if enabled {
                            installLaunchdAgent()
                        } else {
                            uninstallLaunchdAgent()
                        }
                    }
                Text("Uses launchd KeepAlive to automatically restart the app if it crashes. Requires the app to be installed in /Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Unread") {
                Picker("Unread stays for", selection: $unreadWindowDays) {
                    Text("1 day").tag(1); Text("2 days").tag(2); Text("7 days").tag(7); Text("Forever").tag(0)
                }
                Text("Older stories are marked read at launch and once a day. Starred and saved stories are never touched. \"Since you last looked\" is the number that matters; this keeps the totals honest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let stats {
                Section("Database") {
                    LabeledContent("File size", value: formatBytes(stats.dbFileSizeBytes))
                    LabeledContent("Total articles", value: "\(stats.totalArticles)")
                    LabeledContent("Unread", value: "\(stats.unreadCount)")
                    LabeledContent("Starred", value: "\(stats.starredCount)")
                    LabeledContent("Feeds", value: "\(stats.feedCount)")
                    if let oldest = stats.oldestArticleDate {
                        LabeledContent("Oldest article", value: oldest.relativeTime + " ago")
                    }
                    if !stats.articlesByCategory.isEmpty {
                        HStack(alignment: .top) {
                            Text("By category")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(stats.articlesByCategory, id: \.category) { item in
                                    Text("\(item.category.capitalized): \(item.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    HStack {
                        Button("Clean Up Now") {
                            Task {
                                isCleaning = true
                                let count = try? await appDB.cleanupOldArticles()
                                cleanupMessage = "Removed \(count ?? 0) old articles"
                                await loadStats()
                                isCleaning = false
                            }
                        }
                        .disabled(isCleaning)
                        if let msg = cleanupMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Auto-cleanup runs on launch (90 days, keeps starred + min 10 per feed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Feed Health") {
                if feedStatuses.isEmpty {
                    Text("No feeds")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(feedStatuses) { feed in
                        HStack {
                            Circle()
                                .fill({ () -> Color in
                                    switch feed.health() {
                                    case .ok: return .green
                                    case .stale: return .orange
                                    case .failing: return .red
                                    }
                                }())
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(feed.title)
                                    .font(.caption)
                                if let error = feed.lastFetchError {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if feed.consecutiveErrors > 0 {
                                Text("\(feed.consecutiveErrors) errors")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            if let lastFetch = feed.lastFetchedAt {
                                Text(lastFetch.relativeTime)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Section("Test Notification") {
                Button("Send Test Notification") {
                    let content = UNMutableNotificationContent()
                    content.title = AppInfo.displayName
                    content.subtitle = "Test Notification"
                    content.body = "If you see the globe icon, notifications are working correctly."
                    content.sound = .default
                    content.categoryIdentifier = "NEWS"
                    let request = UNNotificationRequest(
                        identifier: "test-\(UUID().uuidString)",
                        content: content,
                        trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                .buttonStyle(.bordered)
                Text("Fires a notification immediately to verify icon and delivery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                if PulseFeedApp.sparkleConfigured {
                    Button("Check for Updates") {
                        updaterController.startUpdater()
                        updaterController.checkForUpdates(nil)
                    }
                    .buttonStyle(.bordered)
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updaterController.updater.automaticallyChecksForUpdates },
                        set: { updaterController.updater.automaticallyChecksForUpdates = $0 }
                    ))
                } else {
                    Text("Automatic updates are not configured for this build (no Sparkle signing key). Update by rebuilding: cd PulseFeed && make install")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadStats() }
        .task { feedStatuses = (try? await appDB.fetchFeedStatuses()) ?? [] }
    }

    private func loadStats() async {
        stats = try? await appDB.fetchDatabaseStats()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.pulsefeed.feed.plist")
    }

    private func installLaunchdAgent() {
        guard let bundledPlist = Bundle.main.url(forResource: "com.pulsefeed.feed", withExtension: "plist") else {
            print("PulseFeed: [CrashRecovery] Plist not found in bundle")
            return
        }
        let dest = launchAgentURL
        let dir = dest.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: bundledPlist, to: dest)
            let result = Process()
            result.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            result.arguments = ["load", dest.path]
            try result.run()
            result.waitUntilExit()
            print("PulseFeed: [CrashRecovery] launchd agent loaded")
        } catch {
            print("PulseFeed: [CrashRecovery] Install failed: \(error)")
        }
    }

    private func uninstallLaunchdAgent() {
        let dest = launchAgentURL
        guard FileManager.default.fileExists(atPath: dest.path) else { return }
        do {
            let result = Process()
            result.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            result.arguments = ["unload", dest.path]
            try result.run()
            result.waitUntilExit()
            try FileManager.default.removeItem(at: dest)
            print("PulseFeed: [CrashRecovery] launchd agent unloaded and removed")
        } catch {
            print("PulseFeed: [CrashRecovery] Uninstall failed: \(error)")
        }
    }
}


// MARK: - Power (own pane in the sidebar chromes; embedded in General for the tabbed chrome)

struct PowerSections: View {
    @ObservedObject private var powerMonitor = PowerMonitor.shared
    @AppStorage("menubar_btc_capsule") private var btcCapsule = false
    @AppStorage(XTileGlyph.animationDefaultsKey) private var animateX = false

    var body: some View {
        Section("Power") {
            HStack {
                Image(systemName: powerStatus.icon)
                    .foregroundStyle(powerStatus.color)
                Text(powerStatus.title)
            }
            Text(powerStatus.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Menu bar") {
            Toggle("Show BTC 24h change beside the menu bar icon", isOn: $btcCapsule)
            Toggle("Animate the menu bar X (coloured outline, turning quadrants)", isOn: $animateX)
            Text("Hidden on battery. The icon always shows a red dot while a BREAKING story is unread and the count of stories that arrived since you last opened the popover.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        DataSourcesSection()
    }

    private var powerStatus: (icon: String, color: Color, title: String, caption: String) {
        let base: (icon: String, color: Color, title: String, caption: String)
        switch powerMonitor.tier {
        case .ac:
            base = ("bolt.fill", .green, "AC Power — full performance",
                    "Each source polls on its own schedule (1 minute floor). Live prices via WebSocket. Full AI enrichment.")
        case .battery:
            base = ("battery.50", .orange, "Battery — 5-minute polling",
                    "All sources poll every 5 minutes. Crypto prices via CoinGecko on each poll. Stock quotes every 30 minutes. AI enrichment only for high-relevance articles.")
        case .critical:
            base = ("battery.25", .red, "Low battery — 30-minute polling, news only",
                    "Below 20% or Low Power Mode: RSS only every 30 minutes. No stock quotes, Hacker News, ESPN, digest, or AI until charging.")
        }
        var title = base.title
        if let level = powerMonitor.batteryLevel {
            title += " · \(Int(level * 100))%"
        }
        return (base.icon, base.color, title, base.caption)
    }

}

struct PowerPane: View {
    var body: some View {
        Form {
            PowerSections()
        }
        .formStyle(.grouped)
        .padding()
    }
}
