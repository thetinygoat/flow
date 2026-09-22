import AppKit
import GhosttyKit

/// One window: workspace sidebar on the left, terminal area on the right.
final class MainWindowController: NSWindowController {
    let sidebar: SidebarViewController
    let terminalArea = TerminalAreaViewController()
    private let store: WorkspaceStore

    init(store: WorkspaceStore) {
        self.store = store
        self.sidebar = SidebarViewController(store: store)

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: terminalArea))
        split.splitView.autosaveName = "MainSplit"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.toolbarStyle = .unified
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.minSize = NSSize(width: 600, height: 400)
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MainWindow")

        super.init(window: window)

        if !split.splitView.isSubviewCollapsed(sidebar.view), sidebar.view.frame.width < 240 {
            split.splitView.setPosition(240, ofDividerAt: 0)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Ghostty renders the terminal background with the configured opacity, but
    /// only a non-opaque window lets the desktop show through it.
    func applyAppearance(config: GhosttyConfig, app: ghostty_app_t) {
        guard let window else { return }
        terminalArea.backgroundColor = config.backgroundColor
        let dim = config.unfocusedSplitOpacity
        terminalArea.paneTreeView.unfocusedFill = dim > 0 ? config.unfocusedSplitFill.withAlphaComponent(dim) : nil
        terminalArea.show(store.selected)
        if config.backgroundOpacity < 1 {
            window.isOpaque = false
            window.backgroundColor = .white.withAlphaComponent(0.001)
            if config.backgroundBlur > 0 {
                ghostty_set_window_background_blur(app, Unmanaged.passUnretained(window).toOpaque())
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = config.backgroundColor
        }
    }

    /// Workspace shortcuts use command and tab shortcuts use control, so each
    /// modifier reveals only the hints it can complete.
    func showShortcutHints(for modifier: ShortcutModifier?) {
        sidebar.setShortcutHintsVisible(modifier == .command)
        terminalArea.setShortcutHintsVisible(modifier == .control)
    }

    /// Re-reads the store and updates the sidebar, tab strip, and window title.
    func refresh() {
        sidebar.reload()
        terminalArea.show(store.selected)
        let workspace = store.selected?.name ?? "Flow"
        let tab = store.selected?.selectedTab?.title
        window?.title = tab.map { "\(workspace) — \($0)" } ?? workspace
    }
}

enum ShortcutModifier {
    case command, control

    /// Caps lock and the fn key are left out so they never hide the hints.
    static let relevantFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    /// Nil unless command or control is held on its own.
    init?(_ flags: NSEvent.ModifierFlags) {
        switch flags.intersection(Self.relevantFlags) {
        case .command: self = .command
        case .control: self = .control
        default: return nil
        }
    }
}
