import XCTest

final class DropTextTests: XCTestCase {
    func testEscapesShellCharacters() {
        XCTAssertEqual(DropText.escape("/tmp/My Files/a (1).txt"), #"/tmp/My\ Files/a\ \(1\).txt"#)
        XCTAssertEqual(DropText.escape("it's $HOME & more"), #"it\'s\ \$HOME\ \&\ more"#)
        XCTAssertEqual(DropText.escape(#"back\slash"#), #"back\\slash"#)
        XCTAssertEqual(DropText.escape("/plain/path.txt"), "/plain/path.txt")
    }

    func testFilesAreEscapedAndJoined() {
        let files = [URL(fileURLWithPath: "/tmp/a b.txt"), URL(fileURLWithPath: "/tmp/c.txt")]
        XCTAssertEqual(DropText.text(url: nil, fileURLs: files, string: nil), #"/tmp/a\ b.txt /tmp/c.txt"#)
    }

    func testURLWinsAndIsEscaped() {
        let text = DropText.text(url: "https://example.com/?q=a&b", fileURLs: [URL(fileURLWithPath: "/x")], string: "ignored")
        XCTAssertEqual(text, #"https://example.com/\?q=a\&b"#)
    }

    func testPlainTextIsLeftAlone() {
        XCTAssertEqual(DropText.text(url: nil, fileURLs: [], string: "ls -la && echo hi"), "ls -la && echo hi")
        XCTAssertNil(DropText.text(url: nil, fileURLs: [], string: nil))
    }
}
