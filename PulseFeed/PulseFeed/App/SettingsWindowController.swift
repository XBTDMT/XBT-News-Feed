import AppKit
import SwiftUI
import Sparkle

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func open(appDB: AppDatabase, updaterController: SPUStandardUpdaterController) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = AppDesign.current.settings(appDB: appDB, updater: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.shortName) Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
