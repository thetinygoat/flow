import AppKit
import UniformTypeIdentifiers
import GhosttyKit
import Sparkle

/// Wires libghostty, the windows, and the app-wide pieces (menus,
/// notifications, secure input, saving) together. Each window manages its own
/// workspaces; this routes actions to the right one.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GhosttyRuntime!
    private var windows: [TerminalWindow] = []
    /// Folders macOS asked to open before launch finished.
    private var pendingDirectories: [String]? = []
    private var pendingSave: DispatchWorkItem?
    private var modifierMonitor: Any?
    private var hintTimer: Timer?
    private var hintsSuppressed = false
    private lazy var aboutWindow = AboutWindowController()
    private let notifications = DesktopNotifications()
    /// Sparkle asks on the second launch whether to check for updates
    /// automatically; nothing is checked before the user agrees.
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var serviceProvider = ServiceProvider { [weak self] directory, newWindow in
        self?.openWorkspace(in: directory, newWindow: newWindow)
    }

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
        runtime.onConfigChange = { [weak self] in
            guard let self else { return }
            for window in self.windows {
                window.controller.applyAppearance(config: self.runtime.config, app: self.runtime.app)
            }
        }
        notifications.isInView = { [weak self] id in
            guard let self, let (window, surface) = self.surface(withID: id) else { return false }
            return window.isInView(surface)
        }
        notifications.onOpen = { [weak self] id in
            guard let self, let (window, surface) = self.surface(withID: id) else { return }
            window.reveal(surface)
        }
        SecureInput.shared.global = UserDefaults.standard.bool(forKey: Self.secureKeyboardEntryKey)

        NSApp.mainMenu = buildMainMenu()
        NSApp.servicesProvider = serviceProvider

        let saved = Session.load()?.windows.filter { !$0.workspaces.isEmpty } ?? []
        for savedWindow in saved {
            let window = makeWindow(frame: savedWindow.frame)
            window.restore(savedWindow)
            if window.store.workspaces.isEmpty {
                window.newWorkspace()
            }
        }
        if windows.isEmpty {
            newWindow()
        }
        windows.forEach { $0.show() }
        NSApp.activate()
        pendingDirectories?.forEach { openWorkspace(in: $0, newWindow: false) }
        pendingDirectories = nil

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
            self?.windows.forEach { $0.controller.showShortcutHints(for: nil) }
        }
    }

    private func updateShortcutHints(for event: NSEvent) {
        hintTimer?.invalidate()
        windows.forEach { $0.controller.showShortcutHints(for: nil) }
        let modifiers = event.modifierFlags.intersection(ShortcutModifier.relevantFlags)
        if event.type == .keyDown {
            hintsSuppressed = true
        } else if modifiers.isEmpty {
            hintsSuppressed = false
        }
        guard !hintsSuppressed, let modifier = ShortcutModifier(modifiers), let window = currentWindow else { return }
        hintTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { _ in
            window.controller.showShortcutHints(for: modifier)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingSave?.cancel()
        session().save()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Without a runtime, libghostty never started and nothing is running.
        guard runtime?.needsConfirmQuit == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Flow?"
        alert.informativeText = "A terminal still has a running process."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Folders dropped on the Dock icon or passed to `open -a Flow` each open
    /// as a workspace.
    func application(_ application: NSApplication, open urls: [URL]) {
        let directories = urls.filter { url in
            var isDirectory: ObjCBool = false
            return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }.map { $0.path(percentEncoded: false) }
        if pendingDirectories != nil {
            pendingDirectories?.append(contentsOf: directories)
        } else {
            directories.forEach { openWorkspace(in: $0, newWindow: false) }
        }
    }

    /// Clicking the Dock icon with every window closed opens a new one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if windows.isEmpty {
            newWindow()
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "").target = self
        return menu
    }

    // MARK: Windows

    /// The window menu commands and keyboard shortcuts act on.
    private var currentWindow: TerminalWindow? {
        windows.first { $0.window === NSApp.keyWindow }
            ?? windows.first { $0.window === NSApp.mainWindow }
            ?? windows.last
    }

    private func window(containing surface: TerminalSurfaceView) -> TerminalWindow? {
        windows.first { $0.contains(surface) }
    }

    private func surface(withID id: UUID) -> (TerminalWindow, TerminalSurfaceView)? {
        for window in windows {
            if let surface = window.surface(withID: id) { return (window, surface) }
        }
        return nil
    }

    private func makeWindow(frame: CGRect?) -> TerminalWindow {
        let window = TerminalWindow(frame: frame) { [unowned self] in self.runtime.config }
        window.delegate = self
        window.controller.applyAppearance(config: runtime.config, app: runtime.app)
        windows.append(window)
        return window
    }

    @objc private func newWindow() {
        openWorkspace(in: nil, newWindow: true)
    }

    /// Opens a workspace in the directory, in the front window unless a new one
    /// is asked for or there is no window.
    func openWorkspace(in directory: String?, newWindow: Bool) {
        if !newWindow, let window = currentWindow {
            window.newWorkspace(in: directory)
            window.show()
        } else {
            let window = makeWindow(frame: nil)
            window.newWorkspace(in: directory)
            window.show()
        }
        NSApp.activate()
    }

    private func session() -> Session {
        Session(windows: windows.map { $0.snapshot() })
    }

    /// Changes arrive in bursts (every shell prompt updates the directory), so
    /// writes are coalesced.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.session().save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: Menu actions

    @objc func newWorkspace() {
        guard let window = currentWindow else { return newWindow() }
        window.newWorkspace()
    }

    @objc func newTab() {
        guard let window = currentWindow else { return newWindow() }
        window.newTab()
    }

    @objc private func closePane() {
        currentWindow?.closeFocusedPane()
    }

    @objc func closeTab() {
        currentWindow?.closeSelectedTab()
    }

    @objc private func splitRight() {
        currentWindow?.splitFocused(.right)
    }

    @objc private func splitDown() {
        currentWindow?.splitFocused(.down)
    }

    @objc private func selectWorkspace(_ sender: NSMenuItem) {
        currentWindow?.selectWorkspace(at: sender.tag)
    }

    @objc private func previousWorkspace() {
        currentWindow?.cycleWorkspace(by: -1)
    }

    @objc private func nextWorkspace() {
        currentWindow?.cycleWorkspace(by: 1)
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        currentWindow?.selectTab(at: sender.tag)
    }

    private func makeSurface(workingDirectory: String?) -> TerminalSurfaceView {
        var configuration = TerminalSurfaceConfiguration()
        configuration.workingDirectory = workingDirectory
        let surface = TerminalSurfaceView(runtime: runtime, configuration: configuration)
        surface.delegate = self
        return surface
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
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "").target = updater
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
        let newWindowItem = fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "n")
        newWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "New Workspace", action: #selector(newWorkspace), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(closePane), keyEquivalent: "w")
        let closeTabItem = fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTabItem.keyEquivalentModifierMask = [.command, .option]
        let closeWindowItem = fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindowItem.keyEquivalentModifierMask = [.command, .shift]
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
    /// Ghostty's new_window binding (cmd+n) opens a workspace, which is what a
    /// window is in other terminals.
    func runtimeWantsNewWorkspace(_ runtime: GhosttyRuntime) {
        newWorkspace()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsNewTabFrom surface: TerminalSurfaceView?) {
        guard let surface, let window = window(containing: surface) else { return newTab() }
        window.newTab(nextTo: surface)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsSplit direction: SplitDirection, from surface: TerminalSurfaceView) -> Bool {
        guard let window = window(containing: surface) else { return false }
        window.split(surface, direction: direction)
        return true
    }

    func runtime(_ runtime: GhosttyRuntime, wantsGotoSplit direction: PaneNavigation, from surface: TerminalSurfaceView) {
        window(containing: surface)?.gotoSplit(direction, from: surface)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsToggleZoomFrom surface: TerminalSurfaceView) {
        window(containing: surface)?.toggleZoom(surface)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsResizeSplit direction: ResizeDirection, amount: Int, from surface: TerminalSurfaceView) {
        window(containing: surface)?.resizeSplit(surface, direction: direction, amount: amount)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsEqualizeSplitsFrom surface: TerminalSurfaceView) {
        window(containing: surface)?.equalizeSplits(from: surface)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsSecureKeyboardEntry enabled: Bool) {
        setSecureKeyboardEntry(enabled)
    }

    func runtimeWantsOpenConfig(_ runtime: GhosttyRuntime) {
        openConfig()
    }

    func runtime(_ runtime: GhosttyRuntime, wantsNotification title: String, body: String, from surface: TerminalSurfaceView) {
        guard let window = window(containing: surface) else { return }
        let workspace = window.store.workspace(containing: surface)?.0.name ?? ""
        notifications.post(title: title, body: body, subtitle: workspace, from: surface.id)
    }

    func runtime(_ runtime: GhosttyRuntime, didFinish command: CommandFinish, in surface: TerminalSurfaceView) {
        guard let window = window(containing: surface) else { return }
        let config = runtime.config
        let when = config.notifyOnCommandFinish
        guard command.shouldAlert(when: when, inView: window.isInView(surface), minimumDuration: config.notifyOnCommandFinishAfter) else { return }
        let actions = config.notifyOnCommandFinishAction
        if actions.contains(.bell) {
            NSSound.beep()
        }
        if actions.contains(.notify) {
            let workspace = window.store.workspace(containing: surface)?.0.name ?? ""
            notifications.post(title: command.title, body: command.body, subtitle: workspace, from: surface.id, evenIfInView: when == .always)
        }
    }

    func runtime(_ runtime: GhosttyRuntime, wantsClose surface: TerminalSurfaceView) {
        window(containing: surface)?.close(surface)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsCloseTabs mode: TabCloseMode, from surface: TerminalSurfaceView) {
        window(containing: surface)?.closeTabs(mode, from: surface)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsCloseWindowFrom surface: TerminalSurfaceView) {
        window(containing: surface)?.window?.performClose(nil)
    }

    func runtime(_ runtime: GhosttyRuntime, wantsGotoTab target: ghostty_action_goto_tab_e) {
        currentWindow?.gotoWorkspace(target)
    }
}

// MARK: - Windows and terminals

extension AppDelegate: TerminalWindowDelegate, TerminalSurfaceViewDelegate {
    func terminalWindow(_ window: TerminalWindow, makeSurfaceIn directory: String?) -> TerminalSurfaceView {
        makeSurface(workingDirectory: directory)
    }

    func terminalWindowDidChange(_ window: TerminalWindow) {
        scheduleSave()
    }

    func terminalWindowWillClose(_ window: TerminalWindow) {
        windows.removeAll { $0 === window }
        scheduleSave()
    }

    func surfaceDidChange(_ surface: TerminalSurfaceView) {
        window(containing: surface)?.controller.refresh()
        scheduleSave()
    }

    func surfaceDidFocus(_ surface: TerminalSurfaceView) {
        notifications.clear(for: surface.id)
        window(containing: surface)?.surfaceDidFocus(surface)
    }
}
