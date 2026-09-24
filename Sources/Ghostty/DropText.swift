import Foundation

/// What to type into a terminal for something dropped on it: URLs and file
/// paths are shell-escaped so they arrive as single arguments, several files
/// are separated by spaces, and plain text is left alone because it may be a
/// command meant to run as written.
enum DropText {
    static func text(url: String?, fileURLs: [URL], string: String?) -> String? {
        if let url {
            return escape(url)
        }
        if !fileURLs.isEmpty {
            return fileURLs.map { escape($0.path) }.joined(separator: " ")
        }
        return string
    }

    private static let specialCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"

    /// A backslash before a newline joins the lines instead of keeping it,
    /// so control characters are single-quoted, each on its own, which
    /// bash, zsh and fish all read the same way.
    static func escape(_ string: String) -> String {
        var result = ""
        for character in string {
            if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && $0 != "\t" }) {
                result += "'\(character)'"
                continue
            }
            if specialCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
