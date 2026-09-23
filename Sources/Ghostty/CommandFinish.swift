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
