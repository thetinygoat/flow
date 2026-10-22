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

    /// The sounds macOS offers for alerts, which agent alerts can play.
    static var sounds: [String] {
        let directory = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }
}
