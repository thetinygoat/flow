import XCTest

final class WorkspaceTests: XCTestCase {
    func testTabTitleUsesDirectoryUntilTheShellSetsATitle() {
        let leaf = FakeLeaf(workingDirectory: NSHomeDirectory() + "/Code/flow")
        let tab = TestTab(leaf: leaf)
        XCTAssertEqual(tab.title, "~/Code/flow")
        leaf.title = "Running tests"
        XCTAssertEqual(tab.title, "Running tests")
        leaf.title = ""
        leaf.workingDirectory = "/tmp"
        XCTAssertEqual(tab.title, "/tmp")
        leaf.workingDirectory = ""
        XCTAssertEqual(tab.title, "Terminal")
        leaf.workingDirectory = nil
        XCTAssertEqual(tab.title, "Terminal")
    }

    func testRemovingSelectedTabSelectsNeighbor() {
        let workspace = WorkspaceModel<FakeLeaf>()
        let tabs = (0..<3).map { _ in TestTab(leaf: FakeLeaf()) }
        tabs.forEach(workspace.add)
        workspace.select(tabs[1])

        workspace.remove(tabs[1])
        XCTAssertTrue(workspace.selectedTab === tabs[2])

        workspace.remove(tabs[2])
        XCTAssertTrue(workspace.selectedTab === tabs[0])

        workspace.remove(tabs[0])
        XCTAssertNil(workspace.selectedTab)
    }

    func testRemovingUnselectedTabKeepsSelection() {
        let workspace = WorkspaceModel<FakeLeaf>()
        let tabs = (0..<2).map { _ in TestTab(leaf: FakeLeaf()) }
        tabs.forEach(workspace.add)
        workspace.select(tabs[0])
        workspace.remove(tabs[1])
        XCTAssertTrue(workspace.selectedTab === tabs[0])
    }

    func testRemovingBackgroundPaneKeepsFocus() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tab = TestTab(leaf: a)
        tab.panes.split(a, direction: .right, with: b)
        tab.panes.split(b, direction: .down, with: c)
        tab.focus(a)

        tab.removePane(c)

