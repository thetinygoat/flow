import Foundation

/// A config file in Ghostty's syntax, kept line by line so a setting can be
/// changed without touching the comments, order or other settings around it.
struct ConfigDocument: Equatable {
    private var lines: [String]

    init(_ text: String) {
        lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
    }

    var text: String {
        lines.map { $0 + "\n" }.joined()
    }

    /// True when no line sets anything.
    var isEmpty: Bool {
        lines.allSatisfy { Self.entry($0) == nil }
    }

    /// Every value set for the key, in order. Ghostty uses the last one, except
    /// for keys that build a list such as `font-family`.
    func values(for key: String) -> [String] {
        lines.compactMap { line in
            Self.entry(line).flatMap { $0.key == key ? $0.value : nil }
        }
    }

    subscript(key: String) -> String? {
        get { values(for: key).last }
        set { setValues(newValue.map { [$0] } ?? [], for: key) }
    }

    /// Replaces the lines setting the key with one line per value, where the
    /// first of them was, or at the end. No values removes the key, so Ghostty
    /// goes back to its default.
    mutating func setValues(_ values: [String], for key: String) {
        let indices = lines.indices.filter { Self.entry(lines[$0])?.key == key }
        let ending = lines.contains { $0.hasSuffix("\r") } ? "\r" : ""
        let replacement = values.map { "\(key) = \(Self.format($0))\(ending)" }
        let position = indices.first ?? lines.endIndex
        for index in indices.reversed() {
            lines.remove(at: index)
        }
        lines.insert(contentsOf: replacement, at: position)
    }

    /// Options whose value is a file, which Ghostty finds relative to the
    /// file that sets them.
    static let pathKeys = ["config-file", "custom-shader", "background-image", "bell-audio-path"]

    /// A document moved to another directory needs its relative paths made
    /// absolute to keep pointing at the same files. Each stays on its own
    /// line, so the lines keep their numbers.
    mutating func anchorPaths(at directory: URL) {
        for index in lines.indices {
            guard let entry = Self.entry(lines[index]), Self.pathKeys.contains(entry.key),
                  var path = ConfigPath(entry.value), path.isRelative else { continue }
            path.path = path.resolved(from: directory).path
            lines[index] = line(entry.key, path.value, endingLike: lines[index])
        }
    }

    /// Empties the lines whose setting matches, keeping them as lines so the
    /// ones after them keep their numbers. False when none matched.
    mutating func blankEntries(where matches: (_ key: String, _ value: String) -> Bool) -> Bool {
        var blanked = false
        for index in lines.indices {
            guard let entry = Self.entry(lines[index]), matches(entry.key, entry.value) else { continue }
            lines[index] = ""
            blanked = true
        }
        return blanked
    }

    /// Changes the values the transform returns one for, each on its own
    /// line. False when none changed.
    mutating func replaceValues(for key: String, _ transform: (String) -> String?) -> Bool {
        var replaced = false
        for index in lines.indices {
            guard let entry = Self.entry(lines[index]), entry.key == key, let value = transform(entry.value) else { continue }
            lines[index] = line(key, value, endingLike: lines[index])
            replaced = true
        }
        return replaced
    }

    mutating func removeEntries(where matches: (_ key: String, _ value: String) -> Bool) {
        lines.removeAll { line in Self.entry(line).map { matches($0.key, $0.value) } ?? false }
    }

    /// Adds a value after every other line, for a key that may be set more
    /// than once, such as `keybind`.
    mutating func append(_ key: String, _ value: String) {
        let ending = lines.contains { $0.hasSuffix("\r") } ? "\r" : ""
        lines.append("\(key) = \(Self.format(value))\(ending)")
    }

    private func line(_ key: String, _ value: String, endingLike original: String) -> String {
        "\(key) = \(Self.format(value))\(original.hasSuffix("\r") ? "\r" : "")"
    }

    /// The key and value of a line that sets something, read the way Ghostty
    /// reads it: comments are whole lines, a carriage return is whitespace,
    /// quotes around a value are dropped, and a key on its own turns it on.
    private static func entry(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let equals = trimmed.firstIndex(of: "=") else { return (trimmed, "true") }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    private static func format(_ value: String) -> String {
        value.isEmpty || value != value.trimmingCharacters(in: .whitespaces) ? "\"\(value)\"" : value
    }
}

/// A path option's value, read the way Ghostty reads it: a leading `?` makes
/// the file optional, then quotes around the path are dropped. Only `~/` is
/// expanded; any other relative path starts from the file that sets it.
struct ConfigPath: Equatable {
    var path: String
    var optional: Bool

    init?(_ value: String) {
        var value = Substring(value)
        optional = value.hasPrefix("?")
        if optional { value = value.dropFirst() }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = value.dropFirst().dropLast()
        }
        guard !value.isEmpty else { return nil }
        path = String(value)
    }

    var value: String {
        (optional ? "?" : "") + path
    }

    var isRelative: Bool {
        !path.hasPrefix("/") && !path.hasPrefix("~/")
    }

    func resolved(from directory: URL) -> URL {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
        }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
    }
}
