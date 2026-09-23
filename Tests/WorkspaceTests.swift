import XCTest

final class WorkspaceTests: XCTestCase {
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

    func testNeedsAttentionWhenAnyPaneInAnyTabDoes() {
        let workspace = WorkspaceModel<FakeLeaf>()
        let a = FakeLeaf(), b = FakeLeaf(), c = FakeLeaf()
        let first = TestTab(leaf: a)
        first.panes.split(a, direction: .right, with: b)
        workspace.add(first)
        workspace.add(TestTab(leaf: c))
        XCTAssertFalse(workspace.needsAttention)

        b.needsAttention = true
        XCTAssertTrue(workspace.needsAttention, "a pane that is not focused")
        b.needsAttention = false
        c.needsAttention = true
        XCTAssertTrue(workspace.needsAttention, "a tab that is not selected")
        c.needsAttention = false
        XCTAssertFalse(workspace.needsAttention)
    }

    func testBusyWhenAnyPaneInAnyTabIs() {
        let workspace = WorkspaceModel<FakeLeaf>()
        let a = FakeLeaf(), b = FakeLeaf(), c = FakeLeaf()
        let first = TestTab(leaf: a)
        first.panes.split(a, direction: .down, with: b)
        workspace.add(first)
        workspace.add(TestTab(leaf: c))
        XCTAssertFalse(workspace.isBusy)

        b.isBusy = true
        XCTAssertTrue(workspace.isBusy)
        b.isBusy = false
        c.isBusy = true
        XCTAssertTrue(workspace.isBusy)
        c.isBusy = false
        XCTAssertFalse(workspace.isBusy)
    }

    func testNameFollowsDirectoryUntilRenamed() {
        let workspace = WorkspaceModel<FakeLeaf>()
        XCTAssertEqual(workspace.name, "~")

        let leaf = FakeLeaf(workingDirectory: NSHomeDirectory() + "/Code/flow")
        workspace.add(TestTab(leaf: leaf))
        XCTAssertEqual(workspace.name, "~/C/flow")

        leaf.workingDirectory = "/tmp"
        XCTAssertEqual(workspace.name, "/tmp")

        workspace.customName = "mine"
        leaf.workingDirectory = "/var"
        XCTAssertEqual(workspace.name, "mine")
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
}
