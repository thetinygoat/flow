import XCTest

final class ConfigFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testSkipsCommentOnlyTemplate() throws {
        let template = try file("appsupport", "# This is the configuration file for Ghostty.\n#\n# font-size = 13\n\n")
        let real = try file("xdg", "theme = Catppuccin Mocha\n")
        XCTAssertEqual(ConfigFile.firstWithSettings(among: [template, real]), real)
    }

    func testPrefersEarlierFileWithSettings() throws {
        let first = try file("first", "font-size = 14\n")
        let second = try file("second", "theme = dark\n")
        XCTAssertEqual(ConfigFile.firstWithSettings(among: [first, second]), first)
    }

    func testSkipsMissingFiles() throws {
        let missing = directory.appendingPathComponent("missing")
        let real = try file("real", "  font-family = Iosevka\n")
        XCTAssertEqual(ConfigFile.firstWithSettings(among: [missing, real]), real)
    }

    func testNilWhenNothingHasSettings() throws {
        let empty = try file("empty", "")
        let comments = try file("comments", "# only comments\n")
        XCTAssertNil(ConfigFile.firstWithSettings(among: [empty, comments]))
    }
}
