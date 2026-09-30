import Foundation

/// The sound played when an agent needs the user or has finished. A waiting
/// agent is stuck until answered, so it sounds even in the terminal the user
/// is looking at; the rest only sound where a notification would be posted.
enum AgentSound: Equatable, Hashable {
    case needsInput, finished

    var name: String {
        switch self {
        case .needsInput: "Ping"
        case .finished: "Glass"
        }
    }

    static func make(for update: AgentSessionStore.Update, isVisible: Bool) -> AgentSound? {
        switch update.kind {
        case .needsInput:
            update.repeatsWait ? nil : .needsInput
        case .turnEnded:
            isVisible ? nil : .finished
        case .attention:
            isVisible || update.session.attention.nonEmpty == nil ? nil : .finished
        default:
            nil
        }
    }
}

/// Several sessions finishing together would otherwise stack the same sound.
struct AgentSoundThrottle {
    static let interval: TimeInterval = 0.3

    private var lastPlayed: [AgentSound: Date] = [:]

    mutating func allows(_ sound: AgentSound, at now: Date) -> Bool {
        if let last = lastPlayed[sound], now.timeIntervalSince(last) < Self.interval { return false }
        lastPlayed[sound] = now
        return true
    }
}
