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

    func testListsEveryWorkspaceAndTabWithShortcutsOnTheFirstNine() {
        let names = (1...11).map { "w\($0)" }
        let menu = makeMenu(.init(workspaces: .init(names: names, selected: 10), tabs: .init(names: ["a", "b"], selected: 0)))
        menu.menuNeedsUpdate(menu.menu)

        let workspaces = menu.menu.items.filter { $0.action == #selector(Receiver.selectWorkspace(_:)) }
        XCTAssertEqual(workspaces.map(\.title), names)
        XCTAssertEqual(workspaces.map(\.keyEquivalent), (1...9).map { "\($0)" } + ["", ""])
        XCTAssertEqual(workspaces.map(\.state), Array(repeating: .off, count: 10) + [.on])

        let tabs = menu.menu.items.filter { $0.action == #selector(Receiver.selectTab(_:)) }
        XCTAssertEqual(tabs.map(\.title), ["a", "b"])
        XCTAssertEqual(tabs.map(\.keyEquivalentModifierMask), [.control, .control])
        XCTAssertEqual(tabs.map(\.state), [.on, .off])
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
