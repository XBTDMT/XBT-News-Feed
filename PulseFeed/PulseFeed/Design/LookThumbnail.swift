import Foundation

/// The welcome flow's Look step shows a small picture of each design: `look-<design>.png`, made by
/// `make public-images` from the showcase's own popover renders and copied into the bundle by `make bundle`
/// (`Contents/Resources/Welcome/`). Nil when the bundle has none (`swift run`); the step keeps the symbol.
enum LookThumbnail {
    static let subdirectory = "Welcome"

    static func resourceName(for design: AppDesign) -> String { "look-\(design.rawValue)" }

    static func url(for design: AppDesign, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName(for: design), withExtension: "png", subdirectory: subdirectory)
    }

    /// `make showcase` only: the folder its own run just wrote the thumbnails to, so the welcome renders never
    /// show the previous run's pictures. Nil everywhere else.
    @MainActor static var directoryOverride: URL?

    /// What the Look step shows: the showcase's fresh thumbnail when one is set, else the bundle's.
    @MainActor static func current(for design: AppDesign) -> URL? {
        if let dir = directoryOverride {
            let file = dir.appendingPathComponent(resourceName(for: design) + ".png")
            return FileManager.default.fileExists(atPath: file.path) ? file : nil
        }
        return url(for: design)
    }
}
