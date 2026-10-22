import GhosttyKit
import XCTest

final class ConfigSettingTests: XCTestCase {
    private static let initialized = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)

    /// An option the file leaves out should show what Ghostty actually uses.
    func testDefaultsMatchGhostty() throws {
        XCTAssertEqual(Self.initialized, GHOSTTY_SUCCESS)
        let config = try GhosttyConfig(file: nil)
        func get<T>(_ key: String, _ value: T) -> T {
            var result = value
            XCTAssertTrue(key.withCString { ghostty_config_get(config.cValue, &result, $0, UInt(key.utf8.count)) }, key)
            return result
        }
        func string(_ key: String) -> String {
            String(cString: get(key, UnsafePointer<CChar>?.none)!)
        }
        XCTAssertEqual(Double(get(Option.fontSize.key, Float(0))), Option.fontSize.defaultValue)
        XCTAssertEqual(get(Option.fontThicken.key, true), Option.fontThicken.defaultValue)
        XCTAssertEqual(string(Option.cursorStyle.key), Option.cursorStyle.defaultValue)
        XCTAssertEqual(get(Option.backgroundOpacity.key, Double(0)), Option.backgroundOpacity.defaultValue)
        XCTAssertEqual(get(Option.unfocusedSplitOpacity.key, Double(0)), Option.unfocusedSplitOpacity.defaultValue)
        XCTAssertEqual(string(Option.scrollbar.key), Option.scrollbar.defaultValue)
        XCTAssertEqual(string(Option.confirmClose.key), Option.confirmClose.defaultValue)
        XCTAssertEqual(string(Option.copyOnSelect.key), Option.copyOnSelect.defaultValue)
        XCTAssertEqual(get(Option.mouseHideWhileTyping.key, true), Option.mouseHideWhileTyping.defaultValue)
        XCTAssertEqual(get(Option.autoSecureInput.key, false), Option.autoSecureInput.defaultValue)
        XCTAssertEqual(config.notifyOnCommandFinish, Option.notifyOnCommandFinish.defaultValue)
        XCTAssertEqual(config.notifyOnCommandFinishAction, Option.notifyOnCommandFinishAction.defaultValue)
        XCTAssertEqual(config.notifyOnCommandFinishAfter, Option.notifyOnCommandFinishAfter.defaultValue)
    }

    func testDurationsReadAndWriteLikeGhostty() {
        XCTAssertEqual(ConfigDuration.parse("5s"), .seconds(5))
        XCTAssertEqual(ConfigDuration.parse("1m 30s"), .seconds(90))
        XCTAssertEqual(ConfigDuration.parse("1h"), .seconds(3600))
        XCTAssertEqual(ConfigDuration.parse("500ms"), .milliseconds(500))
        XCTAssertNil(ConfigDuration.parse("soon"))
        XCTAssertEqual(ConfigDuration.format(.seconds(90)), "90s")
        XCTAssertEqual(ConfigDuration.format(.seconds(120)), "2m")
    }

    func testCommandFinishActionsStartFromTheBell() {
        XCTAssertEqual(CommandFinish.Actions(config: "notify"), [.bell, .notify])
        XCTAssertEqual(CommandFinish.Actions(config: "no-bell,notify"), [.notify])
        XCTAssertEqual(CommandFinish.Actions(config: "false"), [])
        XCTAssertNil(CommandFinish.Actions(config: "shout"))
        XCTAssertEqual(CommandFinish.Actions([.notify]).config, "no-bell,notify")
    }

    func testThemeIsOneThemeOrALightAndDarkPair() {
        XCTAssertEqual(ThemeChoice("Nord"), ThemeChoice(light: "Nord", dark: "Nord"))
        XCTAssertEqual(ThemeChoice("light:Builtin Light, dark:Nord"), ThemeChoice(light: "Builtin Light", dark: "Nord"))
        XCTAssertEqual(ThemeChoice(nil), ThemeChoice(light: nil, dark: nil))
        XCTAssertEqual(ThemeChoice(light: "A", dark: "B").value, "light:A,dark:B")
        XCTAssertEqual(ThemeChoice(light: "A", dark: "A").value, "A")
        XCTAssertNil(ThemeChoice(light: nil, dark: nil).value)
    }
}
