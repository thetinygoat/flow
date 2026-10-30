import Foundation
import UniformTypeIdentifiers

/// A link from terminal output. Any program can print one, and the text it
/// shows need not match where it goes, so it is checked before Launch
/// Services can act on it. Adapted from Ghostty's UntrustedURL.swift.
struct UntrustedLink: Equatable {
    enum Refusal: Equatable {
        case malformedURL
        case unsafeCharacters
        case invalidWebURL
        case inaccessibleFile
        case unsafeFile

        var message: String {
            switch self {
            case .malformedURL: "The target is not an absolute URL with a scheme."
            case .unsafeCharacters: "The target contains invisible or line-breaking characters."
            case .invalidWebURL: "The web target does not contain a valid host."
            case .inaccessibleFile: "The local target does not exist or is not a regular file or folder."
            case .unsafeFile: "Opening this local target could run code."
            }
        }
    }

    enum Decision: Equatable {
        case open(URL)
        /// A custom scheme can start any app registered for it.
        case confirm(URL)
        case block(Refusal)
    }

    let string: String

    init(_ string: String) {
        self.string = string
    }

    /// Text a `link` pattern matched may be a path, such as `src/main.swift`,
    /// so it is resolved against the terminal's directory before the checks.
    static func matched(_ text: String, relativeTo directory: String?) -> UntrustedLink {
        guard !containsUnsafeCharacters(text),
              let url = LinkTarget.url(for: text, relativeTo: directory), url.isFileURL else {
            return UntrustedLink(text)
        }
        return UntrustedLink(url.absoluteString)
    }

    var decision: Decision {
        // Checked before parsing, since URL percent-encodes these and the
        // encoded form would look harmless.
        guard !Self.containsUnsafeCharacters(string) else { return .block(.unsafeCharacters) }
        // Without a scheme a later step could read the target as a local path.
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return .block(.malformedURL)
        }

        switch scheme {
        case "http", "https":
            // `https:relative` has a scheme but no host, and handlers resolve it differently.
            guard let host = url.host, !host.isEmpty else { return .block(.invalidWebURL) }
            return .open(url)
        case "mailto":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  !components.path.isEmpty else { return .block(.malformedURL) }
            return .open(url)
        case "file":
            return fileDecision(for: url)
        default:
            return .confirm(url)
        }
    }

    static func containsUnsafeCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: isUnsafeCharacter)
    }

    /// One line showing where the link really goes. A file's path is shown
    /// as it will be opened, so `..` or a symlink can't make it look like
    /// somewhere else, and any unsafe character left is shown as an escape.
    var displayString: String {
        let normalized: String
        if let url = URL(string: string), url.scheme != nil {
            // Other URLs stay byte for byte, since a handler may care about repeated slashes.
            normalized = url.isFileURL ? url.standardizedFileURL.resolvingSymlinksInPath().path : string
        } else {
            normalized = URL(filePath: string).standardizedFileURL.path
        }
        var result = ""
        for scalar in normalized.unicodeScalars {
            if Self.isUnsafeCharacter(scalar) {
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

private extension UntrustedLink {
    func fileDecision(for url: URL) -> Decision {
        // A query or fragment names nothing on disk, and handlers read them differently.
        guard url.isFileURL, url.query == nil, url.fragment == nil else { return .block(.malformedURL) }
        // A file URL naming another host could reach the network.
        if let host = url.host, !host.isEmpty, host.caseInsensitiveCompare("localhost") != .orderedSame {
            return .block(.malformedURL)
        }

        // Judge what the link really points at, not how it is spelled.
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? target.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isExecutableKey, .isRegularFileKey]),
              values.isDirectory == true || values.isRegularFile == true else {
            return .block(.inaccessibleFile)
        }
        guard !Self.isUnsafeFile(target, values: values) else { return .block(.unsafeFile) }
        return .open(target)
    }

    static func isUnsafeFile(_ url: URL, values: URLResourceValues) -> Bool {
        // Launch Services picks a handler by extension, even without the executable bit.
        if unsafePathExtensions.contains(url.pathExtension.lowercased()) { return true }
        // Content types catch files whose extension is missing or misleading.
        if let type = values.contentType, unsafeContentTypes.contains(where: { type.conforms(to: $0) }) { return true }
        return values.isDirectory != true && values.isExecutable == true
    }

    static func isUnsafeCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Controls, including CR, LF and NEL.
        case 0x00...0x1F, 0x7F...0x9F: true
        // Direction marks and zero-width characters can reorder or hide part of the target.
        case 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        // Line and paragraph separators, and invisible padding.
        case 0x2028...0x2029, 0x2060, 0xFEFF: true
        default: false
        }
    }

    static let unsafePathExtensions: Set<String> = [
        "action", "app", "applescript", "class", "command", "desktop", "inetloc", "jar", "mobileconfig",
        "mpkg", "pkg", "scpt", "terminal", "tool", "url", "webloc", "workflow",
    ]

    static let unsafeContentTypes: [UTType] = [.application, .executable, .script]
}
