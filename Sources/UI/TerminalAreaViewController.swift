import AppKit

protocol TerminalAreaViewControllerDelegate: AnyObject {
    func terminalArea(_ area: TerminalAreaViewController, didSelect tab: TerminalTab, in workspace: Workspace)
    func terminalArea(_ area: TerminalAreaViewController, didClose tab: TerminalTab, in workspace: Workspace)
}

/// The right side of the window: a tab bar for the current workspace and the
/// selected tab's terminal surface below it.
final class TerminalAreaViewController: NSViewController, TabBarViewDelegate {
    weak var delegate: TerminalAreaViewControllerDelegate?

    private let tabBar = TabBarView()

    /// Stays opaque even when the terminal is translucent, so tab titles stay readable.
    var backgroundColor: NSColor {
        get { tabBar.backgroundColor }
        set {
            tabBar.backgroundColor = newValue
            paneTreeView.backgroundColor = newValue
        }
    }
    let paneTreeView = PaneTreeView()
    private var workspace: Workspace?

    override func loadView() {
        tabBar.delegate = self

        let stack = NSStackView(views: [tabBar, paneTreeView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        paneTreeView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            paneTreeView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tabBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        paneTreeView.setContentHuggingPriority(.defaultLow, for: .vertical)
        tabBar.setContentHuggingPriority(.required, for: .vertical)
        view = stack
    }

    func setShortcutHintsVisible(_ visible: Bool) {
        tabBar.setShortcutHintsVisible(visible)
    }

    func show(_ workspace: Workspace?) {
        self.workspace = workspace
        reloadTabs()
        paneTreeView.show(workspace?.selectedTab?.panes)
        paneTreeView.updateDimming(focused: workspace?.selectedTab?.focusedSurface)
    }

    private func reloadTabs() {
        let tabs = workspace?.tabs ?? []
        let selectedIndex = workspace?.selectedTab.flatMap { selected in tabs.firstIndex { $0 === selected } }
        tabBar.reload(titles: tabs.map(\.title), selectedIndex: selectedIndex)
        tabBar.isHidden = tabs.count < 2
    }

    func focusSelectedSurface() {
        guard let surface = workspace?.selectedTab?.focusedSurface else { return }
        view.window?.makeFirstResponder(surface)
    }

    // MARK: TabBarViewDelegate

    func tabBar(_ tabBar: TabBarView, didSelectTabAt index: Int) {
        guard let workspace, index < workspace.tabs.count else { return }
        delegate?.terminalArea(self, didSelect: workspace.tabs[index], in: workspace)
    }

    func tabBar(_ tabBar: TabBarView, didCloseTabAt index: Int) {
        guard let workspace, index < workspace.tabs.count else { return }
        delegate?.terminalArea(self, didClose: workspace.tabs[index], in: workspace)
    }
}
