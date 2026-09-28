import XCTest

final class AgentEnvironmentTests: XCTestCase {
    func testVariablesNameTheTerminalWorkspaceAndSocket() {
        let surface = UUID(), workspace = UUID()
        let socket = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("flow/agent.sock").path

        XCTAssertEqual(AgentEnvironment.variables(surface: surface, workspace: workspace, flw: "/Applications/Flow.app/Contents/Helpers/flw"), [
            "FLOW_SURFACE_ID": surface.uuidString,
            "FLOW_WORKSPACE_ID": workspace.uuidString,
            "FLOW_SOCKET": socket,
            "FLOW_FLW": "/Applications/Flow.app/Contents/Helpers/flw",
        ])
        XCTAssertTrue(socket.hasPrefix(NSHomeDirectory() + "/Library/Application Support/"))
    }

    func testShellIntegrationKeepsTheUsersDataDirsAndZdotdir() {
        let directory = "/Applications/Flow.app/Contents/Resources/shell-integration"

        XCTAssertEqual(ShellIntegration.environment(directory: directory, current: [:]), [
            "XDG_DATA_DIRS": directory + ":/usr/local/share:/usr/share",
            "ZDOTDIR": directory + "/zsh",
        ])
        XCTAssertEqual(ShellIntegration.environment(directory: directory, current: ["XDG_DATA_DIRS": "/opt/share", "ZDOTDIR": "/Users/me/.zsh"]), [
            "XDG_DATA_DIRS": directory + ":/opt/share",
            "ZDOTDIR": directory + "/zsh",
            "FLOW_ZSH_ZDOTDIR": "/Users/me/.zsh",
        ])
    }
}
