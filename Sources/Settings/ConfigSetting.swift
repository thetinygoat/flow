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
        self.init(key: key, defaultValue: defaultValue, parse: ConfigBool.parse, format: { String($0) })
    }
}

/// The spellings Ghostty accepts for true and false.
enum ConfigBool {
    static func parse(_ text: String) -> Bool? {
        if ["1", "t", "T", "true"].contains(text) { return true }
        if ["0", "f", "F", "false"].contains(text) { return false }
        return nil
    }
}

extension ConfigSetting where Value == Double {
    /// Ghostty reads numbers with a decimal point whatever the user's locale.
    init(_ key: String, default defaultValue: Double) {
        self.init(key: key, defaultValue: defaultValue, parse: { Double($0) }, format: {
            $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
        })
    }
}

extension ConfigSetting where Value == String {
    init(_ key: String, default defaultValue: String) {
        self.init(key: key, defaultValue: defaultValue, parse: { $0 }, format: { $0 })
    }
}

extension ConfigSetting where Value == String {
    /// An option with a fixed set of values. Ghostty's other spellings of
    /// true and false read as `true` and `false`.
    init(_ key: String, default defaultValue: String, choices: Set<String>) {
        self.init(key: key, defaultValue: defaultValue, parse: { text in
            let value = ConfigBool.parse(text).map(String.init) ?? text
            return choices.contains(value) ? value : nil
        }, format: { $0 })
    }
}

extension ConfigSetting where Value == Duration {
    /// Ghostty writes durations as numbers with units, such as `1m 30s`.
    init(_ key: String, default defaultValue: Duration) {
        self.init(key: key, defaultValue: defaultValue, parse: ConfigDuration.parse, format: ConfigDuration.format)
    }
}

enum ConfigDuration {
    /// Longer suffixes first, so `ms` is not read as minutes.
    private static let units: [(suffix: String, duration: Duration)] = [
        ("ms", .milliseconds(1)), ("µs", .microseconds(1)), ("us", .microseconds(1)), ("ns", .nanoseconds(1)),
        ("y", .seconds(365 * 86400)), ("w", .seconds(7 * 86400)), ("d", .seconds(86400)),
        ("h", .seconds(3600)), ("m", .seconds(60)), ("s", .seconds(1)),
    ]

    static func parse(_ text: String) -> Duration? {
        var remaining = Substring(text.filter { !$0.isWhitespace })
        guard !remaining.isEmpty else { return nil }
        if remaining == "0" { return .zero }
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
        let (seconds, attoseconds) = duration.components
        guard attoseconds == 0 else { return "\(seconds * 1000 + attoseconds / 1_000_000_000_000_000)ms" }
        return seconds % 60 == 0 && seconds > 0 ? "\(seconds / 60)m" : "\(seconds)s"
    }
}

/// A Ghostty option made of named switches, such as `no-cursor,sudo`. Ghostty
/// starts from its defaults and each name turns a switch on, or off with a
/// `no-` prefix; a boolean on its own sets them all.
struct ConfigFlags: Equatable {
    let names: [String]
    var on: Set<String>

    func parse(_ text: String) -> ConfigFlags? {
        var flags = self
        if let all = ConfigBool.parse(text) {
            flags.on = all ? Set(names) : []
            return flags
        }
        for part in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let negated = part.hasPrefix("no-")
            let name = negated ? String(part.dropFirst(3)) : part
            guard names.contains(name) else { return nil }
            if negated { flags.on.remove(name) } else { flags.on.insert(name) }
        }
        return flags
    }

    /// Only the switches that differ from `defaults`, which is all Ghostty needs.
    func format(from defaults: ConfigFlags) -> String {
        names.filter { on.contains($0) != defaults.on.contains($0) }
            .map { on.contains($0) ? $0 : "no-" + $0 }
            .joined(separator: ",")
    }
}

extension ConfigSetting where Value == ConfigFlags {
    init(_ key: String, default defaultValue: ConfigFlags) {
        self.init(key: key, defaultValue: defaultValue, parse: defaultValue.parse, format: { $0.format(from: defaultValue) })
    }
}

/// The options the Settings window shows.
enum Option {
    static let fontFamily = "font-family"
    static let theme = "theme"
    static let fontSize = ConfigSetting<Double>("font-size", default: 13)
    static let fontThicken = ConfigSetting<Bool>("font-thicken", default: false)
    static let cursorStyle = ConfigSetting<String>("cursor-style", default: "block", choices: ["block", "bar", "underline", "block_hollow"])
    static let cursorBlink = ConfigSetting<Bool>("cursor-style-blink", default: true)
    static let backgroundOpacity = ConfigSetting<Double>("background-opacity", default: 1)
    /// On or off. Ghostty also takes a radius, where `true` is its default of
    /// 20; any radius above 0 reads as on and stays until blur is turned off.
    static let backgroundBlur = ConfigSetting<Bool>(
        key: "background-blur", defaultValue: false,
        parse: { text in ConfigBool.parse(text) ?? Int(text).map { $0 > 0 } },
        format: { String($0) })
    static let unfocusedSplitOpacity = ConfigSetting<Double>("unfocused-split-opacity", default: 0.7)
    static let scrollbar = ConfigSetting<String>("scrollbar", default: "system", choices: ["system", "never"])
    static let command = ConfigSetting<String>("command", default: "")
    static let confirmClose = ConfigSetting<String>("confirm-close-surface", default: "true", choices: ["false", "true", "always"])
    /// `true` copies to the system clipboard on macOS, like `clipboard` and `both`.
    static let copyOnSelect = ConfigSetting<String>(
        "copy-on-select", default: "none", choices: ["false", "true", "none", "primary", "clipboard", "both"])
    /// The `cursor` switch has the shell set a blinking bar at its prompt,
    /// which overrides `cursor-style` and `cursor-style-blink` there.
    static let shellIntegrationFeatures = ConfigSetting<ConfigFlags>("shell-integration-features", default: ConfigFlags(
        names: ["cursor", "sudo", "title", "ssh-env", "ssh-terminfo", "path"], on: ["cursor", "title", "path"]))
    static let mouseHideWhileTyping = ConfigSetting<Bool>("mouse-hide-while-typing", default: false)
    static let autoSecureInput = ConfigSetting<Bool>("macos-auto-secure-input", default: true)
    static let notifyOnCommandFinish = ConfigSetting<CommandFinish.When>(
        key: "notify-on-command-finish", defaultValue: .never, parse: CommandFinish.When.init(rawValue:), format: \.rawValue)
    static let notifyOnCommandFinishAction = ConfigSetting<CommandFinish.Actions>(
        key: "notify-on-command-finish-action", defaultValue: .bell, parse: CommandFinish.Actions.init(config:), format: \.config)
    static let notifyOnCommandFinishAfter = ConfigSetting<Duration>("notify-on-command-finish-after", default: .seconds(5))

    static let keys = [
        fontFamily, theme, fontSize.key, fontThicken.key, cursorStyle.key, cursorBlink.key, backgroundOpacity.key,
        backgroundBlur.key, unfocusedSplitOpacity.key, scrollbar.key, command.key, confirmClose.key, copyOnSelect.key,
        shellIntegrationFeatures.key, mouseHideWhileTyping.key, autoSecureInput.key, notifyOnCommandFinish.key,
        notifyOnCommandFinishAction.key, notifyOnCommandFinishAfter.key,
    ]
}
