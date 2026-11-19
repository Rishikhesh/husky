import Foundation

/// the developer style's spoken symbols. in everyday writing "dash" and "dot"
/// are words ("a quick dash to the shop"), so these run only when the user
/// picked the developer style:
///
/// - "main dot swift" → main.swift
/// - "my dash component" / "my hyphen component" → my-component
/// - "dash dash force" → --force
/// - "user underscore id" → user_id, "underscore private" → _private
/// - "tilde" → ~ (and "tilde slash projects" → ~/projects, by `SpokenSlash`)
/// - "backtick npm install backtick" → `npm install`
///
/// a lone "dash x" is left alone: "ls dash la" could be ls -la or ls-la, and
/// guessing wrong in a terminal is worse than a word to fix.
struct CodeWords: TranscriptTransform {
    private static let word = #"[\p{L}\p{N}_.~\-/]"#

    private static let rules: [(NSRegularExpression?, String)] = [
        // a flag: "dash dash force" → --force. before the joins, so the
        // second dash is not read as joining two words.
        (CleanupRegex.compile(#"(?<![\p{L}\p{N}])(?:dash|hyphen)\s+(?:dash|hyphen)\s+(?=[\p{L}\p{N}])"#, options: [.caseInsensitive]), "--"),
        (CleanupRegex.compile(#"(?<=\#(word))\s+dot\s+(?=[\p{L}\p{N}_])"#, options: [.caseInsensitive]), "."),
        (CleanupRegex.compile(#"(?<=[\p{L}\p{N}_])\s+(?:dash|hyphen)\s+(?=[\p{L}\p{N}])"#, options: [.caseInsensitive]), "-"),
        (CleanupRegex.compile(#"(?<=\#(word))\s+underscore\s+(?=[\p{L}\p{N}])"#, options: [.caseInsensitive]), "_"),
        (CleanupRegex.compile(#"(?<![\p{L}\p{N}])underscore\s+(?=[\p{L}\p{N}])"#, options: [.caseInsensitive]), "_"),
        (CleanupRegex.compile(#"(?<![\p{L}\p{N}])tilde(?![\p{L}\p{N}])"#, options: [.caseInsensitive]), "~"),
    ]

    private static let backtickPair = CleanupRegex.compile(
        #"(?<![\p{L}\p{N}])back\s?ticks?\s+(.+?)\s+back\s?ticks?(?![\p{L}\p{N}])"#,
        options: [.caseInsensitive]
    )
    private static let backtick = CleanupRegex.compile(
        #"(?<![\p{L}\p{N}])back\s?tick(?![\p{L}\p{N}])"#,
        options: [.caseInsensitive]
    )

    func apply(_ transcript: String) -> String {
        var text = transcript
        for (expression, symbol) in Self.rules {
            guard let expression else { continue }
            text = expression.stringByReplacingMatches(
                in: text, range: text.fullNSRange,
                withTemplate: NSRegularExpression.escapedTemplate(for: symbol)
            )
        }
        if let pair = Self.backtickPair {
            text = pair.stringByReplacingMatches(in: text, range: text.fullNSRange, withTemplate: "`$1`")
        }
        if let single = Self.backtick {
            text = single.stringByReplacingMatches(in: text, range: text.fullNSRange, withTemplate: "`")
        }
        return text
    }
}
