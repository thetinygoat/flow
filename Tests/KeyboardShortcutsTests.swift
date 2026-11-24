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

    func testRefusesKeysTakenOutsideTheMenusItCanSearch() {
        func reason(_ text: String) -> String? {
            KeyboardShortcuts.unavailable(KeyTrigger(text)!)
        }
        XCTAssertEqual(reason("a"), "Shortcuts need ⌘, ⌃ or ⌥.")
        XCTAssertEqual(reason("shift+a"), "Shortcuts need ⌘, ⌃ or ⌥.")
        XCTAssertNil(reason("f5"))
        XCTAssertEqual(reason("super+digit_1"), "⌘1 is already the shortcut for Switch workspace.")
        XCTAssertEqual(reason("super+9"), "⌘9 is already the shortcut for Last workspace.")
        XCTAssertEqual(reason("ctrl+9"), "⌃9 is already the shortcut for Switch tab.")
        XCTAssertEqual(reason("super+arrow_up"), "⌘↑ is already the shortcut for Step up the list.")
        XCTAssertEqual(reason("ctrl+super+enter"), "⌃⌘↩ goes to the terminal.")
        XCTAssertEqual(reason("ctrl+/"), "⌃/ goes to the terminal.")
        XCTAssertNil(reason("ctrl+shift+/"))
        XCTAssertNil(reason("super+shift+1"))
        XCTAssertNil(reason("alt+p"))
    }
}
