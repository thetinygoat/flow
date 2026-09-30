import XCTest

final class AgentEventTests: XCTestCase {
    func testRoundTripsThroughOneLine() throws {
        let event = AgentEvent(
            agent: "test", kind: .needsInput, sessionID: "abc", surfaceID: UUID(), workspaceID: UUID(),
            cwd: "/tmp/project", at: Date(timeIntervalSince1970: 1_790_000_000), detail: "permission"
        )
        let line = try event.line()

        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        XCTAssertEqual(line.filter { $0 == UInt8(ascii: "\n") }.count, 1)
        XCTAssertEqual(try AgentEvent(line: line), event)
    }

    func testTimesTravelToTheMillisecond() throws {
        let event = AgentEvent(agent: "test", kind: .working, surfaceID: nil, workspaceID: nil, cwd: "/",
                               at: Date(timeIntervalSince1970: 1_790_000_000.125))
        let line = String(decoding: try event.line(), as: UTF8.self)

        XCTAssertTrue(line.contains(#""at":"2026-09-21T14:13:20.125Z""#), line)
        XCTAssertEqual(try AgentEvent(line: Data(line.utf8)).at.timeIntervalSince1970, 1_790_000_000.125, accuracy: 0.0005)
    }

    func testReadsWholeSecondTimes() throws {
        let event = try AgentEvent(line: Data(#"{"kind":"working","at":"2026-09-21T14:13:20Z"}"#.utf8))
        XCTAssertEqual(event.at, Date(timeIntervalSince1970: 1_790_000_000))
    }

    func testIgnoresUnknownFieldsAndFillsMissingOnes() throws {
        let surface = UUID()
        let json = #"{"v":1,"kind":"turnEnded","surfaceID":"\#(surface.uuidString)","at":"2026-09-28T10:00:00Z","extra":{"nested":true}}"#

        let event = try AgentEvent(line: Data(json.utf8))

        XCTAssertEqual(event.kind, .turnEnded)
        XCTAssertEqual(event.surfaceID, surface)
        XCTAssertEqual(event.agent, "")
        XCTAssertEqual(event.sessionID, "")
        XCTAssertNil(event.detail)
    }

    func testUnknownKindDecodesWithoutThrowing() throws {
        let event = try AgentEvent(line: Data(#"{"v":2,"kind":"somethingNew"}"#.utf8))
        XCTAssertEqual(event.kind, .unknown)
        XCTAssertEqual(event.v, 2)
    }

    func testRejectsLinesThatAreNotEvents() {
        XCTAssertThrowsError(try AgentEvent(line: Data("not json".utf8)))
        XCTAssertThrowsError(try AgentEvent(line: Data(#"{"agent":"x"}"#.utf8)))
    }
}

final class FlwCommandTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let surface = UUID(), workspace = UUID()

    func parse(_ arguments: [String], environment: [String: String]? = nil) throws -> FlwCommand {
        let environment = environment ?? [
            "FLOW_SURFACE_ID": surface.uuidString,
            "FLOW_WORKSPACE_ID": workspace.uuidString,
            "FLOW_SOCKET": "/tmp/flow.sock",
        ]
        return try FlwCommand.parse(arguments, environment: environment, currentDirectory: "/work", now: now)
    }

    func testEventDefaultsToTheTerminalItRunsIn() throws {
        XCTAssertEqual(try parse(["event", "turnEnded", "--agent", "test", "--detail", "hi"]), .event(AgentEvent(
            agent: "test", kind: .turnEnded, surfaceID: surface, workspaceID: workspace, cwd: "/work", at: now, detail: "hi"
        ), socket: "/tmp/flow.sock"))
    }

    func testOptionsOverrideTheEnvironment() throws {
        let other = UUID(), otherWorkspace = UUID()
        let command = try parse(["event", "working", "--surface", other.uuidString, "--workspace", otherWorkspace.uuidString,
                                 "--cwd", "/elsewhere", "--session", "s1"])
        XCTAssertEqual(command, .event(AgentEvent(
            agent: "", kind: .working, sessionID: "s1", surfaceID: other, workspaceID: otherWorkspace, cwd: "/elsewhere", at: now
        ), socket: "/tmp/flow.sock"))
    }

    func testOutsideFlowLeavesTheSocketToFindAndNoTerminal() throws {
        XCTAssertEqual(try parse(["ping"], environment: [:]), .ping(socket: nil))
        XCTAssertEqual(try parse(["ping"], environment: ["FLOW_SOCKET": ""]), .ping(socket: nil))
        guard case let .event(event, _) = try parse(["event", "attention"], environment: [:]) else { return XCTFail() }
        XCTAssertNil(event.surfaceID)
        XCTAssertNil(event.workspaceID)
    }

    func testRejectsBadEventArguments() {
        XCTAssertThrowsError(try parse(["event"]))
        XCTAssertThrowsError(try parse(["event", "unknown"]))
        XCTAssertThrowsError(try parse(["event", "finished"]))
        XCTAssertThrowsError(try parse(["event", "working", "--color", "red"]))
        XCTAssertThrowsError(try parse(["event", "working", "--detail"]))
        XCTAssertThrowsError(try parse(["event", "working", "--surface", "not-a-uuid"]))
    }

    func testAgentSubcommands() throws {
        XCTAssertEqual(try parse(["hook", "claude"]), .hook(adapter: "claude", socket: "/tmp/flow.sock"))
        XCTAssertEqual(try parse(["launch", "claude", "-p", "hi", "--"]), .launch(adapter: "claude", arguments: ["-p", "hi", "--"]))
        XCTAssertEqual(try parse(["shims", "/tmp/shims"]), .shims(directory: "/tmp/shims"))
        XCTAssertEqual(try parse(["hook"]), .usage)
        XCTAssertEqual(try parse(["launch"]), .usage)
        XCTAssertEqual(try parse(["shims"]), .usage)
        XCTAssertEqual(try parse(["agents"]), .usage)
    }

    func testRefreshPrintsTheSnippetForTheUsersShell() throws {
        guard case let .refreshAgents(posix) = try parse(["agents", "refresh"], environment: ["SHELL": "/bin/zsh"]),
              case let .refreshAgents(fish) = try parse(["agents", "refresh"], environment: ["SHELL": "/opt/homebrew/bin/fish"]) else {
            return XCTFail()
        }
        XCTAssertEqual(posix, #"""
            dir="${TMPDIR:-/tmp}/flow-shims/$FLOW_SURFACE_ID"
            "$FLOW_FLW" shims "$dir" && PATH="$dir:$PATH"
            """#)
        XCTAssertTrue(fish.contains(#""$FLOW_FLW" shims $dir; and set -gx --prepend PATH $dir"#))
    }

    func testAnythingElseShowsUsage() throws {
        XCTAssertEqual(try parse([]), .usage)
        XCTAssertEqual(try parse(["help"]), .usage)
        XCTAssertEqual(try parse(["frobnicate"]), .usage)
    }
}
