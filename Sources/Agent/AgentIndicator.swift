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

/// A terminal's indicator and when it took it.
struct AgentStatus: Equatable {
    var indicator: AgentIndicator
    var since: Date
}

extension AgentSessionStore {
    func status(of surface: UUID) -> AgentStatus? {
        guard let session = sessions[surface], let indicator = AgentIndicator(session) else { return nil }
        return AgentStatus(indicator: indicator, since: session.indicatorSince ?? session.updatedAt)
    }

    func indicator(for surfaces: some Sequence<UUID>) -> AgentIndicator? {
        var result: AgentIndicator?
        for surface in surfaces {
            guard let indicator = sessions[surface].flatMap(AgentIndicator.init) else { continue }
            result = max(result ?? indicator, indicator)
        }
        return result
    }
}