        XCTAssertTrue(tab.focusedLeaf === a)
        XCTAssertEqual(tab.panes.leaves.map(\.title), ["a", "b"])
    }

    func testRemovingFocusedPaneFocusesItsNeighbor() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tab = TestTab(leaf: a)
        tab.panes.split(a, direction: .right, with: b)
        tab.panes.split(b, direction: .down, with: c)
        tab.focus(c)

        tab.removePane(c)

        XCTAssertTrue(tab.focusedLeaf === b)
    }

    func testTabsClosedByEachMode() {
        let workspace = WorkspaceModel<FakeLeaf>()
        let tabs = ["a", "b", "c", "d"].map { TestTab(leaf: FakeLeaf($0)) }
        tabs.forEach(workspace.add)
        func titles(_ mode: TabCloseMode, from index: Int) -> [String] {
            workspace.tabs(closing: mode, from: tabs[index]).map(\.title)
        }

        XCTAssertEqual(titles(.this, from: 1), ["b"])
        XCTAssertEqual(titles(.others, from: 1), ["a", "c", "d"])
        XCTAssertEqual(titles(.right, from: 1), ["c", "d"])
        XCTAssertEqual(titles(.right, from: 3), [], "nothing to the right of the last tab")
        XCTAssertEqual(workspace.tabs(closing: .this, from: TestTab(leaf: FakeLeaf("elsewhere"))).count, 0)
    }

    func testDerivedNameCacheFollowsDirectoryFocusAndTabChanges() {
        var lookups: [String] = []
        let workspace = WorkspaceModel<FakeLeaf>(resolveName: { path in
            lookups.append(path)
            return path.folderName
        })
        let first = FakeLeaf(workingDirectory: "/first")
        let second = FakeLeaf(workingDirectory: "/second")
        let tab = TestTab(leaf: first)
        tab.panes.split(first, direction: .right, with: second)
        workspace.add(tab)
        for _ in 0..<20 { XCTAssertEqual(workspace.name, "first") }
        XCTAssertEqual(lookups, ["/first"])
        tab.focus(second)
        XCTAssertEqual(workspace.name, "second")
        second.workingDirectory = "/changed"
        XCTAssertEqual(workspace.name, "changed")
        workspace.customName = "mine"
        second.workingDirectory = "/renamed"
        XCTAssertEqual(workspace.name, "mine")
        XCTAssertEqual(lookups, ["/first", "/second", "/changed"])
        workspace.customName = nil
        XCTAssertEqual(workspace.name, "renamed")
        let other = TestTab(leaf: FakeLeaf(workingDirectory: "/other"))
        workspace.add(other)
        XCTAssertEqual(workspace.name, "other")
        workspace.select(tab)
        XCTAssertEqual(workspace.name, "renamed")
        workspace.invalidateDerivedName()
        XCTAssertEqual(workspace.name, "renamed")
        XCTAssertEqual(lookups, ["/first", "/second", "/changed", "/renamed", "/other", "/renamed", "/renamed"])
    }

    func testNameFollowsDirectoryUntilRenamed() {
        let workspace = WorkspaceModel<FakeLeaf>()
        XCTAssertEqual(workspace.name, "~")

        let leaf = FakeLeaf(workingDirectory: NSHomeDirectory() + "/Code/flow")
        workspace.add(TestTab(leaf: leaf))
        XCTAssertEqual(workspace.name, "flow")

        leaf.workingDirectory = "/tmp"
        XCTAssertEqual(workspace.name, "tmp")

        workspace.customName = "mine"
        leaf.workingDirectory = "/var"
        XCTAssertEqual(workspace.name, "mine")
    }

    func testNameIsTheRepositoryAnywhereInsideIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = root.appendingPathComponent("segment")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("src/lib"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: repository.appendingPathComponent(".git/HEAD"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let leaf = FakeLeaf(workingDirectory: repository.path)
        let workspace = WorkspaceModel<FakeLeaf>()
        workspace.add(TestTab(leaf: leaf))
        XCTAssertEqual(workspace.name, "segment")

        leaf.workingDirectory = repository.appendingPathComponent("src/lib").path
        XCTAssertEqual(workspace.name, "segment")

        leaf.workingDirectory = root.path
        XCTAssertEqual(workspace.name, root.lastPathComponent, "outside the repository the folder names it")
    }

    func testARepositoryAtHomeNamesNothing() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Downloads/notes"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: home.appendingPathComponent(".git/HEAD"))
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let workTree = try XCTUnwrap(GitRepository(containing: home.path)).workTree

        XCTAssertEqual(WorkspaceModel<FakeLeaf>.name(forDirectory: home.appendingPathComponent("Downloads/notes").path, home: workTree), "notes")
        XCTAssertEqual(WorkspaceModel<FakeLeaf>.name(forDirectory: home.appendingPathComponent("Downloads/notes").path, home: nil), home.lastPathComponent,
                       "the same repository away from home names the workspace")
    }

    func testNewWorkspaceGoesRightAfterTheSelectedOne() {
        let store = TestStore()
        let first = store.addWorkspace()
        let second = store.addWorkspace()
        let third = store.addWorkspace()
        XCTAssertEqual(store.workspaces.map(\.id), [first, second, third].map(\.id), "each new one follows the one added before it")

        store.select(first)
        let fourth = store.addWorkspace()
        XCTAssertEqual(store.workspaces.map(\.id), [first, fourth, second, third].map(\.id))
        XCTAssertTrue(store.selected === fourth)
    }

    func testStoreRemovalSelection() {
        let store = TestStore()
        let first = store.addWorkspace()
        let second = store.addWorkspace()
        let third = store.addWorkspace()
        store.select(second)

        store.remove(second)
        XCTAssertTrue(store.selected === third)
        store.remove(third)
        XCTAssertTrue(store.selected === first)
        store.remove(first)
        XCTAssertNil(store.selected)
        XCTAssertTrue(store.workspaces.isEmpty)
    }

    func testStoreFindsWorkspaceContainingLeaf() {
        let store = TestStore()
        let first = store.addWorkspace()
        let second = store.addWorkspace()
        let leaf = FakeLeaf()
        let tab = TestTab(leaf: FakeLeaf())
        tab.panes.split(tab.panes.leaves[0], direction: .right, with: leaf)
        second.add(tab)
        first.add(TestTab(leaf: FakeLeaf()))

        let found = store.workspace(containing: leaf)
        XCTAssertTrue(found?.0 === second)
        XCTAssertTrue(found?.1 === tab)
        XCTAssertNil(store.workspace(containing: FakeLeaf()))
    }

    func testStoreFindsTheWorkspaceAndTabForAnUnselectedPane() {
        let store = TestStore()
        let workspace = store.addWorkspace()
        let tab = TestTab(leaf: FakeLeaf())
        let leaf = FakeLeaf()
        tab.panes.split(tab.panes.leaves[0], direction: .right, with: leaf)
        workspace.add(tab)
        workspace.add(TestTab(leaf: FakeLeaf()))
        store.addWorkspace().add(TestTab(leaf: FakeLeaf()))

        let found = store.workspace(containing: leaf)
        XCTAssertTrue(found?.0 === workspace)
        XCTAssertTrue(found?.1 === tab)
        XCTAssertNil(store.workspace(containing: FakeLeaf()))
    }

    func testStoreNotifiesOnChange() {
        let store = TestStore()
        var changes = 0
        store.onChange = { changes += 1 }
        let workspace = store.addWorkspace()
        store.select(workspace)
        store.notifyChanged()
        store.remove(workspace)
        XCTAssertEqual(changes, 4)
    }

    func testSelectingCurrentWorkspacePublishesItsNewlySelectedTab() {
        let store = TestStore()
        let workspace = store.addWorkspace()
        let first = TestTab(leaf: FakeLeaf())
        let second = TestTab(leaf: FakeLeaf())
        workspace.add(first)
        workspace.add(second)
        var published: TestTab?
        store.onChange = { published = store.selected?.selectedTab }

        workspace.select(first)
        store.select(workspace)

        XCTAssertTrue(published === first)
    }

    func testMovingWorkspacesPreservesSelectionAndNotifies() {
        let store = TestStore()
        let workspaces = (0..<4).map { _ in store.addWorkspace() }
        store.select(workspaces[1])
        var changes = 0
        store.onChange = { changes += 1 }

        XCTAssertTrue(store.move(workspaces[1], toInsertionIndex: 4))
        XCTAssertEqual(store.workspaces.map(\.id), [workspaces[0], workspaces[2], workspaces[3], workspaces[1]].map(\.id))
        XCTAssertTrue(store.selected === workspaces[1])

        XCTAssertTrue(store.move(workspaces[3], toInsertionIndex: 0))
        XCTAssertEqual(store.workspaces.map(\.id), [workspaces[3], workspaces[0], workspaces[2], workspaces[1]].map(\.id))
        XCTAssertTrue(store.selected === workspaces[1])

        XCTAssertTrue(store.move(workspaces[0], toInsertionIndex: 3))
        XCTAssertEqual(store.workspaces.map(\.id), [workspaces[3], workspaces[2], workspaces[0], workspaces[1]].map(\.id))
        XCTAssertEqual(changes, 3)
    }

    func testInvalidAndUnchangedMovesDoNotNotify() {
        let store = TestStore()
        let first = store.addWorkspace()
        let second = store.addWorkspace()
        var changes = 0
        store.onChange = { changes += 1 }

        XCTAssertTrue(store.move(first, toInsertionIndex: 0))
        XCTAssertTrue(store.move(first, toInsertionIndex: 1))
        XCTAssertTrue(store.move(second, toInsertionIndex: 2))
        XCTAssertFalse(store.move(first, toInsertionIndex: -1))
        XCTAssertFalse(store.move(first, toInsertionIndex: 3))
        XCTAssertFalse(store.move(WorkspaceModel<FakeLeaf>(), toInsertionIndex: 0))
        XCTAssertEqual(store.workspaces.map(\.id), [first.id, second.id])
        XCTAssertEqual(changes, 0)
        store.remove(first)
        changes = 0
        XCTAssertFalse(store.move(first, toInsertionIndex: 0))
        XCTAssertEqual(store.workspaces.map(\.id), [second.id])
        XCTAssertTrue(store.selected === second)
        XCTAssertEqual(changes, 0)
    }

    func testMoveObserversSeeFinalOrderAndPreservedSelection() {
        let store = TestStore()
        let workspaces = (0..<3).map { _ in store.addWorkspace() }
        store.select(workspaces[1])
        var observedOrders: [[UUID]] = []
        store.onChange = {
            observedOrders.append(store.workspaces.map(\.id))
            XCTAssertTrue(store.selected === workspaces[1])
        }

        XCTAssertTrue(store.move(workspaces[1], toInsertionIndex: 3))
        XCTAssertTrue(store.move(workspaces[2], toInsertionIndex: 0))
        XCTAssertEqual(observedOrders, [
            [workspaces[0].id, workspaces[2].id, workspaces[1].id],
            [workspaces[2].id, workspaces[0].id, workspaces[1].id],
        ])
    }
}
