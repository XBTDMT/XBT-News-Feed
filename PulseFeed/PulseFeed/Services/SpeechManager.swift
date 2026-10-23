import AVFoundation

@MainActor
final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    private(set) var currentText: String = ""

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Double) {
        if isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        currentText = text
        let utterance = AVSpeechUtterance(string: text)
        // Map 0.3–0.7 slider to AVSpeechUtterance rate range
        // AVSpeechUtteranceMinimumSpeechRate (0.0) to MaximumSpeechRate (1.0)
        // Default is ~0.5. Map our 0.3–0.7 to 0.3–0.6 of AV range.
        let avRate = Float((rate - 0.3) / (0.7 - 0.3)) * 0.3 + 0.3
        utterance.rate = avRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentText = ""
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
