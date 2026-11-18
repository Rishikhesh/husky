import XCTest

final class FuzzyDictionaryTests: XCTestCase {
    private let entries = [
        DictionaryEntry(wrong: "versell", right: "Vercel"),
        DictionaryEntry(wrong: "get hub", right: "GitHub"),
        DictionaryEntry(wrong: "cube", right: "Kubernetes"),
        DictionaryEntry(wrong: "eye phone", right: "iPhone"),
        DictionaryEntry(wrong: "cloud code", right: "Claude Code"),
        DictionaryEntry(wrong: "type script", right: "TypeScript"),
    ]

    private func fuzzy(_ text: String) -> String {
        DictionarySubstitutions(entries: entries, fuzzy: true).apply(text)
    }

    func testNearMissesSnapToThePreferredSpelling() {
        XCTAssertEqual(fuzzy("deploy it on versel"), "deploy it on Vercel")
        XCTAssertEqual(fuzzy("push it to git hub"), "push it to GitHub")
        XCTAssertEqual(fuzzy("we run kubernetis"), "we run Kubernetes")
        XCTAssertEqual(fuzzy("we run kubernetes"), "we run Kubernetes")
    }

    func testCommonWordsAndShortWordsAreNeverFuzzed() {
        XCTAssertEqual(fuzzy("versus the vessel"), "versus the vessel")
        // "cloud code" is close to "Claude Code" but both words are
        // everyday english: only an exact spelling snaps.
        XCTAssertEqual(fuzzy("cloud code"), "Claude Code") // exact row
        let noExactRow = DictionarySubstitutions(
            entries: [DictionaryEntry(wrong: "x", right: "Claude Code")],
            fuzzy: true
        )
        XCTAssertEqual(noExactRow.apply("the cloud code"), "the cloud code")
        XCTAssertEqual(noExactRow.apply("claude code"), "Claude Code")

        let short = DictionarySubstitutions(
            entries: [DictionaryEntry(wrong: "x", right: "Zod")],
            fuzzy: true
        )
        XCTAssertEqual(short.apply("zed and zud"), "zed and zud")
    }

    func testPunctuationAroundTheWordStays() {
        XCTAssertEqual(fuzzy("(versel), then"), "(Vercel), then")
        XCTAssertEqual(fuzzy("is it on git hub?"), "is it on GitHub?")
        // punctuation between words splits the phrase.
        XCTAssertEqual(fuzzy("git, hub"), "git, hub")
    }

    func testThePreferredCasingIsUsedAsWritten() {
        XCTAssertEqual(fuzzy("Iphone"), "iPhone")
        XCTAssertEqual(fuzzy("VERSEL"), "Vercel")
    }

    func testMultiWordRightValues() {
        XCTAssertEqual(fuzzy("type script rocks"), "TypeScript rocks")
        let cleaner = DeterministicCleaner(
            entries: [DictionaryEntry(wrong: "x", right: "Claude Code")]
        )
        XCTAssertEqual(cleaner.clean("open claud code"), "Open Claude Code.")
    }

    func testExactRowsWinBeforeFuzzy() {
        let substitutions = DictionarySubstitutions(
            entries: [
                DictionaryEntry(wrong: "versel", right: "Versailles"),
                DictionaryEntry(wrong: "x", right: "Vercel"),
            ],
            fuzzy: true
        )
        XCTAssertEqual(substitutions.apply("versel"), "Versailles")
        XCTAssertEqual(substitutions.apply("vercell"), "Vercel")
    }

    func testAddressesAndContractionsAreLeftAlone() {
        XCTAssertEqual(fuzzy("mail versel@x.io"), "mail versel@x.io")
    }

    func testOffMeansExactOnly() {
        let exactOnly = DictionarySubstitutions(entries: entries)
        XCTAssertEqual(exactOnly.apply("versel"), "versel")
        XCTAssertEqual(
            DeterministicCleaner(entries: entries, fuzzyMatching: false)
                .clean("deploy on versel"),
            "Deploy on versel."
        )
    }

    func testFuzzyRunsWithCleanupOff() {
        XCTAssertEqual(
            DeterministicCleaner(entries: entries, fullCleanup: false)
                .clean("deploy on versel um"),
            "deploy on Vercel um"
        )
    }
}
