import XCTest

/// the whole cleaner, so capitalisation and the full stop are in the answer.
final class SpokenSlashTests: XCTestCase {
    private func cleaned(_ input: String) -> String {
        DeterministicCleaner(entries: []).clean(input)
    }

    func testASpokenSlashJoinsTheWordsAroundIt() {
        XCTAssertEqual(cleaned("delete apps slash site"), "Delete apps/site.")
        XCTAssertEqual(cleaned("open src slash app slash main"), "Open src/app/main.")
        XCTAssertEqual(cleaned("and slash or"), "And/or.")
    }

    /// the engine hears "apps slash" as "app's slash"; paths have no apostrophe.
    func testAPossessiveBeforeTheSlashIsAPlural() {
        XCTAssertEqual(cleaned("Yes, delete the app's slash site."), "Yes, delete the apps/site.")
    }

    func testNumbersAroundASlash() {
        XCTAssertEqual(cleaned("two slash three"), "Two/three.")
        XCTAssertEqual(cleaned("page 24 slash 7"), "Page 24/7.")
    }

    /// after an article the slash is the thing itself, not the symbol.
    func testSlashAsAWordStays() {
        XCTAssertEqual(cleaned("type a slash here"), "Type a slash here.")
        XCTAssertEqual(cleaned("use the forward slash key"), "Use the forward slash key.")
        XCTAssertEqual(cleaned("ends with slash"), "Ends with slash.")
    }

    func testAWebAddressIsStillTheURLParsers() {
        XCTAssertEqual(cleaned("github dot com slash husky"), "github.com/husky")
    }
}
