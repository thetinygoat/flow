import AppKit

/// The Workspace menu lists every workspace in the key window and every tab
/// in its selected workspace, under the names the sidebar and tab strip show.
/// It is filled in only when it opens or is searched for a key equivalent, so
/// it is never out of date and costs nothing in between.
final class WorkspaceMenu: NSObject, NSMenuDelegate {
    struct Entries {
        var names: [String]
        var selected: Int?
    }

    struct Contents {
        var workspaces: Entries
        var tabs: Entries
    }

    let menu: NSMenu
    /// Nil when no terminal window is key.
    var contents: () -> Contents? = { nil }
    private let fixedItemCount: Int
    private weak var target: AnyObject?
    private let selectWorkspace: Selector
    private let selectTab: Selector

    /// Workspace and tab items carry their index as the tag.
    init(title: String, fixedItems: [NSMenuItem], target: AnyObject, selectWorkspace: Selector, selectTab: Selector) {
        menu = NSMenu(title: title)
        fixedItems.forEach(menu.addItem)
        fixedItemCount = fixedItems.count
        self.target = target
        self.selectWorkspace = selectWorkspace
        self.selectTab = selectTab
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.numberOfItems > fixedItemCount {
            menu.removeItem(at: fixedItemCount)
        }
        guard let contents = contents() else { return }
        add(contents.workspaces, action: selectWorkspace, modifiers: .command)
        add(contents.tabs, action: selectTab, modifiers: .control)
    }

    /// AppKit does not refill the menu before matching key equivalents,
    /// but it asks this first and then searches the items, so they are
    /// brought up to date here.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
        menuNeedsUpdate(menu)
        return false
    }

    private func add(_ entries: Entries, action: Selector, modifiers: NSEvent.ModifierFlags) {
        guard !entries.names.isEmpty else { return }
        menu.addItem(.separator())
        for (index, name) in entries.names.enumerated() {
            let item = menu.addItem(withTitle: name, action: action, keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            item.tag = index
            item.state = index == entries.selected ? .on : .off
        }
    }
}
