import AppKit
import GhosttyKit

protocol TerminalWindowDelegate: AnyObject {
    func terminalWindow(_ window: TerminalWindow, makeSurfaceIn directory: String?) -> TerminalSurfaceView
    func terminalWindowDidChange(_ window: TerminalWindow)
    func terminalWindowWillClose(_ window: TerminalWindow)
}

/// One window and the workspaces in it. Everything that happens inside a
/// window — tabs, splits, zoom, switching and closing — goes through here.
final class TerminalWindow: NSObject, NSWindowDelegate {
    let store = WorkspaceStore()
    let controller: MainWindowController
    weak var delegate: TerminalWindowDelegate?
    private let config: () -> GhosttyConfig

    init(frame: CGRect?, config: @escaping () -> GhosttyConfig) {
        self.config = config
        controller = MainWindowController(store: store, frame: frame)
        super.init()
        controller.window?.delegate = self
        controller.sidebar.delegate = self
        controller.terminalArea.delegate = self
        controller.onResetZoom = { [weak self] in self?.resetZoom() }
        store.onChange = { [weak self] in
            guard let self else { return }
            self.controller.refresh()
            self.delegate?.terminalWindowDidChange(self)
        }
    }

    var window: NSWindow? { controller.window }

    func show() {
        controller.showWindow(nil)
        controller.terminalArea.focusSelectedSurface()
    }

    // MARK: Session

    func snapshot() -> Session.Window {
        store.snapshot(frame: window?.frame)
    }

    func restore(_ saved: Session.Window) {
        store.restore(saved) { makeSurface(in: $0) }
    }

    // MARK: Lookup

    func contains(_ surface: TerminalSurfaceView) -> Bool {
        store.workspace(containing: surface) != nil
    }

    func surface(withID id: UUID) -> TerminalSurfaceView? {
        store.workspaces.lazy.flatMap(\.tabs).flatMap(\.panes.surfaces).first { $0.id == id }
    }

    var focusedSurface: TerminalSurfaceView? {
        store.selected?.selectedTab?.focusedSurface
    }

    /// True when the user is looking at this terminal right now.
    func isInView(_ surface: TerminalSurfaceView) -> Bool {
        NSApp.isActive && window?.isKeyWindow == true && surface.focused
    }

    // MARK: Workspaces and tabs

