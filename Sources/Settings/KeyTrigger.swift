import AppKit

/// A key and the modifiers held with it, as Ghostty's `keybind` option names
/// them, such as `super+shift+p`. Ghostty's other spellings of the same key,
/// such as `bracket_left` for `[` or `cmd` for `super`, read as the same
/// trigger.
struct KeyTrigger: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let ctrl = Modifiers(rawValue: 1)
        static let alt = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let `super` = Modifiers(rawValue: 8)

        private static let flagPairs: [(Modifiers, NSEvent.ModifierFlags)] = [
            (.ctrl, .control), (.alt, .option), (.shift, .shift), (.super, .command),
        ]

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        init(_ flags: NSEvent.ModifierFlags) {
            self = Self(Self.flagPairs.filter { flags.contains($0.1) }.map(\.0))
        }

        var flags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(Self.flagPairs.filter { contains($0.0) }.map(\.1))
        }
    }

    var modifiers: Modifiers
    /// The character a key types, such as `p` or `[`, or else Ghostty's name
    /// for it, such as `enter` or `arrow_up`.
    var key: String

    init(_ modifiers: Modifiers, _ key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Nil for anything but modifiers and one key, such as a sequence.
    init?(_ text: String) {
        var modifiers: Modifiers = []
        var key: String?
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // A trailing `+` is the plus key itself, as in `super++`.
        if parts.count > 1, parts.last == "", parts[parts.count - 2] == "" {
            parts.removeLast(2)
            parts.append("+")
        }
        for part in parts {
            if let modifier = Self.modifierNames[part] {
                guard !modifiers.contains(modifier) else { return nil }
                modifiers.insert(modifier)
            } else {
                guard key == nil, let name = Self.canonicalKey(part) else { return nil }
                key = name
            }
        }
        guard let key else { return nil }
        self.init(modifiers, key)
    }

    /// From a key pressed with modifiers held, ignoring Caps Lock and Fn.
    init?(event: NSEvent) {
        let modifiers = Modifiers(event.modifierFlags)
        if let name = Self.keyCodeNames[event.keyCode] {
            self.init(modifiers, name)
            return
        }
        // Keys AppKit reports in the private use area, such as Help, have no
        // name Ghostty shares.
        guard let characters = event.characters(byApplyingModifiers: []), characters.count == 1,
              let scalar = characters.unicodeScalars.first, scalar.value >= 0x20, !(0xE000...0xF8FF).contains(scalar.value),
              let key = Self.canonicalKey(characters) else { return nil }
        self.init(modifiers, key)
    }

    /// How the config file writes it. A key that types a character goes by
    /// that character, as Ghostty's defaults do: Ghostty's name for it, such
    /// as `equal`, is a different binding, of the key's place.
    var configValue: String {
        configValue(key: key)
    }

    /// Ghostty binds its digit shortcuts twice, by the character and by the
    /// key's place for layouts where the digits are shifted, so unbinding
    /// one takes both.
    var ghosttySpellings: [String] {
        guard key.count == 1, key.first?.isNumber == true else { return [configValue] }
        return [configValue, configValue(key: "digit_\(key)")]
    }

    private func configValue(key: String) -> String {
        (Self.modifierOrder.filter { modifiers.contains($0.modifier) }.map(\.name) + [key]).joined(separator: "+")
    }

    /// One keycap per modifier and one for the key, as menus show them.
    var symbols: [String] {
        Self.modifierOrder.filter { modifiers.contains($0.modifier) }.map(\.symbol) + [keySymbol]
    }

    var keySymbol: String {
        if let symbol = Self.keySymbols[key] { return symbol }
        if key.count == 1 { return key.uppercased() }
        if key.hasPrefix("f"), Int(key.dropFirst()) != nil { return key.uppercased() }
        return key.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

    /// Nil for a key a menu cannot show.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        let equivalent: String
        if let special = Self.keyEquivalents[key] {
            equivalent = special
        } else if key.count == 1 {
            equivalent = key
        } else if key.hasPrefix("f"), let number = Int(key.dropFirst()), (1...35).contains(number) {
            equivalent = String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
        } else {
            return nil
        }
        return (equivalent, modifiers.flags)
    }

    // MARK: Names

    private static let modifierOrder: [(modifier: Modifiers, name: String, symbol: String)] = [
        (.ctrl, "ctrl", "⌃"), (.alt, "alt", "⌥"), (.shift, "shift", "⇧"), (.super, "super", "⌘"),
    ]

    private static let modifierNames: [String: Modifiers] = [
        "ctrl": .ctrl, "control": .ctrl, "alt": .alt, "opt": .alt, "option": .alt,
        "shift": .shift, "super": .super, "cmd": .super, "command": .super,
    ]

    /// Ghostty's names for keys that type a character, under that character.
    private static let characterNames: [String: String] = {
        var names: [String: String] = [
            "backquote": "`", "grave_accent": "`", "backslash": "\\", "bracket_left": "[", "left_bracket": "[",
            "bracket_right": "]", "right_bracket": "]", "comma": ",", "equal": "=", "minus": "-", "period": ".",
            "quote": "'", "apostrophe": "'", "semicolon": ";", "slash": "/", "plus": "+",
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
            "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        ]
        for letter in "abcdefghijklmnopqrstuvwxyz" { names["key_\(letter)"] = String(letter) }
        for digit in 0...9 { names["digit_\(digit)"] = "\(digit)" }
        return names
    }()

    private static let otherNames = ["up": "arrow_up", "down": "arrow_down", "left": "arrow_left", "right": "arrow_right"]

    /// One spelling per key: its character, or Ghostty's name for it.
    private static func canonicalKey(_ part: String) -> String? {
        guard !part.isEmpty else { return nil }
        if part == " " { return "space" }
        if part.count == 1 { return part.lowercased() }
        if let character = characterNames[part] { return character }
        if let name = otherNames[part] { return name }
        guard part.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" }), part.first?.isLetter == true else { return nil }
        return part
    }

    private static let keySymbols: [String: String] = [
        "enter": "↩", "tab": "⇥", "space": "Space", "escape": "⎋", "backspace": "⌫", "delete": "⌦",
        "arrow_up": "↑", "arrow_down": "↓", "arrow_left": "←", "arrow_right": "→",
        "home": "↖", "end": "↘", "page_up": "⇞", "page_down": "⇟",
    ]

    private static let keyEquivalents: [String: String] = [
        "enter": "\r", "tab": "\t", "space": " ", "escape": "\u{1B}", "backspace": "\u{8}",
        "delete": String(UnicodeScalar(NSDeleteFunctionKey)!),
        "arrow_up": String(UnicodeScalar(NSUpArrowFunctionKey)!), "arrow_down": String(UnicodeScalar(NSDownArrowFunctionKey)!),
        "arrow_left": String(UnicodeScalar(NSLeftArrowFunctionKey)!), "arrow_right": String(UnicodeScalar(NSRightArrowFunctionKey)!),
        "home": String(UnicodeScalar(NSHomeFunctionKey)!), "end": String(UnicodeScalar(NSEndFunctionKey)!),
        "page_up": String(UnicodeScalar(NSPageUpFunctionKey)!), "page_down": String(UnicodeScalar(NSPageDownFunctionKey)!),
    ]

    /// Keys that type no character, by their place on the keyboard.
    private static let keyCodeNames: [UInt16: String] = [
        36: "enter", 76: "enter", 48: "tab", 49: "space", 51: "backspace", 53: "escape", 117: "delete",
        123: "arrow_left", 124: "arrow_right", 125: "arrow_down", 126: "arrow_up",
        115: "home", 119: "end", 116: "page_up", 121: "page_down",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
        101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15",
        106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
    ]
}
