import SwiftUI
import AppKit

struct ShareButton: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.controlSize = .small
        button.imageScaling = .scaleProportionallyDown
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.url = url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    @MainActor
    class Coordinator: NSObject {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        @objc func share(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
