import Foundation

/// A Ghostty option the Settings window changes, with Ghostty's default so an
/// option the file leaves out shows what is in effect.
struct ConfigSetting<Value: Equatable> {
    let key: String
    let defaultValue: Value
    let parse: (String) -> Value?
    let format: (Value) -> String
}

extension ConfigSetting where Value == Bool {
    init(_ key: String, default defaultValue: Bool) {
        self.init(key: key, defaultValue: defaultValue, parse: { ["true": true, "false": false][$0] }, format: { String($0) })
    }
}

extension ConfigSetting where Value == Double {
    init(_ key: String, default defaultValue: Double) {
        self.init(key: key, defaultValue: defaultValue, parse: { Double($0) }, format: { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) })
    }
}

extension ConfigSetting where Value == String {
    init(_ key: String, default defaultValue: String) {
        self.init(key: key, defaultValue: defaultValue, parse: { $0 }, format: { $0 })
    }
}

extension ConfigSetting where Value == Duration {
    /// Ghostty writes durations as numbers with units, such as `1m 30s`.
    init(_ key: String, default defaultValue: Duration) {
        self.init(key: key, defaultValue: defaultValue, parse: ConfigDuration.parse, format: ConfigDuration.format)
    }
}

enum ConfigDuration {
    private static let units: [(suffix: String, duration: Duration)] = [
        ("ms", .milliseconds(1)), ("h", .seconds(3600)), ("m", .seconds(60)), ("s", .seconds(1)),
    ]

    static func parse(_ text: String) -> Duration? {
        var remaining = Substring(text.filter { !$0.isWhitespace })
        guard !remaining.isEmpty else { return nil }
        var total = Duration.zero
        while !remaining.isEmpty {
            let digits = remaining.prefix(while: \.isNumber)
            remaining = remaining.dropFirst(digits.count)
            guard let amount = Int(digits),
                  let unit = units.first(where: { remaining.hasPrefix($0.suffix) }) else { return nil }
            remaining = remaining.dropFirst(unit.suffix.count)
            total += unit.duration * amount
        }
        return total
    }

    static func format(_ duration: Duration) -> String {
        let seconds = duration.components.seconds
        return seconds % 60 == 0 && seconds > 0 ? "\(seconds / 60)m" : "\(seconds)s"
    }
}

/// The options the Settings window shows.
enum Option {
    static let fontFamily = "font-family"
    static let theme = "theme"
    static let fontSize = ConfigSetting<Double>("font-size", default: 13)
    static let fontThicken = ConfigSetting<Bool>("font-thicken", default: false)
    static let cursorStyle = ConfigSetting<String>("cursor-style", default: "block")
    static let cursorBlink = ConfigSetting<Bool>("cursor-style-blink", default: true)
    static let backgroundOpacity = ConfigSetting<Double>("background-opacity", default: 1)
    static let backgroundBlur = ConfigSetting<Bool>(
        key: "background-blur", defaultValue: false,
        parse: { $0 == "false" || $0 == "0" ? false : true }, format: { $0 ? "true" : "false" })
    static let unfocusedSplitOpacity = ConfigSetting<Double>("unfocused-split-opacity", default: 0.7)
    static let scrollbar = ConfigSetting<String>("scrollbar", default: "system")
    static let command = ConfigSetting<String>("command", default: "")
    static let confirmClose = ConfigSetting<String>("confirm-close-surface", default: "true")
    static let copyOnSelect = ConfigSetting<String>("copy-on-select", default: "true")
    static let mouseHideWhileTyping = ConfigSetting<Bool>("mouse-hide-while-typing", default: false)
    static let autoSecureInput = ConfigSetting<Bool>("macos-auto-secure-input", default: true)
    static let secureInputIndication = ConfigSetting<Bool>("macos-secure-input-indication", default: true)
    static let notifyOnCommandFinish = ConfigSetting<CommandFinish.When>(
        key: "notify-on-command-finish", defaultValue: .never, parse: CommandFinish.When.init(rawValue:), format: \.rawValue)
    static let notifyOnCommandFinishAction = ConfigSetting<CommandFinish.Actions>(
        key: "notify-on-command-finish-action", defaultValue: .bell, parse: CommandFinish.Actions.init(config:), format: \.config)
    static let notifyOnCommandFinishAfter = ConfigSetting<Duration>("notify-on-command-finish-after", default: .seconds(5))
}
