import XCTest

final class SessionTests: XCTestCase {
    func testRestorePreservesSelectionAfterSkippingEmptyWorkspaces() {
        let firstTab = Session.Tab(layout: .terminal(id: UUID(), workingDirectory: "/first"), zoomedPane: nil)
        let secondTab = Session.Tab(layout: .terminal(id: UUID(), workingDirectory: "/second"), zoomedPane: nil)
        let empty = Session.Workspace(id: UUID(), customName: "empty", tabs: [], selectedTab: 0)
        let middle = Session.Workspace(id: UUID(), customName: "middle", tabs: [firstTab, secondTab], selectedTab: 0)
        let last = Session.Workspace(id: UUID(), customName: "last", tabs: [secondTab], selectedTab: 0)
        for (selection, expected) in [(1, middle.id), (2, last.id)] {
            let store = TestStore()
            store.restore(.init(workspaces: [empty, middle, last], selectedWorkspace: selection)) { id, directory, _ in
                FakeLeaf(id: id, workingDirectory: directory)
            }
            XCTAssertEqual(store.workspaces.map(\.id), [middle.id, last.id])
            XCTAssertEqual(store.selected?.id, expected)
            XCTAssertEqual(store.workspaces[0].selectedTab?.focusedLeaf.workingDirectory, "/first")
        }
    }

    func testRestoreFallsBackWhenTheSelectedWorkspaceIsEmpty() {
        let tab = Session.Tab(layout: .terminal(id: UUID(), workingDirectory: "/"), zoomedPane: nil)
        let first = Session.Workspace(id: UUID(), customName: nil, tabs: [tab], selectedTab: 0)
        let empty = Session.Workspace(id: UUID(), customName: nil, tabs: [], selectedTab: 0)
        let last = Session.Workspace(id: UUID(), customName: nil, tabs: [tab], selectedTab: 0)
        let store = TestStore()
        store.restore(.init(workspaces: [first, empty, last], selectedWorkspace: 1)) { id, directory, _ in
            FakeLeaf(id: id, workingDirectory: directory)
        }
        XCTAssertEqual(store.selected?.id, last.id)
    }

    func testSnapshotCanSaveOtherPlacesThanTheOnesInView() {
        let store = TestStore()
        let first = store.addWorkspace()
        let tabs = (0..<2).map { _ in TestTab(leaf: FakeLeaf()) }
        tabs.forEach(first.add)
        first.select(tabs[0])
        store.addWorkspace().add(TestTab(leaf: FakeLeaf()))
        let places = store.places
        store.select(first)
        first.select(tabs[1])

        let saved = store.snapshot(places: places)
        XCTAssertEqual(saved.selectedWorkspace, 1)
        XCTAssertEqual(saved.workspaces[0].selectedTab, 0)
        let inView = store.snapshot()
        XCTAssertEqual(inView.selectedWorkspace, 0)
        XCTAssertEqual(inView.workspaces[0].selectedTab, 1)
    }

    func testSavedSessionIsReadableAndDeterministic() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = TestStore()
        store.addWorkspace(customName: "work").add(TestTab(leaf: FakeLeaf()))
        let session = Session(windows: [store.snapshot()])

