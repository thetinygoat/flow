import XCTest

@MainActor
final class AgentIndicatorTests: XCTestCase {
    let surfaces = (0..<4).map { _ in UUID() }
    var store: AgentSessionStore!

    override func setUp() async throws {
        let live = Set(surfaces)
        store = AgentSessionStore(isLive: live.contains)
    }

    func send(_ kinds: AgentEvent.Kind..., to surface: UUID) {
        for kind in kinds {
            store.apply(AgentEvent(agent: "test", kind: kind, surfaceID: surface, workspaceID: nil, cwd: "/", at: Date()))
        }
    }

    func testAWorkspaceShowsItsMostUrgentTerminal() {
        XCTAssertNil(store.indicator(for: surfaces))
        send(.sessionStarted, to: surfaces[0])
        XCTAssertNil(store.indicator(for: surfaces))
        send(.turnStarted, .turnEnded, to: surfaces[1])
        XCTAssertEqual(store.indicator(for: surfaces), .done)
        send(.turnStarted, to: surfaces[2])
        XCTAssertEqual(store.indicator(for: surfaces), .working)
        send(.turnStarted, .needsInput, to: surfaces[3])
        XCTAssertEqual(store.indicator(for: surfaces), .waiting)
        XCTAssertEqual(store.indicator(for: surfaces[1...2]), .working)
    }

    func testEndedSessionsShowNothing() {
        send(.turnStarted, .turnEnded, .sessionEnded, to: surfaces[0])
        XCTAssertNil(store.indicator(for: surfaces))
    }

    func title(_ title: String, for surface: UUID) {
        store.apply(AgentEvent(agent: "test", kind: .titleChanged, surfaceID: surface, workspaceID: nil, cwd: "/", at: Date(), title: title))
    }

    func testAWorkspaceShowsTheTitleOfItsMostUrgentTitledSession() {
        XCTAssertNil(store.title(for: surfaces))
        send(.turnStarted, .turnEnded, to: surfaces[0])
        title("Done one", for: surfaces[0])
        send(.sessionStarted, to: surfaces[1])
        title("Idle one", for: surfaces[1])
        XCTAssertEqual(store.title(for: surfaces), "Done one")
        send(.turnStarted, to: surfaces[2])
        XCTAssertEqual(store.title(for: surfaces), "Done one")
        title("Working one", for: surfaces[2])
        XCTAssertEqual(store.title(for: surfaces), "Working one")
        send(.sessionEnded, to: surfaces[2])
        XCTAssertEqual(store.title(for: surfaces), "Done one")
    }

    func testWithoutUrgencyTheLatestSessionsTitleWins() {
        send(.sessionStarted, to: surfaces[0])
        title("Older", for: surfaces[0])
        send(.sessionStarted, to: surfaces[1])
        title("Newer", for: surfaces[1])
        XCTAssertEqual(store.title(for: surfaces), "Newer")
        send(.working, to: surfaces[0])
        send(.turnEnded, to: surfaces[0])
        store.markSeen(surfaces[0])
        XCTAssertEqual(store.title(for: surfaces), "Older")
    }
}
