import XCTest

/// Hook input recorded from Claude Code 2.1.283.
enum ClaudeHookFixtures {
    static let sessionStart = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","hook_event_name":"SessionStart","source":"startup"}"#
    static let userPromptSubmit = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"f7775cc5-c1db-4737-8ed2-2d010c75f921","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"First run the shell command 'echo hi' with the Bash tool. Then use the Agent/Task tool to launch a general-purpose subagent that runs 'echo sub' with Bash. Then reply with the single word ok."}"#
    static let preToolUse = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"f7775cc5-c1db-4737-8ed2-2d010c75f921","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hi","description":"Echo hi to test bash tool"},"tool_use_id":"toolu_01Qh7rZi5PRxMyHKtJ554mnq"}"#
    static let postToolUse = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"f7775cc5-c1db-4737-8ed2-2d010c75f921","permission_mode":"default","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi","description":"Echo hi to test bash tool"},"tool_response":{"stdout":"hi","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_01Qh7rZi5PRxMyHKtJ554mnq","duration_ms":31}"#
    static let subagentPreToolUse = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"f7775cc5-c1db-4737-8ed2-2d010c75f921","permission_mode":"default","agent_id":"af40843b4cd16fa52","agent_type":"general-purpose","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo sub","description":"Run echo sub command"},"tool_use_id":"toolu_01BKzNHaTX38cP1a2Szfxivm"}"#
    static let subagentStop = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"f7775cc5-c1db-4737-8ed2-2d010c75f921","permission_mode":"default","agent_id":"af40843b4cd16fa52","agent_type":"general-purpose","hook_event_name":"SubagentStop","stop_hook_active":false,"agent_transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34/subagents/agent-af40843b4cd16fa52.jsonl","last_assistant_message":"The command `echo sub` executed successfully. The output is:\n\n```\nsub\n```","background_tasks":[{"id":"af40843b4cd16fa52","type":"subagent","status":"running","description":"Run echo sub command","agent_type":"general-purpose"}],"session_crons":[]}"#
    static let stop = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"f7775cc5-c1db-4737-8ed2-2d010c75f921","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"ok","background_tasks":[{"id":"af40843b4cd16fa52","type":"subagent","status":"running","description":"Run echo sub command","agent_type":"general-purpose"}],"session_crons":[]}"#
    static let stopWithoutMessage = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"1f4a6a5c-83ab-4093-a210-4c6eb238314e","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[],"session_crons":[]}"#
    static let sessionEnd = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","prompt_id":"1f4a6a5c-83ab-4093-a210-4c6eb238314e","hook_event_name":"SessionEnd","reason":"other"}"#

    // Print mode never notifies and the PushNotification tool is behind a
    // feature flag, so these follow the documented shape instead.
    static let permissionPrompt = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","transcript_path":"/Users/me/.claude/projects/-Users-me-project/62dfedaf-72b8-418a-a11c-30c406412c34.jsonl","cwd":"/Users/me/project","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}"#
    static let authSuccess = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","cwd":"/Users/me/project","hook_event_name":"Notification","message":"Authenticated","notification_type":"auth_success"}"#
    static let pushNotification = #"{"session_id":"62dfedaf-72b8-418a-a11c-30c406412c34","cwd":"/Users/me/project","hook_event_name":"PostToolUse","tool_name":"PushNotification","tool_input":{"message":"Build finished","status":"proactive"},"tool_response":{},"tool_use_id":"toolu_01"}"#
}

final class AgentAdapterTests: XCTestCase {
    func testNamesAreUniqueAndEveryAdapterHasABinary() {
        XCTAssertEqual(Set(AgentAdapter.all.map(\.name)).count, AgentAdapter.all.count)
        for adapter in AgentAdapter.all {
            XCTAssertFalse(adapter.binary.isEmpty, adapter.name)
            XCTAssertFalse(adapter.binary.contains("/"), adapter.name)
            XCTAssertEqual(AgentAdapter.named(adapter.name)?.binary, adapter.binary)
        }
        XCTAssertNil(AgentAdapter.named("nonexistent"))
    }
}

final class ClaudeCodeTests: XCTestCase {
    let surface = UUID(), workspace = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let session = "62dfedaf-72b8-418a-a11c-30c406412c34"

