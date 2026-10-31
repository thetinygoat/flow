import XCTest

@MainActor
final class AgentSessionStoreTests: XCTestCase {
    let surface = UUID()
    var store: AgentSessionStore!
    var changes = 0
    var visible = false
    var updates: [AgentSessionStore.Update] = []

    override func setUp() async throws {
        let live = surface
        store = AgentSessionStore(isLive: { $0 == live }, isVisible: { [unowned self] _ in self.visible })
        store.onChange = { [unowned self] _ in self.changes += 1 }
        store.onUpdate = { [unowned self] in self.updates.append($0) }
    }

    func send(_ kind: AgentEvent.Kind, detail: String? = nil, session: String = "s1", to surface: UUID? = nil, at: Date = Date(),
              agent: String = "test") {
        store.apply(AgentEvent(agent: agent, kind: kind, sessionID: session, surfaceID: surface ?? self.surface,
                               workspaceID: nil, cwd: "/", at: at, detail: detail))
    }

    var session: AgentSessionStore.Session? { store.sessions[surface] }

    func testATurnGoesFromIdleToWorkingAndBack() {
        send(.sessionStarted)
        XCTAssertEqual(session?.state, .idle)
        send(.turnStarted)
        XCTAssertEqual(session?.state, .working)
        send(.working, detail: "Bash")
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.detail, "Bash")
        send(.turnEnded, detail: "done")
        XCTAssertEqual(session?.state, .idle)
        XCTAssertEqual(session?.detail, "done")
    }

    func testWaitingForInputAndResuming() {
        send(.turnStarted)
        send(.needsInput, detail: "permission")
        XCTAssertEqual(session?.state, .waiting)
        XCTAssertEqual(session?.detail, "permission")
        send(.working)
        XCTAssertEqual(session?.state, .working)
        send(.needsInput)
        send(.turnStarted)
        XCTAssertEqual(session?.state, .working)
        send(.needsInput)
        send(.turnEnded)
        XCTAssertEqual(session?.state, .idle)
    }

    func testStatusSinceIsWhenTheIndicatorLastChanged() {
        let start = Date()
        send(.turnStarted, at: start)
        XCTAssertEqual(store.status(of: surface), AgentStatus(indicator: .working, since: start))
        send(.working, detail: "Bash", at: start + 1)
        XCTAssertEqual(store.status(of: surface)?.since, start)
        send(.needsInput, detail: "permission", at: start + 2)
        send(.needsInput, detail: "another", at: start + 3)
        send(.attention, detail: "ping", at: start + 4)
        XCTAssertEqual(store.status(of: surface), AgentStatus(indicator: .waiting, since: start + 2))
        send(.turnEnded, at: start + 5)
        XCTAssertEqual(store.status(of: surface), AgentStatus(indicator: .done, since: start + 5))
        store.markSeen(surface)
        XCTAssertNil(session?.indicatorSince)
        XCTAssertNil(store.status(of: surface))
    }

    func testANewSessionStartsItsOwnWait() {
        let start = Date()
        send(.needsInput, at: start)
        send(.sessionStarted, session: "s2", at: start + 1)
        XCTAssertNil(session?.indicatorSince)
        send(.needsInput, session: "s2", at: start + 2)
        XCTAssertEqual(store.status(of: surface)?.since, start + 2)
    }

    func testIdleSessionsHaveNoStatus() {
        send(.sessionStarted)
        XCTAssertNil(store.status(of: surface))
        visible = true
        send(.turnStarted)
        send(.turnEnded)
        XCTAssertNil(store.status(of: surface))
    }

    func testWorkingWhileIdleMeansTheTurnStartWasMissed() {
        send(.sessionStarted)
        send(.working)
        XCTAssertEqual(session?.state, .working)
    }

    func testAnyStateCanEnd() {
        for lead in [[], [AgentEvent.Kind.turnStarted], [.turnStarted, .needsInput]] {
            send(.sessionStarted)
            lead.forEach { send($0) }
            send(.sessionEnded)
            XCTAssertEqual(session?.state, .ended)
        }
    }

    func testTheRunningAgentIsNamedUntilItsSessionEnds() {
        XCTAssertNil(store.runningAgent(in: surface))
        send(.sessionStarted, agent: "claude")
        XCTAssertEqual(store.runningAgent(in: surface), "claude")
        send(.sessionEnded, agent: "claude")
        XCTAssertNil(store.runningAgent(in: surface))
    }

    func testTheAgentsOwnStartTakesOverFromItsLaunch() {
        let launch = Date(timeIntervalSince1970: 1)
        send(.launched, session: "", at: launch, agent: "codex")
        XCTAssertEqual(store.runningAgent(in: surface), "codex")
        XCTAssertNil(store.status(of: surface), "no dot until the agent does something")
        send(.sessionStarted, session: "s1", at: launch.addingTimeInterval(1), agent: "codex")
        send(.turnStarted, session: "s1", at: launch.addingTimeInterval(2), agent: "codex")
        XCTAssertEqual(session?.sessionID, "s1")
        XCTAssertEqual(session?.state, .working)
    }

    func testALaunchOvertakenByTheAgentsOwnStartIsIgnored() {
        let launch = Date(timeIntervalSince1970: 1)
        send(.sessionStarted, session: "s1", at: launch.addingTimeInterval(1), agent: "claude")
        send(.turnStarted, session: "s1", at: launch.addingTimeInterval(2), agent: "claude")
        send(.launched, session: "", at: launch, agent: "claude")
        XCTAssertEqual(session?.sessionID, "s1")
        XCTAssertEqual(session?.state, .working)
    }

    func testALaunchReplacesASessionThatNeverSaidItEnded() {
        send(.turnStarted, session: "s1", at: Date(timeIntervalSince1970: 1), agent: "claude")
        send(.launched, session: "", at: Date(timeIntervalSince1970: 2), agent: "codex")
        XCTAssertEqual(store.runningAgent(in: surface), "codex")
        XCTAssertEqual(session?.state, .idle)
    }

    func testTheSessionEndsWhenTheShellGetsItsPromptBack() {
        store.endSession(in: surface, at: Date())
        XCTAssertNil(session)
        send(.launched, session: "", agent: "codex")
        store.endSession(in: surface, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(session?.state, .ended, "even with a clock behind the session's")
        XCTAssertNil(store.runningAgent(in: surface))
    }

    func testAttentionRecordsAMessageWithoutChangingState() {
        send(.turnStarted, detail: "Read")
        send(.attention, detail: "look here")
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.attention, "look here")
        XCTAssertEqual(session?.detail, "Read")
    }

    func testSessionStartedReplacesThePreviousSession() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 2)
        send(.sessionStarted, session: "old", at: early)
        send(.turnStarted, session: "old", at: early)
        send(.attention, detail: "old news", session: "old", at: early)
        send(.sessionStarted, session: "new", at: late)
        XCTAssertEqual(session, AgentSessionStore.Session(agent: "test", sessionID: "new", startedAt: late, updatedAt: late))
    }

    func testAFinishedTurnStaysUnseenUntilMarkedSeen() {
        send(.turnStarted)
        send(.turnEnded)
        XCTAssertEqual(session?.finishedUnseen, true)
        send(.attention, detail: "hey")
        store.markSeen(surface)
        XCTAssertEqual(session?.finishedUnseen, false)
        XCTAssertNil(session?.attention)
        send(.turnEnded)
        send(.turnStarted)
        XCTAssertEqual(session?.finishedUnseen, false)
    }

    func testEventsForUnknownTerminalsAreDropped() {
        send(.turnStarted, to: UUID())
        store.apply(AgentEvent(agent: "test", kind: .turnStarted, surfaceID: nil, workspaceID: nil, cwd: "/", at: Date()))
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(changes, 0)
    }

    func testUnknownKindsAreDropped() {
        send(.unknown)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testATurnEndingInFrontOfTheUserIsAlreadySeen() {
        visible = true
        send(.turnStarted)
        send(.turnEnded)
        XCTAssertEqual(session?.finishedUnseen, false)
        XCTAssertNil(session.flatMap(AgentIndicator.init))
    }

    func testMarkingSeenClearsTheDoneIndicator() {
        send(.turnStarted)
        send(.turnEnded)
        XCTAssertEqual(store.indicator(for: [surface]), .done)
        store.markSeen(surface)
        XCTAssertNil(store.indicator(for: [surface]))
    }

    func testUpdatesCarryThePreviousSession() {
        send(.turnStarted)
        send(.needsInput, detail: "permission_prompt")
        XCTAssertEqual(updates.last?.kind, .needsInput)
        XCTAssertEqual(updates.last?.previous?.state, .working)
        XCTAssertEqual(updates.last?.session.state, .waiting)
    }

    func testRemoveDropsTheSession() {
        send(.turnStarted)
        let before = changes
        store.remove(surface)
        XCTAssertNil(session)
        XCTAssertEqual(changes, before)
        store.remove(surface)
        XCTAssertEqual(changes, before)
    }

    func testAnEventOlderThanTheLastOneIsIgnored() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 1.5)
        send(.turnEnded, detail: "done", at: late)
        let before = changes
        send(.needsInput, detail: "permission_prompt", at: early)
        XCTAssertEqual(session?.state, .idle)
        XCTAssertEqual(session?.detail, "done")
        XCTAssertEqual(changes, before)
    }

    func testEventsAtTheSameTimeApplyInArrivalOrder() {
        let now = Date(timeIntervalSince1970: 1)
        send(.turnStarted, at: now)
        send(.turnEnded, at: now)
        XCTAssertEqual(session?.state, .idle)
        send(.turnStarted, at: now)
        XCTAssertEqual(session?.state, .working)
    }

    func testAStartOfTheLiveSessionKeepsItGoingWhateverItsTime() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 2)
        for startedAt in [early, late] {
            store.remove(surface)
            send(.sessionStarted, at: early)
            send(.turnStarted, at: early)
            send(.working, detail: "Bash", at: early)
            send(.sessionStarted, at: startedAt)
            XCTAssertEqual(session?.state, .working)
            XCTAssertEqual(session?.detail, "Bash")
            XCTAssertEqual(session?.startedAt, early)
            XCTAssertEqual(session?.updatedAt, startedAt)
        }
    }

    func testAStartOfAnotherSessionReplacesIt() {
        let now = Date(timeIntervalSince1970: 1)
        send(.turnStarted, at: now)
        send(.attention, detail: "old news", at: now)
        send(.sessionStarted, session: "s2", at: now)
        XCTAssertEqual(session, AgentSessionStore.Session(agent: "test", sessionID: "s2", startedAt: now, updatedAt: now))
    }

    func testAStartOfAnEndedSessionStartsItAfresh() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 2)
        send(.turnStarted, at: early)
        send(.sessionEnded, at: early)
        send(.sessionStarted, at: late)
        XCTAssertEqual(session, AgentSessionStore.Session(agent: "test", sessionID: "s1", startedAt: late, updatedAt: late))
    }

    func testAnOlderSessionStartStillStartsAFreshSession() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 2)
        send(.turnStarted, session: "old", at: late)
        send(.sessionStarted, session: "new", at: early)
        XCTAssertEqual(session?.sessionID, "new")
        XCTAssertEqual(session?.state, .idle)
    }

    // MARK: Notifications

    let workspace = UUID()
    let now = Date(timeIntervalSince1970: 10)

    func route(_ message: String, from surface: UUID? = nil) -> AgentSessionStore.NotificationRoute {
        store.route(notification: message, from: surface ?? self.surface, workspaceID: workspace, cwd: "/project", at: now)
    }

    func testAnApprovalCodexShowsTheUserWaitsOnThem() {
        send(.turnStarted, at: Date(timeIntervalSince1970: 1), agent: "codex")
        let route = route("Approval requested: x")
        XCTAssertEqual(route, .event(AgentEvent(agent: "codex", kind: .needsInput, sessionID: "s1", surfaceID: surface,
                                                workspaceID: workspace, cwd: "/project", at: now, detail: "Approval requested: x")))
        if case .event(let event) = route { store.apply(event) }
        XCTAssertEqual(session?.state, .waiting)
        XCTAssertEqual(session?.detail, "Approval requested: x")
    }

    func testNotificationsCodexsHooksCoverAreNotPosted() {
        send(.turnStarted, agent: "codex")
        XCTAssertEqual(route("Agent turn complete"), .ignore)
    }

    func testOtherNotificationsArePosted() {
        XCTAssertEqual(route("Approval requested: x"), .post, "no agent")
        send(.turnStarted, agent: "claude")
        XCTAssertEqual(route("Approval requested: x"), .post, "an agent that does not read notifications")
        send(.turnStarted, agent: "codex")
        send(.sessionEnded, agent: "codex")
        XCTAssertEqual(route("Approval requested: x"), .post, "an ended session")
        XCTAssertEqual(route("Approval requested: x", from: UUID()), .post, "another terminal")
    }
}

@MainActor
final class AgentRefreshTests: XCTestCase {
    func testRepeatedWorkingEventsKeepDetailsWithoutRefreshingIndicators() {
        let id = UUID()
        let store = AgentSessionStore(isLive: { $0 == id })
        var changes: [UUID] = []
        var updates: [AgentSessionStore.Update] = []
        store.onChange = { changes.append($0) }
        store.onUpdate = { updates.append($0) }
        func send(_ kind: AgentEvent.Kind, detail: String? = nil) {
            store.apply(AgentEvent(agent: "test", kind: kind, surfaceID: id, workspaceID: nil,
                                   cwd: "/", at: Date(), detail: detail))
        }
        send(.sessionStarted)
        send(.turnStarted)
        for index in 0..<100 { send(.working, detail: "tool\(index)") }
        send(.attention, detail: "look here")
        XCTAssertEqual(changes, [id])
        XCTAssertEqual(updates.count, 103)
        XCTAssertEqual(store.sessions[id]?.detail, "tool99")
        XCTAssertEqual(store.sessions[id]?.attention, "look here")
        send(.needsInput)
        send(.working)
        send(.turnEnded)
        store.markSeen(id)
        XCTAssertEqual(changes, Array(repeating: id, count: 5))
    }
}
