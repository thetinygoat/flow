import XCTest

final class AgentEnvironmentTests: XCTestCase {
    func testVariablesNameTheTerminalWorkspaceAndSocket() {
        let surface = UUID(), workspace = UUID()

        XCTAssertEqual(AgentEnvironment.variables(surface: surface, workspace: workspace, socket: "/tmp/agent.1.sock",
                                                  flw: "/Applications/Flow.app/Contents/Helpers/flw", shims: "/tmp/flow-shims/1"), [
            "FLOW_SURFACE_ID": surface.uuidString,
            "FLOW_WORKSPACE_ID": workspace.uuidString,
            "FLOW_SOCKET": "/tmp/agent.1.sock",
            "FLOW_FLW": "/Applications/Flow.app/Contents/Helpers/flw",
            "FLOW_SHIMS": "/tmp/flow-shims/1",
        ])
    }

    func testEachFlowHasItsOwnShims() {
        XCTAssertEqual(AgentShims.root(temporaryDirectory: "/tmp/"), "/tmp/flow-shims/\(getpid())")
        XCTAssertEqual(AgentShims.root(), (NSTemporaryDirectory() as NSString).appendingPathComponent("flow-shims/\(getpid())"))
    }

    func testEachFlowHasItsOwnSocket() {
        let socket = AgentEnvironment.socketURL().path
        XCTAssertEqual(socket, NSHomeDirectory() + "/Library/Application Support/flow/agent.\(getpid()).sock")
        XCTAssertNotEqual(AgentEnvironment.socketURL(pid: 1), AgentEnvironment.socketURL())
    }

    func testFindsTheNewestSocketOfARunningFlow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flow-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(AgentEnvironment.newestRunningSocket(in: directory))

        let live = AgentEnvironment.socketURL(pid: getpid(), in: directory)
        let alsoLive = AgentEnvironment.socketURL(pid: 1, in: directory)
        let dead = AgentEnvironment.socketURL(pid: deadPID(), in: directory)
        for (url, age) in [(live, 20.0), (alsoLive, 10.0), (dead, 0.0)] {
            try Data().write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        try Data().write(to: directory.appendingPathComponent("agent.sock"))
        try Data().write(to: directory.appendingPathComponent("agent.x.sock"))

        XCTAssertEqual(Set(AgentEnvironment.sockets(in: directory).map(\.url)), [live, alsoLive, dead])
        XCTAssertEqual(AgentEnvironment.newestRunningSocket(in: directory), alsoLive)
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

/// A pid no process has, found by starting one and waiting for it to exit.
func deadPID() -> pid_t {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try? process.run()
    process.waitUntilExit()
    return process.processIdentifier
}
