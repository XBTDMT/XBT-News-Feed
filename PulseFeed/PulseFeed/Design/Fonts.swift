import Foundation
import CoreText

/// Registers every `.ttf` under `Contents/Resources/Fonts` (Manrope, for Stream). Called once at
/// launch; `DesignTokens.font` falls back to the system font when a family did not register.
enum Fonts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registeredFamilies: Set<String> = []

    @discardableResult
    static func registerBundledFonts() -> Bool {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else {
            print("PulseFeed: [Fonts] no bundled Fonts directory (running outside the .app?)")
            return false
        }
        var ok = true
        for url in files where url.pathExtension.lowercased() == "ttf" {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                   let first = descriptors.first,
                   let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String {
                    lock.lock(); registeredFamilies.insert(family); lock.unlock()
                    print("PulseFeed: [Fonts] registered \(family) from \(url.lastPathComponent)")
                }
            } else {
                ok = false
                print("PulseFeed: [Fonts] failed to register \(url.lastPathComponent): \(String(describing: error?.takeRetainedValue()))")
            }
        }
        return ok
    }

    static func isRegistered(_ family: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return registeredFamilies.contains(family)
    }
}