    func translate(_ json: String) throws -> AgentEvent? {
        let payload = try XCTUnwrap(HookPayload(
            json: Data(json.utf8), agent: "claude",
            environment: ["FLOW_SURFACE_ID": surface.uuidString, "FLOW_WORKSPACE_ID": workspace.uuidString], now: now
        ))
        return ClaudeCode.translate(payload)
    }

    func expected(_ kind: AgentEvent.Kind, _ detail: String? = nil) -> AgentEvent {
        AgentEvent(agent: "claude", kind: kind, sessionID: session, surfaceID: surface, workspaceID: workspace,
                   cwd: "/Users/me/project", at: now, detail: detail)
    }

    func testTranslatesTheSessionLifecycle() throws {
        XCTAssertEqual(try translate(ClaudeHookFixtures.sessionStart), expected(.sessionStarted))
        XCTAssertEqual(try translate(ClaudeHookFixtures.userPromptSubmit), expected(.turnStarted))
        XCTAssertEqual(try translate(ClaudeHookFixtures.preToolUse), expected(.working, "Bash"))
        XCTAssertEqual(try translate(ClaudeHookFixtures.postToolUse), expected(.working, "Bash"))
        XCTAssertEqual(try translate(ClaudeHookFixtures.stop), expected(.turnEnded, "ok"))
        XCTAssertEqual(try translate(ClaudeHookFixtures.stopWithoutMessage), expected(.turnEnded))
        XCTAssertEqual(try translate(ClaudeHookFixtures.sessionEnd), expected(.sessionEnded))
    }

    func testNotificationsThatWaitOnTheUserNeedInput() throws {
        XCTAssertEqual(try translate(ClaudeHookFixtures.permissionPrompt), expected(.needsInput, "permission_prompt"))
        for type in ["agent_needs_input", "elicitation_dialog", "elicitation_url_dialog"] {
            let json = ClaudeHookFixtures.permissionPrompt.replacingOccurrences(of: "permission_prompt", with: type)
            XCTAssertEqual(try translate(json), expected(.needsInput, type))
        }
        XCTAssertNil(try translate(ClaudeHookFixtures.authSuccess))
        XCTAssertNil(try translate(ClaudeHookFixtures.permissionPrompt.replacingOccurrences(of: "permission_prompt", with: "idle_prompt")))
    }

    func testPushNotificationAsksForAttention() throws {
        XCTAssertEqual(try translate(ClaudeHookFixtures.pushNotification), expected(.attention, "Build finished"))
    }