        XCTAssertTrue(session.save(to: url))
        let first = try Data(contentsOf: url)
        XCTAssertTrue(session.save(to: url))
        XCTAssertEqual(try Data(contentsOf: url), first)
        XCTAssertEqual(Session.load(from: url), session)
        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertGreaterThan(text.split(separator: "\n").count, 10)
        let selection = try XCTUnwrap(text.range(of: "\"selectedWorkspace\""))
        let workspaces = try XCTUnwrap(text.range(of: "\"workspaces\""))
        XCTAssertLessThan(selection.lowerBound, workspaces.lowerBound)
    }

    func testReorderedWorkspacesRestoreFromFileWithSelectionAndContents() throws {
        let store = TestStore()
        let workspaces = ["first", "second", "third"].map { name in
            let workspace = store.addWorkspace(customName: name)
            workspace.add(TestTab(leaf: FakeLeaf(workingDirectory: "/" + name)))
            return workspace
        }
        store.select(workspaces[0])
        store.move(workspaces[0], toInsertionIndex: 3)
        store.move(workspaces[2], toInsertionIndex: 0)
        let expected = store.snapshot()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        Session(windows: [expected]).save(to: url)

        let loaded = try XCTUnwrap(Session.load(from: url))
        let restored = TestStore()
        restored.restore(loaded.windows[0]) { id, directory, _ in
            FakeLeaf(id: id, workingDirectory: directory)
        }

        XCTAssertEqual(restored.workspaces.map(\.id), [workspaces[2].id, workspaces[1].id, workspaces[0].id])
        XCTAssertEqual(restored.selected?.id, workspaces[0].id)
        XCTAssertEqual(restored.snapshot(), expected)
    }

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
        restored.restore(decoded.windows[0]) { id, directory, _ in FakeLeaf(id: id, workingDirectory: directory) }

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
                workspaces: [.init(id: UUID(), customName: nil, tabs: [.init(layout: .terminal(id: UUID(), workingDirectory: "/x"), zoomedPane: nil)], selectedTab: 0)],
                selectedWorkspace: 0,
                frame: CGRect(x: 10, y: 20, width: 800, height: 600)),
            .init(
                workspaces: [.init(id: UUID(), customName: "second", tabs: [.init(layout: .terminal(id: UUID(), workingDirectory: "/y"), zoomedPane: nil)], selectedTab: 0)],
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
        restored.restore(window) { id, directory, _ in FakeLeaf(id: id, workingDirectory: directory) }
        let restoredTab = restored.workspaces[0].tabs[0]
        XCTAssertEqual(restoredTab.panes.zoomed?.workingDirectory, "/b")
        XCTAssertTrue(restoredTab.focusedLeaf === restoredTab.panes.zoomed, "the zoomed pane gets focus")
        XCTAssertNil(restored.workspaces[0].tabs[1].panes.zoomed)
    }

    func testOutOfRangeZoomIsIgnored() {
        let window = Session.Window(
            workspaces: [.init(id: UUID(), customName: nil, tabs: [.init(
                layout: .split(axis: .horizontal, ratio: 0.5, first: .terminal(id: UUID(), workingDirectory: "/a"), second: .terminal(id: UUID(), workingDirectory: "/b")),
                zoomedPane: 5)], selectedTab: 0)],
            selectedWorkspace: 0,
            frame: nil)
        let restored = TestStore()
        restored.restore(window) { id, directory, _ in FakeLeaf(id: id, workingDirectory: directory) }
        XCTAssertNil(restored.workspaces[0].tabs[0].panes.zoomed)
    }

    func testSnapshotCarriesFrame() {
        let store = TestStore()
        store.addWorkspace().add(TestTab(leaf: FakeLeaf(workingDirectory: "/a")))
        let frame = CGRect(x: 100, y: 200, width: 900, height: 700)
        XCTAssertEqual(store.snapshot(frame: frame).frame, frame)
        XCTAssertNil(store.snapshot().frame)
    }

    func testRoundTripPreservesIds() {
        let store = TestStore()
        let workspace = store.addWorkspace()
        let a = FakeLeaf(workingDirectory: "/a"), b = FakeLeaf(workingDirectory: "/b")
        let tab = TestTab(leaf: a)
        tab.panes.split(a, direction: .right, with: b)
        workspace.add(tab)

        let data = try! JSONEncoder().encode(Session(windows: [store.snapshot()]))
        let decoded = try! JSONDecoder().decode(Session.self, from: data)
        var leafWorkspaces: [UUID] = []
        let restored = TestStore()
        restored.restore(decoded.windows[0]) { id, directory, workspace in
            leafWorkspaces.append(workspace)
            return FakeLeaf(id: id, workingDirectory: directory)
        }

        XCTAssertEqual(restored.workspaces[0].id, workspace.id)
        XCTAssertEqual(restored.workspaces[0].tabs[0].panes.leaves.map(\.id), [a.id, b.id])
        XCTAssertEqual(leafWorkspaces, [workspace.id, workspace.id])
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

final class SessionPerformanceTests: XCTestCase {
    func testRestorePublishesOnlyTheCompletedWindow() {
        let original = TestStore()
        for index in 0..<30 {
            original.addWorkspace(customName: "w\(index)").add(TestTab(leaf: FakeLeaf()))
        }
        original.select(original.workspaces[7])
        let saved = original.snapshot()
        let restored = TestStore()
        var snapshots: [Session.Window] = []
        restored.onChange = { snapshots.append(restored.snapshot()) }
        restored.restore(saved) { id, directory, _ in FakeLeaf(id: id, workingDirectory: directory) }
        XCTAssertEqual(snapshots, [saved])
    }

    func testNestedBatchesPublishOnceAndEmptyBatchesDoNotPublish() {
        let store = TestStore()
        var changes = 0
        store.onChange = { changes += 1 }
        store.performBatch {
            store.addWorkspace()
            store.performBatch { store.addWorkspace() }
            XCTAssertEqual(changes, 0)
        }
        XCTAssertEqual(changes, 1)
        store.performBatch {}
        XCTAssertEqual(changes, 1)
    }

    func testSlowWriterKeepsOnlyTheLatestPendingSnapshot() {
        let began = expectation(description: "first write started")
        let resume = DispatchSemaphore(value: 0)
        let first = Session(windows: [])
        let intermediate = Session(windows: [.init(workspaces: [], selectedWorkspace: 1)])
        let last = Session(windows: [.init(workspaces: [], selectedWorkspace: 2)])
        var written: [Session] = []
        let writer = SessionWriter { session in
            XCTAssertFalse(Thread.isMainThread)
            written.append(session)
            if written.count == 1 {
                began.fulfill()
                XCTAssertEqual(resume.wait(timeout: .now() + 5), .success)
            }
            return true
        }
        writer.save(first)
        wait(for: [began], timeout: 2)
        writer.save(intermediate)
        writer.save(last)
        resume.signal()
        writer.flush(last)
        XCTAssertEqual(written, [first, last])
    }

    func testFailedWritesAreRetriedAndSuccessfulWritesAreDeduplicated() {
        var attempts = 0
        let writer = SessionWriter { _ in
            attempts += 1
            return attempts > 1
        }
        let session = Session(windows: [])
        writer.flush(session)
        writer.flush(session)
        writer.flush(session)
        XCTAssertEqual(attempts, 2)
    }
}
