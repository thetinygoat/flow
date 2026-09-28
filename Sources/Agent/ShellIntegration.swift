import Foundation

/// Loads Flow's shell scripts alongside libghostty's. Both are found through
/// the same variables, and libghostty applies a terminal's own environment
/// after its integration, so a per-terminal value would replace libghostty's.
/// Set in the app's environment instead, these are what libghostty builds on:
/// fish finds Flow's script in a later `XDG_DATA_DIRS` entry, and zsh reaches
/// Flow's `.zshenv` through the `ZDOTDIR` libghostty restores before loading
/// the user's own.
enum ShellIntegration {
    static let zshDirectoryKey = "FLOW_ZSH_ZDOTDIR"

    static func environment(directory: String, current: [String: String]) -> [String: String] {
        let zsh = (directory as NSString).appendingPathComponent("zsh")
        var variables = [
            "XDG_DATA_DIRS": ([directory] + [current["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/share:/usr/share"]).joined(separator: ":"),
            "ZDOTDIR": zsh,
        ]
        if let zdotdir = current["ZDOTDIR"], zdotdir != zsh {
            variables[zshDirectoryKey] = zdotdir
        }
        return variables
    }
}
