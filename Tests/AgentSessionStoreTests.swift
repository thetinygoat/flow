import XCTest

@MainActor
final class AgentSessionStoreTests: XCTestCase {
    let surface = UUID()
    var store: AgentSessionStore!
    var changes = 0

    override func setUp() async throws {
        let live = surface
        store = AgentSessionStore { $0 == live }
        store.onChange = { [unowned self] in self.changes += 1 }
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
}
