import XCTest

final class UntrustedLinkTests: XCTestCase {
    func testWebAndMailLinksOpen() {
        for value in ["http://example.com", "https://example.com/path", "mailto:user@example.com"] {
            XCTAssertEqual(UntrustedLink(value).decision, .open(URL(string: value)!), value)
        }
    }

    func testWebLinksNeedAHost() {
        for value in ["https:relative", "http:///missing-host"] {
            XCTAssertEqual(UntrustedLink(value).decision, .block(.invalidWebURL), value)
        }
    }

    func testOSC8TargetsNeedAScheme() {
        for value in ["/tmp/file.txt", "../file.txt", "payload.command", ""] {
            XCTAssertEqual(UntrustedLink(value).decision, .block(.malformedURL), value)
        }
    }

    func testCustomSchemesAsk() {
        for value in ["vscode://file/tmp/example.swift", "ssh://example.com"] {
            XCTAssertEqual(UntrustedLink(value).decision, .confirm(URL(string: value)!), value)
        }
    }

    func testInvisibleAndLineBreakingCharactersAreBlocked() {
        for scalar in ["\u{0085}", "\u{2028}", "\u{2029}", "\u{202E}", "\u{2066}"] {
            XCTAssertEqual(UntrustedLink("https://example.com/a\(scalar)b").decision, .block(.unsafeCharacters))
        }
    }

    func testPlainFilesAndFoldersOpen() throws {
        let directory = try makeDirectory()
        let file = directory.appending(path: "document.txt")
        try "safe".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(UntrustedLink(file.absoluteString).decision, .open(file.resolvingSymlinksInPath()))
        XCTAssertEqual(UntrustedLink(directory.absoluteString).decision, .open(directory.resolvingSymlinksInPath()))
    }

    func testFilesThatCouldRunCodeAreBlocked() throws {
        let directory = try makeDirectory()
        for name in ["payload.command", "payload.tool", "payload.app", "payload.workflow", "payload.sh"] {
            let file = directory.appending(path: name)
            try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)
            XCTAssertEqual(UntrustedLink(file.absoluteString).decision, .block(.unsafeFile), name)
        }

        let executable = directory.appending(path: "payload.txt")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertEqual(UntrustedLink(executable.absoluteString).decision, .block(.unsafeFile))

        XCTAssertEqual(UntrustedLink("file:///System/Applications/Calculator.app").decision, .block(.unsafeFile))
    }

    func testSymlinksAreJudgedByWhatTheyPointAt() throws {
        let directory = try makeDirectory()
        let payload = directory.appending(path: "payload.command")
        let link = directory.appending(path: "document.txt")
        try "#!/bin/sh\n".write(to: payload, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: payload)

        XCTAssertEqual(UntrustedLink(link.absoluteString).decision, .block(.unsafeFile))
    }

    func testMissingFilesAndOtherHostsAreBlocked() {
        XCTAssertEqual(UntrustedLink("file:///no/such/file.txt").decision, .block(.inaccessibleFile))
        XCTAssertEqual(UntrustedLink("file://example.com/etc/hosts").decision, .block(.malformedURL))
    }

    func testMatchedPathsResolveAgainstTheTerminalDirectory() throws {
        let directory = try makeDirectory()
        try "safe".write(to: directory.appending(path: "notes.md"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: directory.appending(path: "run.command"), atomically: true, encoding: .utf8)

        XCTAssertEqual(UntrustedLink.matched("notes.md", relativeTo: directory.path).decision,
                       .open(directory.appending(path: "notes.md").resolvingSymlinksInPath()))
        XCTAssertEqual(UntrustedLink.matched("run.command", relativeTo: directory.path).decision, .block(.unsafeFile))
        XCTAssertEqual(UntrustedLink.matched("https://example.com", relativeTo: directory.path).decision,
                       .open(URL(string: "https://example.com")!))
        XCTAssertEqual(UntrustedLink.matched("notes\u{202E}.md", relativeTo: directory.path).decision, .block(.unsafeCharacters))
    }

    func testDisplayShowsTheRealTarget() {
        XCTAssertEqual(UntrustedLink("/tmp/preview\u{2028}////../payload.command////").displayString, "/tmp/payload.command")
        XCTAssertEqual(UntrustedLink("https://example.com/a\u{202E}b").displayString, "https://example.com/a\\u{202E}b")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
