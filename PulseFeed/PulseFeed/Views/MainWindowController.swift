import SwiftUI
import AppKit

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?

    func open(appDB: AppDatabase, feedEngine: FeedEngine) {
        // Capture the popover window BEFORE opening the main window
        let popoverWindow = NSApp.keyWindow

        if let window, window.isVisible {
            MainMenu.stepUp()
            window.makeKeyAndOrderFront(nil)
            popoverWindow?.close()
            return
        }

        let design = AppDesign.current
        let mainView = design.mainWindow(appDB: appDB)
            .environment(feedEngine)
        let hostingView = NSHostingView(rootView: mainView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: design.mainWindowDefaultSize.width, height: design.mainWindowDefaultSize.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.shortName
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: design.mainWindowMinSize.width, height: design.mainWindowMinSize.height)
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("PulseFeedMain")
        window.isReleasedWhenClosed = false
        MainMenu.stepUp()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            // Let the close finish before deciding whether any regular window is still open.
            DispatchQueue.main.async { MainActor.assumeIsolated { MainMenu.stepDownIfNoWindows() } }
        }

        popoverWindow?.close()
    }
}
