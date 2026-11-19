import XCTest

/// the developer style end to end; the everyday style must leave the same
/// words alone.
final class CodeWordsTests: XCTestCase {
    private func dev(_ input: String) -> String {
        DeterministicCleaner(entries: [], style: .developer).clean(input)
    }

    private func everyday(_ input: String) -> String {
        DeterministicCleaner(entries: []).clean(input)
    }

    func testDotJoinsAFileName() {
        XCTAssertEqual(dev("open main dot swift"), "Open main.swift.")
        XCTAssertEqual(dev("edit src slash app slash main dot swift"), "Edit src/app/main.swift.")
        XCTAssertEqual(dev("read package dot json"), "Read package.json.")
    }

    func testDashJoinsAndDoubleDashIsAFlag() {
        XCTAssertEqual(dev("make my dash component"), "Make my-component.")
        XCTAssertEqual(dev("run git push dash dash force"), "Run git push --force.")
        XCTAssertEqual(dev("a well hyphen known name"), "A well-known name.")
    }

    func testUnderscore() {
        XCTAssertEqual(dev("rename it to user underscore id"), "Rename it to user_id.")
        XCTAssertEqual(dev("underscore private"), "_private.")
    }

    func testTildeAndSlash() {
        XCTAssertEqual(dev("cd tilde slash projects"), "Cd ~/projects.")
    }

    func testBackticks() {
        XCTAssertEqual(dev("run backtick npm install backtick first"), "Run `npm install` first.")
    }

    /// in everyday writing these are words.
    func testEverydayLeavesTheWordsAlone() {
        XCTAssertEqual(everyday("make a quick dash to the shop"), "Make a quick dash to the shop.")
        XCTAssertEqual(everyday("connect each dot to the next"), "Connect each dot to the next.")
        XCTAssertEqual(everyday("open main dot swift"), "Open main dot swift.")
    }

    func testTheStyleTravelsInTheOptions() {
        var options = CleanupOptions()
        options.style = .developer
        XCTAssertEqual(DeterministicCleaner(entries: [], options: options).options.style, .developer)
        XCTAssertEqual(options.raw.style, .developer)
    }
}

extension CodeWordsTests {
    func testCodeAtTheStartKeepsItsCase() {
        XCTAssertEqual(dev("backtick npm install backtick works"), "`npm install` works.")
    }
}
