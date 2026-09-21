import AppKit

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

    /// Re-reads the store and updates the sidebar, tab strip, and window title.
    func refresh() {
        sidebar.reload()
        terminalArea.show(store.selected)
        let workspace = store.selected?.name ?? "flow"
        let tab = store.selected?.selectedTab?.title
        window?.title = tab.map { "\(workspace) — \($0)" } ?? workspace
    }
}
