import AppKit
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
        XCTAssertEqual(get(Option.shellIntegrationFeatures.key, CUnsignedInt(0)), 0b100101, "cursor, title and path")
        XCTAssertEqual(get(Option.autoSecureInput.key, false), Option.autoSecureInput.defaultValue)
        XCTAssertEqual(config.notifyOnCommandFinish, Option.notifyOnCommandFinish.defaultValue)
        XCTAssertEqual(config.notifyOnCommandFinishAction, Option.notifyOnCommandFinishAction.defaultValue)
        XCTAssertEqual(config.notifyOnCommandFinishAfter, Option.notifyOnCommandFinishAfter.defaultValue)
    }

    func testNumbersUseADecimalPointInEveryLocale() {
        XCTAssertEqual(Option.backgroundOpacity.format(0.85), "0.85")
        XCTAssertEqual(Option.fontSize.format(13.5), "13.5")
        XCTAssertEqual(Option.fontSize.format(14), "14")
    }

    func testDurationsReadAndWriteLikeGhostty() {
        XCTAssertEqual(ConfigDuration.parse("5s"), .seconds(5))
        XCTAssertEqual(ConfigDuration.parse("1m 30s"), .seconds(90))
        XCTAssertEqual(ConfigDuration.parse("1h"), .seconds(3600))
        XCTAssertEqual(ConfigDuration.parse("500ms"), .milliseconds(500))
        XCTAssertEqual(ConfigDuration.parse("1d 2h"), .seconds(93600))
        XCTAssertEqual(ConfigDuration.parse("250us"), .microseconds(250))
        XCTAssertNil(ConfigDuration.parse("soon"))
        XCTAssertEqual(ConfigDuration.parse("0"), .zero)
        XCTAssertEqual(ConfigDuration.format(.seconds(90)), "90s")
        XCTAssertEqual(ConfigDuration.format(.seconds(120)), "2m")
        XCTAssertEqual(ConfigDuration.format(.milliseconds(500)), "500ms")
        XCTAssertEqual(ConfigDuration.format(.milliseconds(1500)), "1500ms")
    }

    func testBlurIsOnForAnyRadius() {
        XCTAssertEqual(Option.backgroundBlur.parse("true"), true)
        XCTAssertEqual(Option.backgroundBlur.parse("f"), false)
        XCTAssertEqual(Option.backgroundBlur.parse("30"), true)
        XCTAssertEqual(Option.backgroundBlur.parse("0"), false)
        XCTAssertNil(Option.backgroundBlur.parse("macos-glass-regular"))
        XCTAssertEqual(Option.backgroundBlur.format(true), "true")
    }

    /// The theme standing in for Ghostty's own colors in a light and dark
    /// pair has to keep matching them.
    func testGhosttysDefaultColorsHaveANamedTheme() throws {
        XCTAssertEqual(Self.initialized, GHOSTTY_SUCCESS)
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/GhosttyResources/ghostty/themes/\(Themes.ghosttyDefault)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path)
        let theme = try GhosttyConfig(file: file)
        let defaults = try GhosttyConfig(file: nil)
        XCTAssertEqual(theme.backgroundColor, defaults.backgroundColor)
        XCTAssertEqual(theme.foregroundColor, defaults.foregroundColor)
        // The theme rounds a few palette channels differently, by one step.
        XCTAssertEqual(theme.palette.count, defaults.palette.count)
        for (themed, original) in zip(theme.palette, defaults.palette) {
            for channel in [\NSColor.redComponent, \.greenComponent, \.blueComponent] {
                XCTAssertEqual(themed[keyPath: channel], original[keyPath: channel], accuracy: 1.5 / 255)
            }
        }
    }

    func testChoicesReadGhosttysOtherSpellings() {
        XCTAssertEqual(Option.confirmClose.parse("1"), "true")
        XCTAssertEqual(Option.confirmClose.parse("F"), "false")
        XCTAssertEqual(Option.confirmClose.parse("always"), "always")
        XCTAssertEqual(Option.copyOnSelect.parse("clipboard"), "clipboard")
        XCTAssertNil(Option.cursorStyle.parse("beam"))
    }

    func testPathsReadLikeGhostty() {
        XCTAssertEqual(ConfigPath("?\"x y\"").map { [$0.path, String($0.optional)] }, ["x y", "true"])
        XCTAssertEqual(ConfigPath("?x").map { [$0.path, String($0.optional)] }, ["x", "true"])
        XCTAssertNil(ConfigPath("?"))
        XCTAssertNil(ConfigPath(""))
        XCTAssertEqual(ConfigPath("~/a")?.resolved(from: URL(fileURLWithPath: "/tmp")).path, NSHomeDirectory() + "/a")
        XCTAssertEqual(ConfigPath("a")?.resolved(from: URL(fileURLWithPath: "/tmp")).path, "/tmp/a")
    }

    func testBooleansTakeGhosttysSpellings() {
        XCTAssertEqual(Option.fontThicken.parse("t"), true)
        XCTAssertEqual(Option.fontThicken.parse("1"), true)
        XCTAssertEqual(Option.fontThicken.parse("F"), false)
        XCTAssertNil(Option.fontThicken.parse("yes"))
    }

    func testCommandFinishActionsStartFromTheBell() {
        XCTAssertEqual(CommandFinish.Actions(config: "notify"), [.bell, .notify])
        XCTAssertEqual(CommandFinish.Actions(config: "no-bell,notify"), [.notify])
        XCTAssertEqual(CommandFinish.Actions(config: "false"), [])
        XCTAssertNil(CommandFinish.Actions(config: "shout"))
        XCTAssertEqual(CommandFinish.Actions([.notify]).config, "no-bell,notify")
    }

    func testShellIntegrationFeaturesKeepOtherSwitches() {
        let setting = Option.shellIntegrationFeatures
        var features = try! XCTUnwrap(setting.parse("sudo,no-title"))
        XCTAssertEqual(features.on, ["cursor", "sudo", "path"])
        features.on.remove("cursor")
        XCTAssertEqual(setting.format(features), "no-cursor,sudo,no-title")
        XCTAssertEqual(setting.parse("false")?.on, [])
        XCTAssertNil(setting.parse("teleport"))
    }

    func testThemeIsOneThemeOrALightAndDarkPair() {
        XCTAssertEqual(ThemeChoice("Nord"), ThemeChoice(light: "Nord", dark: "Nord"))
        XCTAssertEqual(ThemeChoice("light:Builtin Light, dark:Nord"), ThemeChoice(light: "Builtin Light", dark: "Nord"))
        XCTAssertEqual(ThemeChoice(nil), ThemeChoice(light: nil, dark: nil))
        XCTAssertEqual(ThemeChoice(light: "A", dark: "B").value, "light:A,dark:B")
        XCTAssertEqual(ThemeChoice(light: nil, dark: "B").value, "light:\(Themes.ghosttyDefault),dark:B")
        XCTAssertEqual(ThemeChoice(light: "A", dark: "A").value, "A")
        XCTAssertNil(ThemeChoice(light: nil, dark: nil).value)
    }
}
