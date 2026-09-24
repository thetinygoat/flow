import Foundation

extension String {
    /// "/Users/me/Code" becomes "~/Code".
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        guard hasPrefix(home) else { return self }
        return "~" + dropFirst(home.count)
    }

    /// "~/Documents/project" becomes "~/D/project", the way fish shows the prompt.
    var fishStylePath: String {
        var parts = abbreviatingHome.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return abbreviatingHome }
        for index in parts.indices.dropLast() where parts[index] != "~" && !parts[index].isEmpty {
            let keep = parts[index].hasPrefix(".") ? 2 : 1
            parts[index] = String(parts[index].prefix(keep))
        }
        return parts.joined(separator: "/")
    }
}

final class TabModel<Leaf: PaneLeaf> {
    let id = UUID()
    let panes: PaneTreeModel<Leaf>
    private(set) var focusedLeaf: Leaf

    init(leaf: Leaf) {
        panes = PaneTreeModel(leaf: leaf)
        focusedLeaf = leaf
    }

    init(panes: PaneTreeModel<Leaf>, focused: Leaf) {
        self.panes = panes
        focusedLeaf = focused
    }

    var title: String {
        focusedLeaf.title.isEmpty ? "Terminal" : focusedLeaf.title
    }

    func focus(_ leaf: Leaf) {
        guard panes.contains(leaf) else { return }
        focusedLeaf = leaf
    }

    /// Removes a pane that is not the tab's last. Focus only moves when the
    /// removed pane had it, so a pane closing in the background leaves the
    /// user typing where they were.
    func removePane(_ leaf: Leaf) {
        guard let next = panes.remove(leaf), focusedLeaf === leaf else { return }
        focusedLeaf = next
    }
}

final class WorkspaceModel<Leaf: PaneLeaf> {
    let id = UUID()
    /// Set when the user renames the workspace. Otherwise the name follows
    /// the focused pane's directory.
    var customName: String?
    private(set) var tabs: [TabModel<Leaf>] = []
    private(set) var selectedTab: TabModel<Leaf>?

    init(customName: String? = nil) {
        self.customName = customName
    }

    var name: String {
        customName ?? selectedTab?.focusedLeaf.workingDirectory?.fishStylePath ?? "~"
    }

    func add(_ tab: TabModel<Leaf>) {
        tabs.append(tab)
        selectedTab = tab
    }

    func remove(_ tab: TabModel<Leaf>) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: index)
        if selectedTab === tab {
            selectedTab = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)]
        }
    }

    func select(_ tab: TabModel<Leaf>) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        selectedTab = tab
    }

    func tab(containing leaf: Leaf) -> TabModel<Leaf>? {
        tabs.first { $0.panes.contains(leaf) }
    }
}

/// All workspaces plus which one is selected. Observers get `onChange` after every mutation.
final class WorkspaceStoreModel<Leaf: PaneLeaf> {
    private(set) var workspaces: [WorkspaceModel<Leaf>] = []
    private(set) var selected: WorkspaceModel<Leaf>?
    var onChange: (() -> Void)?

    @discardableResult
    func addWorkspace(customName: String? = nil) -> WorkspaceModel<Leaf> {
        let workspace = WorkspaceModel<Leaf>(customName: customName)
        workspaces.append(workspace)
        selected = workspace
        onChange?()
        return workspace
    }

    func remove(_ workspace: WorkspaceModel<Leaf>) {
        guard let index = workspaces.firstIndex(where: { $0 === workspace }) else { return }
        workspaces.remove(at: index)
        if selected === workspace {
            selected = workspaces.isEmpty ? nil : workspaces[min(index, workspaces.count - 1)]
        }
        onChange?()
    }

    func select(_ workspace: WorkspaceModel<Leaf>) {
        selected = workspace
        onChange?()
    }

    func workspace(containing leaf: Leaf) -> (WorkspaceModel<Leaf>, TabModel<Leaf>)? {
        for workspace in workspaces {
            if let tab = workspace.tab(containing: leaf) { return (workspace, tab) }
        }
        return nil
    }

    func notifyChanged() {
        onChange?()
    }
}
