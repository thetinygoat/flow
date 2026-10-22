import Foundation

/// A command that finished in a terminal, as reported through shell
/// integration, and the rules for alerting about it.
struct CommandFinish {
    /// Ghostty's `notify-on-command-finish`.
    enum When: String {
        case never, unfocused, always
    }

    /// Ghostty's `notify-on-command-finish-action`.
    struct Actions: OptionSet {
        let rawValue: UInt32
        static let bell = Actions(rawValue: 1 << 0)
        static let notify = Actions(rawValue: 1 << 1)
        private static let names: [(String, Actions)] = [("bell", .bell), ("notify", .notify)]

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Ghostty starts from the bell alone, and each comma-separated name
        /// turns an action on, or off with a `no-` prefix.
        init?(config: String) {
            switch config {
            case "true": self = [.bell, .notify]; return
            case "false": self = []; return
            default: self = .bell
            }
            for part in config.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let name = part.hasPrefix("no-") ? String(part.dropFirst(3)) : part
                guard let action = Self.names.first(where: { $0.0 == name })?.1 else { return nil }
                if part.hasPrefix("no-") { remove(action) } else { insert(action) }
            }
        }

        var config: String {
            Self.names.map { name, action in contains(action) ? name : "no-" + name }.joined(separator: ",")
        }
    }

    /// Nil when the shell did not report one.
    let exitCode: Int?
    let duration: Duration

    func shouldAlert(when: When, inView: Bool, minimumDuration: Duration) -> Bool {
        switch when {
        case .never: return false
        case .unfocused where inView: return false
        default: return duration >= minimumDuration
        }
    }

    var title: String {
        switch exitCode {
        case nil: "Command Finished"
        case 0: "Command Succeeded"
        default: "Command Failed"
        }
    }

    var body: String {
        let took = duration.formatted(.units(
            allowed: [.hours, .minutes, .seconds, .milliseconds],
            width: .abbreviated,
            fractionalPart: .hide))
        guard let exitCode else { return "Command took \(took)." }
        return "Command took \(took) and exited with code \(exitCode)."
    }
}
