import Foundation
import Observation
import Translation

extension Locale.Language {
    /// The language without its region: "en", "ru", or "zh-Hans" / "zh-Hant" where the script matters.
    /// Matches `NLLanguage` raw values.
    var baseKey: String {
        let maximal = Locale.Language(identifier: maximalIdentifier)
        let code = maximal.languageCode?.identifier ?? minimalIdentifier
        if code == "zh", let script = maximal.script?.identifier { return "zh-\(script)" }
        return code
    }

    var scriptKey: String? {
        Locale.Language(identifier: maximalIdentifier).script?.identifier
    }
}

/// Languages Apple Translation supports, one entry per language.
///
/// Translation lists regional variants separately (11 kinds of English) and downloads them
/// separately too, so each language is pinned to its default variant: en → en-US, zh-Hant → zh-Hant-TW.
@Observable
final class LanguageCatalog {
    struct Language: Identifiable, Hashable {
        let key: String
        /// The variant passed to Translation.
        let variant: Locale.Language
        let name: String
        var id: String { key }
    }

    static let shared = LanguageCatalog()

    private(set) var languages: [Language] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    var keys: [String] { languages.map(\.key) }

    func load() async {
        if loadTask == nil {
            loadTask = Task {
                self.languages = Self.collapse(await Self.fetchSupported())
            }
        }
        await loadTask?.value
    }

    /// Off the main actor: `LanguageAvailability` isn't Sendable, so it can't be awaited from there.
    nonisolated private static func fetchSupported() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    /// Whether the language itself is downloaded, independent of any pair.
    nonisolated static func status(of language: Locale.Language) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: language, to: nil)
    }

    func variant(for key: String) -> Locale.Language {
        languages.first { $0.key == key }?.variant ?? Locale.Language(identifier: key)
    }

    func name(for key: String) -> String {
        languages.first { $0.key == key }?.name ?? Self.displayName(for: key)
    }

    /// The language's name in the UI language, capitalized: "Английский" / "English".
    static func displayName(for key: String) -> String {
        let name = L10n.locale.localizedString(forIdentifier: key) ?? key
        return name.prefix(1).uppercased(with: L10n.locale) + name.dropFirst()
    }

    private static func collapse(_ supported: [Locale.Language]) -> [Language] {
        Dictionary(grouping: supported, by: \.baseKey)
            .map { key, variants in
                let preferred = Locale.Language(identifier: key).maximalIdentifier
                let variant = variants.first { $0.maximalIdentifier == preferred }
                    ?? variants.min { $0.minimalIdentifier < $1.minimalIdentifier }
                    ?? variants[0]
                return Language(key: key, variant: variant, name: displayName(for: key))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
