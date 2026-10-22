import Foundation

/// The sound played when an agent in a terminal the user is not looking at
/// needs them or has finished.
enum AgentSound: Equatable, Hashable {
    case needsInput, finished

    /// The alert an event belongs to, which the user picks a sound and
    /// notifications for in Settings.
    init?(alerting kind: AgentEvent.Kind) {
        switch kind {
        case .needsInput: self = .needsInput
        case .turnEnded, .attention: self = .finished
        case .sessionStarted, .turnStarted, .working, .sessionEnded, .unknown: return nil
        }
    }

    var soundPreference: String {
        self == .needsInput ? Preferences.needsInputSound : Preferences.finishedSound
    }

    var notificationPreference: String {
        self == .needsInput ? Preferences.needsInputNotification : Preferences.finishedNotification
    }

    static func make(for update: AgentSessionStore.Update, isVisible: Bool) -> AgentSound? {
        switch update.kind {
        case .needsInput:
            isVisible || update.repeatsWait ? nil : .needsInput
        case .turnEnded:
            isVisible ? nil : .finished
        case .attention:
            isVisible || update.session.attention.nonEmpty == nil ? nil : .finished
        case .sessionStarted, .turnStarted, .working, .sessionEnded, .unknown:
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
