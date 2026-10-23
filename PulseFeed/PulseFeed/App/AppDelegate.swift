import AppKit
import SwiftUI
import UserNotifications
import WebKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Set by PulseFeedApp after init so didReceive can access the database
    var appDB: AppDatabase?

    /// Set by PulseFeedApp after init; started here so polling begins at launch, not when the
    /// popover is first opened.
    var feedEngine: FeedEngine?

    /// Set by PulseFeedApp so the debug hook can open Settings.
    var updaterController: SPUStandardUpdaterController?

    /// What this launch does about the welcome flow (WelcomeGate), decided before the engine starts.
    private var launchPlan = WelcomeGate.LaunchPlan(showWelcome: false, prepareFreshInstall: false, askNotificationsAtLaunch: true)

    /// Pre-compiled ad-block rules for ReaderWebView
    nonisolated(unsafe) static var adBlockRuleList: WKContentRuleList?

    /// Crash log path — static so the C function pointer handler can access it
    nonisolated(unsafe) static var crashLogPath: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Line-buffer stdout so `print` reaches a captured log promptly (fully buffered when not a tty).
        setvbuf(stdout, nil, _IOLBF, 0)

        // Export hook (PULSEFEED_DEBUG_EXPORT_ICON=<png>): write the master icon at 1024 px and quit — `make icon`.
        if let out = ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_EXPORT_ICON"], !out.isEmpty {
            let ok = AppIconRenderer.writePNG(style: .master, to: URL(fileURLWithPath: out))
            print("PulseFeed: [Icon] exported \(AppIconStyle.master.rawValue) to \(out): \(ok)")
            NSApp.terminate(nil)
            return
        }

        // Catalog check hook (PULSEFEED_CHECK_CATALOG=<catalog.json>:<report.json>): fetch and parse every
        // feed source, write the report, and with PULSEFEED_CHECK_CATALOG_WRITE=1 stamp passes back into the
        // catalog; then quit — `make check-catalog`.
        if let spec = ProcessInfo.processInfo.environment["PULSEFEED_CHECK_CATALOG"], !spec.isEmpty {
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            let write = ProcessInfo.processInfo.environment["PULSEFEED_CHECK_CATALOG_WRITE"] == "1"
            Task {
                do {
                    let catalogURL = URL(fileURLWithPath: parts[0])
                    let catalog = try Catalog.load(from: catalogURL)
                    let checks = await CatalogChecker.check(catalog.sources)
                    let (stamped, failed, offline) = CatalogChecker.applying(checks, to: catalog, now: Date())
                    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    if parts.count > 1 { try e.encode(checks).write(to: URL(fileURLWithPath: parts[1])) }
                    if write { try CatalogChecker.encode(stamped).write(to: catalogURL) }
                    print("PulseFeed: [Catalog] checked \(checks.count): \(checks.count - failed.count - offline.count) ok, \(failed.count) failed, \(offline.count) offline")
                    for f in failed { print("PulseFeed: [Catalog] FAILED \(f.url): \(f.error ?? "")") }
                } catch {
                    print("PulseFeed: [Catalog] check failed: \(error)")
                }
                NSApp.terminate(nil)
            }
            return
        }

        // Typed-interests hook (PULSEFEED_DEBUG_INTERESTS="<text>"): resolve, print, apply nothing, quit.
        if let typed = ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_INTERESTS"], !typed.isEmpty {
            Task {
                if let catalog = Catalog.bundled {
                    let r = await InterestMatcher.resolve(typed, catalog: catalog, context: .topics)
                    print("PulseFeed: [Interests] engine: \(r.engine); \(r.result.sure.count) sure, \(r.result.suggested.count) suggested")
                    for m in r.result.sure { print("PulseFeed: [Interests]   \(m)") }
                    for m in r.result.suggested { print("PulseFeed: [Interests]   suggested \(m)") }
                } else {
                    print("PulseFeed: [Interests] no bundled catalog")
                }
                NSApp.terminate(nil)
            }
            return
        }

        // Welcome hook (PULSEFEED_DEBUG_WELCOME=1, optional PULSEFEED_DEBUG_WELCOME_STEP=0…6): the flow in dry
        // run on the tool database (launchPath), no freeze, no engine; Finish prints the draft. Quit to end it.
        if ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_WELCOME"] == "1", let appDB {
            let step = Int(ProcessInfo.processInfo.environment["PULSEFEED_DEBUG_WELCOME_STEP"] ?? "")
                .flatMap(WelcomeStep.init(rawValue:)) ?? .welcome
            WelcomeWindowController.shared.open(appDB: appDB, dryRun: true, startStep: step)
            return
        }

        // Showcase hook (PULSEFEED_RENDER_SHOWCASE=<dir>, `make showcase` only): the fictional fixture into the
        // throwaway database (launchPath), the unstarted engine given its prices and last tick, this design's
        // surfaces drawn offscreen as PNGs, exit 0. Before the freeze, the catalog sync and the engine start.
        if let outputDir = ShowcaseGate.outputDirectory() {
            ShowcaseGate.refuseUnlessAllowed()   // already checked in PulseFeedApp.init; never relaxed here
            guard let appDB, let feedEngine, AppDatabase.launchPath() != AppDatabase.defaultPath else {
                print("PulseFeed: [Showcase] no throwaway database; nothing drawn")
                exit(1)
            }
            Fonts.registerBundledFonts()
            Task { @MainActor in
                ShowcasePictures.install()   // before the fixture: its stories carry the pictures' URLs
                guard ShowcasePictures.server.base != nil else {
                    print("PulseFeed: [Showcase] the picture server did not start; nothing drawn")
                    exit(1)
                }
                do {
                    try await ShowcaseFixture.install(in: appDB)
                } catch {
                    print("PulseFeed: [Showcase] fixture failed: \(error)")
                    exit(1)
                }
                ShowcaseRenderer.prepare(engine: feedEngine)
                // Rendered from a run-loop block, not from this task: the renderer pumps the run loop so the
                // views' observations deliver, and the main queue does not drain inside one of its own jobs.
                RunLoop.main.perform(inModes: [.default]) {
                    MainActor.assumeIsolated {
                        do {
                            let paths = try ShowcaseRenderer.run(outputDir: outputDir, design: AppDesign.current,
                                                                 appDB: appDB, engine: feedEngine)
                            for p in paths { print("PulseFeed: [Showcase] \(p.path)") }
                            exit(0)
                        } catch {
                            print("PulseFeed: [Showcase] failed: \(error)")
                            exit(1)
                        }
                    }
                }
            }
            return
        }

        // -- Single-instance guard: quit if another copy is already running --
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != .current }
            if !others.isEmpty {
                print("PulseFeed: [App] Another instance already running (PID \(others.first!.processIdentifier)). Quitting.")
                NSApp.terminate(nil)
                return
            }
        }

        // -- Crash log directory + uncaught exception handler --
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PulseFeed")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        AppDelegate.crashLogPath = logDir.appendingPathComponent("crash.log").path
        NSSetUncaughtExceptionHandler { exception in
            let path = AppDelegate.crashLogPath
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "[\(timestamp)] \(exception.name.rawValue): \(exception.reason ?? "unknown")\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: Data(entry.utf8))
            }
        }

        // Appearance (Settings › General), bundled fonts (Manrope for Stream) and the running design's app icon.
        AppAppearance.apply(AppAppearance.current)
        Fonts.registerBundledFonts()
        AppIcon.apply()

        // An install already in use keeps today's alert rules, AI profile and markets as its own
        // settings before the built-in defaults are read (SettingsFreeze). The same "has stories" answer
        // decides the welcome flow: an install in use never sees it; a fresh one starts with nothing on.
        // A database that did not open (or whose history cannot be read) decides nothing: no freeze, no welcome.
        if let appDB, let hasHistory = try? appDB.hasHistory() {
            SettingsFreeze.materialize(.standard, isExistingInstall: hasHistory)
            launchPlan = WelcomeGate.launchPlan(.standard, hasHistory: hasHistory)
            if launchPlan.prepareFreshInstall {
                do { try appDB.prepareFreshInstall() } catch { print("PulseFeed: [Welcome] fresh-install reset failed: \(error)") }
            }
        }

        // The bundled catalog reaches the database when its version moves on; new sources arrive switched off.
        let syncedVersion = UserDefaults.standard.integer(forKey: AppDatabase.catalogVersionKey)
        if let appDB, let catalog = Catalog.bundled, syncedVersion < catalog.version {
            Task {
                do {
                    let r = try await appDB.syncCatalog(catalog, enableNew: false, previousVersion: syncedVersion)
                    UserDefaults.standard.set(catalog.version, forKey: AppDatabase.catalogVersionKey)
                    print("PulseFeed: [Catalog] v\(catalog.version): \(r.inserted) sources added (off), \(r.topicsAssigned) topics assigned")
                } catch {
                    print("PulseFeed: [Catalog] sync to v\(catalog.version) failed: \(error)")
                }
            }
        }

        // Start polling now, independent of any window being opened.
        feedEngine?.start()
        if launchPlan.showWelcome, let appDB {
            let engine = feedEngine
            WelcomeWindowController.shared.open(appDB: appDB) { engine?.tickNow(reason: "welcome finished") }
        }
        // The learning week records what is shown, opened, starred, saved or dismissed (local table).
        if let appDB { EngagementLog.shared.attach(appDB) }

        // One-time repair: titles stored with HTML entities by double-encoding feeds.
        if let appDB {
            Task {
                if let n = try? await appDB.repairHTMLEntityTitles(), n > 0 {
                    print("PulseFeed: [Repair] decoded HTML entities in \(n) stored titles")
                }
            }
        }

        // Verification hook (PULSEFEED_DEBUG_OPEN): open windows without a click.
        if !DebugOpen.requested.isEmpty, let appDB, let feedEngine {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if DebugOpen.wants("popover"), let updater = self.updaterController {
                    // MenuBarExtra cannot be opened programmatically on this macOS, so host the same
                    // popover view in a plain window for screenshots.
                    let design = AppDesign.current
                    let content = design.popover(appDB: appDB, updater: updater).environment(feedEngine)
                    let window = NSWindow(
                        contentRect: NSRect(origin: .zero, size: design.popoverSize),
                        styleMask: [.titled], backing: .buffered, defer: false)
                    window.title = "Popover preview"
                    window.contentView = NSHostingView(rootView: content)
                    window.isReleasedWhenClosed = false
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                    DebugOpen.previewWindow = window
                }
                if DebugOpen.wants("window") { MainWindowController.shared.open(appDB: appDB, feedEngine: feedEngine) }
                if DebugOpen.wants("widget") { HeadlineWidgetController.shared.toggle(appDB: appDB, feedEngine: feedEngine) }
                if DebugOpen.wants("refresh") { feedEngine.refreshAll() }
                if DebugOpen.wants("urgent") { await feedEngine.debugPostUrgentSample() }
                if DebugOpen.wants("relaunch") {
                    try? await Task.sleep(for: .seconds(1))
                    Relauncher.relaunch()
                }
                if DebugOpen.wants("settings"), let updater = self.updaterController {
                    SettingsWindowController.shared.open(appDB: appDB, updaterController: updater)
                }
            }
        }

        // Icon diagnostic — log but don't set programmatically (usernotifd reads .icns via LaunchServices)
        let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns")
        let iconExists = iconPath != nil
        let iconSize = iconPath.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int } ?? 0
        print("PulseFeed: [Icon] AppIcon.icns exists: \(iconExists), size: \(iconSize) bytes")
        print("PulseFeed: [Icon] Bundle path: \(Bundle.main.bundlePath)")
        print("PulseFeed: [Icon] Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")

        if !iconExists {
            print("PulseFeed: [Icon] WARNING — AppIcon.icns NOT FOUND in bundle Resources!")
        } else if iconSize < 1000 {
            print("PulseFeed: [Icon] WARNING — AppIcon.icns suspiciously small (\(iconSize) bytes)")
        } else {
            print("PulseFeed: [Icon] AppIcon.icns looks good (\(iconSize) bytes)")
        }

        // LSUIElement in Info.plist handles dock hiding, but keep as fallback for dev builds
        if Bundle.main.object(forInfoDictionaryKey: "LSUIElement") == nil {
            NSApp.setActivationPolicy(.accessory)
        }

        // Notifications require a bundle identifier — only if we have one
        guard Bundle.main.bundleIdentifier != nil else {
            print("PulseFeed: [App] WARNING — No bundle identifier, notifications disabled. Use `make run` instead of `swift run`.")
            return
        }

        // Set notification delegate BEFORE requesting auth
        UNUserNotificationCenter.current().delegate = self

        // Register notification categories (NEWS, PRICE_ALERT)
        NotificationService.setupCategories()

        // Ask for notification permission at launch, except on a fresh install: its welcome flow asks in
        // the Alerts step, where the person can see why.
        if launchPlan.askNotificationsAtLaunch { Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                print("PulseFeed: [Notifications] Authorization granted: \(granted)")

                if granted, FirstRun.shouldSendWelcome() {
                    // A one-time greeting on first run, 3 seconds after permission lands.
                    FirstRun.recordWelcomeSent()
                    try? await Task.sleep(for: .seconds(3))
                    let content = UNMutableNotificationContent()
                    content.title = AppInfo.displayName
                    content.body = "Notifications are working. You'll see news alerts here."
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: "pulsefeed-test-\(UUID().uuidString)",
                        content: content,
                        trigger: nil)
                    try await center.add(request)
                    print("PulseFeed: [Notifications] Test notification sent")
                }
            } catch {
                print("PulseFeed: [Notifications] Authorization error: \(error)")
            }
        } }

        // Pre-compile ad block rules for ReaderWebView
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "PulseFeedAdBlock",
            encodedContentRuleList: ReaderWebView.adBlockRulesJSON
        ) { ruleList, error in
            AppDelegate.adBlockRuleList = ruleList
            if let error = error {
                print("PulseFeed: [AdBlock] Compile error: \(error)")
            } else {
                print("PulseFeed: [AdBlock] Rules compiled successfully")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let articleID = userInfo["articleID"] as? String
        let urlString = userInfo["url"] as? String
        let summaryIDs = userInfo["summaryIDs"] as? [String]

        if let summaryIDs {
            switch response.actionIdentifier {
            case "SUMMARY_MARK_READ":
                if let engine = await MainActor.run(body: { self.feedEngine }) { await engine.markRecapRead() }
                if let appDB = await MainActor.run(body: { self.appDB }) { try? await appDB.markReadIncludingCluster(ids: summaryIDs) }
            case "DISMISS", UNNotificationDismissActionIdentifier:
                break
            default:
                // Tapping the recap counts as reading it, then opens the main window on what is left.
                if let appDB = await MainActor.run(body: { self.appDB }) { try? await appDB.markReadIncludingCluster(ids: summaryIDs) }
                await MainActor.run {
                    if let appDB = self.appDB, let engine = self.feedEngine {
                        MainWindowController.shared.open(appDB: appDB, feedEngine: engine)
                    }
                }
            }
            return
        }

        switch response.actionIdentifier {
        case "OPEN_ACTION", UNNotificationDefaultActionIdentifier:
            // Open article in browser + mark read
            if let urlString, let url = URL(string: urlString) {
                await MainActor.run {
                    _ = NSWorkspace.shared.open(url)
                }
            }
            if let articleID, let appDB = await MainActor.run(body: { self.appDB }) {
                try? await appDB.markRead(articleID)
            }

        case "MARK_READ_ACTION":
            // Mark read only — no browser open
            if let articleID, let appDB = await MainActor.run(body: { self.appDB }) {
                try? await appDB.markRead(articleID)
            }

        case "DISMISS", UNNotificationDismissActionIdentifier:
            break

        default:
            break
        }
    }
}
