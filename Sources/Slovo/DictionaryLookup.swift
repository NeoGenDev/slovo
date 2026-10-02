import AppKit
import CoreServices

/// A single word's entry from the dictionaries enabled in Dictionary.app.
struct DictionaryEntry: Equatable {
    let word: String
    /// "UK həˈləʊ · US həˈloʊ" when the dictionary marks it up (Oxford bilingual dictionaries do).
    let pronunciation: String?
    let body: String

    func openInDictionaryApp() {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard let url = URL(string: "dict://\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum DictionaryLookup {
    private static let maxWordLength = 40

    static func entry(for text: String) -> DictionaryEntry? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSingleWord(word), let raw = definition(of: word) else { return nil }
        return parse(raw, word: word)
    }

    static func isSingleWord(_ text: String) -> Bool {
        !text.isEmpty
            && text.count <= maxWordLength
            && !text.contains(where: \.isWhitespace)
            && text.contains(where: \.isLetter)
    }

    private static func definition(of word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
    }

    /// Entries are plain text whose shape depends on the dictionary: Oxford bilingual ones start
    /// with "run | BrE rʌn, AmE rən | noun …", explanatory ones go straight to the definition.
    static func parse(_ raw: String, word: String) -> DictionaryEntry? {
        var body = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))

        // The headword may carry stress marks ("приве́т"), hence diacritic-insensitive.
        if let headword = body.range(of: word, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) {
            body = body[headword.upperBound...]
        }

        var variants: [String] = []
        var headerEnd: Substring.Index?
        for (label, name) in [("BrE", L10n.britishEnglish), ("AmE", L10n.americanEnglish)] {
            guard let range = body.range(of: "\(label) ") else { continue }
            let rest = body[range.upperBound...]
            let transcription = rest.prefix { !",|/".contains($0) }.trimmingCharacters(in: .whitespaces)
            guard !transcription.isEmpty else { continue }
            variants.append("\(name) \(transcription)")
            // The transcription block ends at the next "|" (or "/" in some entries).
            headerEnd = rest.firstIndex { "|/".contains($0) }.map { body.index(after: $0) } ?? headerEnd
        }
        if let headerEnd {
            body = body[headerEnd...]
        }

        // Usage examples are glued to the previous one ("пробе́жка▸ he went"); give each marker room.
        let text = body
            .replacingOccurrences(of: "▸", with: " ▸ ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,|/").union(.whitespacesAndNewlines))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let pronunciation = variants.isEmpty ? nil : variants.joined(separator: " · ")
        guard !text.isEmpty || pronunciation != nil else { return nil }
        return DictionaryEntry(word: word, pronunciation: pronunciation, body: text)
    }
}
