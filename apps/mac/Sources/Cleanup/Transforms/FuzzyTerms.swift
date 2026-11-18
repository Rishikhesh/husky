import Foundation

/// snaps near-misses of your dictionary's right-hand spellings onto them:
/// "versel" → "Vercel", "kubernetis" → "Kubernetes", "git hub" → "GitHub".
/// it runs after the exact rows, inside the dictionary stage, so a word you
/// taught it exactly always wins. the scoring is T3 Code's (pingdotgg/t3code,
/// customWords.ts): edit distance over the longer key, a phonetic discount,
/// a 0.18 cut. it is more careful than that one, because rewriting an
/// ordinary word is worse than missing a jargon one:
///   - a key under four letters is never fuzzed;
///   - a single word that is everyday english (`CommonWords`) is never
///     touched — "versus" stays "versus" next to "Vercel";
///   - a phrase of everyday words only snaps when it spells the term exactly
///     ("type script" → "TypeScript"), never when it is merely close
///     ("cloud code" stays, even next to "Claude Code");
///   - the phonetic discount is halved, not T3's 0.3;
///   - a word that already spells part of one of your terms only joins
///     that term, so what an exact row wrote is not fuzzed into another.
/// the preferred spelling goes in as you wrote it — "iPhone" stays "iPhone"
/// at a sentence start; capitalization later respects that (ADR 0038).
/// punctuation around the words stays where it was.
struct FuzzyTerms {
    static let threshold = 0.18
    static let minimumLength = 4

    private struct Term {
        let spelling: String
        let key: String
        let pieces: Set<String>
    }

    private struct Token {
        let core: Range<String.Index>
        let key: String
        let hasLeadingPunctuation: Bool
        let hasTrailingPunctuation: Bool
        let isCommon: Bool
        let isPieceOfATerm: Bool
    }

    private let terms: [Term]
    /// the key of every word inside a term: "claude" and "code" for
    /// "Claude Code".
    private let pieces: Set<String>

    init(preferred spellings: [String]) {
        var seen = Set<String>()
        terms = spellings.compactMap { raw in
            let spelling = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.key(spelling)
            guard key.count >= Self.minimumLength,
                  key.allSatisfy({ $0.isASCII }),
                  seen.insert(key).inserted else {
                return nil
            }
            let pieces = spelling
                .split(whereSeparator: \.isWhitespace)
                .map { Self.key(String($0)) }
            return Term(spelling: spelling, key: key, pieces: Set(pieces))
        }
        pieces = terms.reduce(into: Set()) { $0.formUnion($1.pieces) }
    }

    func apply(_ text: String) -> String {
        guard !terms.isEmpty else {
            return text
        }
        // nil marks a chunk that is not a plain word ("jass@jass.gg",
        // "don't", "café") — it ends any phrase and is never rewritten.
        let chunks = text.split(whereSeparator: \.isWhitespace)
        let tokens = chunks.map(token(in:))

        var output = ""
        var cursor = text.startIndex
        var index = 0
        while index < tokens.count {
            guard let match = bestMatch(
                at: index,
                tokens: tokens,
                chunks: chunks,
                in: text
            ), let first = tokens[index],
               let last = tokens[index + match.count - 1]
            else {
                index += 1
                continue
            }
            let range = first.core.lowerBound..<last.core.upperBound
            output += text[cursor..<range.lowerBound]
            output += match.term.spelling
            cursor = range.upperBound
            index += match.count
        }
        output += text[cursor...]
        return output
    }

