import Foundation

/// Flow's own options in the config file, for what Ghostty has no option for.
/// libghostty never sees them.
enum FlowOption {
    static let secureKeyboardEntry = ConfigSetting<Bool>("secure-keyboard-entry", default: false)
    static let needsInputNotification = ConfigSetting<Bool>("agent-needs-input-notification", default: true)
    static let needsInputSound = sound("agent-needs-input-sound", default: "Ping")
    static let finishedNotification = ConfigSetting<Bool>("agent-finished-notification", default: true)
    static let finishedSound = sound("agent-finished-sound", default: "Glass")

    static let keys: Set<String> = [
        secureKeyboardEntry.key, needsInputNotification.key, needsInputSound.key, finishedNotification.key, finishedSound.key,
    ]

    /// A sound's name, or `none` for silence, which reads as no name. An empty
    /// value goes back to the default, as it does for Ghostty's options.
    private static func sound(_ key: String, default defaultValue: String) -> ConfigSetting<String> {
        ConfigSetting(key: key, defaultValue: defaultValue,
                      parse: { $0.isEmpty ? nil : $0 == "none" ? "" : $0 },
                      format: { $0.isEmpty ? "none" : $0 })
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

    /// Earlier versions of Flow kept these options in the user defaults. Each
    /// value someone set moves to the config file, unless the file sets the
    /// option already, and leaves the defaults only once the file is written,
    /// so a write that fails is tried again at the next launch.
    static func moveFromDefaults(_ defaults: UserDefaults, domain: String, to file: URL) {
        let stored = defaults.persistentDomain(forName: domain) ?? [:]
        func move<Value>(_ option: ConfigSetting<Value>, from name: String) -> (name: String, key: String, value: String?)? {
            guard let value = stored[name] else { return nil }
            let changed = (value as? Value).flatMap { $0 == option.defaultValue ? nil : option.format($0) }
            return (name, option.key, changed)
        }
        let moves = [
            move(secureKeyboardEntry, from: "SecureKeyboardEntry"),
            move(needsInputNotification, from: "AgentNeedsInputNotification"),
            move(needsInputSound, from: "AgentNeedsInputSound"),
            move(finishedNotification, from: "AgentFinishedNotification"),
            move(finishedSound, from: "AgentFinishedSound"),
        ].compactMap { $0 }
        guard !moves.isEmpty else { return }

        let text: String
        if FileManager.default.fileExists(atPath: file.path) {
            guard let existing = try? String(contentsOf: file, encoding: .utf8) else { return }
            text = existing
        } else {
            text = ConfigFile.header
        }
        var document = ConfigDocument(text)
        for move in moves where document[move.key] == nil {
            document[move.key] = move.value
        }
        if document != ConfigDocument(text) {
            do {
                try ConfigFile.write(document.text, to: file)
            } catch {
                logger.error("could not move settings to \(file.path, privacy: .public): \(error, privacy: .public)")
                return
            }
        }
        moves.forEach { defaults.removeObject(forKey: $0.name) }
    }
}

/// Flow's options as the config file set them when it was last loaded.
struct FlowOptions {
    private let document: ConfigDocument

    init(_ document: ConfigDocument = ConfigDocument("")) {
        self.document = document
    }

    init(file: URL) {
        self.init(ConfigDocument((try? String(contentsOf: file, encoding: .utf8)) ?? ""))
    }

    func value<Value>(_ option: ConfigSetting<Value>) -> Value {
        document[option.key].flatMap(option.parse) ?? option.defaultValue
    }
}
