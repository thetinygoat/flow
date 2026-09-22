import XCTest

final class PathTests: XCTestCase {
    let home = NSHomeDirectory()

    func testAbbreviatingHome() {
        XCTAssertEqual(home.abbreviatingHome, "~")
        XCTAssertEqual((home + "/Code").abbreviatingHome, "~/Code")
        XCTAssertEqual("/usr/local".abbreviatingHome, "/usr/local")
    }

    func testFishStylePath() {
        XCTAssertEqual(home.fishStylePath, "~")
        XCTAssertEqual((home + "/Code").fishStylePath, "~/Code")
        XCTAssertEqual((home + "/Downloads/actual-budget").fishStylePath, "~/D/actual-budget")
        XCTAssertEqual((home + "/.config/ghostty").fishStylePath, "~/.c/ghostty")
        XCTAssertEqual("/usr/local/bin".fishStylePath, "/u/l/bin")
        XCTAssertEqual("/".fishStylePath, "/")
    }
}
