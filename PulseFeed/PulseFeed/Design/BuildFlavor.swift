import Foundation

/// Which copy of the app this is. The public build (`-DPUBLIC_BUILD`, `make test-public`) leaves out the
/// providers whose terms do not allow a public app (Yahoo quotes, ESPN, Binance): they live under
/// `Services/Private/`, each file wrapped in `#if !PUBLIC_BUILD`, and the export strips them.
enum BuildFlavor {
    static let isPublic = true
}
