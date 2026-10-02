import Foundation

/// What to tell the user when an agent in a terminal they are not looking at
/// needs them, finishes, or asks for their attention.
struct AgentNotification: Equatable {
    var title: String
    var body: String

    static let waitingBody = "Waiting for your input"
    static let finishedBody = "Finished"

    /// Reasons agents give for waiting, in words for people. Unlisted reasons
    /// get the generic body.
    static let waitingReasons = [
        "permission_prompt": "Needs permission",
        "permission": "Needs permission",
        "elicitation_dialog": "Has a question for you",
        "elicitation_url_dialog": "Needs you to open a link",
    ]

    static func make(for update: AgentSessionStore.Update, title: String, isVisible: Bool) -> AgentNotification? {
        guard !isVisible else { return nil }
        let session = update.session
        switch update.kind {
        case .needsInput:
            guard !update.repeatsWait else { return nil }
            return AgentNotification(title: title, body: session.detail.flatMap { waitingReasons[$0] } ?? waitingBody)
        case .turnEnded:
            return AgentNotification(title: title, body: session.detail.nonEmpty ?? finishedBody)
        case .attention:
            return session.attention.nonEmpty.map { AgentNotification(title: title, body: $0) }
        default:
            return nil
        }
    }
}

extension Optional<String> {
    var nonEmpty: String? {
        flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
}
