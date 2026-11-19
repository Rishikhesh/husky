import Foundation

protocol Cleaner {
    func clean(_ transcript: String, continuingASentence: Bool) -> String
}

struct DeterministicCleaner: Cleaner {
    private let entries: [DictionaryEntry]
    private let fullCleanup: Bool
    private let fuzzyMatching: Bool
    private let removeFillers: Bool
    private let style: SpeakingStyle

    /// `fullCleanup: false` is the user's "cleanup off": the words come
    /// through as parakeet heard them, and only the dictionary still runs —
    /// a word you taught it is yours regardless (ADR 0038). close-misspelling
    /// matching is part of the dictionary stage, so it runs with cleanup off
    /// too; filler removal is cleanup, so off means the ums stay.
    init(
        entries: [DictionaryEntry] = [],
        fullCleanup: Bool = true,
        fuzzyMatching: Bool = true,
        removeFillers: Bool = true,
        style: SpeakingStyle = .everyday
    ) {
        self.entries = entries
        self.fullCleanup = fullCleanup
        self.fuzzyMatching = fuzzyMatching
        self.removeFillers = removeFillers
        self.style = style
    }

    /// the three cleanup switches at once. every cleaner the app builds
    /// outside the main dictation path takes these, so none of them can
    /// quietly fall back to a default the user turned off.
    init(entries: [DictionaryEntry], options: CleanupOptions) {
        self.init(
            entries: entries,
            fullCleanup: options.fullCleanup,
            fuzzyMatching: options.fuzzyMatching,
            removeFillers: options.removeFillers,
            style: options.style
        )
    }

    var options: CleanupOptions {
        CleanupOptions(
            fullCleanup: fullCleanup,
            fuzzyMatching: fuzzyMatching,
            removeFillers: removeFillers,
            style: style
        )
    }

    /// `continuingASentence` is the one thing the pipeline knows about the
    /// place the words are going: the caret sits mid-sentence, so the first
    /// word keeps the case it was said in. nowhere to read it (the fix-a-word
    /// playground, a field that refused the question) means false, which is
    /// what the cleaner has always done.
    func clean(
        _ transcript: String,
        continuingASentence: Bool = false
    ) -> String {
        transforms(continuingASentence: continuingASentence)
            .reduce(transcript) { partial, transform in
                transform.apply(partial)
            }
    }

    /// the text the dictionary itself matches against: every transform up to
    /// `DictionarySubstitutions` and none after it. "fix a word" builds an
    /// entry's `wrong` side out of this string, so pointing at a word cannot
    /// produce an entry that never fires. the boundary is found in the one
    /// transform list rather than copied into a second, because two lists
    /// drift. with `fullCleanup: false` it is the transcript untouched, which
    /// is already all the dictionary sees there.
    func asHeard(_ transcript: String) -> String {
        let transforms = transforms(continuingASentence: false)
        guard let boundary = transforms.firstIndex(where: {
            $0 is DictionarySubstitutions
        }) else {
            return transcript
        }
        return transforms[..<boundary].reduce(transcript) { partial, transform in
            transform.apply(partial)
        }
    }

    private func transforms(
        continuingASentence: Bool
    ) -> [any TranscriptTransform] {
        let dictionary = DictionarySubstitutions(
            entries: entries,
            fuzzy: fuzzyMatching
        )
        guard fullCleanup else {
            return [dictionary]
        }
        // ADR 0019 makes this order a behavior contract. ADR 0020 removed
        // the three stages that guessed at intent — self-corrections,
        // repetition collapse, filler removal — leaving only stages that
        // render what you said into how it is written.
        // the dictionary runs second, ahead of the parsers: it has to read
        // the engine's own words, because that is what "fix a word" points
        // at. an entry keyed on parsed text — "7" where the engine heard
        // "seven" — stops firing (this amends ADR 0019's order).
        // the dictionary stage matches exact rows first, then (when on)
        // snaps close misspellings onto your right-hand spellings; both
        // read the engine's words, so neither moves.
        // filler removal amends ADR 0020 as a setting, on by default: pure
        // hesitation sounds only (um, uh, erm, hmm — never "like" or "you
        // know"). it runs after the parsers, so spoken commas around a
        // filler are already real ones it can tidy, and before
        // capitalization and punctuation finishing, so "um, so" still
        // starts with a capital and the spacing it leaves is closed up.
        var stages: [any TranscriptTransform] = [
            UnicodeWhitespaceNormalizer(),
            dictionary,
            SpokenPunctuation(),
            EmailParser(),
            URLParser(),
            NumberParser(),
        ]
        if style == .developer {
            stages.append(CodeWords())
        }
        stages += [
            // after the url parser, which owns a slash that follows a
            // domain, and after numbers, so "24 slash 7" is 24/7.
            SpokenSlash(),
        ]
        if removeFillers {
            stages.append(FillerRemoval())
        }
        stages += [
            Capitalization(continuingASentence: continuingASentence),
            PunctuationFinishing(),
        ]
        return stages
    }
}

/// the user's three cleanup switches: Clean up, Match close misspellings,
/// Remove ums and uhs. one value, so a cleaner is built from all of them or
/// none.
struct CleanupOptions: Equatable, Sendable {
    var fullCleanup = true
    var fuzzyMatching = true
    var removeFillers = true
    var style: SpeakingStyle = .everyday

    /// the same switches with cleanup off: raw words, the dictionary (and its
    /// close-misspelling matching) still applied.
    var raw: CleanupOptions {
        var options = self
        options.fullCleanup = false
        return options
    }
}

/// who is talking, for the spoken symbols that mean different things to
/// different people: "dash" and "dot" are words in an email and symbols in
/// a terminal. a new style is a case here and its rules in the cleaner.
enum SpeakingStyle: String, CaseIterable, Sendable {
    case everyday
    case developer

    var title: String {
        switch self {
        case .everyday: "Everyday"
        case .developer: "Developer"
        }
    }

    var explanation: String {
        switch self {
        case .everyday:
            "Say “slash” for /. Dash, dot and the rest stay words."
        case .developer:
            "Also “dot”, “dash” or “hyphen”, “underscore”, “tilde” and “backtick”: main dot swift → main.swift, dash dash force → --force, user underscore id → user_id."
        }
    }
}
