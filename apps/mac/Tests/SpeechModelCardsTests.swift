import XCTest

/// every model can do either job, so each job's cards show all of them,
/// each with what it costs in that job.
final class SpeechModelCardsTests: XCTestCase {
    func testEveryModelIsOnBothJobsCards() {
        XCTAssertEqual(Set(SpeechModel.cards(for: .dictation)), Set(SpeechModel.allCases))
        XCTAssertEqual(Set(SpeechModel.cards(for: .meetings)), Set(SpeechModel.allCases))
    }

    /// the job's own default leads its cards.
    func testEachJobLeadsWithItsDefault() {
        XCTAssertEqual(SpeechModel.cards(for: .dictation).first, SpeechModel.dictationDefault)
        XCTAssertEqual(SpeechModel.cards(for: .meetings).first, SpeechModel.meetingDefault)
    }

    func testOnlyWhistleSaysItIsExperimental() {
        XCTAssertEqual(SpeechModel.whistle.badge, "experimental")
        XCTAssertEqual(SpeechModel.allCases.filter { $0.badge != nil }, [.whistle])
    }

    /// a card states the consequence for its own job: whisper is slow for
    /// dictation, parakeet garbles a language it doesn't know in a meeting.
    func testATraitIsWrittenForTheJobItIsShownIn() {
        for model in SpeechModel.allCases {
            XCTAssertFalse(model.trait(for: .dictation).isEmpty, "\(model)")
            XCTAssertFalse(model.trait(for: .meetings).isEmpty, "\(model)")
        }
        XCTAssertTrue(SpeechModel.whisperLargeV3.trait(for: .dictation).contains("slow"))
        XCTAssertTrue(SpeechModel.parakeetV2.trait(for: .meetings).contains("english only"))
    }

    /// a meeting recorded with whistle names it in its manifest, and a
    /// build reading that manifest gets whistle back.
    func testWhistleIsStoredByItsName() throws {
        let stored = try JSONEncoder().encode(SpeechModel.whistle)
        XCTAssertEqual(String(decoding: stored, as: UTF8.self), #""whistle""#)
        XCTAssertEqual(SpeechModel(storedDictationValue: "whistle"), .whistle)
    }

    func testRecordWithListsWhistleWhenItIsOnThisMac() {
        let choices = RecordWith.choices(
            installed: [.whisperLargeV3, .whistle],
            default: .whisperLargeV3,
            isRecording: false)

        XCTAssertEqual(choices, [RecordWith.Choice(model: .whistle, title: "whistle")])
    }
}

/// parakeet ultra: a third parakeet, run by FluidAudio like the other two,
/// stored by its own name and offered on both jobs' cards.
@MainActor
final class ParakeetUltraTests: XCTestCase {
    func testItIsAParakeetWithItsOwnStoredName() throws {
        XCTAssertEqual(SpeechModel.parakeetUltra.family, .parakeet)
        XCTAssertNil(SpeechModel.parakeetUltra.whisperVariant)
        XCTAssertFalse(SpeechModel.parakeetUltra.translatesToEnglish)
        let stored = try JSONEncoder().encode(SpeechModel.parakeetUltra)
        XCTAssertEqual(String(decoding: stored, as: UTF8.self), #""parakeetUltra""#)
        XCTAssertEqual(try JSONDecoder().decode(SpeechModel.self, from: stored), .parakeetUltra)
        XCTAssertEqual(SpeechModel(storedDictationValue: "parakeetUltra"), .parakeetUltra)
    }

    /// dictation lists it after the english default and before v3, which
    /// it beats at the same speed.
    func testDictationOffersItBeforeV3() throws {
        let cards = SpeechModel.cards(for: .dictation)
        let ultra = try XCTUnwrap(cards.firstIndex(of: .parakeetUltra))
        XCTAssertEqual(ultra, 1)
        XCTAssertLessThan(ultra, try XCTUnwrap(cards.firstIndex(of: .parakeetV3)))
    }

    func testItsCardSaysWhatItCosts() {
        let model = SpeechModel.parakeetUltra
        XCTAssertEqual(model.shortName, "parakeet ultra")
        XCTAssertEqual(model.approximateSize, "~630 mb")
        XCTAssertNil(model.badge)
        XCTAssertTrue(model.trait(for: .dictation).contains("25 languages"))
        XCTAssertTrue(model.trait(for: .meetings).contains("european languages only"))
        XCTAssertEqual(model.dictationPace, SpeechModel.parakeetV3.dictationPace)
    }

    /// a dictation choice of ultra survives a relaunch.
    func testDictationKeepsTheChoice() {
        let defaults = UserDefaults(suiteName: "ParakeetUltraTests.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.dictationModel = .parakeetUltra
        XCTAssertEqual(AppSettings(userDefaults: defaults).dictationModel, .parakeetUltra)
        settings.meetingModel = .parakeetUltra
        XCTAssertEqual(AppSettings(userDefaults: defaults).meetingModel, .parakeetUltra)
    }
}
