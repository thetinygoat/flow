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
