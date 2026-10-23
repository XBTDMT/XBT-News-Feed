import Foundation

/// Who may draw the showcase (`PULSEFEED_RENDER_SHOWCASE=<dir>`, `make showcase`): only the copy of the
/// bundle `make showcase` re-signs as `com.pulsefeed.showcase`. That copy has its own defaults domain, so
/// the fixture's settings never reach the owner's (`com.pulsefeed.app`), and the single-instance guard
/// never sees it as a second copy of the running app. Under any other bundle id the run is refused before
/// the database, the engine or a window is touched.
enum ShowcaseGate {
    static let bundleID = "com.pulsefeed.showcase"
    static let environmentKey = "PULSEFEED_RENDER_SHOWCASE"
    static let refusedExitCode: Int32 = 2

    static func allowed(bundleID: String?) -> Bool { bundleID == Self.bundleID }

    /// The folder the PNGs go to; nil when the hook is unset (a normal launch).
    static func outputDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let raw = environment[environmentKey], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    /// Called first thing at launch: a showcase run under the wrong bundle id prints why and exits 2.
    static func refuseUnlessAllowed(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    bundleID: String? = Bundle.main.bundleIdentifier) {
        guard outputDirectory(environment: environment) != nil, !allowed(bundleID: bundleID) else { return }
        print("PulseFeed: [Showcase] refused: run it through make showcase")
        exit(refusedExitCode)
    }
}
