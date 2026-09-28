import XCTest

final class TitleContextTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func context(_ excerpts: [(Excerpt.Role, String)]) -> TitleContext {
        var context = TitleContext()
        excerpts.forEach { context.append(Excerpt(role: $0.0, text: $0.1)) }
        return context
    }

    func testKeepsTheFirstTwoUserMessagesAndTheLastFour() {
        let context = context([(.user, "u1"), (.assistant, "a1"), (.user, "u2"), (.assistant, "a2"), (.user, "u3"), (.assistant, "a3"), (.user, "u4")])
        XCTAssertEqual(context.first.map(\.text), ["u1", "u2"])
        XCTAssertEqual(context.recent.map(\.text), ["a2", "u3", "a3", "u4"])
        XCTAssertEqual(context.messageCount, 7)
        XCTAssertEqual(context.messages.map(\.text), ["u1", "u2", "a2", "u3", "a3", "u4"])
    }

    func testAMessageInBothListsIsShownOnce() {
        let context = context([(.user, "u1"), (.assistant, "a1")])
        XCTAssertEqual(context.messages.map(\.text), ["u1", "a1"])
    }

    func testMessagesAreOneShortLineAndBlankOnesAreSkipped() {
        let context = context([(.user, "Fix\n\n  this\u{7}  " + String(repeating: "x", count: 500)), (.assistant, " \n ")])
        XCTAssertEqual(context.messageCount, 1)
        XCTAssertEqual(context.first[0].text.count, TitleContext.messageLimit)
        XCTAssertTrue(context.first[0].text.hasPrefix("Fix this xxx"))
    }

    func testNamesOnceThereIsAPromptAndAReply() {
        XCTAssertFalse(context([]).shouldName(now: now))
        XCTAssertFalse(context([(.user, "hi")]).shouldName(now: now))
        XCTAssertFalse(context([(.assistant, "hi")]).shouldName(now: now))
        XCTAssertTrue(context([(.user, "hi"), (.assistant, "hello")]).shouldName(now: now))
    }

    func testNamesAgainOnlyAfterTheCooldownAndNewMessages() {
        var context = context([(.user, "hi"), (.assistant, "hello")])
        context.beginAttempt(now: now)
        context.inFlightSince = nil
        context.lastAttempt = now
        XCTAssertFalse(context.shouldName(now: now.addingTimeInterval(TitleContext.cooldown)))
        context.append(Excerpt(role: .user, text: "more"))
        XCTAssertFalse(context.shouldName(now: now.addingTimeInterval(TitleContext.cooldown - 1)))
        XCTAssertTrue(context.shouldName(now: now.addingTimeInterval(TitleContext.cooldown)))
    }

    func testARunInFlightHoldsOffOthersUntilItIsStale() {
        var context = context([(.user, "hi"), (.assistant, "hello")])
        context.beginAttempt(now: now)
        XCTAssertEqual(context.messageCountAtLastAttempt, 2)
        XCTAssertFalse(context.shouldName(now: now.addingTimeInterval(TitleContext.inFlightLimit - 1)))
        XCTAssertTrue(context.shouldName(now: now.addingTimeInterval(TitleContext.inFlightLimit)))
    }

    func testThePromptHoldsTheConversationAndTheCurrentTitle() {
        var context = context([(.user, "Fix the login"), (.assistant, "Fixed it")])
        XCTAssertTrue(context.prompt.contains("user: Fix the login\nassistant: Fixed it"))
        XCTAssertFalse(context.prompt.contains("Current title"))
        context.title = "Login fix"
        XCTAssertTrue(context.prompt.contains("Current title: Login fix"))
        XCTAssertTrue(context.prompt.hasSuffix("If the current title still fits, reply with it exactly."))
    }
}

final class TitleStoreTests: XCTestCase {
    var store: TitleStore!
    let surface = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        store = TitleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("flow-titles-\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.directory)
    }