    func testDropsSubagentsAndEventsFlowDoesNotUse() throws {
        XCTAssertNil(try translate(ClaudeHookFixtures.subagentPreToolUse))
        XCTAssertNil(try translate(ClaudeHookFixtures.subagentStop))
        XCTAssertNil(try translate(#"{"session_id":"s","hook_event_name":"PreCompact"}"#))
        XCTAssertNil(try translate(#"{"session_id":"s"}"#))
    }

    func testTurnEndedDetailIsOneShortLine() throws {
        let long = String(repeating: "word ", count: 100)
        let json = ClaudeHookFixtures.stop.replacingOccurrences(of: #""last_assistant_message":"ok""#, with: #""last_assistant_message":"Done.\n\n\#(long)""#)
        let detail = try XCTUnwrap(try translate(json)?.detail)
        XCTAssertEqual(detail.count, ClaudeCode.detailLimit)
        XCTAssertTrue(detail.hasPrefix("Done. word word"))
        XCTAssertTrue(detail.hasSuffix("…"))
        XCTAssertFalse(detail.contains("\n"))
    }

    // MARK: Settings

    let flw = "/Applications/Flow Beta.app/Contents/Helpers/flw"

    func settings(in arguments: [String]) throws -> [String: Any] {
        XCTAssertEqual(arguments.filter { $0 == "--settings" }.count, 1)
        let index = try XCTUnwrap(arguments.firstIndex(of: "--settings"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(arguments[index + 1].utf8)) as? [String: Any])
    }

    func commands(_ settings: [String: Any], _ event: String) -> [String] {
        let entries = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return entries.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    func testAddsFlowsHooksAndSilencesClaudesNotifications() throws {
        let arguments = ClaudeCode.arguments(["-p", "hi"], flw: flw)
        XCTAssertEqual(Array(arguments.suffix(2)), ["-p", "hi"])
        let settings = try settings(in: arguments)

        XCTAssertEqual(settings["preferredNotifChannel"] as? String, "notifications_disabled")
        XCTAssertEqual(Set((settings["hooks"] as? [String: Any] ?? [:]).keys), Set(ClaudeCode.hookEvents))
        for event in ClaudeCode.hookEvents {
            XCTAssertEqual(commands(settings, event), ["'/Applications/Flow Beta.app/Contents/Helpers/flw' hook claude"])
        }
        let hook = try XCTUnwrap(((settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]).first
        XCTAssertEqual(hook?["type"] as? String, "command")
        XCTAssertEqual(hook?["async"] as? Bool, true)
    }

    func testMergesIntoTheUsersInlineSettings() throws {
        let user = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}],"PreCompact":[{"hooks":[{"type":"command","command":"true"}]}]}}"#
        let arguments = ClaudeCode.arguments(["--model", "haiku", "--settings", user, "-p", "hi"], flw: flw)
        XCTAssertEqual(Array(arguments.suffix(4)), ["--model", "haiku", "-p", "hi"])
        let settings = try settings(in: arguments)

        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertEqual(commands(settings, "Stop"), ["say done", "'\(flw)' hook claude"])
        XCTAssertEqual(commands(settings, "PreCompact"), ["true"])
        XCTAssertEqual(commands(settings, "SessionStart"), ["'\(flw)' hook claude"])
    }

    func testMergesTheUsersSettingsFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("flow-settings-\(UUID().uuidString).json")
        try Data(#"{"hooks":{"Notification":[{"matcher":"idle_prompt","hooks":[{"type":"command","command":"say idle"}]}]}}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let settings = try settings(in: ClaudeCode.arguments(["--settings=\(file.path)"], flw: flw))

        XCTAssertEqual(commands(settings, "Notification"), ["say idle", "'\(flw)' hook claude"])
    }

    func testLeavesSettingsItCannotReadForClaudeToReport() {
        XCTAssertEqual(ClaudeCode.arguments(["--settings", "/nonexistent.json"], flw: flw), ["--settings", "/nonexistent.json"])
        XCTAssertEqual(ClaudeCode.arguments(["--settings", "{not json"], flw: flw), ["--settings", "{not json"])
    }

    func testArgumentsAfterDoubleDashAreNotOptions() throws {
        let arguments = ClaudeCode.arguments(["--", "--settings", "x"], flw: flw)
        XCTAssertEqual(Array(arguments.suffix(3)), ["--", "--settings", "x"])
        XCTAssertEqual(arguments.count, 5)
    }
}

final class AgentLauncherTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeExecutable(_ directory: String, _ name: String, mode: Int = 0o755) throws -> String {
        let dir = root.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: file, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: mode])
        return file
    }

    func path(_ directories: String...) -> String {
        directories.map { root.appendingPathComponent($0).path }.joined(separator: ":")
    }

    func testResolvesPastTheShimDirectory() throws {
        try makeExecutable("shims", "claude")
        try makeExecutable("notexec", "claude", mode: 0o644)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dir/claude"), withIntermediateDirectories: true)
        let real = try makeExecutable("bin", "claude")
        let shims = root.appendingPathComponent("shims").path

        XCTAssertEqual(AgentLauncher.resolve("claude", path: path("shims", "notexec", "dir", "bin"), excluding: shims + "/"), real)
        XCTAssertEqual(AgentLauncher.resolve("claude", path: path("shims", "bin")), shims + "/claude")
        XCTAssertNil(AgentLauncher.resolve("claude", path: path("shims"), excluding: shims))
        XCTAssertNil(AgentLauncher.resolve("claude", path: nil))
    }

