import SwiftUI
import AppKit
import Sparkle

@main
struct PulseFeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var feedEngine: FeedEngine
    @State private var menuBarStatus: MenuBarStatusModel

    private let appDB: AppDatabase
    private let updaterController: SPUStandardUpdaterController

    init() {
        // A showcase run under any bundle but build/Showcase.app's stops here, before anything is opened.
        ShowcaseGate.refuseUnlessAllowed()
        let db = try! AppDatabase(path: AppDatabase.launchPath())
        self.appDB = db
        let engine = FeedEngine(appDB: db)
        _feedEngine = State(initialValue: engine)
        let status = MenuBarStatusModel(appDB: db)
        status.start()
        _menuBarStatus = State(initialValue: status)
        // Only start Sparkle when a signing key is configured. With SUPublicEDKey empty and an
        // ad-hoc signature the updater cannot start, and Sparkle shows an "Unable to Check For
        // Updates" alert at every launch.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: Self.sparkleConfigured, updaterDelegate: nil, userDriverDelegate: nil)
        // Give AppDelegate access to DB for notification action handling, and the engine so it
        // can start polling at launch.
        appDelegate.appDB = db
        appDelegate.feedEngine = engine
        appDelegate.updaterController = updaterController
        MenuActions.shared.appDB = db
        MenuActions.shared.feedEngine = engine
        MenuActions.shared.updaterController = updaterController
    }

    var body: some Scene {
        MenuBarExtra {
            AppDesign.current.popover(appDB: appDB, updater: updaterController)
                .environment(feedEngine)
        } label: {
            MenuBarLabel(design: AppDesign.current, status: menuBarStatus, engine: feedEngine)
        }
        .menuBarExtraStyle(.window)
    }

    /// True when Info.plist carries a non-empty SUPublicEDKey, i.e. updates can actually be verified.
    static var sparkleConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}

/// `PULSEFEED_DEBUG_OPEN=popover,window,settings,widget` opens surfaces after launch so a session
/// without a mouse can screenshot them (the popover opens as a plain "Popover preview" window,
/// because MenuBarExtra cannot be opened programmatically). Ignored when unset.
enum DebugOpen {
    static let requested: Set<String> = {
        let raw = ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_OPEN"] ?? ""
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    }()
    static func wants(_ surface: String) -> Bool { requested.contains(surface) }
    /// `PULSEFEED_DEBUG_SETTINGS_PANE=general` picks the pane the sidebar chrome opens on.
    static let settingsPane: SettingsPane? = ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_SETTINGS_PANE"].flatMap(SettingsPane.init(rawValue:))
    @MainActor static var previewWindow: NSWindow?
}
