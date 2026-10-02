import Foundation
import NaturalLanguage

/// Splits a long text into pieces to translate one by one: paragraphs, and groups of sentences
/// for paragraphs longer than `maxLength`. The whitespace between pieces is kept, so the
/// translations can be joined back in the original layout.
enum TextChunker {
    struct Piece {
        let text: String
        /// What followed the piece in the original: a space, a line break or a blank line.
        let separator: String
    }

    static let maxLength = 1000

    static func pieces(of text: String) -> [Piece] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            guard let paragraph = trimmed(range, in: text) else { return }
            if text[paragraph].count <= maxLength {
                ranges.append(paragraph)
            } else {
                ranges += sentenceGroups(in: paragraph, of: text, tokenizer: tokenizer)
            }
        }
        return ranges.indices.map { index in
            let end = ranges[index].upperBound
            let next = index + 1 < ranges.count ? ranges[index + 1].lowerBound : end
            return Piece(text: String(text[ranges[index]]), separator: String(text[end..<next]))
        }
    }

    private static func trimmed(_ range: Range<String.Index>, in text: String) -> Range<String.Index>? {
        guard let first = text[range].firstIndex(where: { !$0.isWhitespace }),
              let last = text[range].lastIndex(where: { !$0.isWhitespace }) else { return nil }
        return first..<text.index(after: last)
    }

    /// Consecutive sentences joined while they fit in `maxLength`; a longer sentence stays whole.
    private static func sentenceGroups(
        in paragraph: Range<String.Index>,
        of text: String,
        tokenizer: NLTokenizer
    ) -> [Range<String.Index>] {
        var groups: [Range<String.Index>] = []
        var current: Range<String.Index>?
        tokenizer.enumerateTokens(in: paragraph) { range, _ in
            guard let sentence = trimmed(range, in: text) else { return true }
            if let open = current, text[open.lowerBound..<sentence.upperBound].count <= maxLength {
                current = open.lowerBound..<sentence.upperBound
            } else {
                if let open = current { groups.append(open) }
                current = sentence
            }
            return true
        }
        if let current { groups.append(current) }
        return groups
    }
}
