import AppKit

/// A key and the modifiers held with it, as Ghostty's `keybind` option names
/// them, such as `super+shift+p`. Two triggers are equal when Ghostty takes
/// them as one binding: `cmd` is `super` and `left_bracket` is
/// `bracket_left`, but `p`, the character, and `key_p`, the key's place, are
/// separate bindings of the same key press.
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
    /// The character a key types, such as `p` or `[`, or Ghostty's name for
    /// its place, such as `key_p` or `enter`.
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

    /// The key press, by the character it types where it types one, so
    /// `super+key_p` and `super+p` are one press.
    var press: KeyTrigger {
        KeyTrigger(modifiers, Self.placeCharacters[key] ?? key)
    }

    /// Both bindings of the press, by character and by place. Ghostty tries
    /// the place first, so a key is only free once both are unbound.
    var ghosttySpellings: [String] {
        let press = press
        return [press.configValue] + (Self.placeNames[press.key].map { [configValue(key: $0)] } ?? [])
    }

    private func configValue(key: String) -> String {
        (Self.modifierOrder.filter { modifiers.contains($0.modifier) }.map(\.name) + [key]).joined(separator: "+")
    }

    /// One keycap per modifier and one for the key, as menus show them.
    var symbols: [String] {
        Self.modifierOrder.filter { modifiers.contains($0.modifier) }.map(\.symbol) + [keySymbol]
    }

    var keySymbol: String {
        let key = press.key
        if let symbol = Self.keySymbols[key] { return symbol }
        if key.count == 1 { return key.uppercased() }
        if key.hasPrefix("f"), Int(key.dropFirst()) != nil { return key.uppercased() }
        return key.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

    /// Nil for a key a menu cannot show.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        let key = press.key
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

    /// Ghostty's names for the places of keys that type a character, with
    /// the character on a US keyboard.
    private static let placeCharacters: [String: String] = {
        var names: [String: String] = [
            "backquote": "`", "backslash": "\\", "bracket_left": "[", "bracket_right": "]", "comma": ",",
            "equal": "=", "minus": "-", "period": ".", "quote": "'", "semicolon": ";", "slash": "/",
        ]
        for letter in "abcdefghijklmnopqrstuvwxyz" { names["key_\(letter)"] = String(letter) }
        for digit in 0...9 { names["digit_\(digit)"] = "\(digit)" }
        return names
    }()

    private static let placeNames = Dictionary(uniqueKeysWithValues: placeCharacters.map { ($1, $0) })

    /// The older names Ghostty still reads, as it reads them: some for a
    /// character, others for a place.
    private static let olderNames: [String: String] = {
        var names = [
            "plus": "+", "apostrophe": "'", "grave_accent": "backquote", "left_bracket": "bracket_left",
            "right_bracket": "bracket_right", "up": "arrow_up", "down": "arrow_down", "left": "arrow_left", "right": "arrow_right",
        ]
        for (digit, name) in ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"].enumerated() {
            names[name] = "\(digit)"
            names["kp_\(digit)"] = "numpad_\(digit)"
        }
        return names
    }()

    /// One spelling per binding: the character, or the name of the place.
    private static func canonicalKey(_ part: String) -> String? {
        guard !part.isEmpty else { return nil }
        if part == " " { return "space" }
        if part.count == 1 { return part.lowercased() }
        if let name = olderNames[part] { return name }
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