    private func bestMatch(
        at start: Int,
        tokens: [Token?],
        chunks: [Substring],
        in text: String
    ) -> (term: Term, count: Int)? {
        var best: (term: Term, count: Int, score: Double)?
        for count in 1...min(3, tokens.count - start) {
            let window = tokens[start..<start + count].compactMap { $0 }
            guard window.count == count,
                  isOnePhrase(window, chunks: chunks[start..<start + count], in: text)
            else {
                break
            }
            let candidate = window.map(\.key).joined()
            guard candidate.count >= Self.minimumLength else {
                continue
            }
            for term in terms {
                guard let score = score(candidate, window: window, against: term),
                      // a tie goes to the shorter phrase: fewer words eaten.
                      score < (best?.score ?? Self.threshold) else {
                    continue
                }
                best = (term, count, score)
            }
        }
        guard let best else {
            return nil
        }
        return (best.term, best.count)
    }

    /// a phrase is words a space apart on one line, with punctuation only
    /// on its outside edges: "git hub," is one, "git, hub" is two.
    private func isOnePhrase(
        _ window: [Token],
        chunks: ArraySlice<Substring>,
        in text: String
    ) -> Bool {
        guard window.count > 1 else {
            return true
        }
        let chunks = Array(chunks)
        for offset in 0..<window.count - 1 {
            if window[offset].hasTrailingPunctuation
                || window[offset + 1].hasLeadingPunctuation
                || text[chunks[offset].endIndex..<chunks[offset + 1].startIndex]
                    .contains(where: \.isNewline) {
                return false
            }
        }
        return true
    }

    private func score(
        _ candidate: String,
        window: [Token],
        against term: Term
    ) -> Double? {
        if window.count == 1, window[0].isCommon {
            return nil
        }
        if candidate == term.key {
            return 0
        }
        // "Claude" is yours; it can be part of "Claude Code", never a
        // near-miss of some other term.
        if window.contains(where: {
            $0.isPieceOfATerm && !term.pieces.contains($0.key)
        }) || window.allSatisfy({ $0.isCommon || $0.key.count < Self.minimumLength }) {
            return nil
        }
        let longest = max(candidate.count, term.key.count)
        guard abs(candidate.count - term.key.count)
                <= max(Int(Double(longest) * 0.25), 2) else {
            return nil
        }
        let distance = Double(Self.editDistance(candidate, term.key))
            / Double(longest)
        let soundsAlike = candidate.allSatisfy(\.isLetter)
            && term.key.allSatisfy(\.isLetter)
            && Self.soundex(candidate) == Self.soundex(term.key)
        return soundsAlike ? distance * 0.5 : distance
    }

    private func token(in chunk: Substring) -> Token? {
        guard let first = chunk.firstIndex(where: Self.isWordCharacter),
              let last = chunk.lastIndex(where: Self.isWordCharacter) else {
            return nil
        }
        let core = first..<chunk.index(after: last)
        guard chunk[core].allSatisfy({ $0.isASCII && Self.isWordCharacter($0) })
        else {
            return nil
        }
        let key = chunk[core].lowercased()
        return Token(
            core: core,
            key: key,
            hasLeadingPunctuation: first != chunk.startIndex,
            hasTrailingPunctuation: core.upperBound != chunk.endIndex,
            isCommon: CommonWords.contains(key),
            isPieceOfATerm: pieces.contains(key)
        )
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    static func key(_ value: String) -> String {
        String(value.filter(isWordCharacter)).lowercased()
    }

    static func editDistance(_ left: String, _ right: String) -> Int {
        let left = Array(left)
        let right = Array(right)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }

    static func soundex(_ value: String) -> String {
        func code(_ character: Character) -> Character {
            switch character {
            case "b", "f", "p", "v": "1"
            case "c", "g", "j", "k", "q", "s", "x", "z": "2"
            case "d", "t": "3"
            case "l": "4"
            case "m", "n": "5"
            case "r": "6"
            default: "0"
            }
        }
        let characters = Array(value.lowercased())
        guard let first = characters.first else {
            return ""
        }
        var result = String(first).uppercased()
        var previous = code(first)
        for character in characters.dropFirst() {
            let next = code(character)
            if next != "0", next != previous {
                result.append(next)
            }
            previous = next
        }
        return String((result + "000").prefix(4))
    }
}
