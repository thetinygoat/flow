import XCTest

final class PathTests: XCTestCase {
    let home = NSHomeDirectory()

    func testAbbreviatingHome() {
        XCTAssertEqual(home.abbreviatingHome, "~")
        XCTAssertEqual((home + "/Code").abbreviatingHome, "~/Code")
        XCTAssertEqual("/usr/local".abbreviatingHome, "/usr/local")
    }

    func testSiblingOfHomeIsNotAbbreviated() {
        XCTAssertEqual((home + "-work").abbreviatingHome, home + "-work")
        XCTAssertEqual((home + "-work/Code").abbreviatingHome, home + "-work/Code")
    }

    func testFolderName() {
        XCTAssertEqual(home.folderName, "~")
        XCTAssertEqual((home + "/Code/flow").folderName, "flow")
        XCTAssertEqual((home + "/.config").folderName, ".config")
        XCTAssertEqual("/usr/local/bin".folderName, "bin")
        XCTAssertEqual("/".folderName, "/")
    }
}
