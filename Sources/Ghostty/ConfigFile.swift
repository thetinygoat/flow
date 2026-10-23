import AppKit
import UniformTypeIdentifiers

/// Flow's config file. It uses Ghostty's syntax, so every Ghostty option works
/// in it, but Flow reads only this file and not Ghostty's own config.
enum ConfigFile {
    /// `~/.config/flow/config`, or the file named by the FLOW_CONFIG
    /// environment variable.
    static var url: URL {
        if let override = ProcessInfo.processInfo.environment["FLOW_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        return configHome.appendingPathComponent("flow", isDirectory: true).appendingPathComponent("config")
    }

    /// Ghostty's config files, in the order Ghostty loads them.
    static var ghosttyFiles: [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
        let xdg = configHome.appendingPathComponent("ghostty", isDirectory: true)
        return [
            xdg.appendingPathComponent("config"),
            xdg.appendingPathComponent("config.ghostty"),
            appSupport.appendingPathComponent("config"),
            appSupport.appendingPathComponent("config.ghostty"),
        ]
    }

    private static var configHome: URL {
        ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
    }

    static let header = """
        # Flow settings. The Settings window rewrites the lines it manages; all
        # other lines are preserved. All Ghostty options are supported.

        """

    /// Earlier versions of Flow read Ghostty's config, so the first time Flow
    /// makes its own it copies those settings over and nothing changes for
    /// people who set Flow up through Ghostty.
    static func createIfMissing() {
        guard ProcessInfo.processInfo.environment["FLOW_CONFIG"] == nil else { return }
        do {
            try create(at: url, importing: ghosttyFiles)
        } catch {
            logger.error("could not create \(url.path, privacy: .public): \(error, privacy: .public)")
        }
    }

    static func create(at url: URL, importing ghosttyFiles: [URL]) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try write(header + imported(from: ghosttyFiles), to: url)
    }

    /// Writes through symlinks, including one whose target does not exist
    /// yet, so a config kept with someone's dotfiles stays a link to them.
    static func write(_ text: String, to url: URL) throws {
        let target = writeTarget(for: url)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    static func writeTarget(for url: URL) -> URL {
        var url = url
        for _ in 0..<16 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { break }
            url = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
        }
        return url
    }

    /// The settings in the given files, each under a note of where it came
    /// from. Files holding only comments, such as the template Ghostty writes
    /// on its first launch, are left out.
    static func imported(from files: [URL]) -> String {
        files.compactMap { file -> String? in
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            var document = ConfigDocument(contents)
            guard !document.isEmpty else { return nil }
            document.anchorIncludes(at: file.deletingLastPathComponent())
            return "\n# Imported from \(file.path.abbreviatingHome)\n" + document.text
        }.joined()
    }
}

extension ConfigFile {
    /// Opens the config file in the user's text editor, creating it first if
    /// it was removed.
    static func openInEditor() {
        let url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            try? write(header, to: url)
        }
        // The file has no extension, so it is opened as plain text rather
        // than with whatever claims extensionless files.
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }
}
