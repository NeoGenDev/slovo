import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// Below this, a short or ambiguous text ("ok", "release") goes to one of the user's languages.
    private static let confidenceThreshold = 0.7

    /// The language key of `text`, limited to `candidates` (the languages Translation supports).
    /// `preferred` are the user's languages, used to settle low-confidence guesses.
    static func detect(_ text: String, candidates: [String], preferred: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map(NLLanguage.init(rawValue:))
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        if best.value >= confidenceThreshold { return best.key.rawValue }

        // `languageHints` would be simpler, but they override even confident results
        // (German text with ru/en hints comes back as English), so settle ties by script instead.
        let script = Locale.Language(identifier: best.key.rawValue).scriptKey
        var choice: (key: String, probability: Double)?
        for key in preferred where Locale.Language(identifier: key).scriptKey == script {
            let probability = hypotheses[NLLanguage(rawValue: key)] ?? 0
            if choice == nil || probability > choice!.probability {
                choice = (key, probability)
            }
        }
        return choice?.key ?? best.key.rawValue
    }
}
