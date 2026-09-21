import Foundation

final class TerminalTab {
    let id = UUID()
    let panes: PaneTree
    private(set) var focusedSurface: TerminalSurfaceView

    init(surface: TerminalSurfaceView) {
        panes = PaneTree(surface: surface)
        focusedSurface = surface
    }

    init(panes: PaneTree, focused: TerminalSurfaceView) {
        self.panes = panes
        focusedSurface = focused
    }

    var title: String {
        focusedSurface.title.isEmpty ? "Terminal" : focusedSurface.title
    }

    func focus(_ surface: TerminalSurfaceView) {
        guard panes.contains(surface) else { return }
        focusedSurface = surface
    }
}

final class Workspace {
    let id = UUID()
    var name: String
    private(set) var tabs: [TerminalTab] = []
    private(set) var selectedTab: TerminalTab?

    init(name: String) {
        self.name = name
    }

    func add(_ tab: TerminalTab) {
        tabs.append(tab)
        selectedTab = tab
    }

    func remove(_ tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: index)
        if selectedTab === tab {
            selectedTab = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)]
        }
    }

    func select(_ tab: TerminalTab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        selectedTab = tab
    }

    func tab(containing surface: TerminalSurfaceView) -> TerminalTab? {
        tabs.first { $0.panes.contains(surface) }
    }
}

/// All workspaces plus which one is selected. Observers get `onChange` after every mutation.
final class WorkspaceStore {
    private(set) var workspaces: [Workspace] = []
    private(set) var selected: Workspace?
    var onChange: (() -> Void)?

    @discardableResult
    func addWorkspace(named name: String) -> Workspace {
        let workspace = Workspace(name: name)
        workspaces.append(workspace)
        selected = workspace
        onChange?()
        return workspace
    }

    func remove(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0 === workspace }) else { return }
        workspaces.remove(at: index)
        if selected === workspace {
            selected = workspaces.isEmpty ? nil : workspaces[min(index, workspaces.count - 1)]
        }
        onChange?()
    }

    func select(_ workspace: Workspace) {
        selected = workspace
        onChange?()
    }

    func workspace(containing surface: TerminalSurfaceView) -> (Workspace, TerminalTab)? {
        for workspace in workspaces {
            if let tab = workspace.tab(containing: surface) { return (workspace, tab) }
        }
        return nil
    }

    func notifyChanged() {
        onChange?()
    }
}
