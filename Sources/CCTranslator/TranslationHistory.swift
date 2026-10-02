import Foundation
import Observation

/// Recent translations for the menu bar menu. Kept only on this Mac, in the app's preferences.
@Observable
final class TranslationHistory {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        let source: String
        let translation: String
        let sourceLanguage: String
        let targetLanguage: String
        let date: Date
    }

    static let shared = TranslationHistory()
    static let limit = 10

    private(set) var entries: [Entry] {
        didSet { save() }
    }

    private static let defaultsKey = "translationHistory"

    init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        entries = data.flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    /// Puts the translation on top. The same text translated again, e.g. into another language
    /// from the popup's menu, replaces its older entry instead of adding a second one.
    func record(source: String, translation: String, pair: LanguagePair) {
        var updated = entries.filter { $0.source != source }
        updated.insert(
            Entry(source: source, translation: translation, sourceLanguage: pair.source, targetLanguage: pair.target, date: .now),
            at: 0
        )
        entries = Array(updated.prefix(Self.limit))
    }

    func clear() {
        entries = []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
