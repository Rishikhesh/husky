import Foundation

/// takes out the sounds that are only hesitation — um, uh, erm, hmm — and the
/// comma they leave behind. an opt-out amendment to ADR 0020: only pure
/// fillers, never "like", "you know", "so" or "well", which can carry meaning.
/// it runs after the parsers and before capitalization and punctuation
/// finishing, so "um, so we ship" still comes out "So we ship."
struct FillerRemoval: TranscriptTransform {
    /// um, umm, uh, uhh, uhm, erm, er, hmm, mm, ah — with any held letter.
    static let fillers = "u+m+|u+h+|u+h+m+|e+r+m+|e+r+|h+m+|m{2,}|a+h+"

    /// an optional comma before, the filler as a whole word (not part of an
    /// address or a contraction), an optional comma after.
    private static let expression = CleanupRegex.compile(
        "(,?)[ \\t]*(?<![\\p{L}\\p{N}_'’@.-])(\(fillers))"
            + "(?![\\p{L}\\p{N}_'’-]|[.@][\\p{L}\\p{N}])(,?)",
        options: [.caseInsensitive]
    )

    func apply(_ transcript: String) -> String {
        guard let expression = Self.expression else {
            return transcript
        }
        let nsTranscript = transcript as NSString
        return expression.replacingMatches(in: transcript) { match in
            let filler = nsTranscript.substring(with: match.range(at: 2))
            let leadingComma = nsTranscript.substring(with: match.range(at: 1))
            let trailingComma = nsTranscript.substring(with: match.range(at: 3))
            let before = nsTranscript.substring(to: match.range.location)
                .trimmingCharacters(in: .whitespaces)
            // "the ER", "5 mm": a filler spelled in capitals, or millimetres
            // after a number, is a word.
            if filler.count > 1, filler == filler.uppercased() {
                return nil
            }
            if filler.lowercased().hasPrefix("mm"),
               before.last?.isNumber == true {
                return nil
            }
            // "so, um, I think" keeps the first comma; "we ship, um." and a
            // filler at the very end lose it, or it dangles.
            let after = nsTranscript.substring(
                from: match.range.location + match.range.length
            ).trimmingCharacters(in: .whitespaces)
            let endsAClause = after.isEmpty
                || after.first.map { ".?!\n".contains($0) } == true
            return trailingComma.isEmpty && endsAClause ? "" : leadingComma
        }
    }
}
