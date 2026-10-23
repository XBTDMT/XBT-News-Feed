import Foundation

/// The two free keys a person can add to upgrade a job (spec D13, G-2): Finnhub for real exchange quotes,
/// balldontlie for live NBA scores. Nothing ships a key; each person signs up for their own.
enum ProviderKey: String, CaseIterable, Sendable {
    case finnhub, balldontlie

    var fileName: String { ".\(rawValue)-key" }

    var providerName: String {
        switch self {
        case .finnhub: return "Finnhub"
        case .balldontlie: return "balldontlie"
        }
    }
}

/// Keys live in files beside `.claude-api-key`, readable by this user only.
struct ProviderKeyStore: Sendable {
    let directory: URL

    static var standard: ProviderKeyStore { standard() }

    /// A tool run's keys: a temporary folder of this run alone (like its throwaway database), so a key saved
    /// in one dry run never shows as added in the next.
    static let toolRunDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PulseFeed-tool-keys-\(UUID().uuidString)")

    /// The install's keys; a tool run (`AppDatabase.toolRunKeys`, e.g. the showcase) gets `toolRunDirectory`
    /// instead, so the owner's keys never shape what it draws.
    static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderKeyStore {
        if AppDatabase.toolRunKeys.contains(where: { !(environment[$0] ?? "").isEmpty }) {
            return ProviderKeyStore(directory: toolRunDirectory)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ProviderKeyStore(directory: appSupport.appendingPathComponent("PulseFeed"))
    }

    private func url(_ key: ProviderKey) -> URL { directory.appendingPathComponent(key.fileName) }

    func get(_ key: ProviderKey) -> String? {
        guard let value = try? String(contentsOf: url(key), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func set(_ key: ProviderKey, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { remove(key); return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(trimmed.utf8).write(to: url(key), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(key).path)
    }

    func remove(_ key: ProviderKey) {
        try? FileManager.default.removeItem(at: url(key))
    }
}

/// The card's Test button: one real call with the pasted key, passed only on a real answer.
enum ProviderKeyTest {
    static func request(_ key: ProviderKey, value: String) -> URLRequest {
        switch key {
        case .finnhub:
            var c = URLComponents(string: "https://finnhub.io/api/v1/quote")!
            c.queryItems = [URLQueryItem(name: "symbol", value: "AAPL"), URLQueryItem(name: "token", value: value)]
            return URLRequest(url: c.url!)
        case .balldontlie:
            var r = URLRequest(url: URL(string: "https://api.balldontlie.io/v1/teams")!)
            r.setValue(value, forHTTPHeaderField: "Authorization")
            return r
        }
    }

    static func passed(_ key: ProviderKey, status: Int, body: Data) -> Bool {
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        switch key {
        case .finnhub: return ((json["c"] as? NSNumber)?.doubleValue ?? 0) > 0
        case .balldontlie: return !((json["data"] as? [Any]) ?? []).isEmpty
        }
    }

    enum Outcome: Equatable, Sendable { case passed, rejected, unreachable }

    /// No answer, rate-limited (429) or a server error is "couldn't check"; any other refusal is the key.
    static func outcome(_ key: ProviderKey, status: Int?, body: Data) -> Outcome {
        guard let status else { return .unreachable }
        if status == 429 || status >= 500 { return .unreachable }
        return passed(key, status: status, body: body) ? .passed : .rejected
    }

    static func run(_ key: ProviderKey, value: String, session: URLSession = .shared) async -> Outcome {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected }
        guard let (data, response) = try? await session.data(for: request(key, value: trimmed)) else { return .unreachable }
        return outcome(key, status: (response as? HTTPURLResponse)?.statusCode, body: data)
    }
}

/// What each card says (spec D13): what changes, that it is free and quick, where the key goes, that
/// skipping is fine. The welcome flow and Settings › Power › Data sources show the same words.
enum ProviderKeyCopy {
    static func title(_ key: ProviderKey) -> String {
        switch key {
        case .finnhub: return "Real exchange prices"
        case .balldontlie: return "Live game updates"
        }
    }

    static func whatChanges(_ key: ProviderKey) -> String {
        switch key {
        case .finnhub:
            return "Without a key, stock prices come from tokenized copies traded on crypto exchanges (marked with an x) and the dollar from the ECB's daily rates. A free Finnhub key switches the stocks to real exchange quotes."
        case .balldontlie:
            return "Without a key you get NBA news and results from your sources. A free balldontlie key adds live scores for the NBA teams you follow, checked every minute while they play."
        }
    }

    static func cost(_ key: ProviderKey) -> String {
        "Free, and it takes about a minute: sign up, copy your key, paste it here."
    }

    static func privacy(_ key: ProviderKey) -> String {
        "Your key stays on this Mac and is only sent to \(key.providerName)."
    }

    static func skip(_ key: ProviderKey) -> String {
        "Skipping is fine: the app works without it."
    }

    static func unreachable(_ key: ProviderKey) -> String {
        "Couldn't reach \(key.providerName) right now, so the key was not checked. Try again in a moment."
    }

    static func signUpURL(_ key: ProviderKey) -> URL {
        switch key {
        case .finnhub: return URL(string: "https://finnhub.io/register")!
        case .balldontlie: return URL(string: "https://app.balldontlie.io/")!
        }
    }
}
