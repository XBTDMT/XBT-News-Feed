import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device language model (FoundationModels, macOS 26+). No key, no network.
/// A fresh session per request keeps the small context window from filling up.
struct OnDeviceEnricher: Enricher {
    let name = "on-device"

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .unavailable(let reason) = SystemLanguageModel.default.availability {
                return String(describing: reason)
            }
            return nil
        }
        #endif
        return "FoundationModels not present"
    }

    func generate(system: String, user: String, maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw AIEngineError.unavailable }
            let session = LanguageModelSession(instructions: system)
            var options = GenerationOptions()
            options.temperature = 0.2
            options.maximumResponseTokens = maxTokens
            do {
                let response = try await session.respond(to: user, options: options)
                return response.content
            } catch {
                throw AIEngineError.transport(String(describing: error))
            }
        }
        #endif
        throw AIEngineError.unavailable
    }
}
