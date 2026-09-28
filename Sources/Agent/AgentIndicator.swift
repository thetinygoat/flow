import Foundation

/// The one mark shown for a group of terminals, such as a workspace or a tab.
/// Cases are ordered by how urgently they need the user.
enum AgentIndicator: Int, Comparable {
    case done, working, waiting

    /// Idle sessions the user has seen, and ended ones, show nothing.
    init?(_ session: AgentSessionStore.Session) {
        switch session.state {
        case .waiting: self = .waiting
        case .working: self = .working
        case .idle where session.finishedUnseen: self = .done
        case .idle, .ended: return nil
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension AgentSessionStore {
    func indicator(for surfaces: some Sequence<UUID>) -> AgentIndicator? {
        surfaces.compactMap { sessions[$0].flatMap(AgentIndicator.init) }.max()
    }

    /// The title of the session that needs the user most, or when none does,
    /// of the one that changed last. Ended sessions have none.
    func title(for surfaces: some Sequence<UUID>) -> String? {
        surfaces.compactMap { sessions[$0] }
            .filter { $0.state != .ended && $0.title != nil }
            .max { (urgency($0), $0.updatedAt) < (urgency($1), $1.updatedAt) }?
            .title
    }

    private func urgency(_ session: Session) -> Int {
        AgentIndicator(session).map { $0.rawValue + 1 } ?? 0
    }
}
