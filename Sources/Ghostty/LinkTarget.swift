import Foundation

/// What a clicked link in the terminal opens. Ghostty's link matching finds
/// both URLs and bare file paths such as `~/notes.md` or `src/main.swift`;
/// paths have no scheme, so they become file URLs, with `~` expanded and
/// relative paths resolved against the terminal's directory.
enum LinkTarget {
    static func url(for text: String, relativeTo directory: String?) -> URL? {
        let path = resolvedPath(text, relativeTo: directory)
        // Something like `notes.txt:12` parses as a URL with the scheme
        // "notes.txt", so a matching file wins over the scheme.
        if let candidate = URL(string: text), candidate.scheme != nil,
           !FileManager.default.fileExists(atPath: path) {
            return candidate
        }
        return path.isEmpty ? nil : URL(filePath: path)
    }

    private static func resolvedPath(_ text: String, relativeTo directory: String?) -> String {
        let expanded = NSString(string: text).expandingTildeInPath
        guard !expanded.hasPrefix("/"), let directory else { return NSString(string: expanded).standardizingPath }
        return NSString(string: NSString(string: directory).appendingPathComponent(expanded)).standardizingPath
    }
}
