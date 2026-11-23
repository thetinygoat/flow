import Foundation

/// One `keybind` value, read the way Ghostty reads it.
enum Keybind: Equatable {
    /// Removes every binding, the defaults included.
    case clear
    /// Nil for a trigger Flow does not follow, such as a sequence.
    case bind(trigger: KeyTrigger?, triggerText: String, action: String)

    init?(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespaces)
        if value == "clear" {
            self = .clear
            return
        }
        var rest = Substring(value)
        while let colon = rest.firstIndex(of: ":"), ["all", "global", "unconsumed", "performable"].contains(rest[..<colon]) {
            rest = rest[rest.index(after: colon)...]
        }
        // An equals sign followed by `+` or `=` is the key itself, as in
        // `super+==action`.
        var search = rest.startIndex
        var equals: Substring.Index?
        while let index = rest[search...].firstIndex(of: "=") {
            let next = rest.index(after: index)
            if next < rest.endIndex, rest[next] == "+" || rest[next] == "=" {
                search = next
                continue
            }
            equals = index
            break
        }
        guard let equals else { return nil }
        let triggerText = String(rest[..<equals])
        guard triggerText != "chain" else { return nil }
        let isSequence = triggerText.split(separator: ">").count > 1
        self = .bind(trigger: isSequence ? nil : KeyTrigger(triggerText), triggerText: triggerText,
                     action: String(rest[rest.index(after: equals)...]).trimmingCharacters(in: .whitespaces))
    }

    /// The command Settings can change that the line binds.
    var command: KeyboardShortcuts.Command? {
        guard case .bind(_, _, let action) = self else { return nil }
        return KeyboardShortcuts.command(for: action)
    }

    /// What libghostty reads in place of a binding to one of Flow's actions:
    /// the key press unbound, so no binding of Ghostty's runs before Flow's
    /// menu. The first value takes the binding's place; the others unbind
    /// the press's other spelling.
    static func ghosttyValues(for value: String) -> [String]? {
        guard let keybind = Keybind(value), keybind.command?.isFlows == true,
              case .bind(let trigger, let triggerText, _) = keybind else { return nil }
        let others = trigger.map { trigger in trigger.ghosttySpellings.filter { KeyTrigger($0) != trigger } } ?? []
        return ["\(triggerText)=unbind"] + others.map { "\($0)=unbind" }
    }
}

/// The keys of the commands Settings can change: their defaults, then the
/// config's `keybind` lines in the order Ghostty reads them. A later line
/// wins, and a key press bound to anything else, under either spelling, is
/// taken from these commands.
struct KeyBindings: Equatable {
    private var keys: [String: KeyTrigger]

    static let defaults = KeyBindings(lines: [])

    /// Lines from included files can't bind Flow's own actions, since only
    /// the config file itself is kept from libghostty.
    init(lines: [(value: String, isIncluded: Bool)]) {
        keys = Dictionary(uniqueKeysWithValues: KeyboardShortcuts.changeable.map { ($0.action, $0.defaultKey) })
        for line in lines {
            guard let keybind = Keybind(line.value) else { continue }
            guard case .bind(let trigger, _, _) = keybind else {
                keys = [:]
                continue
            }
            guard let trigger else { continue }
            keys = keys.filter { $0.value.press != trigger.press }
            if let command = keybind.command, !(line.isIncluded && command.isFlows) {
                keys[command.action] = trigger
            }
        }
    }

    init(document: ConfigDocument, includes: [ConfigDocument] = []) {
        self.init(lines: document.values(for: "keybind").map { ($0, false) }
            + includes.flatMap { $0.values(for: "keybind") }.map { ($0, true) })
    }

    func shortcut(for action: String) -> KeyTrigger? {
        keys[action]
    }

    func command(using key: KeyTrigger) -> KeyboardShortcuts.Command? {
        keys.first { $0.value.press == key.press }.flatMap { KeyboardShortcuts.command(for: $0.key) }
    }
}

/// The `keybind` lines the Keyboard settings write, at the end of the file
/// so they win over any line before them.
extension ConfigDocument {
    func hasShortcutLines(for command: KeyboardShortcuts.Command) -> Bool {
        values(for: "keybind").contains { Self.isShortcutLine($0, for: command) }
    }

    mutating func resetShortcut(for command: KeyboardShortcuts.Command) {
        removeEntries { key, value in key == "keybind" && Self.isShortcutLine(value, for: command) }
    }

    /// Nil leaves the command without a key. A key another of these
    /// commands had goes to this one.
    mutating func setShortcut(_ key: KeyTrigger?, for command: KeyboardShortcuts.Command, includes: [ConfigDocument] = []) {
        resetShortcut(for: command)
        let current = KeyBindings(document: self, includes: includes).shortcut(for: command.action)
        guard current?.press != key?.press else { return }
        // Ghostty keeps every key bound to its action until it is unbound.
        if let current, key == nil || !command.isFlows {
            current.ghosttySpellings.forEach { append("keybind", "\($0)=unbind") }
        }
        if let key {
            append("keybind", "\(key.configValue)=\(command.action)")
        }
    }

    /// A binding to the command, or the unbinding of its default.
    private static func isShortcutLine(_ value: String, for command: KeyboardShortcuts.Command) -> Bool {
        guard let keybind = Keybind(value), case .bind(let trigger, _, let action) = keybind else { return false }
        return action == command.action || (action == "unbind" && trigger?.press == command.defaultKey.press)
    }
}
