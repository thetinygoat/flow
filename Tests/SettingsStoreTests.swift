import XCTest

final class SettingsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSavesChangesAndKeepsTheRestOfTheFile() throws {
        let file = directory.appendingPathComponent("config")
        try "# mine\nkeybind = cmd+k=clear_screen\nfont-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        var saves = 0
        store.onSave = { saves += 1 }
        store.set(Option.fontSize, 15)
        store.set(Option.cursorStyle, "bar")
        store.saveNow()
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# mine\nkeybind = cmd+k=clear_screen\nfont-size = 15\ncursor-style = bar\n")
    }

    func testTheDefaultRemovesTheLine() throws {
        let file = directory.appendingPathComponent("config")
        try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        store.set(Option.fontSize, Option.fontSize.defaultValue)
        store.saveNow()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "")
        XCTAssertEqual(store.value(Option.fontSize), 13)
    }

    func testWritesThroughASymlink() throws {
        let real = directory.appendingPathComponent("dotfiles/config")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: real, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = SettingsStore(file: link)
        store.set(Option.fontSize, 15)
        store.saveNow()
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), real.path)
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "font-size = 15\n")
    }

    func testKeepsEditsMadeElsewhereWhileASaveIsWaiting() throws {
        let file = directory.appendingPathComponent("config")
        try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        store.set(Option.fontSize, 15)
        try "font-size = 12\ntheme = Nord\n".write(to: file, atomically: true, encoding: .utf8)
        store.set(Option.cursorStyle, "bar")
        store.saveNow()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "font-size = 15\ntheme = Nord\ncursor-style = bar\n")
    }

    func testListsSettingsAnIncludedFileOverrides() throws {
        let file = directory.appendingPathComponent("config")
        try "config-file = ?extra\nfont-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        try "font-size = 16\nconfig-file = more\nkeybind = cmd+k=clear_screen\n".write(to: directory.appendingPathComponent("extra"), atomically: true, encoding: .utf8)
        try "theme = Nord\nconfig-file = extra\n".write(to: directory.appendingPathComponent("more"), atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        XCTAssertEqual(store.overrides.count, 2)
        XCTAssertTrue(store.overrides[0].hasPrefix("font-size is set in "))
        XCTAssertTrue(store.overrides[1].hasPrefix("theme is set in "))
    }

    func testLeavesAFileItCannotReadAlone() throws {
        let file = directory.appendingPathComponent("config")
        let contents = Data("# caf\u{E9}\nfont-size = 12\n".data(using: .isoLatin1)!)
        try contents.write(to: file)
        let store = SettingsStore(file: file)
        XCTAssertNotNil(store.readError)
        store.set(Option.cursorStyle, "bar")
        XCTAssertFalse(store.saveNow())
        XCTAssertEqual(try Data(contentsOf: file), contents)
        XCTAssertNotNil(store.fileError)
    }

    func testRetriesAFailedSave() throws {
        let locked = directory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let file = locked.appendingPathComponent("config")
        try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let store = SettingsStore(file: file)
        store.set(Option.fontSize, 15)
        XCTAssertFalse(store.saveNow())
        XCTAssertNotNil(store.saveError)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        try "font-size = 12\ntheme = Nord\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload(problems: [])
        XCTAssertEqual(store.value(Option.fontSize), 15)
        XCTAssertTrue(store.saveNow())
        XCTAssertNil(store.saveError)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "font-size = 15\ntheme = Nord\n")
    }

    func testWritesAHeldChangeOnceTheFileCanBeRead() throws {
        let file = directory.appendingPathComponent("config")
        try Data("# caf\u{E9}\nfont-size = 12\n".data(using: .isoLatin1)!).write(to: file)
        let store = SettingsStore(file: file)
        store.set(Option.fontSize, 15)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertNotNil(store.readError)

        try "# cafe\nfont-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload(problems: [])
        XCTAssertNil(store.fileError)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# cafe\nfont-size = 15\n")
    }

    func testRecreatesADeletedFileWithTheHeader() throws {
        let file = directory.appendingPathComponent("config")
        try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        try FileManager.default.removeItem(at: file)
        store.set(Option.cursorStyle, "bar")
        XCTAssertTrue(store.saveNow())
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ConfigFile.header + "cursor-style = bar\n")
    }

    func testLeavesADirectoryAtTheConfigPathAlone() throws {
        let file = directory.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let store = SettingsStore(file: file)
        XCTAssertNotNil(store.readError)
        store.set(Option.fontSize, 15)
        XCTAssertFalse(store.saveNow())
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    func testClearsTheSaveErrorWhenChangesAreUndone() throws {
        let locked = directory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let file = locked.appendingPathComponent("config")
        try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let store = SettingsStore(file: file)
        store.set(Option.fontSize, 15)
        store.saveNow()
        XCTAssertNotNil(store.saveError)
        store.set(Option.fontSize, 12)
        store.saveNow()
        XCTAssertNil(store.saveError)
    }

    func testCannotShowAGlassBlur() throws {
        let file = directory.appendingPathComponent("config")
        try "background-blur = macos-glass-regular\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(SettingsStore(file: file).hasUnknownValue(Option.backgroundBlur))
    }

    func testPromptCursorSwitchKeepsTheOtherSwitches() throws {
        let file = directory.appendingPathComponent("config")
        try "shell-integration-features = sudo\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        var features = store.value(Option.shellIntegrationFeatures)
        features.on.remove("cursor")
        store.set(Option.shellIntegrationFeatures, features)
        XCTAssertEqual(store.values(for: Option.shellIntegrationFeatures.key), ["no-cursor,sudo"])
        features.on.insert("cursor")
        store.set(Option.shellIntegrationFeatures, features)
        XCTAssertEqual(store.values(for: Option.shellIntegrationFeatures.key), ["sudo"])
        features.on.remove("sudo")
        store.set(Option.shellIntegrationFeatures, features)
        XCTAssertEqual(store.values(for: Option.shellIntegrationFeatures.key), [])
    }

    func testAnEmptyIncludeClearsTheOnesBeforeIt() throws {
        let file = directory.appendingPathComponent("config")
        try "config-file = extra\nconfig-file = \"\"\n".write(to: file, atomically: true, encoding: .utf8)
        try "font-size = 16\n".write(to: directory.appendingPathComponent("extra"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SettingsStore(file: file).overrides, [])
    }

    func testAThemesValueShowsAndADefaultChoiceOverridesIt() throws {
        let theme = directory.appendingPathComponent("glassy")
        try "background = #000000\nbackground-opacity = 0.5\n".write(to: theme, atomically: true, encoding: .utf8)
        let file = directory.appendingPathComponent("config")
        try "theme = \(theme.path)\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        XCTAssertEqual(store.value(Option.backgroundOpacity), 0.5)

        store.set(Option.backgroundOpacity, 1)
        XCTAssertEqual(store.values(for: Option.backgroundOpacity.key), ["1"])
        store.set(Option.backgroundOpacity, 0.5)
        XCTAssertEqual(store.values(for: Option.backgroundOpacity.key), [])
    }

    func testDoesNotReportIncludedFallbackFonts() throws {
        let file = directory.appendingPathComponent("config")
        try "config-file = fonts\nfont-family = Iosevka\n".write(to: file, atomically: true, encoding: .utf8)
        try "font-family = Symbols Nerd Font\n".write(to: directory.appendingPathComponent("fonts"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SettingsStore(file: file).overrides, [])
    }

    func testReportsASaveThatFails() throws {
        let readOnly = directory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        let file = readOnly.appendingPathComponent("config")
        try "".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path) }
        let store = SettingsStore(file: file)
        var saves = 0
        store.onSave = { saves += 1 }
        store.set(Option.fontSize, 15)
        store.saveNow()
        XCTAssertNotNil(store.saveError)
        XCTAssertEqual(saves, 0)
    }

    func testKeepsEditsMadeElsewhere() throws {
        let file = directory.appendingPathComponent("config")
        try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
        let store = SettingsStore(file: file)
        try "font-size = 12\ntheme = Nord\n".write(to: file, atomically: true, encoding: .utf8)
        store.set(Option.fontSize, 15)
        store.saveNow()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "font-size = 15\ntheme = Nord\n")
    }
}
