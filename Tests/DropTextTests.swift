import XCTest

final class DropTextTests: XCTestCase {
    func testEscapesShellCharacters() {
        XCTAssertEqual(DropText.escape("/tmp/My Files/a (1).txt"), #"/tmp/My\ Files/a\ \(1\).txt"#)
        XCTAssertEqual(DropText.escape("it's $HOME & more"), #"it\'s\ \$HOME\ \&\ more"#)
        XCTAssertEqual(DropText.escape(#"back\slash"#), #"back\\slash"#)
        XCTAssertEqual(DropText.escape("/plain/path.txt"), "/plain/path.txt")
    }

    func testControlCharactersAreQuoted() {
        XCTAssertEqual(DropText.escape("/tmp/a\nb"), "/tmp/a'\n'b")
        XCTAssertEqual(DropText.escape("x\r\ny"), "x'\r\n'y")
    }

    /// The escaped text, run through each shell, must name the same file.
    func testRoundTripsThroughShells() throws {
        let names = ["/tmp/a b/c (1).txt", "/tmp/line\nbreak.txt", "/tmp/back\\slash\nand 'quote'", "/tmp/tab\there", "/tmp/$HOME & `x`!"]
        let shells = ["/bin/bash", "/bin/zsh", "/opt/homebrew/bin/fish"].filter(FileManager.default.isExecutableFile(atPath:))
        for shell in shells {
            for name in names {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-c", "printf %s " + DropText.escape(name)]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                XCTAssertEqual(String(decoding: data, as: UTF8.self), name, "\(shell): \(DropText.escape(name))")
            }
        }
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
