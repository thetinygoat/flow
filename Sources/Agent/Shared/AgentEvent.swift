import Foundation

/// What a coding agent running in a Flow terminal reports about itself. It
/// travels as one JSON object per line over the agent socket.
struct AgentEvent: Codable, Equatable {
    static let currentVersion = 1

    enum Kind: String, Codable {
        case sessionStarted, turnStarted, working, needsInput, turnEnded, sessionEnded, attention
        /// A kind from a newer `flw` than this app, which it can safely skip.
        case unknown

        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    var v = AgentEvent.currentVersion
    /// Shown to the user only; Flow never branches on it.
    var agent: String
    var kind: Kind
    var sessionID: String
    var surfaceID: UUID?
    var workspaceID: UUID?
    var cwd: String
    var at: Date
    /// The tool for `working`, the reason for `needsInput`, the last message
    /// for `turnEnded`, the message for `attention`.
    var detail: String?

    init(agent: String, kind: Kind, sessionID: String = "", surfaceID: UUID?, workspaceID: UUID?, cwd: String, at: Date, detail: String? = nil) {
        self.agent = agent
        self.kind = kind
        self.sessionID = sessionID
        self.surfaceID = surfaceID
        self.workspaceID = workspaceID
        self.cwd = cwd
        self.at = at
        self.detail = detail
    }

    /// Only `kind` is required, so hand-written events and older senders still get through.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decodeIfPresent(Int.self, forKey: .v) ?? Self.currentVersion
        agent = try container.decodeIfPresent(String.self, forKey: .agent) ?? ""
        kind = try container.decode(Kind.self, forKey: .kind)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        surfaceID = try container.decodeIfPresent(UUID.self, forKey: .surfaceID)
        workspaceID = try container.decodeIfPresent(UUID.self, forKey: .workspaceID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        at = try container.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    /// One line of the wire format, newline included.
    func line() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    init(line: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(Self.self, from: line)
    }
}
