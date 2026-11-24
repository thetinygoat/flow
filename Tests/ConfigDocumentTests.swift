import XCTest

final class ConfigDocumentTests: XCTestCase {
    func testReadsValuesTheWayGhosttyDoes() {
        let document = ConfigDocument("# font-size = 9\n  font-size = 12\nfont-family = \"Iosevka Term\"\nfont-size=14\n")
        XCTAssertEqual(document["font-size"], "14")
        XCTAssertEqual(document["font-family"], "Iosevka Term")
        XCTAssertNil(document["theme"])
    }

    func testChangesAValueInPlace() {
        var document = ConfigDocument("# comment\nfont-size = 12\ntheme = Nord\n")
        document["font-size"] = "15"
        XCTAssertEqual(document.text, "# comment\nfont-size = 15\ntheme = Nord\n")
    }

    func testRepeatedKeyBecomesOneLineWhereTheFirstWas() {
        var document = ConfigDocument("font-size = 12\ntheme = Nord\nfont-size = 13\n")
        document["font-size"] = "15"
        XCTAssertEqual(document.text, "font-size = 15\ntheme = Nord\n")
    }

    func testAppendsANewKey() {
        var document = ConfigDocument("theme = Nord")
        document["font-size"] = "15"
        XCTAssertEqual(document.text, "theme = Nord\nfont-size = 15\n")
    }

    func testRemovingAKeyKeepsEverythingElse() {
        var document = ConfigDocument("# keep\nfont-size = 12\n\ntheme = Nord\n")
        document["font-size"] = nil
        XCTAssertEqual(document.text, "# keep\n\ntheme = Nord\n")
    }

    func testListKeysKeepEveryValue() {
        var document = ConfigDocument("font-family = Iosevka\nfont-family = Symbols Nerd Font\n")
        var families = document.values(for: "font-family")
        families[0] = "Berkeley Mono"
        document.setValues(families, for: "font-family")
        XCTAssertEqual(document.text, "font-family = Berkeley Mono\nfont-family = Symbols Nerd Font\n")
    }

    func testQuotesValuesGhosttyWouldOtherwiseTrim() {
        var document = ConfigDocument("")
        document["command"] = ""
        XCTAssertEqual(document.text, "command = \"\"\n")
        XCTAssertEqual(document["command"], "")
    }

    func testAnchoringKeepsEachPathOnItsOwnLine() {
        var document = ConfigDocument("config-file = a\r\ntheme = Nord\r\nconfig-file = ?/b\r\ncustom-shader = \"my shader.glsl\"\r\n")
        document.anchorPaths(at: URL(fileURLWithPath: "/etc/flow"))
        XCTAssertEqual(document.text, "config-file = /etc/flow/a\r\ntheme = Nord\r\nconfig-file = ?/b\r\ncustom-shader = /etc/flow/my shader.glsl\r\n")
    }

    func testBlanksMatchingSettingsAndKeepsTheirLines() {
        var document = ConfigDocument("# agent-sound = Ping\nagent-sound = Ping\ntheme = Nord\n")
        XCTAssertFalse(document.blankEntries { key, _ in key == "font-size" })
        XCTAssertTrue(document.blankEntries { key, _ in key == "agent-sound" })
        XCTAssertEqual(document.text, "# agent-sound = Ping\n\ntheme = Nord\n")
    }

    func testReadsWindowsLineEndingsAndKeepsThem() {
        var document = ConfigDocument("font-size = 12\r\ntheme = Nord\r\n")
        XCTAssertEqual(document["font-size"], "12")
        XCTAssertEqual(document["theme"], "Nord")
        document["font-size"] = "15"
        XCTAssertEqual(document.text, "font-size = 15\r\ntheme = Nord\r\n")
    }

    func testAKeyOnItsOwnTurnsItOn() {
        let document = ConfigDocument("font-thicken\n")
        XCTAssertEqual(document["font-thicken"], "true")
        XCTAssertFalse(document.isEmpty)
    }

    func testEmptyWhenOnlyComments() {
        XCTAssertTrue(ConfigDocument("# a\n\n   # b\n").isEmpty)
        XCTAssertFalse(ConfigDocument("# a\ntheme = Nord\n").isEmpty)
    }
}
