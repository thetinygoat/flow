import Foundation

extension String {
    /// "/Users/me/Code" becomes "~/Code".
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        guard self == home || hasPrefix(home + "/") else { return self }
        return "~" + dropFirst(home.count)
    }

    /// "/Users/me/Code/flow" becomes "flow"; home and the root keep "~" and "/".
    var folderName: String {
        let path = abbreviatingHome
        guard path != "~", path != "/" else { return path }
        return (path as NSString).lastPathComponent
    }
}

extension PaneLeaf {
    /// The terminal's own title, or else where it is.
    var displayTitle: String {
        if !title.isEmpty { return title }
        guard let workingDirectory, !workingDirectory.isEmpty else { return "Terminal" }
        return workingDirectory.abbreviatingHome
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
        focusedLeaf.displayTitle
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

/// Which tabs a close-tab request closes, relative to the tab it came from.
enum TabCloseMode {
    case this, others, right
}

final class WorkspaceModel<Leaf: PaneLeaf> {
    let id: UUID
    /// Set when the user renames the workspace. Otherwise the name follows
    /// the focused pane's directory.
    var customName: String?
    private(set) var tabs: [TabModel<Leaf>] = []
    private(set) var selectedTab: TabModel<Leaf>?
    private var derivedName: (directory: String, name: String)?
    private let resolveName: (String) -> String

    init(id: UUID = UUID(), customName: String? = nil,
         resolveName: @escaping (String) -> String = { WorkspaceModel<Leaf>.name(forDirectory: $0) }) {
        self.id = id
        self.customName = customName
        self.resolveName = resolveName
    }

    var name: String {
        if let customName { return customName }
        guard let directory = selectedTab?.focusedLeaf.workingDirectory else { return "~" }
        if let derivedName, derivedName.directory == directory { return derivedName.name }
        let name = resolveName(directory)
        derivedName = (directory, name)
        return name
    }

    func invalidateDerivedName() {
        derivedName = nil
    }

    /// Inside a repository the workspace is named after it, so it keeps its
    /// name in a subdirectory. A repository at home holds dotfiles rather than
    /// a project, so it names nothing.
    static func name(forDirectory directory: String, home: String? = GitRepository.home) -> String {
        guard let repository = GitRepository(containing: directory), repository.workTree != home else {
            return directory.folderName
        }
        return (repository.workTree as NSString).lastPathComponent
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

    func tabs(closing mode: TabCloseMode, from tab: TabModel<Leaf>) -> [TabModel<Leaf>] {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return [] }
        switch mode {
        case .this: return [tab]
        case .others: return tabs.filter { $0 !== tab }
        case .right: return Array(tabs[(index + 1)...])
        }
    }

    func tab(containing leaf: Leaf) -> TabModel<Leaf>? {
        tabs.first { $0.panes.contains(leaf) }
    }
}

/// All workspaces plus which one is selected. Observers get `onChange` after
/// each mutation, or once at the end of the outermost nonempty batch.
final class WorkspaceStoreModel<Leaf: PaneLeaf> {
    private(set) var workspaces: [WorkspaceModel<Leaf>] = []
    private(set) var selected: WorkspaceModel<Leaf>?
    /// Terminals by when they last had focus, most recent first.
    private(set) var recentlyFocused: [UUID] = []
    var onChange: (() -> Void)?
    private var batchDepth = 0
    private var hasPendingChange = false

    /// The new workspace goes right after the selected one, next to the work
    /// it was opened from, and becomes the selected one.
    @discardableResult
    func addWorkspace(id: UUID = UUID(), customName: String? = nil) -> WorkspaceModel<Leaf> {
        let workspace = WorkspaceModel<Leaf>(id: id, customName: customName)
        let index = selected.flatMap { selected in workspaces.firstIndex { $0 === selected } }.map { $0 + 1 } ?? workspaces.endIndex
        workspaces.insert(workspace, at: index)
        selected = workspace
        notifyChanged()
        return workspace
    }

    func remove(_ workspace: WorkspaceModel<Leaf>) {
        guard let index = workspaces.firstIndex(where: { $0 === workspace }) else { return }
        workspaces.remove(at: index)
        if selected === workspace {
            selected = workspaces.isEmpty ? nil : workspaces[min(index, workspaces.count - 1)]
        }
        notifyChanged()
    }

    func select(_ workspace: WorkspaceModel<Leaf>) {
        selected = workspace
        notifyChanged()
    }

    @discardableResult
    func move(_ workspace: WorkspaceModel<Leaf>, toInsertionIndex index: Int) -> Bool {
        guard (0...workspaces.count).contains(index),
              let source = workspaces.firstIndex(where: { $0 === workspace }) else { return false }
        let destination = index > source ? index - 1 : index
        guard source != destination else { return true }
        workspaces.remove(at: source)
        workspaces.insert(workspace, at: destination)
        notifyChanged()
        return true
    }

    func noteFocus(_ leaf: Leaf) {
        recentlyFocused.removeAll { $0 == leaf.id }
        recentlyFocused.insert(leaf.id, at: 0)
    }

    func workspace(containing leaf: Leaf) -> (WorkspaceModel<Leaf>, TabModel<Leaf>)? {
        for workspace in workspaces {
            if let tab = workspace.tab(containing: leaf) { return (workspace, tab) }
        }
        return nil
    }

    func notifyChanged() {
        guard batchDepth == 0 else {
            hasPendingChange = true
            return
        }
        onChange?()
    }

    func performBatch(_ changes: () -> Void) {
        batchDepth += 1
        changes()
        batchDepth -= 1
        if batchDepth == 0, hasPendingChange {
            hasPendingChange = false
            notifyChanged()
        }
    }
}
