import XCTest

final class LinkTargetTests: XCTestCase {
    func testWebURLsStayURLs() {
        XCTAssertEqual(LinkTarget.url(for: "https://example.com/a?b=1", relativeTo: "/tmp")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertEqual(LinkTarget.url(for: "mailto:hi@example.com", relativeTo: nil)?.scheme, "mailto")
    }

    func testAbsolutePathsBecomeFileURLs() {
        let url = LinkTarget.url(for: "/usr/bin/git", relativeTo: "/tmp")
        XCTAssertTrue(url?.isFileURL == true)
        XCTAssertEqual(url?.path, "/usr/bin/git")
    }

    func testTildeExpands() {
        XCTAssertEqual(LinkTarget.url(for: "~/notes.md", relativeTo: "/tmp")?.path, NSHomeDirectory() + "/notes.md")
    }

    func testRelativePathsResolveAgainstTheTerminalDirectory() {
        XCTAssertEqual(LinkTarget.url(for: "src/main.swift", relativeTo: "/Users/me/project")?.path, "/Users/me/project/src/main.swift")
        XCTAssertEqual(LinkTarget.url(for: "../other/x.txt", relativeTo: "/Users/me/project")?.path, "/Users/me/other/x.txt")
    }

    func testExistingFileBeatsSchemeLookalike() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: directory.appendingPathComponent("notes.txt:12").path, contents: nil)

        let url = LinkTarget.url(for: "notes.txt:12", relativeTo: directory.path)
        XCTAssertTrue(url?.isFileURL == true)
    }

    func testEmptyTextOpensNothing() {
        XCTAssertNil(LinkTarget.url(for: "", relativeTo: nil))
    }
}
