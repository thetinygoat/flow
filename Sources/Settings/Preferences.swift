import Foundation

/// Flow's own settings, which Ghostty has no option for. They live in the user
/// defaults rather than the config file, which libghostty reads and would
/// report unknown keys in.
enum Preferences {
    static let secureKeyboardEntry = "SecureKeyboardEntry"
    static let needsInputNotification = "AgentNeedsInputNotification"
    static let needsInputSound = "AgentNeedsInputSound"
    static let finishedNotification = "AgentFinishedNotification"
    static let finishedSound = "AgentFinishedSound"

    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            needsInputNotification: true,
            needsInputSound: "Ping",
            finishedNotification: true,
            finishedSound: "Glass",
        ])
    }

    /// The alert sounds macOS offers and the user's own, the places
    /// `NSSound(named:)` looks.
    static let sounds: [String] = {
        let directories = [
            URL(fileURLWithPath: "/System/Library/Sounds"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds"),
        ]
        let names = directories.flatMap { directory in
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .map { $0.deletingPathExtension().lastPathComponent }
        }
        return Array(Set(names)).sorted()
    }()
}
