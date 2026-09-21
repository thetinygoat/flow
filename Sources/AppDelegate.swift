import AppKit
import GhosttyKit

/// Wires libghostty, the workspace model, and the window together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GhosttyRuntime!
    private let store = WorkspaceStore()
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            runtime = try GhosttyRuntime()
        } catch {
            let alert = NSAlert()
            alert.messageText = "flow could not start libghostty"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        runtime.delegate = self

        NSApp.mainMenu = buildMainMenu()

        windowController = MainWindowController(store: store)
        windowController.sidebar.delegate = self
        windowController.terminalArea.delegate = self
        store.onChange = { [weak self] in self?.windowController.refresh() }

        newWorkspace()
        windowController.showWindow(nil)
        windowController.terminalArea.focusSelectedSurface()
        NSApp.activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runtime.needsConfirmQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit flow?"
        alert.informativeText = "A terminal still has a running process."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Workspace operations

    @objc func newWorkspace() {
        let workspace = store.addWorkspace(named: "Workspace \(store.workspaces.count + 1)")
        addTab(to: workspace)
    }

    @objc func newTab() {
        guard let workspace = store.selected else { return newWorkspace() }
        addTab(to: workspace)
    }

    @objc func closeTab() {
        guard let tab = store.selected?.selectedTab else { return }
        close(tab.surface)
    }

    private func addTab(to workspace: Workspace) {
        var configuration = TerminalSurfaceConfiguration()
        configuration.workingDirectory = workspace.selectedTab?.surface.pwd
        let surface = TerminalSurfaceView(runtime: runtime, configuration: configuration)
        surface.delegate = self
        workspace.add(TerminalTab(surface: surface))
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    private func close(_ surface: TerminalSurfaceView) {
        guard let (workspace, tab) = store.workspace(containing: surface) else { return }
        if surface.needsConfirmQuit {
            let alert = NSAlert()
            alert.messageText = "Close terminal?"
            alert.informativeText = "The terminal still has a running process."
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        workspace.remove(tab)
        if workspace.tabs.isEmpty {
            store.remove(workspace)
        } else {
            store.notifyChanged()
        }
        if store.workspaces.isEmpty {
            NSApp.terminate(nil)
            return
        }
        windowController.terminalArea.focusSelectedSurface()
    }

    private func close(_ tab: TerminalTab) {
        close(tab.surface)
    }

    // MARK: Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenu: appMenu, title: "flow")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Workspace", action: #selector(newWorkspace), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        mainMenu.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenu: editMenu, title: "Edit")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        mainMenu.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}

extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

// MARK: - GhosttyRuntimeDelegate

extension AppDelegate: GhosttyRuntimeDelegate {
    func runtimeWantsNewWorkspace(_ runtime: GhosttyRuntime) {
        newWorkspace()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsNewTabFrom surface: TerminalSurfaceView?) {
        if let surface, let (workspace, _) = store.workspace(containing: surface) {
            addTab(to: workspace)
        } else {
            newTab()
        }
    }

    func runtime(_ runtime: GhosttyRuntime, wantsSplit direction: ghostty_action_split_direction_e, from surface: TerminalSurfaceView) -> Bool {
        logger.info("splits are not implemented yet")
        return false
    }

    func runtime(_ runtime: GhosttyRuntime, wantsClose surface: TerminalSurfaceView) {
        close(surface)
    }
}

// MARK: - UI delegates

extension AppDelegate: SidebarViewControllerDelegate, TerminalAreaViewControllerDelegate, TerminalSurfaceViewDelegate {
    func sidebar(_ sidebar: SidebarViewController, didSelect workspace: Workspace) {
        store.select(workspace)
        windowController.terminalArea.focusSelectedSurface()
    }

    func sidebar(_ sidebar: SidebarViewController, didRename workspace: Workspace, to name: String) {
        workspace.name = name
        store.notifyChanged()
    }

    func terminalArea(_ area: TerminalAreaViewController, didSelect tab: TerminalTab, in workspace: Workspace) {
        workspace.select(tab)
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    func terminalArea(_ area: TerminalAreaViewController, didClose tab: TerminalTab, in workspace: Workspace) {
        close(tab)
    }

    func surfaceDidChange(_ surface: TerminalSurfaceView) {
        windowController.refresh()
    }
}
