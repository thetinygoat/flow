import Foundation

/// What each terminal's coding agent is doing, built from the events `flw`
/// sends. Observers get `onChange` after every change.
@MainActor
final class AgentSessionStore {
    enum State: Equatable {
        case idle, working, waiting, ended
    }

    struct Session: Equatable {
        var agent: String
        var sessionID: String
        var state: State = .idle
        var detail: String?
        var attention: String?
        /// A short name for the conversation, once one has been made.
        var title: String?
        /// A turn ended and the user has not looked at the terminal since.
        var finishedUnseen = false
        var startedAt: Date
        var updatedAt: Date
    }

    /// One applied event, with the terminal's session before and after it.
    struct Update {
        var surface: UUID
        var kind: AgentEvent.Kind
        var previous: Session?
        var session: Session
    }

    private(set) var sessions: [UUID: Session] = [:]
    var onChange: (() -> Void)?
    var onUpdate: ((Update) -> Void)?
    private let isLive: (UUID) -> Bool
    private let isVisible: (UUID) -> Bool

    /// `isLive` tells whether a terminal with that id is open; events for any
    /// other id are dropped. `isVisible` tells whether the user is looking at
    /// it, in which case a finished turn is already seen.
    init(isLive: @escaping (UUID) -> Bool, isVisible: @escaping (UUID) -> Bool = { _ in false }) {
        self.isLive = isLive
        self.isVisible = isVisible
    }

    static let titleLimit = 160

    /// One line of at most `titleLimit` characters, or nil when nothing is left.
    static func sanitizedTitle(_ title: String?) -> String? {
        guard let line = title?.oneLine, !line.isEmpty else { return nil }
        return line.count > titleLimit ? line.prefix(titleLimit - 1) + "…" : line
    }

    func apply(_ event: AgentEvent) {
        guard event.kind != .unknown else {
            logger.notice("agent event of an unknown kind dropped")
            return
        }
        guard let surface = event.surfaceID, isLive(surface) else {
            logger.notice("agent event \(event.kind.rawValue, privacy: .public) dropped: no terminal \(event.surfaceID?.uuidString ?? "nil", privacy: .public)")
            return
        }
        if event.kind == .titleChanged {
            applyTitle(event, to: surface)
            return
        }
        let previous = sessions[surface]
        // Each hook reaches the socket in its own process, so a later hook can
        // overtake an earlier one.
        if let previous, event.kind != .sessionStarted, event.at < previous.updatedAt {
            logger.notice("agent event \(event.kind.rawValue, privacy: .public) ignored: older than the last one for terminal \(surface.uuidString, privacy: .public)")
            return
        }
        logger.notice("agent event \(event.kind.rawValue, privacy: .public) from \(event.agent, privacy: .public) for terminal \(surface.uuidString, privacy: .public)")

        // A session that ended, or was never announced, is started afresh by
        // whatever the agent says next, in case its sessionStarted was missed.
        var session = previous.flatMap { event.kind == .sessionStarted || $0.state == .ended ? nil : $0 }
            ?? Session(agent: event.agent, sessionID: event.sessionID, startedAt: event.at, updatedAt: event.at)
        if session.sessionID != event.sessionID {
            session.title = nil
        }
        session.agent = event.agent
        session.sessionID = event.sessionID
        session.updatedAt = event.at
        if event.kind != .attention {
            session.detail = event.detail
        }
        if let title = Self.sanitizedTitle(event.title) {
            session.title = title
        }

        switch event.kind {
        case .sessionStarted, .unknown, .titleChanged:
            break
        case .turnStarted, .working:
            session.state = .working
            session.finishedUnseen = false
        case .needsInput:
            session.state = .waiting
        case .turnEnded:
            session.state = .idle
            session.finishedUnseen = !isVisible(surface)
        case .sessionEnded:
            session.state = .ended
        case .attention:
            session.attention = event.detail
        }
        sessions[surface] = session
        onUpdate?(Update(surface: surface, kind: event.kind, previous: previous, session: session))
        onChange?()
    }

    /// A title is made in the background and arrives whenever it is ready, so
    /// it is not ordered against the session's other events, and names only
    /// the session it was made for.
    private func applyTitle(_ event: AgentEvent, to surface: UUID) {
        guard var session = sessions[surface], session.state != .ended,
              event.sessionID.isEmpty || event.sessionID == session.sessionID,
              let title = Self.sanitizedTitle(event.title), title != session.title else {
            logger.notice("agent title dropped for terminal \(surface.uuidString, privacy: .public)")
            return
        }
        session.title = title
        sessions[surface] = session
        logger.notice("agent event titleChanged from \(event.agent, privacy: .public) for terminal \(surface.uuidString, privacy: .public): \(title, privacy: .public)")
        onChange?()
    }

    /// Ended sessions have none.
    func title(for surface: UUID) -> String? {
        sessions[surface].flatMap { $0.state == .ended ? nil : $0.title }
    }

    func markSeen(_ surface: UUID) {
        guard var session = sessions[surface], session.finishedUnseen || session.attention != nil else { return }
        session.finishedUnseen = false
        session.attention = nil
        sessions[surface] = session
        onChange?()
    }

    func remove(_ surface: UUID) {
        guard sessions.removeValue(forKey: surface) != nil else { return }
        onChange?()
    }
}
