import Foundation

/// "apps slash site" → "apps/site", "and slash or" → "and/or": a spoken
/// slash between two words joins them. the engine often hears a plural
/// before it as a possessive ("app's slash site"); paths have no
/// apostrophes, so that "'s" becomes "s". a slash after an article — "type
/// a slash here" — is the word, and stays.
struct SpokenSlash: TranscriptTransform {
    private static let expression = CleanupRegex.compile(
        #"(?<![\p{L}\p{N}])([\p{L}\p{N}_.~\-]+?)(['’]s)?\s+slash\s+(?=[\p{L}\p{N}_.~])"#,
        options: [.caseInsensitive]
    )

    /// words after which "slash" is the noun, not the symbol.
    private static let keepsTheWord: Set<String> = [
        "a", "an", "the", "one", "this", "that", "each", "every", "no",
        "forward", "back", "double", "single",
    ]

    func apply(_ transcript: String) -> String {
        guard let expression = Self.expression else {
            return transcript
        }
        // a chain, "src slash app slash main", needs each slash's left word
        // to be found after the previous join, so repeat until nothing moves.
        var current = transcript
        for _ in 0..<8 {
            let next = expression.replacingMatches(in: current) { match in
                guard let word = current.substring(with: match.range(at: 1)) else {
                    return nil
                }
                guard !Self.keepsTheWord.contains(word.lowercased()) else {
                    return nil
                }
                let plural = match.range(at: 2).location != NSNotFound ? "s" : ""
                return word + plural + "/"
            }
            if next == current { break }
            current = next
        }
        return current
    }
}
