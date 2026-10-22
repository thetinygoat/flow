import AppKit
import GhosttyKit

enum GhosttyError: Error {
    case apiFailed
}

/// Owns one `ghostty_config_t`, loaded from Flow's config file.
final class GhosttyConfig {
    let cValue: ghostty_config_t

    init(file: URL = ConfigFile.url) throws {
        guard let config = ghostty_config_new() else { throw GhosttyError.apiFailed }
        if FileManager.default.fileExists(atPath: file.path) {
            ghostty_config_load_file(config, file.path)
        }
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        cValue = config

        for message in diagnostics {
            logger.warning("config: \(message, privacy: .public)")
        }
    }

    /// Takes a copy of a config libghostty owns, such as the one it sends when
    /// the light or dark theme takes effect.
    init(copying config: ghostty_config_t) {
        cValue = ghostty_config_clone(config)
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
        color(for: "background") ?? .windowBackgroundColor
    }

    /// How strongly unfocused panes are dimmed, 0 to 1. Ghostty's setting is
    /// how opaque an unfocused pane stays, so 1 means no dimming.
    var unfocusedSplitDimming: Double {
        1 - value(for: "unfocused-split-opacity", default: 0.85)
    }

    var unfocusedSplitFill: NSColor {
        color(for: "unfocused-split-fill") ?? backgroundColor
    }

    /// `scrollbar = never` hides the scroller; anything else shows it.
    var showsScrollbar: Bool {
        var value: UnsafePointer<CChar>?
        guard read("scrollbar", into: &value), let value else { return true }
        return String(cString: value) != "never"
    }

    var notifyOnCommandFinish: CommandFinish.When {
        var value: UnsafePointer<CChar>?
        guard read("notify-on-command-finish", into: &value), let value else { return .never }
        return CommandFinish.When(rawValue: String(cString: value)) ?? .never
    }

    var notifyOnCommandFinishAction: CommandFinish.Actions {
        CommandFinish.Actions(rawValue: value(for: "notify-on-command-finish-action", default: CommandFinish.Actions.bell.rawValue))
    }

    var notifyOnCommandFinishAfter: Duration {
        .milliseconds(value(for: "notify-on-command-finish-after", default: UInt(5000)))
    }

    /// `split-preserve-zoom = navigation` keeps a tab zoomed while moving
    /// between its panes, zooming whichever pane focus lands on.
    var zoomFollowsNavigation: Bool {
        value(for: "split-preserve-zoom", default: CUnsignedInt(0)) & 1 != 0
    }

    /// Turns on secure input while a terminal is at a password prompt.
    var autoSecureInput: Bool {
        value(for: "macos-auto-secure-input", default: true)
    }

    /// Shows a lock on the terminal while secure input is on.
    var secureInputIndication: Bool {
        value(for: "macos-secure-input-indication", default: true)
    }

    private func color(for key: String) -> NSColor? {
        var color = ghostty_config_color_s()
        guard read(key, into: &color) else { return nil }
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
