import GhosttyKit

enum GhosttyError: Error {
    case apiFailed
}

/// Owns one `ghostty_config_t`, loaded from the user's Ghostty config files.
final class GhosttyConfig {
    let cValue: ghostty_config_t

    init() throws {
        guard let config = ghostty_config_new() else { throw GhosttyError.apiFailed }
        ghostty_config_load_default_files(config)
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

    var diagnostics: [String] {
        (0..<ghostty_config_diagnostics_count(cValue)).map { index in
            String(cString: ghostty_config_get_diagnostic(cValue, UInt32(index)).message)
        }
    }
}