    func event(_ kind: AgentEvent.Kind, session: String = "s1") -> AgentEvent {
        AgentEvent(agent: "claude", kind: kind, sessionID: session, surfaceID: surface, workspaceID: nil, cwd: "/", at: now)
    }

    func stored(_ session: String = "s1") -> TitleContext? {
        store.update(agent: "claude", session: session, create: false) { $0 }
    }

    func testKeepsExcerptsPrivatelyAndNamesAtTheEndOfATurn() throws {
        XCTAssertFalse(store.record(event(.turnStarted), excerpts: [Excerpt(role: .user, text: "Fix the login")], now: now))
        let url = try XCTUnwrap(store.url(agent: "claude", session: "s1"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        let directory = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(directory[.posixPermissions] as? Int, 0o700)

        XCTAssertTrue(store.record(event(.turnEnded), excerpts: [Excerpt(role: .assistant, text: "Fixed")], now: now))
        XCTAssertEqual(stored()?.inFlightSince, now)
        XCTAssertFalse(store.record(event(.turnEnded), excerpts: [], now: now.addingTimeInterval(1)))
    }

    func testEventsWithoutExcerptsWriteNothing() throws {
        XCTAssertFalse(store.record(event(.working), excerpts: [], now: now))
        XCTAssertNil(stored())
    }

    func testTheContextGoesWhenTheSessionEnds() throws {
        _ = store.record(event(.turnStarted), excerpts: [Excerpt(role: .user, text: "hi")], now: now)
        XCTAssertNotNil(stored())
        XCTAssertFalse(store.record(event(.sessionEnded), excerpts: [], now: now))
        XCTAssertNil(stored())
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.url(agent: "claude", session: "s1")).path))
    }

    func testAStartedSessionIsNamedAgainAfterItsNextTurn() {
        _ = store.record(event(.turnStarted), excerpts: [Excerpt(role: .user, text: "hi")], now: now)
        store.update(agent: "claude", session: "s1") { context in
            context.title = "Old"
            context.lastAttempt = self.now
        }
        _ = store.record(event(.sessionStarted), excerpts: [], now: now)
        XCTAssertNil(stored()?.title)
        XCTAssertTrue(store.record(event(.turnEnded), excerpts: [Excerpt(role: .assistant, text: "hello")], now: now.addingTimeInterval(1)))
    }

    func testANewSessionClearsOutContextsLeftForAWeek() throws {
        _ = store.record(event(.turnStarted, session: "old"), excerpts: [Excerpt(role: .user, text: "hi")], now: now)
        _ = store.record(event(.turnStarted, session: "recent"), excerpts: [Excerpt(role: .user, text: "hi")], now: now)
        let old = try XCTUnwrap(store.url(agent: "claude", session: "old"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-TitleStore.staleAge - 60)], ofItemAtPath: old.path)
        _ = store.record(event(.turnStarted, session: "new"), excerpts: [Excerpt(role: .user, text: "hi")], now: now)
        XCTAssertNil(stored("old"))
        XCTAssertNotNil(stored("recent"))
        XCTAssertNotNil(stored("new"))
    }

    func testUnsafeNamesAreNotFiles() {
        XCTAssertNil(store.url(agent: "claude", session: "../escape"))
        XCTAssertNil(store.url(agent: "claude", session: ".hidden"))
        XCTAssertNil(store.url(agent: "", session: "s1"))
        XCTAssertFalse(store.record(event(.turnEnded, session: "a/b"), excerpts: [Excerpt(role: .user, text: "hi")], now: now))
    }

    func testEventsOutsideAFlowTerminalAreNotKept() {
        let event = AgentEvent(agent: "claude", kind: .turnStarted, sessionID: "s1", surfaceID: nil, workspaceID: nil, cwd: "/", at: now)
        XCTAssertFalse(store.record(event, excerpts: [Excerpt(role: .user, text: "hi")], now: now))
        XCTAssertNil(stored())
    }
}

