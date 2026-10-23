import Foundation
import Observation
import UserNotifications

/// The welcome flow's state: the draft, the step, the live preview. Nothing reaches disk until `finish()`
/// (keys added on a card are the one exception: they are saved by the card itself).
@MainActor
@Observable
final class WelcomeFlowModel {
    let appDB: AppDatabase
    let catalog: Catalog
    let region: String
    let dryRun: Bool
    /// False for the showcase renders: no preview fetch runs, `headlines` is set from the fixture.
    let livePreview: Bool
    var draft: WelcomeDraft
    var step: WelcomeStep
    var headlines: [PreviewHeadline] = []
    var isLoadingPreview = false
    var notificationsAsked = false
    var isFinishing = false
    var finishError: String?

    @ObservationIgnored private let preview = WelcomePreview()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored var onFinished: (_ relaunch: Bool) -> Void = { _ in }

    /// `rerun`: "Run the welcome again" on an install in use; the Sources step starts from each source's state.
    init(appDB: AppDatabase, catalog: Catalog, dryRun: Bool, startStep: WelcomeStep = .welcome, rerun: Bool = false,
         livePreview: Bool = true, defaults: UserDefaults = .standard) {
        self.appDB = appDB
        self.catalog = catalog
        self.region = Catalog.region(for: Locale.current)
        self.dryRun = dryRun
        self.livePreview = livePreview
        self.draft = WelcomeDraft.initial(defaults)
        self.step = startStep
        if dryRun, startStep.rawValue > WelcomeStep.topics.rawValue { draft = Self.sample(draft) }
        if rerun {
            Task { [weak self, appDB, catalog] in
                let states = (try? await appDB.sourceStates()) ?? [:]
                self?.draft.current = WelcomeDraft.currentStates(states, catalog: catalog)
            }
        }
        refreshPreview()
    }

    /// What a dry run past the Topics step shows (screenshots): a believable set of picks.
    static func sample(_ base: WelcomeDraft) -> WelcomeDraft {
        var d = base
        d.topics = ["tech", "ai", "nba", "markets", "travel"]
        d.follows = [.follow(name: "lakers", topicID: "nba"), .follow(name: "openai", topicID: "ai")]
        d.instruments = MarketInstrument.suggested
        return d
    }

    var canGoBack: Bool { step.previous != nil && step != .welcome }
    var canAdvance: Bool { step.canAdvance(draft) }

    func next() {
        if step == .topics { draft.suggestInstrumentsIfEmpty(catalog: catalog) }
        if let n = step.next { step = n }
    }

    func back() { if let p = step.previous { step = p } }

    /// Re-fetches the preview a moment after the picks settle.
    func refreshPreview() {
        guard livePreview else { return }
        previewTask?.cancel()
        isLoadingPreview = false   // a cancelled fetch never clears it itself
        let draft = self.draft, catalog = self.catalog, region = self.region
        guard !draft.topics.isEmpty else { headlines = []; return }
        previewTask = Task { [weak self, preview] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.isLoadingPreview = true
            let items = await preview.headlines(for: draft, catalog: catalog, region: region)
            guard !Task.isCancelled else { return }
            self?.headlines = items
            self?.isLoadingPreview = false
        }
    }

    func askForNotifications() {
        notificationsAsked = true
        Task { await NotificationService.requestPermission() }
    }

    func finish() {
        guard !isFinishing else { return }
        if dryRun {
            print("PulseFeed: [Welcome] dry run: \(draft.topics.count) topics, \(draft.follows.count) follows, mode \(draft.alertMode.rawValue), design \(draft.design.rawValue), instruments \(draft.instruments)")
            onFinished(false)
            return
        }
        isFinishing = true
        let draft = self.draft
        Task {
            do {
                let relaunch = try await appDB.applyWelcome(draft, catalog: catalog, region: region,
                                                           runningDesign: AppDesign.current, defaults: .standard)
                let undecided = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
                for action in WelcomeFinish.actions(draft, notificationsUndecided: undecided) {
                    switch action {
                    case .applyAppearance(let a): AppAppearance.apply(a)
                    case .askNotifications: await NotificationService.requestPermission()
                    case .openAtLogin: LoginItemService.setEnabled(true)
                    }
                }
                print("PulseFeed: [Welcome] finished: \(draft.topics.count) topics, \(draft.follows.count) follows")
                isFinishing = false
                onFinished(relaunch)
            } catch {
                isFinishing = false
                finishError = "Could not save your choices: \(error.localizedDescription)"
            }
        }
    }
}

extension Catalog {
    /// The catalog region a Mac's locale reads as (sources are ordered region first).
    static func region(for locale: Locale) -> String {
        let code = locale.region?.identifier.uppercased() ?? "US"
        if code == "GB" { return "uk" }
        let eu: Set<String> = ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
                               "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH", "NO", "IS"]
        if eu.contains(code) { return "eu" }
        let asia: Set<String> = ["JP", "CN", "KR", "IN", "SG", "HK", "TW", "TH", "MY", "ID", "PH", "VN"]
        if asia.contains(code) { return "asia" }
        return "us"
    }
}
