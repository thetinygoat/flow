import Foundation

/// The sound played when an agent in a terminal the user is not looking at
/// needs them or has finished.
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
            isVisible || update.repeatsWait ? nil : .needsInput
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
