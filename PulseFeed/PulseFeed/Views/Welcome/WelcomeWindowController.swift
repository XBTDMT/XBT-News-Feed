import AppKit
import SwiftUI

/// Hosts the welcome flow. Closing the window before Finish applies nothing, so a fresh install sees the
/// flow again at its next launch.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    /// `onFinished` runs after a real Finish (not a dry run), before any relaunch.
    func open(appDB: AppDatabase, dryRun: Bool = false, startStep: WelcomeStep = .welcome, rerun: Bool = false,
              onFinished: @escaping () -> Void = {}) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let catalog = Catalog.bundled else {
            print("PulseFeed: [Welcome] no bundled catalog; the flow cannot open")
            return
        }
        let model = WelcomeFlowModel(appDB: appDB, catalog: catalog, dryRun: dryRun, startStep: startStep, rerun: rerun)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Welcome to News Feed"
        window.contentView = NSHostingView(rootView: WelcomeFlowView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        model.onFinished = { [weak self, weak window] relaunch in
            window?.close()
            self?.window = nil
            guard !dryRun else { return }
            onFinished()
            if relaunch { Relauncher.relaunch() }
        }
        // The utility app has no main menu by itself; the Edit menu is what makes ⌘V work in "Paste your key".
        MainMenu.stepUp()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { MainMenu.stepDownIfNoWindows() } }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        print("PulseFeed: [Welcome] opened\(dryRun ? " (dry run, step \(startStep.rawValue))" : "")")
    }
}