final class TitleReplyTests: XCTestCase {
    func clean(_ reply: String, current: String? = nil) -> String? {
        TitleReply.clean(reply, current: current)
    }

    func testStripsQuotesAndMarkdown() {
        XCTAssertEqual(clean(#""Fix login redirect""#), "Fix login redirect")
        XCTAssertEqual(clean("“Fix login redirect”"), "Fix login redirect")
        XCTAssertEqual(clean("**Fix login redirect**"), "Fix login redirect")
        XCTAssertEqual(clean("# Fix login redirect"), "Fix login redirect")
        XCTAssertEqual(clean("- `Fix login redirect`."), "Fix login redirect")
        XCTAssertEqual(clean("Title: Fix login redirect"), "Fix login redirect")
    }

    func testTakesTheFirstLineAndCollapsesSpace() {
        XCTAssertEqual(clean("\n\n  Fix   login\tredirect  \nThis title captures the work."), "Fix login redirect")
    }

    func testCutsLongTitlesAtAWord() throws {
        let title = try XCTUnwrap(clean("Investigate the intermittent authentication failures in the staging login redirect"))
        XCTAssertLessThanOrEqual(title.count, TitleReply.limit)
        XCTAssertEqual(title, "Investigate the intermittent authentication")
        XCTAssertEqual(clean(String(repeating: "x", count: 80))?.count, TitleReply.limit)
    }

    func testNothingNewIsNil() {
        XCTAssertNil(clean(""))
        XCTAssertNil(clean("  \n ** \n"))
        XCTAssertNil(clean("Fix login redirect", current: "Fix login redirect"))
        XCTAssertNil(clean(#""Fix login redirect""#, current: "Fix login redirect"))
        XCTAssertEqual(clean("Fix login redirect", current: "Login"), "Fix login redirect")
    }
}

final class AgentExcerptTests: XCTestCase {
    func excerpt(_ adapter: AgentAdapter, _ json: String) throws -> Excerpt? {
        let payload = try XCTUnwrap(HookPayload(json: Data(json.utf8), agent: adapter.name, environment: [:], now: Date()))
        return adapter.excerpt(payload)
    }

    func testClaudeCodeGivesThePromptAndTheReply() throws {
        XCTAssertEqual(try excerpt(.claudeCode, ClaudeHookFixtures.userPromptSubmit)?.role, .user)
        XCTAssertTrue(try excerpt(.claudeCode, ClaudeHookFixtures.userPromptSubmit)?.text.hasPrefix("First run the shell command 'echo hi'") == true)
        XCTAssertEqual(try excerpt(.claudeCode, ClaudeHookFixtures.stop), Excerpt(role: .assistant, text: "ok"))
        XCTAssertNil(try excerpt(.claudeCode, ClaudeHookFixtures.stopWithoutMessage))
        XCTAssertNil(try excerpt(.claudeCode, ClaudeHookFixtures.subagentStop))
        XCTAssertNil(try excerpt(.claudeCode, ClaudeHookFixtures.preToolUse))
        XCTAssertNil(try excerpt(.claudeCode, ClaudeHookFixtures.sessionStart))
    }

    func testCodexGivesThePromptAndTheReply() throws {
        XCTAssertEqual(try excerpt(.codex, CodexHookFixtures.userPromptSubmit),
                       Excerpt(role: .user, text: "Create a file named made.txt containing hi, using the shell command: echo hi > made.txt"))
        XCTAssertEqual(try excerpt(.codex, CodexHookFixtures.stop), Excerpt(role: .assistant, text: "ok"))
        XCTAssertNil(try excerpt(.codex, CodexHookFixtures.subagentStop))
        XCTAssertNil(try excerpt(.codex, CodexHookFixtures.interrupt))
    }

    func testOpenCodeSendsItsOwn() throws {
        XCTAssertNil(try excerpt(.openCode, ClaudeHookFixtures.userPromptSubmit))
    }
}

final class SummarizerTests: XCTestCase {
    func arguments(_ adapter: AgentAdapter, environment: [String: String] = [:]) -> [String] {
        adapter.summarizer.arguments(replyFile: "/tmp/reply", environment: environment)
    }

    func value(of option: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: option).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }

    func testClaudeCodeUsesItsSmallModelAndNothingElse() {
        let arguments = arguments(.claudeCode)
        XCTAssertEqual(arguments.first, "-p")
        XCTAssertEqual(value(of: "--model", in: arguments), "haiku")
        XCTAssertEqual(value(of: "--tools", in: arguments), "")
        XCTAssertEqual(value(of: "--settings", in: arguments), #"{"disableAllHooks":true}"#)
        for flag in ["--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"] {
            XCTAssertTrue(arguments.contains(flag), flag)
        }
        XCTAssertFalse(arguments.contains("/tmp/reply"))
        XCTAssertEqual(value(of: "--model", in: self.arguments(.claudeCode, environment: ["ANTHROPIC_SMALL_FAST_MODEL": "claude-x"])), "claude-x")
    }

    func testCodexRunsWithoutToolsAndWritesItsReplyToAFile() {
        let arguments = arguments(.codex)
        XCTAssertEqual(arguments.first, "exec")
        for flag in ["--ephemeral", "--skip-git-repo-check", "--ignore-rules"] {
            XCTAssertTrue(arguments.contains(flag), flag)
        }
        XCTAssertEqual(value(of: "--sandbox", in: arguments), "read-only")
        let overrides = arguments.indices.filter { arguments[$0] == "-c" }.map { arguments[$0 + 1] }
        XCTAssertEqual(Set(overrides), [#"approval_policy="never""#, #"web_search="disabled""#, "mcp_servers={}"])
        let disabled = Set(arguments.indices.filter { arguments[$0] == "--disable" }.map { arguments[$0 + 1] })
        XCTAssertTrue(disabled.isSuperset(of: ["shell_tool", "unified_exec", "apps", "plugins", "hooks"]))
        XCTAssertEqual(value(of: "--output-last-message", in: arguments), "/tmp/reply")
        XCTAssertFalse(arguments.contains("--model") || arguments.contains("-m"))
    }

    func testOpenCodeRunsPure() {
        let arguments = arguments(.openCode)
        XCTAssertEqual(Array(arguments.prefix(2)), ["run", "--pure"])
        XCTAssertEqual(value(of: "--format", in: arguments), "default")
        XCTAssertFalse(arguments.contains("--model") || arguments.contains("-m"))
    }

    func testTheEnvironmentKeepsNothingOfFlow() {
        let environment = [
            "PATH": "/tmp/flow-shims/\(UUID().uuidString):/usr/bin:/bin", "HOME": "/Users/me", "LANG": "en_US.UTF-8",
            "FLOW_SURFACE_ID": UUID().uuidString, "FLOW_WORKSPACE_ID": UUID().uuidString, "FLOW_SOCKET": "/tmp/s", "FLOW_FLW": "/x/flw",
            "OPENCODE_CONFIG_CONTENT": "{}", "CODEX_HOME": "/Users/me/.codex", "XDG_CONFIG_HOME": "/Users/me/.config", "SECRET": "x",
        ]
        XCTAssertEqual(Codex.summarizer.environment(from: environment), [
            "PATH": "/usr/bin:/bin", "HOME": "/Users/me", "LANG": "en_US.UTF-8", "CODEX_HOME": "/Users/me/.codex", "FLOW_AGENTS_DISABLED": "1",
        ])
        let openCode = OpenCode.summarizer.environment(from: environment)
        XCTAssertEqual(openCode["XDG_CONFIG_HOME"], "/Users/me/.config")
        XCTAssertNil(openCode["OPENCODE_CONFIG_CONTENT"])
        XCTAssertFalse(openCode.keys.contains { $0.hasPrefix("FLOW_") && $0 != "FLOW_AGENTS_DISABLED" })
    }
}
