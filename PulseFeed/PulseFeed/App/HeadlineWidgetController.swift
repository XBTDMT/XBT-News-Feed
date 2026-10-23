import AppKit
import SwiftUI

@MainActor
final class HeadlineWidgetController {
    static let shared = HeadlineWidgetController()
    private var panel: NSPanel?

    func toggle(appDB: AppDatabase, feedEngine: FeedEngine) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let view = AppDesign.current.widget(appDB: appDB)
            .environment(feedEngine)

        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.setFrameAutosaveName("PulseFeedWidget")

        // Position top-right if no saved frame
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - panel.frame.width - 20
            let y = screenFrame.maxY - panel.frame.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}
