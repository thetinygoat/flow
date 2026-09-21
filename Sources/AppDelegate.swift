import AppKit
import GhosttyKit

/// Wires libghostty, the workspace model, and the window together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GhosttyRuntime!
    private let store = WorkspaceStore()
    private var windowController: MainWindowController!
    private var pendingSave: DispatchWorkItem?
    private var modifierMonitor: Any?
    private var hintTimer: Timer?

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
        windowController.applyAppearance(config: runtime.config, app: runtime.app)
        runtime.onConfigChange = { [weak self] in
            guard let self else { return }
            self.windowController.applyAppearance(config: self.runtime.config, app: self.runtime.app)
        }
        store.onChange = { [weak self] in
            self?.windowController.refresh()
            self?.scheduleSave()
        }

        if let session = Session.load(), !session.workspaces.isEmpty {
            restore(session)
        } else {
            newWorkspace()
        }
        windowController.showWindow(nil)
        windowController.terminalArea.focusSelectedSurface()
        NSApp.activate()

        // Holding the command key for a moment reveals shortcut badges on
        // workspaces and tabs.
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.commandKeyChanged(held: event.modifierFlags.contains(.command))
            return event
        }
    }

    private func commandKeyChanged(held: Bool) {
        hintTimer?.invalidate()
        hintTimer = nil
        guard held else {
            windowController.setShortcutHintsVisible(false)
            return
        }
        hintTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
            self?.windowController.setShortcutHintsVisible(true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingSave?.cancel()
        store.session().save()
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

    // MARK: Session

    private func restore(_ session: Session) {
        for saved in session.workspaces {
            let workspace = store.addWorkspace(named: saved.name)
            for tab in saved.tabs {
                addTab(to: workspace, workingDirectory: tab.workingDirectory)
            }
            if saved.selectedTab < workspace.tabs.count {
                workspace.select(workspace.tabs[saved.selectedTab])
            }
            if workspace.tabs.isEmpty {
                addTab(to: workspace)
            }
        }
        if session.selectedWorkspace < store.workspaces.count {
            store.select(store.workspaces[session.selectedWorkspace])
        }
    }

    /// Changes arrive in bursts (every shell prompt updates the directory), so
    /// writes are coalesced.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.session().save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
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

    @objc private func selectWorkspace(_ sender: NSMenuItem) {
        selectWorkspace(at: sender.tag)
    }

    @objc private func previousWorkspace() {
        cycleWorkspace(by: -1)
    }

    @objc private func nextWorkspace() {
        cycleWorkspace(by: 1)
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        guard let workspace = store.selected, sender.tag < workspace.tabs.count else { return }
        workspace.select(workspace.tabs[sender.tag])
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    private func selectWorkspace(at index: Int) {
        guard index >= 0, index < store.workspaces.count else { return }
        store.select(store.workspaces[index])
        windowController.terminalArea.focusSelectedSurface()
    }

    private func cycleWorkspace(by offset: Int) {
        guard let selected = store.selected,
              let index = store.workspaces.firstIndex(where: { $0 === selected }) else { return }
        let count = store.workspaces.count
        selectWorkspace(at: ((index + offset) % count + count) % count)
    }

    private func addTab(to workspace: Workspace, workingDirectory: String? = nil) {
        var configuration = TerminalSurfaceConfiguration()
        configuration.workingDirectory = workingDirectory ?? workspace.selectedTab?.surface.pwd
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

        let workspaceMenu = NSMenu(title: "Workspace")
        workspaceMenu.addItem(withTitle: "Previous Workspace", action: #selector(previousWorkspace), keyEquivalent: "[")
        workspaceMenu.addItem(withTitle: "Next Workspace", action: #selector(nextWorkspace), keyEquivalent: "]")
        workspaceMenu.addItem(.separator())
        for number in 1...9 {
            let item = workspaceMenu.addItem(withTitle: "Workspace \(number)", action: #selector(selectWorkspace(_:)), keyEquivalent: "\(number)")
            item.tag = number - 1
        }
        workspaceMenu.addItem(.separator())
        for number in 1...9 {
            let item = workspaceMenu.addItem(withTitle: "Tab \(number)", action: #selector(selectTab(_:)), keyEquivalent: "\(number)")
            item.keyEquivalentModifierMask = .control
            item.tag = number - 1
        }
        mainMenu.addItem(submenu: workspaceMenu, title: "Workspace")

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

    /// Ghostty's tab bindings (cmd+1..9, cmd+shift+[ and ]) drive workspaces here,
    /// since workspaces are flow's top-level unit.
    func runtime(_ runtime: GhosttyRuntime, wantsGotoTab target: ghostty_action_goto_tab_e) {
        switch target {
        case GHOSTTY_GOTO_TAB_PREVIOUS: cycleWorkspace(by: -1)
        case GHOSTTY_GOTO_TAB_NEXT: cycleWorkspace(by: 1)
        case GHOSTTY_GOTO_TAB_LAST: selectWorkspace(at: store.workspaces.count - 1)
        default: selectWorkspace(at: Int(target.rawValue) - 1)
        }
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
