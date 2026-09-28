import Foundation

/// Variables every shell Flow starts inherits, so that coding agents and the
/// hooks they run can tell Flow which terminal they are in and reach it.
enum AgentEnvironment {
    static let surfaceKey = "FLOW_SURFACE_ID"
    static let workspaceKey = "FLOW_WORKSPACE_ID"
    static let socketKey = "FLOW_SOCKET"

    static let socketURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("flow", isDirectory: true)
        .appendingPathComponent("agent.sock")

    static func variables(surface: UUID, workspace: UUID) -> [String: String] {
        [
            surfaceKey: surface.uuidString,
            workspaceKey: workspace.uuidString,
            socketKey: socketURL.path,
        ]
    }
}
