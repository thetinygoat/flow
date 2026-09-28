import XCTest

final class AgentEnvironmentTests: XCTestCase {
    func testVariablesNameTheTerminalWorkspaceAndSocket() {
        let surface = UUID(), workspace = UUID()
        let socket = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("flow/agent.sock").path

        XCTAssertEqual(AgentEnvironment.variables(surface: surface, workspace: workspace), [
            "FLOW_SURFACE_ID": surface.uuidString,
            "FLOW_WORKSPACE_ID": workspace.uuidString,
            "FLOW_SOCKET": socket,
        ])
        XCTAssertTrue(socket.hasPrefix(NSHomeDirectory() + "/Library/Application Support/"))
    }
}
