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

        /// A wait for the same reason the terminal was already waiting for,
        /// which the user has already been told about.
        var repeatsWait: Bool {
            kind == .needsInput && previous?.state == .waiting && previous?.detail == session.detail
        }
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

    func apply(_ event: AgentEvent) {
        guard event.kind != .unknown else {
            logger.notice("agent event of an unknown kind dropped")
            return
        }
        guard let surface = event.surfaceID, isLive(surface) else {
            logger.notice("agent event \(event.kind.rawValue, privacy: .public) dropped: no terminal \(event.surfaceID?.uuidString ?? "nil", privacy: .public)")
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
        session.agent = event.agent
        session.sessionID = event.sessionID
        session.updatedAt = event.at
        if event.kind != .attention {
            session.detail = event.detail
        }

        switch event.kind {
        case .sessionStarted, .unknown:
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
