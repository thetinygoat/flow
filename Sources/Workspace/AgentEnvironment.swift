import Foundation

/// Variables every shell Flow starts inherits, so that coding agents and the
/// hooks they run can tell Flow which terminal they are in and reach it.
enum AgentEnvironment {
    static let socketURL = Session.fileURL.deletingLastPathComponent().appendingPathComponent("agent.sock")

    static func variables(surface: UUID, workspace: UUID) -> [String: String] {
        [
            "FLOW_SURFACE_ID": surface.uuidString,
            "FLOW_WORKSPACE_ID": workspace.uuidString,
            "FLOW_SOCKET": socketURL.path,
        ]
    }
}
