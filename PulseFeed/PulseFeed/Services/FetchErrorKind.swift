import Foundation

/// Whether a fetch error says something about the FEED or only about this Mac's network. A source
/// is not "failing" because the laptop lid was closed: offline-shaped errors must not raise
/// `consecutiveErrors`, or every feed shows a red dot after one sleep.
enum FetchErrorKind: Equatable, Sendable {
    case transient
    case feed

    static func classify(_ error: Error) -> FetchErrorKind {
        guard let urlError = error as? URLError else { return .feed }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost,
             .cannotConnectToHost, .timedOut, .internationalRoamingOff, .dataNotAllowed:
            return .transient
        default:
            return .feed
        }
    }
}
