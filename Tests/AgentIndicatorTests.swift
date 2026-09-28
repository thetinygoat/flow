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
}
