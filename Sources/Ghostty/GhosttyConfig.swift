import AppKit
import GhosttyKit

enum GhosttyError: Error {
    case apiFailed
}

/// Owns one `ghostty_config_t`, loaded from the user's Ghostty config files.
final class GhosttyConfig {
    let cValue: ghostty_config_t

    /// Loads the user's Ghostty config files, or the single file named by the
    /// FLOW_CONFIG environment variable when set.
    init() throws {
        guard let config = ghostty_config_new() else { throw GhosttyError.apiFailed }
        if let override = ProcessInfo.processInfo.environment["FLOW_CONFIG"] {
            ghostty_config_load_file(config, override)
        } else {
            ghostty_config_load_default_files(config)
        }
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        cValue = config

        for message in diagnostics {
            logger.warning("config: \(message, privacy: .public)")
        }
    }

    deinit {
        ghostty_config_free(cValue)
    }

    var backgroundOpacity: Double {
        value(for: "background-opacity", default: 1)
    }

    /// Positive values are a blur radius. Ghostty reserves negative values for
    /// macOS glass styles, which flow does not support yet.
    var backgroundBlur: Int16 {
        value(for: "background-blur", default: 0)
    }

    var backgroundColor: NSColor {
        var color = ghostty_config_color_s()
        guard read("background", into: &color) else { return .windowBackgroundColor }
        return NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1)
    }

    private func value<T>(for key: String, default defaultValue: T) -> T {
        var result = defaultValue
        _ = read(key, into: &result)
        return result
    }

    private func read<T>(_ key: String, into result: inout T) -> Bool {
        key.withCString { ghostty_config_get(cValue, &result, $0, UInt(key.utf8.count)) }
    }

    var diagnostics: [String] {
        (0..<ghostty_config_diagnostics_count(cValue)).map { index in
            String(cString: ghostty_config_get_diagnostic(cValue, UInt32(index)).message)
        }
    }
}
