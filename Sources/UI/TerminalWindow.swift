import AppKit
import GhosttyKit

protocol TerminalWindowDelegate: AnyObject {
    func terminalWindow(_ window: TerminalWindow, makeSurface id: UUID, in directory: String?, workspace: UUID, startImmediately: Bool) -> TerminalSurfaceView
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
        controller.onNewWorkspace = { [weak self] in self?.newWorkspace() }
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
        store.restore(saved) { makeSurface(id: $0, in: $1, workspace: $2, startImmediately: false) }
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
        store.performBatch {
            let workspace = store.addWorkspace()
            workspace.add(TerminalTab(leaf: makeSurface(in: directory, workspace: workspace.id)))
        }
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

    func closeFocusedPane() {
        guard let surface = focusedSurface else { return }
        close(surface)
    }

    func closeSelectedTab() {
        guard let tab = store.selected?.selectedTab else { return }
        close(tab)
    }

    /// Ghostty's close_tab: the surface's own tab, every other tab in its
    /// workspace, or the tabs to its right. One confirmation covers them all.
    func closeTabs(_ mode: TabCloseMode, from surface: TerminalSurfaceView) {
        guard let (workspace, tab) = store.workspace(containing: surface) else { return }
        let closing = workspace.tabs(closing: mode, from: tab)
        guard !closing.isEmpty, confirmClose(closing.flatMap(\.panes.surfaces), what: closing.count == 1 ? "tab" : "tabs") else { return }
        closing.forEach(workspace.remove)
        if workspace.tabs.isEmpty {
            store.remove(workspace)
        } else {
            store.notifyChanged()
        }
        closeWindowIfEmpty()
    }

    func selectWorkspace(at index: Int) {
        guard index >= 0, index < store.workspaces.count else { return }
        store.select(store.workspaces[index])
        controller.terminalArea.focusSelectedSurface()
    }

    func renameSelectedWorkspace() {
        guard let workspace = store.selected else { return }
        controller.beginRename(of: workspace)
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

    /// Switches to the workspace and tab holding the surface and focuses it,
    /// showing every pane if another one is zoomed.
    func reveal(_ surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        if let zoomed = tab.panes.zoomed, zoomed !== surface {
            tab.panes.unzoom()
        }
        show(surface)
        controller.showWindow(nil)
        NSApp.activate()
        controller.terminalArea.focusSelectedSurface()
    }

    /// Switches to the workspace and tab holding the surface and makes it the
    /// tab's focused pane, without moving keyboard focus there.
    private func show(_ surface: TerminalSurfaceView) {
        guard let (workspace, tab) = store.workspace(containing: surface) else { return }
        workspace.select(tab)
        tab.focus(surface)
        store.select(workspace)
    }

    // MARK: Command palette

    /// Opens the palette, or steps to its next item when one of the same mode
    /// is open; one of the other mode is cancelled first. The window shows the
    /// selected item behind the palette while it is in this window, and
    /// otherwise where the palette was opened. `reveal` goes to the chosen
    /// item, in whichever window holds it.
    ///
    /// The items are only made once a palette already open has been
    /// cancelled, so they are listed from where the user is rather than from
    /// a place being previewed.
    func showCommandPalette(_ mode: CommandPalette.Mode, items: @autoclosure () -> [CommandPalette.Item],
                            reveal: @escaping (CommandPalette.Item) -> Void) {
        if let open = controller.commandPalette {
            guard open.mode != mode else { return open.selectNext() }
            open.cancel()
        }
        let restore = rememberPlaces()
        let palette = CommandPaletteView(mode, items: items(), agentIndicator: controller.agentIndicator)
        palette.onSelect = { [weak self] item in
            guard let self else { return }
            guard let item, let surface = surface(withID: item.terminal) else { return restore() }
            show(surface)
        }
        palette.onChoose = { [weak self] item in
            guard let self else { return }
            controller.closeCommandPalette()
            restore()
            reveal(item)
            // Only after the reveal, so the place the palette was opened from
            // is never in view on the way out and keeps a finished agent unseen.
            controller.terminalArea.focusSelectedSurface()
        }
        palette.onCancel = { [weak self] in
            guard let self else { return }
            controller.closeCommandPalette()
            restore()
            controller.terminalArea.focusSelectedSurface()
        }
        controller.showCommandPalette(palette)
    }

    /// Previewing changes which tab each workspace shows and which pane each
    /// tab has focused, including tabs the user never chooses, so the palette
    /// puts them all back when it closes. Otherwise a zoomed tab could be left
    /// focused on a pane hidden by the zoom.
    private func rememberPlaces() -> () -> Void {
        let selected = store.selected
        let selectedTabs = store.workspaces.compactMap { workspace in workspace.selectedTab.map { (workspace, $0) } }
        let focusedPanes = store.workspaces.flatMap(\.tabs).map { ($0, $0.focusedSurface) }
        return { [weak self] in
            guard let self else { return }
            for (tab, surface) in focusedPanes { tab.focus(surface) }
            for (workspace, tab) in selectedTabs { workspace.select(tab) }
            if let selected, store.workspaces.contains(where: { $0 === selected }) {
                store.select(selected)
            } else {
                store.notifyChanged()
            }
        }
    }

    private func makeSurface(id: UUID = UUID(), in directory: String?, workspace: UUID, startImmediately: Bool = true) -> TerminalSurfaceView {
        delegate!.terminalWindow(self, makeSurface: id, in: directory, workspace: workspace, startImmediately: startImmediately)
    }

    private func addTab(to workspace: Workspace) {
        let surface = makeSurface(in: workspace.selectedTab?.focusedSurface.workingDirectory, workspace: workspace.id)
        workspace.add(TerminalTab(leaf: surface))
        store.notifyChanged()
        controller.terminalArea.focusSelectedSurface()
    }

    // MARK: Splits

    func split(_ surface: TerminalSurfaceView, direction: SplitDirection) {
        guard let (workspace, tab) = store.workspace(containing: surface) else { return }
        let added = makeSurface(in: surface.workingDirectory, workspace: workspace.id)
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
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        store.noteFocus(surface)
        guard tab.focusedSurface !== surface else { return }
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
        alert.informativeText = "Closing the \(what) ends whatever is running in it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Closes one pane. The tab closes with its last pane.
    func close(_ surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        guard tab.panes.surfaces.count > 1 else { return close(tab) }
        guard confirmClose([surface], what: "pane") else { return }
        tab.removePane(surface)
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

    /// Menu commands only cancel the key window's palette, and a palette
    /// previewing in a window the user has left would otherwise stay open.
    func windowDidResignKey(_ notification: Notification) {
        controller.commandPalette?.cancel()
    }
}

// MARK: - Sidebar and tab bar

extension TerminalWindow: SidebarViewControllerDelegate, TerminalAreaViewControllerDelegate {
    func sidebar(_ sidebar: SidebarViewController, didSelect workspace: Workspace) {
        store.select(workspace)
        controller.terminalArea.focusSelectedSurface()
    }

    func sidebar(_ sidebar: SidebarViewController, didFinishRenaming workspace: Workspace, to name: String?) {
        if let name { workspace.customName = name }
        store.notifyChanged()
        // Return ends the rename while AppKit is still closing the field, and
        // it then hands focus to the window, so the terminal takes it after.
        DispatchQueue.main.async { [weak self] in
            self?.controller.terminalArea.focusSelectedSurface()
        }
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
