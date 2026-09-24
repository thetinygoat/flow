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

        let session = Session(windows: [store.snapshot()])
        let data = try! JSONEncoder().encode(session)
        let decoded = try! JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)

        let restored = TestStore()
        restored.restore(decoded.windows[0]) { FakeLeaf(workingDirectory: $0) }

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
        let session = Session(windows: [
            .init(
                workspaces: [.init(customName: nil, tabs: [.init(layout: .terminal(workingDirectory: "/x"), zoomedPane: nil)], selectedTab: 0)],
                selectedWorkspace: 0,
                frame: CGRect(x: 10, y: 20, width: 800, height: 600)),
            .init(
                workspaces: [.init(customName: "second", tabs: [.init(layout: .terminal(workingDirectory: "/y"), zoomedPane: nil)], selectedTab: 0)],
                selectedWorkspace: 0,
                frame: nil),
        ])

        session.save(to: url)
        XCTAssertEqual(Session.load(from: url), session)
    }

    func testRoundTripPreservesZoomedPane() {
        let store = TestStore()
        let workspace = store.addWorkspace()
        let a = FakeLeaf(workingDirectory: "/a"), b = FakeLeaf(workingDirectory: "/b"), c = FakeLeaf(workingDirectory: "/c")
        let tab = TestTab(leaf: a)
        tab.panes.split(a, direction: .right, with: b)
        tab.panes.split(b, direction: .down, with: c)
        tab.panes.toggleZoom(b)
        workspace.add(tab)
        workspace.add(TestTab(leaf: FakeLeaf(workingDirectory: "/d")))

        let window = store.snapshot()
        XCTAssertEqual(window.workspaces[0].tabs.map(\.zoomedPane), [1, nil])

        let restored = TestStore()
        restored.restore(window) { FakeLeaf(workingDirectory: $0) }
        let restoredTab = restored.workspaces[0].tabs[0]
        XCTAssertEqual(restoredTab.panes.zoomed?.workingDirectory, "/b")
        XCTAssertTrue(restoredTab.focusedLeaf === restoredTab.panes.zoomed, "the zoomed pane gets focus")
        XCTAssertNil(restored.workspaces[0].tabs[1].panes.zoomed)
    }

    func testOutOfRangeZoomIsIgnored() {
        let window = Session.Window(
            workspaces: [.init(customName: nil, tabs: [.init(
                layout: .split(axis: .horizontal, ratio: 0.5, first: .terminal(workingDirectory: "/a"), second: .terminal(workingDirectory: "/b")),
                zoomedPane: 5)], selectedTab: 0)],
            selectedWorkspace: 0,
            frame: nil)
        let restored = TestStore()
        restored.restore(window) { FakeLeaf(workingDirectory: $0) }
        XCTAssertNil(restored.workspaces[0].tabs[0].panes.zoomed)
    }

    func testSnapshotCarriesFrame() {
        let store = TestStore()
        store.addWorkspace().add(TestTab(leaf: FakeLeaf(workingDirectory: "/a")))
        let frame = CGRect(x: 100, y: 200, width: 900, height: 700)
        XCTAssertEqual(store.snapshot(frame: frame).frame, frame)
        XCTAssertNil(store.snapshot().frame)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(Session.load(from: URL(fileURLWithPath: "/nonexistent/session.json")))
    }
}

final class WindowPlacementTests: XCTestCase {
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let monitor = CGRect(x: 1512, y: 0, width: 2560, height: 1415)

    func testKeepsFrameOnConnectedScreen() {
        let frame = CGRect(x: 1700, y: 100, width: 1800, height: 1040)
        XCTAssertEqual(Session.Window.placing(frame, on: [laptop, monitor]), frame)
    }

    func testKeepsFramePartlyOffScreenWhileTitleBarShows() {
        let frame = CGRect(x: -400, y: -300, width: 1100, height: 700)
        XCTAssertEqual(Session.Window.placing(frame, on: [laptop]), frame)
    }

    func testMovesFrameFromUnpluggedMonitorOntoLaptop() {
        let frame = CGRect(x: 1700, y: 100, width: 1800, height: 1040)
        let placed = Session.Window.placing(frame, on: [laptop])
        XCTAssertEqual(placed.size, CGSize(width: 1512, height: 944))
        XCTAssertTrue(laptop.contains(placed))
    }

    func testCentresSmallerFrame() {
        let placed = Session.Window.placing(CGRect(x: 5000, y: 5000, width: 1100, height: 700), on: [laptop, monitor])
        XCTAssertEqual(placed, CGRect(x: 206, y: 122, width: 1100, height: 700))
    }

    func testTitleBarBelowEveryScreenIsMoved() {
        let frame = CGRect(x: 100, y: -800, width: 1100, height: 700)
        XCTAssertNotEqual(Session.Window.placing(frame, on: [laptop]), frame)
    }

    func testNoScreensKeepsFrame() {
        let frame = CGRect(x: 5000, y: 5000, width: 1100, height: 700)
        XCTAssertEqual(Session.Window.placing(frame, on: []), frame)
    }
}
