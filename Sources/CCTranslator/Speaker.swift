import AVFoundation
import Observation

/// Reads text aloud with the system voices; works offline, no permission needed.
@Observable
final class Speaker {
    static let shared = Speaker()

    /// Which text is being read, as passed to `toggle`, so its button can show it's playing.
    private(set) var speakingID: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Retained here: the synthesizer holds its delegate weakly.
    @ObservationIgnored private var delegate: SpeechDelegate?
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?

    init() {
        let delegate = SpeechDelegate { [weak self] utterance in self?.utteranceEnded(utterance) }
        self.delegate = delegate
        synthesizer.delegate = delegate
    }

    /// Starts reading `text`, or stops if that same text is already being read.
    func toggle(_ text: String, language: Locale.Language, id: String) {
        if speakingID == id {
            stop()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        currentUtterance = ObjectIdentifier(utterance)
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        speakingID = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Ignores the late callback of an utterance that was replaced by a newer one.
    private func utteranceEnded(_ utterance: ObjectIdentifier) {
        guard utterance == currentUtterance else { return }
        currentUtterance = nil
        speakingID = nil
    }

    /// The best installed voice for the language: highest quality, then the user's default for it.
    /// Novelty voices (Bells, Bubbles…) and Personal Voice are skipped.
    static func voice(for language: Locale.Language) -> AVSpeechSynthesisVoice? {
        let maximal = Locale.Language(identifier: language.maximalIdentifier)
        guard let code = maximal.languageCode?.identifier else { return nil }
        let tag = [code, maximal.region?.identifier].compactMap { $0 }.joined(separator: "-")

        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let exact = voices.filter { $0.language == tag }
        let candidates = exact.isEmpty ? voices.filter { $0.language.hasPrefix("\(code)-") } : exact
        let systemDefault = AVSpeechSynthesisVoice(language: tag)
        let rank = { (voice: AVSpeechSynthesisVoice) in
            (voice.quality.rawValue, voice.identifier == systemDefault?.identifier ? 1 : 0)
        }
        return candidates.max { rank($0) < rank($1) } ?? systemDefault
    }
}

/// Kept apart from `Speaker`: an @Observable class inheriting from NSObject trips Sendable checks.
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onEnd: @MainActor @Sendable (ObjectIdentifier) -> Void

    init(onEnd: @escaping @MainActor @Sendable (ObjectIdentifier) -> Void) {
        self.onEnd = onEnd
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor in self.onEnd(finished) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelled = ObjectIdentifier(utterance)
        Task { @MainActor in self.onEnd(cancelled) }
    }
}
