import Foundation
import Observation

/// Text in any other language is translated into the user's language; text in the user's language
/// goes into the language of the last translation, so a reply lands in the conversation's language.
/// Values are `LanguageCatalog` keys.
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()

    var primary: String {
        didSet {
            if lastForeign == primary { lastForeign = oldValue }
            UserDefaults.standard.set(primary, forKey: Keys.primary)
        }
    }

    /// The other side of the last successful translation.
    private(set) var lastForeign: String {
        didSet { UserDefaults.standard.set(lastForeign, forKey: Keys.lastForeign) }
    }

    private enum Keys {
        static let primary = "primaryLanguage"
        static let lastForeign = "lastForeignLanguage"
    }

    /// Starts from the system languages: the first is mine, the next one is the initial foreign language.
    init() {
        let system = Locale.preferredLanguages.map { Locale.Language(identifier: $0).baseKey }
        let primary = UserDefaults.standard.string(forKey: Keys.primary) ?? system.first ?? "en"
        self.primary = primary
        self.lastForeign = UserDefaults.standard.string(forKey: Keys.lastForeign)
            ?? system.first { $0 != primary }
            ?? (primary == "en" ? "es" : "en")
    }

    func target(forSource source: String) -> String {
        source == primary ? lastForeign : primary
    }

    func remember(_ pair: LanguagePair) {
        let foreign = pair.source == primary ? pair.target : pair.source
        if foreign != primary { lastForeign = foreign }
    }

    /// Replaces languages Translation doesn't support, e.g. a system language it lacks.
    func adopt(supported: [String]) {
        guard !supported.isEmpty else { return }
        if !supported.contains(primary) { primary = Self.fallback(in: supported, excluding: lastForeign) }
        if !supported.contains(lastForeign) { lastForeign = Self.fallback(in: supported, excluding: primary) }
    }

    private static func fallback(in supported: [String], excluding other: String) -> String {
        ["en", "es", "ru"].first { $0 != other && supported.contains($0) }
            ?? supported.first { $0 != other }
            ?? other
    }
}
