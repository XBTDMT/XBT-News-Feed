import Foundation

/// The app's names as people see them, read from the bundle so the one place that sets them is Info.plist
/// (the public copy is "News Feed", the owner's build "XBTDMT News Feed" / "XBTDMT Feed"). Views and windows ask here.
enum AppInfo {
    /// The name when no bundle names it (`swift run`, tests).
    static let fallbackName = "News Feed"

    /// `CFBundleDisplayName`, else `CFBundleName`, else "News Feed". Pure, so it is tested with plain dictionaries.
    static func displayName(_ info: [String: Any]?) -> String {
        (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? fallbackName
    }

    static var displayName: String { displayName(Bundle.main.infoDictionary) }

    /// The shorter name of the windows and headers (`PFShortName`, "XBTDMT Feed" for the owner's build),
    /// else the display name.
    static func shortName(_ info: [String: Any]?) -> String {
        (info?["PFShortName"] as? String) ?? displayName(info)
    }

    static var shortName: String { shortName(Bundle.main.infoDictionary) }

    /// Where "Install to /Applications" puts the app.
    static func installURL(displayName: String) -> URL {
        URL(fileURLWithPath: "/Applications/\(displayName).app")
    }
}
