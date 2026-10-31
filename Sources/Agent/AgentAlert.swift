import Foundation

/// The sound and notification for an agent in a terminal the user is not
/// looking at, as they set them up in Settings: one choice for an agent that
/// needs them and one for an agent that has finished.
struct AgentAlert: Equatable {
    var sound: (kind: AgentSound, name: String)?
    var notification: AgentNotification?

    static func make(for update: AgentSessionStore.Update, title: String, isVisible: Bool, defaults: UserDefaults) -> AgentAlert {
        var alert = AgentAlert()
        if let sound = AgentSound.make(for: update, isVisible: isVisible),
           let name = defaults.string(forKey: soundPreference(sound)), !name.isEmpty {
            alert.sound = (sound, name)
        }
        if let kind = notificationKind(update.kind), defaults.bool(forKey: notificationPreference(kind)) {
            alert.notification = AgentNotification.make(for: update, title: title, isVisible: isVisible)
        }
        return alert
    }

    /// Asking for attention goes with finishing, as it does for sounds.
    private static func notificationKind(_ kind: AgentEvent.Kind) -> AgentSound? {
        switch kind {
        case .needsInput: .needsInput
        case .turnEnded, .attention: .finished
        case .launched, .sessionStarted, .turnStarted, .working, .sessionEnded, .unknown: nil
        }
    }

    static func soundPreference(_ sound: AgentSound) -> String {
        sound == .needsInput ? Preferences.needsInputSound : Preferences.finishedSound
    }

    private static func notificationPreference(_ sound: AgentSound) -> String {
        sound == .needsInput ? Preferences.needsInputNotification : Preferences.finishedNotification
    }

    static func == (lhs: AgentAlert, rhs: AgentAlert) -> Bool {
        lhs.sound?.kind == rhs.sound?.kind && lhs.sound?.name == rhs.sound?.name && lhs.notification == rhs.notification
    }
}
