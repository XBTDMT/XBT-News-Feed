import AppKit

/// Applies a design change: spawn a new instance after this one has exited (the single-instance
/// guard in AppDelegate would otherwise kill the newcomer), then quit.
enum Relauncher {
    /// Only a real .app bundle can be reopened with `open -n`; `swift run` cannot.
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    @MainActor
    static func relaunch() {
        guard canRelaunch else {
            print("PulseFeed: [Relaunch] not running from a .app bundle; relaunch skipped")
            return
        }
        let path = Bundle.main.bundleURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""]
        do {
            try process.run()
        } catch {
            print("PulseFeed: [Relaunch] could not spawn the relauncher: \(error)")
            return
        }
        print("PulseFeed: [Relaunch] relaunching \(path)")
        NSApp.terminate(nil)
    }
}
