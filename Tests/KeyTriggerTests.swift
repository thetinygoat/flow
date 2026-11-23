import AppKit
import XCTest

final class KeyTriggerTests: XCTestCase {
    private func trigger(_ text: String) -> KeyTrigger? {
        KeyTrigger(text)
    }

    func testReadsGhosttysOtherNamesForTheSameBinding() {
        XCTAssertEqual(trigger("cmd+shift+bracket_left"), trigger("shift+command+left_bracket"))
        XCTAssertEqual(trigger("super+T"), KeyTrigger(.super, "t"))
        XCTAssertEqual(trigger("opt+up"), KeyTrigger(.alt, "arrow_up"))
        XCTAssertEqual(trigger("ctrl+one"), KeyTrigger(.ctrl, "1"))
        XCTAssertEqual(trigger("super++"), KeyTrigger(.super, "+"))
        XCTAssertEqual(trigger("super+plus"), KeyTrigger(.super, "+"))
        XCTAssertEqual(trigger("kp_1"), KeyTrigger([], "numpad_1"))
        XCTAssertEqual(trigger("f5"), KeyTrigger([], "f5"))
    }

    /// Ghostty binds a character and a key's place separately, though both
    /// are the same press.
    func testACharacterAndItsPlaceAreOnePressButTwoBindings() {
        let pairs = [("super+key_t", "super+t"), ("ctrl+digit_1", "ctrl+1"), ("super+equal", "super+="), ("super+shift+bracket_left", "super+shift+[")]
        for (place, character) in pairs {
            XCTAssertNotEqual(trigger(place), trigger(character), place)
            XCTAssertEqual(trigger(place)?.press, trigger(character), place)
            XCTAssertEqual(trigger(place)?.ghosttySpellings, trigger(character)?.ghosttySpellings, place)
        }
        XCTAssertEqual(trigger("super+key_p")?.symbols, ["⌘", "P"])
        XCTAssertEqual(trigger("super+equal")?.menuKeyEquivalent?.key, "=")
    }

    func testRefusesWhatIsNotOneKey() {
        for text in ["", "super+", "super+shift+shift+a", "super+a+b", "ctrl+a>n", "Super+a"] {
            XCTAssertNil(trigger(text), text)
        }
    }

    func testWritesWhatGhosttyReads() {
        XCTAssertEqual(KeyTrigger([.super, .ctrl, .alt, .shift], "p").configValue, "ctrl+alt+shift+super+p")
        XCTAssertEqual(KeyTrigger(.super, "=").configValue, "super+=")
        XCTAssertEqual(KeyTrigger(.super, "+").configValue, "super++")
        XCTAssertEqual(Keybind("super+==unbind"), .bind(trigger: KeyTrigger(.super, "="), triggerText: "super+=", action: "unbind"))
        XCTAssertEqual(Keybind("super++=unbind"), .bind(trigger: KeyTrigger(.super, "+"), triggerText: "super++", action: "unbind"))
        XCTAssertEqual(KeyTrigger(.super, "1").ghosttySpellings, ["super+1", "super+digit_1"])
        XCTAssertEqual(KeyTrigger(.super, "t").ghosttySpellings, ["super+t", "super+key_t"])
        XCTAssertEqual(KeyTrigger(.super, "enter").ghosttySpellings, ["super+enter"])
    }

    func testShowsKeycapsInMenuOrder() {
        XCTAssertEqual(trigger("super+shift+ctrl+alt+p")?.symbols, ["⌃", "⌥", "⇧", "⌘", "P"])
        XCTAssertEqual(trigger("super+enter")?.symbols, ["⌘", "↩"])
        XCTAssertEqual(trigger("f12")?.symbols, ["F12"])
        XCTAssertEqual(trigger("page_up")?.symbols, ["⇞"])
        XCTAssertEqual(trigger("numpad_add")?.symbols, ["Numpad Add"])
    }

    func testGivesMenusTheirKeyEquivalent() {
        let bracket = trigger("super+shift+[")?.menuKeyEquivalent
        XCTAssertEqual(bracket?.key, "[")
        XCTAssertEqual(bracket?.modifiers, [.shift, .command])
        XCTAssertEqual(trigger("super+shift+enter")?.menuKeyEquivalent?.key, "\r")
        XCTAssertEqual(trigger("f2")?.menuKeyEquivalent?.key, String(UnicodeScalar(NSF2FunctionKey)!))
        XCTAssertEqual(trigger("ctrl+arrow_up")?.menuKeyEquivalent?.key, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertNil(trigger("copy")?.menuKeyEquivalent)
    }

    func testReadsKeysThatTypeNothingFromTheirPlace() throws {
        func event(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                           context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
        }
        XCTAssertEqual(KeyTrigger(event: try event(36, [.command, .shift, .capsLock])), KeyTrigger([.super, .shift], "enter"))
        XCTAssertEqual(KeyTrigger(event: try event(126, [.option, .function, .numericPad])), KeyTrigger(.alt, "arrow_up"))
        XCTAssertEqual(KeyTrigger(event: try event(96, [])), KeyTrigger([], "f5"))
    }
}
