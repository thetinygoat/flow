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
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testImportsEveryFileWithSettingsInOrder() throws {
        let xdg = try file("xdg/config", "font-size = 14\n")
        let appSupport = try file("appsupport/config", "theme = Catppuccin Mocha\n")
        let imported = ConfigFile.imported(from: [xdg, appSupport])
        XCTAssertEqual(ConfigDocument(imported).values(for: "font-size"), ["14"])
        XCTAssertLessThan(try XCTUnwrap(imported.range(of: "font-size")).lowerBound, try XCTUnwrap(imported.range(of: "theme")).lowerBound)
    }

    func testSkipsCommentOnlyTemplateAndMissingFiles() throws {
        let template = try file("template", "# This is the configuration file for Ghostty.\n#\n# font-size = 13\n\n")
        let missing = directory.appendingPathComponent("missing")
        XCTAssertEqual(ConfigFile.imported(from: [template, missing]), "")
    }

    func testMakesRelativeIncludesAbsolute() throws {
        let ghostty = try file("ghostty/config", "config-file = ?keys\nconfig-file = /etc/theme\nconfig-file = ~/colors\nconfig-file = ?\"more\"\n")
        let includes = ConfigDocument(ConfigFile.imported(from: [ghostty])).values(for: "config-file")
        XCTAssertEqual(includes, [
            "?" + directory.appendingPathComponent("ghostty/keys").path, "/etc/theme", "~/colors",
            "?" + directory.appendingPathComponent("ghostty/more").path,
        ])
    }

    func testMakesOtherRelativePathsAbsolute() throws {
        let ghostty = try file("ghostty/config", "custom-shader = shaders/crt.glsl\nbackground-image = /pictures/sky.png\nbell-audio-path = ?ding.wav\n")
        let document = ConfigDocument(ConfigFile.imported(from: [ghostty]))
        XCTAssertEqual(document["custom-shader"], directory.appendingPathComponent("ghostty/shaders/crt.glsl").path)
        XCTAssertEqual(document["background-image"], "/pictures/sky.png")
        XCTAssertEqual(document["bell-audio-path"], "?" + directory.appendingPathComponent("ghostty/ding.wav").path)
    }

    func testImportsAFileThatIsNotUTF8() throws {
        let ghostty = directory.appendingPathComponent("latin1")
        try Data("# caf\u{E9}\nfont-size = 14\n".data(using: .isoLatin1)!).write(to: ghostty)
        XCTAssertEqual(ConfigDocument(ConfigFile.imported(from: [ghostty]))["font-size"], "14")
    }

    func testRefusesToReplaceALinkLoop() throws {
        let a = directory.appendingPathComponent("a"), b = directory.appendingPathComponent("b")
        try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: "b")
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: "a")
        XCTAssertThrowsError(try ConfigFile.write("x", to: a))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: a.path), "b")
    }

    func testCreatesConfigOnceFromGhosttySettings() throws {
        let ghostty = try file("ghostty/config", "font-size = 14\n")
        let flow = directory.appendingPathComponent("flow/config")
        try ConfigFile.create(at: flow, importing: [ghostty])
        XCTAssertEqual(ConfigDocument(try String(contentsOf: flow, encoding: .utf8))["font-size"], "14")

        try "font-size = 20\n".write(to: ghostty, atomically: true, encoding: .utf8)
        try ConfigFile.create(at: flow, importing: [ghostty])
        XCTAssertEqual(ConfigDocument(try String(contentsOf: flow, encoding: .utf8))["font-size"], "14")
    }

    func testCreatesConfigThroughALinkWhoseTargetIsMissing() throws {
        let target = directory.appendingPathComponent("dotfiles/flow/config")
        let link = directory.appendingPathComponent("flow/config")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../dotfiles/flow/config")
        try ConfigFile.create(at: link, importing: [])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "../dotfiles/flow/config")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), ConfigFile.header)
    }

    func testCreatesConfigWithOnlyTheHeaderWithoutGhosttySettings() throws {
        let flow = directory.appendingPathComponent("flow/config")
        try ConfigFile.create(at: flow, importing: [directory.appendingPathComponent("missing")])
        XCTAssertEqual(try String(contentsOf: flow, encoding: .utf8), ConfigFile.header)
    }
}