    func testRewritesArgumentsAndDropsTheShimVariable() throws {
        let real = try makeExecutable("bin", "claude")
        let shims = root.appendingPathComponent("shims").path
        let environment = ["PATH": shims + ":" + path("bin"), "FLOW_SHIM_DIR": shims, "HOME": "/Users/me"]

        let launcher = try XCTUnwrap(AgentLauncher(.claudeCode, arguments: ["-p", "hi"], environment: environment, flw: "/flw"))

        XCTAssertEqual(launcher.executable, real)
        XCTAssertEqual(launcher.arguments.first, "claude")
        XCTAssertEqual(launcher.arguments[1], "--settings")
        XCTAssertEqual(Array(launcher.arguments.suffix(2)), ["-p", "hi"])
        XCTAssertEqual(launcher.environment, ["PATH": environment["PATH"]!, "HOME": "/Users/me"])
    }

    func testOtherLaunchKinds() throws {
        let real = try makeExecutable("bin", "agent")
        let translate: (HookPayload) -> AgentEvent? = { _ in nil }
        let byEnvironment = AgentAdapter(name: "agent", binary: "agent", launch: .environment(["AGENT_HOOKS": "on"]), translate: translate)
        let untouched = AgentAdapter(name: "agent", binary: "agent", launch: .none, translate: translate)

        XCTAssertEqual(AgentLauncher(byEnvironment, arguments: ["x"], environment: ["PATH": path("bin")], flw: "/flw"),
                       AgentLauncher(untouched, arguments: ["x"], environment: ["PATH": path("bin"), "AGENT_HOOKS": "on"], flw: "/flw"))
        XCTAssertEqual(AgentLauncher(untouched, arguments: ["x"], environment: ["PATH": path("bin")], flw: "/flw")?.arguments, ["agent", "x"])
        XCTAssertEqual(AgentLauncher(untouched, arguments: [], environment: ["PATH": path("bin")], flw: "/flw")?.executable, real)
    }

    func testDisabledLaunchesAsTyped() throws {
        try makeExecutable("bin", "claude")
        let launcher = AgentLauncher(.claudeCode, arguments: ["-p", "hi"], environment: ["PATH": path("bin"), "FLOW_AGENTS_DISABLED": "1"], flw: "/flw")
        XCTAssertEqual(launcher?.arguments, ["claude", "-p", "hi"])
    }

    func testMissingBinaryIsNil() {
        XCTAssertNil(AgentLauncher(.claudeCode, arguments: [], environment: ["PATH": path("bin")], flw: "/flw"))
    }

    // MARK: Shims

    func testShimsFollowTheBinariesOnPath() throws {
        let shims = root.appendingPathComponent("shims").path
        let unrelated = try makeExecutable("shims", "codex")
        try makeExecutable("bin", "claude")
        let flw = "/Applications/Flow.app/Contents/Helpers/flw"

        try AgentShims.install(in: shims, path: shims + ":" + path("bin"), flw: flw)

        let shim = shims + "/claude"
        XCTAssertEqual(String(decoding: try Data(contentsOf: URL(fileURLWithPath: shim)), as: UTF8.self), """
            #!/bin/sh
            FLOW_SHIM_DIR='\(shims)' exec '\(flw)' launch claude "$@"

            """)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: shim)[.posixPermissions] as? Int, 0o755)

        try AgentShims.install(in: shims, path: shims + ":" + path("bin"), flw: flw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shim))

        try FileManager.default.removeItem(at: root.appendingPathComponent("bin"))
        try AgentShims.install(in: shims, path: shims + ":" + path("bin"), flw: flw)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shim))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated))
    }

    func testCreatesTheDirectoryPrivately() throws {
        let shims = root.appendingPathComponent("new/shims").path
        try AgentShims.install(in: shims, path: path("bin"), flw: "/flw")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: shims)[.posixPermissions] as? Int, 0o700)
    }

    func testRemovesShimDirectoriesOfClosedTerminals() throws {
        let live = UUID(), closed = UUID()
        for name in [live.uuidString, closed.uuidString, "not-a-terminal"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("flow-shims/\(name)"), withIntermediateDirectories: true)
        }

        AgentShims.removeStale(temporaryDirectory: root.path) { $0 == live }

        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("flow-shims").path)), [live.uuidString])
        XCTAssertEqual(AgentShims.directory(surface: live.uuidString, temporaryDirectory: root.path), root.path + "/flow-shims/" + live.uuidString)
    }
}
