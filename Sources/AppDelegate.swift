import AppKit
import UniformTypeIdentifiers
import GhosttyKit

/// Wires libghostty, the workspace model, and the window together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GhosttyRuntime!
    private let store = WorkspaceStore()
    private var windowController: MainWindowController!
    private var pendingSave: DispatchWorkItem?
    private var modifierMonitor: Any?
    private var hintTimer: Timer?
    private var hintsSuppressed = false
    private lazy var aboutWindow = AboutWindowController()
    private let notifications = DesktopNotifications()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            runtime = try GhosttyRuntime()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Flow could not start libghostty"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        runtime.delegate = self
        notifications.isInView = { [weak self] id in
            guard let self, let surface = self.surface(withID: id) else { return false }
            return self.isInView(surface)
        }
        notifications.onOpen = { [weak self] id in
            guard let self, let surface = self.surface(withID: id) else { return }
            self.reveal(surface)
        }
        SecureInput.shared.global = UserDefaults.standard.bool(forKey: Self.secureKeyboardEntryKey)

        NSApp.mainMenu = buildMainMenu()

        windowController = MainWindowController(store: store)
        windowController.sidebar.delegate = self
        windowController.onResetZoom = { [weak self] in self?.resetZoom() }
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

        if let window = Session.load()?.windows.first, !window.workspaces.isEmpty {
            restore(window)
        } else {
            newWorkspace()
        }
        windowController.showWindow(nil)
        windowController.terminalArea.focusSelectedSurface()
        NSApp.activate()

        // Holding command or control for a moment reveals the shortcut badges
        // for that modifier. Once a key is pressed the shortcut has been used,
        // so the badges stay hidden until the modifier is released.
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.updateShortcutHints(for: event)
            return event
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hintTimer?.invalidate()
            self?.hintsSuppressed = false
            self?.windowController.showShortcutHints(for: nil)
        }
        // Returning to Flow with the alerting terminal already focused never
        // refocuses it, so its attention mark is cleared here.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let surface = self.store.selected?.selectedTab?.focusedSurface,
                  self.windowController.window?.firstResponder === surface else { return }
            surface.needsAttention = false
        }
    }

    private func updateShortcutHints(for event: NSEvent) {
        hintTimer?.invalidate()
        windowController.showShortcutHints(for: nil)
        let modifiers = event.modifierFlags.intersection(ShortcutModifier.relevantFlags)
        if event.type == .keyDown {
            hintsSuppressed = true
        } else if modifiers.isEmpty {
            hintsSuppressed = false
        }
        guard !hintsSuppressed, let modifier = ShortcutModifier(modifiers) else { return }
        hintTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
            self?.windowController.showShortcutHints(for: modifier)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingSave?.cancel()
        session().save()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runtime.needsConfirmQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Flow?"
        alert.informativeText = "A terminal still has a running process."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: Session

    private func session() -> Session {
        Session(windows: [store.snapshot(frame: windowController.window?.frame)])
    }

    private func restore(_ window: Session.Window) {
        store.restore(window) { makeSurface(workingDirectory: $0) }
        if store.workspaces.isEmpty {
            newWorkspace()
        }
    }

    /// Changes arrive in bursts (every shell prompt updates the directory), so
    /// writes are coalesced.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.session().save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: Workspace operations

    @objc func newWorkspace() {
        addTab(to: store.addWorkspace())
    }

    @objc func newTab() {
        guard let workspace = store.selected else { return newWorkspace() }
        addTab(to: workspace)
    }

    @objc func closeTab() {
        guard let tab = store.selected?.selectedTab else { return }
        close(tab)
    }

    @objc private func splitRight() {
        guard let surface = store.selected?.selectedTab?.focusedSurface else { return }
        split(surface, direction: .right)
    }

    @objc private func splitDown() {
        guard let surface = store.selected?.selectedTab?.focusedSurface else { return }
        split(surface, direction: .down)
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

    private func isInView(_ surface: TerminalSurfaceView) -> Bool {
        NSApp.isActive && windowController.window?.isKeyWindow == true && surface.focused
    }

    private func surface(withID id: UUID) -> TerminalSurfaceView? {
        store.workspaces.lazy.flatMap(\.tabs).flatMap(\.panes.surfaces).first { $0.id == id }
    }

    /// Switches to the workspace and tab holding the surface and focuses it.
    private func reveal(_ surface: TerminalSurfaceView) {
        guard let (workspace, tab) = store.workspace(containing: surface) else { return }
        workspace.select(tab)
        tab.focus(surface)
        store.select(workspace)
        windowController.showWindow(nil)
        NSApp.activate()
        windowController.terminalArea.focusSelectedSurface()
    }

    private func makeSurface(workingDirectory: String?) -> TerminalSurfaceView {
        var configuration = TerminalSurfaceConfiguration()
        configuration.workingDirectory = workingDirectory
        let surface = TerminalSurfaceView(runtime: runtime, configuration: configuration)
        surface.delegate = self
        return surface
    }

    private func addTab(to workspace: Workspace) {
        let surface = makeSurface(workingDirectory: workspace.selectedTab?.focusedSurface.workingDirectory)
        workspace.add(TerminalTab(leaf: surface))
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    private func split(_ surface: TerminalSurfaceView, direction: SplitDirection) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        let added = makeSurface(workingDirectory: surface.workingDirectory)
        tab.panes.split(surface, direction: direction, with: added)
        tab.focus(added)
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
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
    private func close(_ surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        guard tab.panes.surfaces.count > 1 else { return close(tab) }
        guard confirmClose([surface], what: "pane") else { return }
        if let next = tab.panes.remove(surface) {
            tab.focus(next)
        }
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    private func close(_ workspace: Workspace) {
        guard confirmClose(workspace.tabs.flatMap(\.panes.surfaces), what: "workspace") else { return }
        store.remove(workspace)
        if store.workspaces.isEmpty {
            NSApp.terminate(nil)
            return
        }
        windowController.terminalArea.focusSelectedSurface()
    }

    private func close(_ tab: TerminalTab) {
        guard let workspace = store.workspaces.first(where: { $0.tabs.contains { $0 === tab } }) else { return }
        guard confirmClose(tab.panes.surfaces, what: "tab") else { return }
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

    // MARK: App

    private static let secureKeyboardEntryKey = "SecureKeyboardEntry"

    @objc private func toggleSecureKeyboardEntry() {
        setSecureKeyboardEntry(!SecureInput.shared.global)
    }

    private func setSecureKeyboardEntry(_ enabled: Bool) {
        SecureInput.shared.global = enabled
        UserDefaults.standard.set(enabled, forKey: Self.secureKeyboardEntryKey)
    }

    @objc private func openConfig() {
        let url = URL(fileURLWithPath: GhosttyConfig.editablePath)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        // Ghostty config files have no extension, so they are opened as plain
        // text rather than with whatever claims extensionless files.
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func reloadConfig() {
        runtime.reloadConfig()
    }

    @objc private func showAbout() {
        aboutWindow.showWindow(nil)
        aboutWindow.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Flow", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openConfig), keyEquivalent: ",")
        let reloadItem = appMenu.addItem(withTitle: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: ",")
        reloadItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Secure Keyboard Entry", action: #selector(toggleSecureKeyboardEntry), keyEquivalent: "")
        appMenu.addItem(.separator())
        let servicesMenu = NSMenu(title: "Services")
        appMenu.addItem(submenu: servicesMenu, title: "Services")
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Flow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenu: appMenu, title: "Flow")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Workspace", action: #selector(newWorkspace), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Split Right", action: #selector(splitRight), keyEquivalent: "d")
        let splitDownItem = fileMenu.addItem(withTitle: "Split Down", action: #selector(splitDown), keyEquivalent: "d")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        mainMenu.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(withTitle: "Find…", action: #selector(TerminalSurfaceView.findInScrollback(_:)), keyEquivalent: "f")
        findMenu.addItem(withTitle: "Find Next", action: #selector(TerminalSurfaceView.findNext(_:)), keyEquivalent: "g")
        let findPrevious = findMenu.addItem(withTitle: "Find Previous", action: #selector(TerminalSurfaceView.findPrevious(_:)), keyEquivalent: "g")
        findPrevious.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(withTitle: "Use Selection for Find", action: #selector(TerminalSurfaceView.useSelectionForFind(_:)), keyEquivalent: "e")
        editMenu.addItem(submenu: findMenu, title: "Find")
        mainMenu.addItem(submenu: editMenu, title: "Edit")

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Increase Font Size", action: #selector(TerminalSurfaceView.increaseFontSize(_:)), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "Decrease Font Size", action: #selector(TerminalSurfaceView.decreaseFontSize(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Font Size", action: #selector(TerminalSurfaceView.resetFontSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        let zoomItem = viewMenu.addItem(withTitle: "Zoom Split", action: #selector(TerminalSurfaceView.toggleSplitZoom(_:)), keyEquivalent: "\r")
        zoomItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        let sidebarItem = viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        let fullScreenItem = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        mainMenu.addItem(submenu: viewMenu, title: "View")

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
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        mainMenu.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSecureKeyboardEntry) {
            menuItem.state = SecureInput.shared.global ? .on : .off
        }
        return true
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

    func runtime(_ runtime: GhosttyRuntime, wantsSplit direction: SplitDirection, from surface: TerminalSurfaceView) -> Bool {
        split(surface, direction: direction)
        return true
    }

    /// Hidden panes have no frames to navigate by, so a zoomed tab is laid out
    /// in full before looking for the neighbor.
    func runtime(_ runtime: GhosttyRuntime, wantsGotoSplit direction: PaneNavigation, from surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        let wasZoomed = tab.panes.zoomed != nil
        if wasZoomed {
            tab.panes.unzoom()
            windowController.terminalArea.show(store.selected)
            windowController.terminalArea.view.layoutSubtreeIfNeeded()
        }
        guard let target = tab.panes.neighbor(of: surface, direction: direction, frame: { $0.convert($0.bounds, to: nil) }) else {
            if wasZoomed { tab.panes.toggleZoom(surface) }
            store.notifyChanged()
            windowController.terminalArea.focusSelectedSurface()
            return
        }
        tab.focus(target)
        if wasZoomed && runtime.config.zoomFollowsNavigation {
            tab.panes.toggleZoom(target)
        }
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsToggleZoomFrom surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        tab.panes.toggleZoom(surface)
        tab.focus(surface)
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    @objc private func resetZoom() {
        guard let tab = store.selected?.selectedTab else { return }
        tab.panes.unzoom()
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsResizeSplit direction: ResizeDirection, amount: Int, from surface: TerminalSurfaceView) {
        windowController.terminalArea.paneTreeView.resize(surface, direction: direction, amount: CGFloat(amount))
    }

    func runtime(_ runtime: GhosttyRuntime, wantsEqualizeSplitsFrom surface: TerminalSurfaceView) {
        guard let (_, tab) = store.workspace(containing: surface) else { return }
        tab.panes.equalize()
        store.notifyChanged()
        windowController.terminalArea.focusSelectedSurface()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsSecureKeyboardEntry enabled: Bool) {
        setSecureKeyboardEntry(enabled)
    }

    func runtimeWantsOpenConfig(_ runtime: GhosttyRuntime) {
        openConfig()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsNotification title: String, body: String, from surface: TerminalSurfaceView) {
        guard !isInView(surface) else { return }
        surface.needsAttention = true
        let workspace = store.workspace(containing: surface)?.0.name ?? ""
        notifications.post(title: title, body: body, subtitle: workspace, from: surface.id)
    }

    func runtime(_ runtime: GhosttyRuntime, didFinish command: CommandFinish, in surface: TerminalSurfaceView) {
        let config = runtime.config
        let when = config.notifyOnCommandFinish
        guard command.shouldAlert(when: when, inView: isInView(surface), minimumDuration: config.notifyOnCommandFinishAfter) else { return }
        if !isInView(surface) {
            surface.needsAttention = true
        }
        let actions = config.notifyOnCommandFinishAction
        if actions.contains(.bell) {
            NSSound.beep()
        }
        if actions.contains(.notify) {
            let workspace = store.workspace(containing: surface)?.0.name ?? ""
            notifications.post(title: command.title, body: command.body, subtitle: workspace, from: surface.id, evenIfInView: when == .always)
        }
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
        workspace.customName = name
        store.notifyChanged()
    }

    func sidebar(_ sidebar: SidebarViewController, wantsClose workspace: Workspace) {
        close(workspace)
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
        scheduleSave()
    }

    func surfaceDidFocus(_ surface: TerminalSurfaceView) {
        notifications.clear(for: surface.id)
        surface.needsAttention = false
        guard let (_, tab) = store.workspace(containing: surface), tab.focusedSurface !== surface else { return }
        tab.focus(surface)
        windowController.refresh()
    }
}
