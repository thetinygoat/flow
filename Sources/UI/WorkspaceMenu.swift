import AppKit

/// The Workspace menu lists every workspace in the key window and every tab
/// in its selected workspace, under the names the sidebar and tab strip show.
/// It is filled in only when it opens or is searched for a key equivalent, so
/// it is never out of date and costs nothing in between.
final class WorkspaceMenu: NSObject, NSMenuDelegate {
    struct Entries: Equatable {
        var names: [String]
        var selected: Int?
    }

    struct Contents: Equatable {
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
    private var displayedContents: Contents?

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
        let current = contents()
        guard current != displayedContents else { return }
        displayedContents = current
        while menu.numberOfItems > fixedItemCount {
            menu.removeItem(at: fixedItemCount)
        }
        guard let contents = current else { return }
        add(contents.workspaces, action: selectWorkspace, modifiers: .command, nineIsLast: true)
        add(contents.tabs, action: selectTab, modifiers: .control, nineIsLast: false)
    }

    /// AppKit does not refill the menu before matching key equivalents,
    /// but it asks this first and then searches the items, so they are
    /// brought up to date here.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
        menuNeedsUpdate(menu)
        return false
    }

    private func add(_ entries: Entries, action: Selector, modifiers: NSEvent.ModifierFlags, nineIsLast: Bool) {
        guard !entries.names.isEmpty else { return }
        menu.addItem(.separator())
        for (index, name) in entries.names.enumerated() {
            let key = Self.keyEquivalent(at: index, of: entries.names.count, nineIsLast: nineIsLast)
            let item = menu.addItem(withTitle: name, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            item.tag = index
            item.state = index == entries.selected ? .on : .off
        }
    }

    /// ⌘9 is Ghostty's last-tab binding, which Flow turns into the last
    /// workspace, so the menu puts it on the last one rather than the ninth.
    static func keyEquivalent(at index: Int, of count: Int, nineIsLast: Bool) -> String {
        guard nineIsLast else { return index < 9 ? "\(index + 1)" : "" }
        if index < 8 { return "\(index + 1)" }
        return index == count - 1 ? "9" : ""
    }
}
