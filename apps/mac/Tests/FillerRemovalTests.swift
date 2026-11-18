import XCTest

@MainActor
final class FillerRemovalTests: XCTestCase {
    private let cleaner = DeterministicCleaner()

    func testFillersAndTheirCommasGo() {
        let cases = [
            ("So, um, I think", "So, I think."),
            ("Um I think", "I think."),
            ("um, so we ship", "So we ship."),
            ("we should uh ship it", "We should ship it."),
            ("um, I uh think erm, this uhm works", "I think this works."),
            ("we ship, um.", "We ship."),
            ("hello. Umm, then hmm we go", "Hello. Then we go."),
            ("mm ok ah fine er done", "Ok fine done."),
            ("so um comma I think", "So I think."),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(cleaner.clean(input), expected, "input: \(input)")
        }
    }

    func testWordsThatCarryMeaningStay() {
        XCTAssertEqual(
            cleaner.clean("like, you know, so well this works"),
            "Like, you know, so well this works."
        )
        XCTAssertEqual(cleaner.clean("umbrella uh-huh summer"), "Umbrella uh-huh summer.")
        XCTAssertEqual(cleaner.clean("take her to the ER"), "Take her to the ER.")
        XCTAssertEqual(cleaner.clean("cut it to 5 mm"), "Cut it to 5 mm.")
        XCTAssertEqual(cleaner.clean("mail um@ah.io"), "Mail um@ah.io")
    }

    func testCleanupOffKeepsFillers() {
        XCTAssertEqual(
            DeterministicCleaner(fullCleanup: false).clean("um, I think"),
            "um, I think"
        )
    }

    func testTheSettingOffKeepsFillers() {
        XCTAssertEqual(
            DeterministicCleaner(removeFillers: false).clean("um, I think"),
            "Um, I think."
        )
    }

    func testThePreviewFollowsTheSettings() {
        var selection = PipelineSelection()
        XCTAssertEqual(
            PipelineRun.throughCleaner("um hi", selection: selection, entries: [])[1].output,
            "Hi."
        )
        selection.removeFillers = false
        XCTAssertEqual(
            PipelineRun.throughCleaner("um hi", selection: selection, entries: [])[1].output,
            "Um hi."
        )
    }

    func testSettingsDefaultOnAndPersist() {
        let suiteName = "FillerRemovalTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: userDefaults)
        XCTAssertTrue(settings.removeFillersEnabled)
        XCTAssertTrue(settings.fuzzyDictionaryEnabled)

        settings.removeFillersEnabled = false
        settings.fuzzyDictionaryEnabled = false
        let reloaded = AppSettings(userDefaults: userDefaults)
        XCTAssertFalse(reloaded.removeFillersEnabled)
        XCTAssertFalse(reloaded.fuzzyDictionaryEnabled)
    }
}
