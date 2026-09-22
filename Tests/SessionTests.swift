import XCTest

final class SessionTests: XCTestCase {
    func testRoundTripPreservesLayoutNamesAndSelection() {
        let store = TestStore()
        let first = store.addWorkspace(customName: "work")
        let a = FakeLeaf(workingDirectory: "/a"), b = FakeLeaf(workingDirectory: "/b"), c = FakeLeaf(workingDirectory: "/c")
        let tab = TestTab(leaf: a)
        tab.panes.split(a, direction: .right, with: b)
        tab.panes.split(b, direction: .down, with: c)
        tab.panes.root.ratio = 0.3
        first.add(tab)
        first.add(TestTab(leaf: FakeLeaf(workingDirectory: "/d")))
        first.select(tab)
        let second = store.addWorkspace()
        second.add(TestTab(leaf: FakeLeaf(workingDirectory: "/e")))
        store.select(first)

        let session = store.session()
        let data = try! JSONEncoder().encode(session)
        let decoded = try! JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)

        let restored = TestStore()
        restored.restore(decoded) { FakeLeaf(workingDirectory: $0) }

        XCTAssertEqual(restored.workspaces.count, 2)
        XCTAssertTrue(restored.selected === restored.workspaces[0])
        XCTAssertEqual(restored.workspaces[0].customName, "work")
        XCTAssertNil(restored.workspaces[1].customName)
        let restoredTab = restored.workspaces[0].tabs[0]
        XCTAssertTrue(restored.workspaces[0].selectedTab === restoredTab)
        XCTAssertEqual(restoredTab.panes.leaves.map(\.workingDirectory), ["/a", "/b", "/c"])
        XCTAssertEqual(restoredTab.panes.root.ratio, 0.3)
        XCTAssertEqual(restoredTab.panes.root.second?.axis, .vertical)
        XCTAssertTrue(restoredTab.focusedLeaf === restoredTab.panes.leaves[0])
    }

    func testSaveAndLoadFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("session.json")
        let session = Session(
            workspaces: [.init(customName: nil, tabs: [.init(layout: .terminal(workingDirectory: "/x"))], selectedTab: 0)],
            selectedWorkspace: 0)

        session.save(to: url)
        XCTAssertEqual(Session.load(from: url), session)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(Session.load(from: URL(fileURLWithPath: "/nonexistent/session.json")))
    }
}
