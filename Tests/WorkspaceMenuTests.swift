import AppKit
import XCTest

final class WorkspaceMenuTests: XCTestCase {
    private final class Receiver: NSObject {
        var selectedWorkspace: Int?
        var selectedTab: Int?

        @objc func selectWorkspace(_ sender: NSMenuItem) { selectedWorkspace = sender.tag }
        @objc func selectTab(_ sender: NSMenuItem) { selectedTab = sender.tag }
    }

    private let receiver = Receiver()

    private func makeMenu(_ contents: WorkspaceMenu.Contents?) -> WorkspaceMenu {
        let menu = WorkspaceMenu(
            title: "Workspace",
            fixedItems: [NSMenuItem(title: "Rename Workspace", action: nil, keyEquivalent: "")],
            target: receiver,
            selectWorkspace: #selector(Receiver.selectWorkspace(_:)),
            selectTab: #selector(Receiver.selectTab(_:)))
        menu.contents = { contents }
        return menu
    }

    func testListsEveryWorkspaceAndTabWithNineOnTheLastWorkspace() {
        let names = (1...11).map { "w\($0)" }
        let menu = makeMenu(.init(workspaces: .init(names: names, selected: 10), tabs: .init(names: ["a", "b"], selected: 0)))
        menu.menuNeedsUpdate(menu.menu)

        let workspaces = menu.menu.items.filter { $0.action == #selector(Receiver.selectWorkspace(_:)) }
        XCTAssertEqual(workspaces.map(\.title), names)
        XCTAssertEqual(workspaces.map(\.keyEquivalent), (1...8).map { "\($0)" } + ["", "", "9"])
        XCTAssertEqual(workspaces.map(\.state), Array(repeating: .off, count: 10) + [.on])

        let tabs = menu.menu.items.filter { $0.action == #selector(Receiver.selectTab(_:)) }
        XCTAssertEqual(tabs.map(\.title), ["a", "b"])
        XCTAssertEqual(tabs.map(\.keyEquivalentModifierMask), [.control, .control])
        XCTAssertEqual(tabs.map(\.state), [.on, .off])
    }

    func testTabsKeepNineOnTheNinth() {
        XCTAssertEqual((0..<11).map { WorkspaceMenu.keyEquivalent(at: $0, of: 11, nineIsLast: false) }, (1...9).map { "\($0)" } + ["", ""])
        XCTAssertEqual((0..<3).map { WorkspaceMenu.keyEquivalent(at: $0, of: 3, nineIsLast: true) }, ["1", "2", "3"], "a short list keeps its numbers")
    }

    func testRebuildingKeepsTheFixedItemsOnce() {
        let menu = makeMenu(.init(workspaces: .init(names: ["w"], selected: 0), tabs: .init(names: ["a"], selected: 0)))
        menu.menuNeedsUpdate(menu.menu)
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertEqual(menu.menu.items.map(\.title), ["Rename Workspace", "", "w", "", "a"])
    }

    func testWithoutAKeyWindowOnlyTheFixedItemsRemain() {
        let menu = makeMenu(nil)
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertEqual(menu.menu.items.map(\.title), ["Rename Workspace"])
    }
}

@MainActor
final class MenuReuseTests: XCTestCase {
    func testRepeatedMenuUpdatesReuseDerivedWorkspaceNames() {
        var lookups = 0
        let workspace = WorkspaceModel<FakeLeaf>(resolveName: { _ in
            lookups += 1
            return "repository"
        })
        workspace.add(TestTab(leaf: FakeLeaf(workingDirectory: "/repo/subdirectory")))
        let menu = WorkspaceMenu(title: "Workspace", fixedItems: [], target: NSObject(),
                                 selectWorkspace: Selector(("workspace:")), selectTab: Selector(("tab:")))
        menu.contents = {
            .init(workspaces: .init(names: [workspace.name], selected: 0), tabs: .init(names: [], selected: nil))
        }
        for _ in 0..<30 { menu.menuNeedsUpdate(menu.menu) }
        XCTAssertEqual(lookups, 1)
        workspace.invalidateDerivedNames()
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertEqual(lookups, 2)
    }

    func testUnchangedMenuKeepsItemsAndSelectionChangesStillApply() {
        let menu = WorkspaceMenu(title: "Workspace", fixedItems: [], target: NSObject(),
                                 selectWorkspace: Selector(("workspace:")), selectTab: Selector(("tab:")))
        var selection = 0
        menu.contents = {
            .init(workspaces: .init(names: ["one", "two"], selected: selection),
                  tabs: .init(names: [], selected: nil))
        }
        menu.menuNeedsUpdate(menu.menu)
        let original = menu.menu.items
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertTrue(zip(original, menu.menu.items).allSatisfy { $0 === $1 })
        selection = 1
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertEqual(menu.menu.items.filter { !$0.isSeparatorItem }.map(\.state), [.off, .on])
        menu.contents = { nil }
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertTrue(menu.menu.items.isEmpty)
    }
}
