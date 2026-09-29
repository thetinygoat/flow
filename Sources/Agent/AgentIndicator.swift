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
}
