import Foundation

/// Variables every shell Flow starts inherits, so that coding agents and the
/// hooks they run can tell Flow which terminal they are in and reach it.
enum AgentEnvironment {
    static let surfaceKey = "FLOW_SURFACE_ID"
    static let workspaceKey = "FLOW_WORKSPACE_ID"
    static let socketKey = "FLOW_SOCKET"
    /// The `flw` inside the app, for the shell integration to call.
    static let flwKey = "FLOW_FLW"
    /// Set by the user to start agents exactly as typed.
    static let disabledKey = "FLOW_AGENTS_DISABLED"
    /// Set by a shim, so `flw launch` can look for the real binary past it.
    static let shimDirectoryKey = "FLOW_SHIM_DIR"

    static let socketURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("flow", isDirectory: true)
        .appendingPathComponent("agent.sock")

    static func variables(surface: UUID, workspace: UUID, flw: String) -> [String: String] {
        [
            surfaceKey: surface.uuidString,
            workspaceKey: workspace.uuidString,
            socketKey: socketURL.path,
            flwKey: flw,
        ]
    }
}
