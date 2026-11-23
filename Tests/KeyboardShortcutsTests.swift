import XCTest

final class KeyboardShortcutsTests: XCTestCase {
    func testNoTwoShortcutsShareKeys() {
        let keys = KeyboardShortcuts.all.flatMap(\.shortcuts).map(\.keys)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testEverySectionHasShortcuts() {
        for section in KeyboardShortcuts.all {
            XCTAssertFalse(section.shortcuts.isEmpty, section.title)
        }
    }

    func testTheListShowsTheKeysInEffect() {
        XCTAssertEqual(KeyboardShortcuts.current(.defaults), KeyboardShortcuts.all)
        let bindings = KeyBindings(document: ConfigDocument("keybind = alt+super+p=toggle_command_palette\nkeybind = super+i=unbind\n"))
        let rows = KeyboardShortcuts.current(bindings).flatMap(\.shortcuts)
        XCTAssertEqual(rows.first { $0.title == "Go back to the previous tab or pane" }?.keys, ["⌥", "⌘", "P", "P"])
        XCTAssertFalse(rows.contains { $0.title == "Go to an agent" })
        XCTAssertFalse(rows.contains { $0.title == "Go to the agent waiting longest" })
    }
}
