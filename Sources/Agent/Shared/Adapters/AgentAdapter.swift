import Foundation

/// Everything Flow knows about one coding agent: how to start it so that it
/// reports to Flow, and how to read what its hooks report. Supporting another
/// agent means adding a value to `all`; the shims, the shell integration and
/// `flw` itself stay the same.
struct AgentAdapter {
    enum Launch {
        /// Rewrites the arguments the user typed. `flw` is the path of the
        /// running helper, for hooks to call back into.
        case flags((_ arguments: [String], _ flw: String) -> [String])
        /// Returns variables to set over the environment the user's shell passed.
        case environment((_ environment: [String: String], _ flw: String) -> [String: String])
        case none
    }

    /// Also the label Flow shows for the agent.
    let name: String
    /// The executable looked up on PATH.
    let binary: String
    let launch: Launch
    /// Returns nil for hook calls Flow has no use for.
    let translate: (HookPayload) -> AgentEvent?

    static let all: [AgentAdapter] = [.claudeCode, .openCode, .codex]

    static func named(_ name: String) -> AgentAdapter? {
        all.first { $0.name == name }
    }
}

/// The JSON object an agent hands its hook on stdin, together with the Flow
/// terminal the hook runs in.
struct HookPayload {
    static let detailLimit = 200

    let fields: [String: Any]
    let agent: String
    let surfaceID: UUID?
    let workspaceID: UUID?
    let at: Date

    init?(json: Data, agent: String, environment: [String: String], now: Date) {
        guard let fields = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        self.fields = fields
        self.agent = agent
        surfaceID = environment[AgentEnvironment.surfaceKey].flatMap(UUID.init)
        workspaceID = environment[AgentEnvironment.workspaceKey].flatMap(UUID.init)
        at = now
    }

    func string(_ key: String) -> String? {
        fields[key] as? String
    }

    /// A message field as one line short enough to show beside a workspace.
    func summary(_ key: String) -> String? {
        string(key).map { message in
            let line = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return line.count > Self.detailLimit ? line.prefix(Self.detailLimit - 1) + "…" : line
        }
    }

    func object(_ key: String) -> [String: Any]? {
        fields[key] as? [String: Any]
    }

    func event(_ kind: AgentEvent.Kind, sessionID: String, cwd: String, detail: String? = nil) -> AgentEvent {
        AgentEvent(agent: agent, kind: kind, sessionID: sessionID, surfaceID: surfaceID, workspaceID: workspaceID, cwd: cwd, at: at, detail: detail)
    }
}

extension String {
    /// The string as one word for `sh`, whatever it contains.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
