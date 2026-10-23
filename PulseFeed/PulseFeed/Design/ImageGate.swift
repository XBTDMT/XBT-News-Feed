import Foundation

/// Stream's safeguard from its sheet: images cost battery and bandwidth, so they follow the tier.
enum ImagePolicy: Sendable, Equatable {
    case heroAndThumbnails
    case heroOnly
    case none
}

enum ImageGate {
    static func policy(for tier: PowerTier) -> ImagePolicy {
        switch tier {
        case .ac: return .heroAndThumbnails
        case .battery: return .heroOnly
        case .critical: return .none
        }
    }
}