    /// Without a directory the workspace starts where the shell's own default is.
    func newWorkspace(in directory: String? = nil) {
        let workspace = store.addWorkspace()
        workspace.add(TerminalTab(leaf: makeSurface(in: directory)))
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func newTab() {
        guard let workspace = store.selected else { return newWorkspace() }
        addTab(to: workspace)
    }

    func newTab(nextTo surface: TerminalSurfaceView) {
        guard let (workspace, _) = store.workspace(containing: surface) else { return newTab() }
        addTab(to: workspace)
    }

    func closeSelectedTab() {
        guard let tab = store.selected?.selectedTab else { return }
        close(tab)
    }

    func selectWorkspace(at index: Int) {
        guard index >= 0, index < store.workspaces.count else { return }
        store.select(store.workspaces[index])
        controller.terminalArea.focusSelectedSurface()
    }

    func cycleWorkspace(by offset: Int) {
        guard let selected = store.selected,
              let index = store.workspaces.firstIndex(where: { $0 === selected }) else { return }
        let count = store.workspaces.count
        selectWorkspace(at: ((index + offset) % count + count) % count)
    }

    /// Ghostty's tab bindings (cmd+1..9, cmd+shift+[ and ]) drive workspaces,
    /// since workspaces are Flow's top-level unit.
    func gotoWorkspace(_ target: ghostty_action_goto_tab_e) {
        switch target {
        case GHOSTTY_GOTO_TAB_PREVIOUS: cycleWorkspace(by: -1)
        case GHOSTTY_GOTO_TAB_NEXT: cycleWorkspace(by: 1)
        case GHOSTTY_GOTO_TAB_LAST: selectWorkspace(at: store.workspaces.count - 1)
        default: selectWorkspace(at: Int(target.rawValue) - 1)
        }
    }

    func selectTab(at index: Int) {
        guard let workspace = store.selected, index < workspace.tabs.count else { return }
        workspace.select(workspace.tabs[index])
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    /// Switches to the workspace and tab holding the surface and focuses it.
    func reveal(_ surface: TerminalSurfaceView) {
        guard let (workspace, tab) = store.workspace(containing: surface) else { return }
        workspace.select(tab)
        tab.focus(surface)
        store.select(workspace)
        controller.showWindow(nil)
        NSApp.activate()
        controller.terminalArea.focusSelectedSurface()
    }

    private func makeSurface(in directory: String?) -> TerminalSurfaceView {
        delegate!.terminalWindow(self, makeSurfaceIn: directory)
    }

    private func addTab(to workspace: Workspace) {
        let surface = makeSurface(in: workspace.selectedTab?.focusedSurface.workingDirectory)
        workspace.add(TerminalTab(leaf: surface))
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    // MARK: Splits

    func split(_ surface: TerminalSurfaceView, direction: SplitDirection) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        let added = makeSurface(in: surface.workingDirectory)
        tab.panes.split(surface, direction: direction, with: added)
        tab.focus(added)
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func splitFocused(_ direction: SplitDirection) {
        guard let surface = focusedSurface else { return }
        split(surface, direction: direction)
    }

    /// Hidden panes have no frames to navigate by, so a zoomed tab is laid out
    /// in full before looking for the neighbor.
    func gotoSplit(_ direction: PaneNavigation, from surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        let wasZoomed = tab.panes.zoomed != nil
        if wasZoomed {
            tab.panes.unzoom()
            controller.terminalArea.show(store.selected)
            controller.terminalArea.view.layoutSubtreeIfNeeded()
        }
        guard let target = tab.panes.neighbor(of: surface, direction: direction, frame: { $0.convert($0.bounds, to: nil) }) else {
            if wasZoomed { tab.panes.toggleZoom(surface) }
            store.notifyChanged()
            controller.terminalArea.focusSelectedSurface()
            return
        }
        tab.focus(target)
        if wasZoomed && config().zoomFollowsNavigation {
            tab.panes.toggleZoom(target)
        }
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func toggleZoom(_ surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        tab.panes.toggleZoom(surface)
        tab.focus(surface)
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    private func resetZoom() {
        guard let tab = store.selected?.selectedTab else { return }
        tab.panes.unzoom()
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func resizeSplit(_ surface: TerminalSurfaceView, direction: ResizeDirection, amount: Int) {
        controller.terminalArea.paneTreeView.resize(surface, direction: direction, amount: CGFloat(amount))
    }

    func equalizeSplits(from surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        tab.panes.equalize()
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func surfaceDidFocus(_ surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface), tab.focusedSurface !== surface else { return }
        tab.focus(surface)
        controller.refresh()
    }

    // MARK: Closing

    private var allSurfaces: [TerminalSurfaceView] {
        store.workspaces.flatMap(\.tabs).flatMap(\.panes.surfaces)
    }

    private func confirmClose(_ surfaces: [TerminalSurfaceView], what: String) -> Bool {
        guard surfaces.contains(where: \.needsConfirmQuit) else { return true }
        let alert = NSAlert()
        alert.messageText = "Close this \(what)?"
        alert.informativeText = "It still has a running process. Closing the \(what) will kill it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Closes one pane. The tab closes with its last pane.
    func close(_ surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        guard tab.panes.surfaces.count > 1 else { return close(tab) }
        guard confirmClose([surface], what: "pane") else { return }
        if let next = tab.panes.remove(surface) {
            tab.focus(next)
        }
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func close(_ workspace: Workspace) {
        guard confirmClose(workspace.tabs.flatMap(\.panes.surfaces), what: "workspace") else { return }
        store.remove(workspace)
        closeWindowIfEmpty()
    }

    func close(_ tab: TerminalTab) {
        guard let workspace = store.workspaces.first(where: { $0.tabs.contains { $0 === tab } }) else { return }
        guard confirmClose(tab.panes.surfaces, what: "tab") else { return }
        workspace.remove(tab)
        if workspace.tabs.isEmpty {
            store.remove(workspace)
        } else {
            store.notifyChanged()
        }
        closeWindowIfEmpty()
    }

    private func closeWindowIfEmpty() {
        if store.workspaces.isEmpty {
            window?.close()
        } else {
            controller.terminalArea.focusSelectedSurface()
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmClose(allSurfaces, what: "window")
    }

    func windowWillClose(_ notification: Notification) {
        delegate?.terminalWindowWillClose(self)
    }
}

// MARK: - Sidebar and tab bar

extension TerminalWindow: SidebarViewControllerDelegate, TerminalAreaViewControllerDelegate {
    func sidebar(_ sidebar: SidebarViewController, didSelect workspace: Workspace) {
        store.select(workspace)
        controller.terminalArea.focusSelectedSurface()
    }

    func sidebar(_ sidebar: SidebarViewController, didRename workspace: Workspace, to name: String) {
        workspace.customName = name
        store.notifyChanged()
    }

    func sidebar(_ sidebar: SidebarViewController, wantsClose workspace: Workspace) {
        close(workspace)
    }

    func terminalArea(_ area: TerminalAreaViewController, didSelect tab: TerminalTab, in workspace: Workspace) {
        workspace.select(tab)
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    func terminalArea(_ area: TerminalAreaViewController, didClose tab: TerminalTab, in workspace: Workspace) {
        close(tab)
    }
}
