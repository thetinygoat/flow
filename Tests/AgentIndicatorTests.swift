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

    func testATitleBelongsToItsOwnTerminal() {
        XCTAssertNil(store.title(for: surfaces[0]))
        send(.turnStarted, .turnEnded, to: surfaces[0])
        title("First", for: surfaces[0])
        send(.turnStarted, .needsInput, to: surfaces[1])
        XCTAssertEqual(store.title(for: surfaces[0]), "First")
        XCTAssertNil(store.title(for: surfaces[1]))
        send(.sessionEnded, to: surfaces[0])
        XCTAssertNil(store.title(for: surfaces[0]))
    }

    func testAWorkspaceShowsTheTitleOfItsFocusedPane() {
        let leaves = surfaces.map { FakeLeaf(id: $0) }
        let workspace = WorkspaceModel<FakeLeaf>()
        let split = TestTab(leaf: leaves[0])
        split.panes.split(leaves[0], direction: .right, with: leaves[1])
        let other = TestTab(leaf: leaves[2])
        workspace.add(split)
        workspace.add(other)
        for (index, surface) in surfaces.prefix(3).enumerated() {
            send(.sessionStarted, to: surface)
            title("Pane \(index)", for: surface)
        }
        func shown() -> String? { workspace.focusedLeaf.flatMap { store.title(for: $0.id) } }

        XCTAssertEqual(shown(), "Pane 2")
        workspace.select(split)
        XCTAssertEqual(shown(), "Pane 0")
        split.focus(leaves[1])
        XCTAssertEqual(shown(), "Pane 1")
        split.panes.split(leaves[1], direction: .down, with: leaves[3])
        split.focus(leaves[3])
        XCTAssertNil(shown())
    }
}
