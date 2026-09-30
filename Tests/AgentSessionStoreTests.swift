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
        store.onChange = { [unowned self] in self.changes += 1 }
        store.onUpdate = { [unowned self] in self.updates.append($0) }
    }

    func send(_ kind: AgentEvent.Kind, detail: String? = nil, session: String = "s1", to surface: UUID? = nil, at: Date = Date()) {
        store.apply(AgentEvent(agent: "test", kind: kind, sessionID: session, surfaceID: surface ?? self.surface,
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
        XCTAssertEqual(changes, before + 1)
        store.remove(surface)
        XCTAssertEqual(changes, before + 1)
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

    func testALateStartOfTheSameSessionIsIgnored() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 2)
        send(.turnStarted, at: late)
        let before = changes
        send(.sessionStarted, at: early)
        XCTAssertEqual(session?.state, .working)
        XCTAssertEqual(session?.updatedAt, late)
        XCTAssertEqual(changes, before)
    }

    func testANewerStartOfTheSameSessionResetsIt() {
        let early = Date(timeIntervalSince1970: 1), late = Date(timeIntervalSince1970: 2)
        send(.turnStarted, at: early)
        send(.attention, detail: "old news", at: early)
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
}
