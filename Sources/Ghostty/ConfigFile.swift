import Foundation

/// Picks the Ghostty config file that Settings opens.
///
/// Ghostty loads every config file it finds, but its own choice of file to
/// edit prefers Application Support over `~/.config`, even when the
/// Application Support file is only the commented-out template Ghostty writes
/// on first launch. Opening the first file that holds an actual setting sends
/// people to the config they really use.
enum ConfigFile {
    /// Ghostty's search order on macOS.
    static var candidates: [URL] {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
        let xdgHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        let xdg = xdgHome.appendingPathComponent("ghostty", isDirectory: true)
        return [
            appSupport.appendingPathComponent("config.ghostty"),
            appSupport.appendingPathComponent("config"),
            xdg.appendingPathComponent("config.ghostty"),
            xdg.appendingPathComponent("config"),
        ]
    }

    static func firstWithSettings(among candidates: [URL]) -> URL? {
        candidates.first { url in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return contents.split(whereSeparator: \.isNewline).contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
        }
    }
}
