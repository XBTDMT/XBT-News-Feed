import AppKit
import SwiftUI

@MainActor
final class ArticleReaderWindowController {
    static let shared = ArticleReaderWindowController()
    private var window: NSWindow?

    func open(url: URL, title: String?) {
        let view = ArticleReaderContentView(url: url)

        if let window, window.isVisible {
            window.contentView = NSHostingView(rootView: view)
            window.title = title ?? "Reader"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title ?? "Reader"
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("PulseFeedReader")
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct ArticleReaderContentView: View {
    let url: URL
    @State private var isReaderMode = true
    @State private var articleText = ""
    @StateObject private var speechManager = SpeechManager()
    @AppStorage("speechRate") private var speechRate = 0.5

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(isReaderMode ? "Show Original" : "Reader Mode") {
                    isReaderMode.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    if speechManager.isSpeaking {
                        speechManager.stop()
                    } else if !articleText.isEmpty {
                        speechManager.speak(articleText, rate: speechRate)
                    }
                } label: {
                    Image(systemName: speechManager.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(speechManager.isSpeaking ? "Stop" : "Listen")
                .disabled(articleText.isEmpty)

                Slider(value: $speechRate, in: 0.3...0.7, step: 0.05)
                    .frame(width: 80)
                    .help("Speech rate")

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open in Browser")
            }
            .padding(8)

            Divider()

            ReaderWebView(url: url, isReaderMode: $isReaderMode, theme: AppDesign.current.readerTheme) { text in
                articleText = text
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear { speechManager.stop() }
    }
}
