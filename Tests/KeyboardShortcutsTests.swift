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
}
