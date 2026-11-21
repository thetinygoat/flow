import AppKit

protocol TerminalAreaViewControllerDelegate: AnyObject {
    func terminalArea(_ area: TerminalAreaViewController, didSelect tab: TerminalTab, in workspace: Workspace)
    func terminalArea(_ area: TerminalAreaViewController, didClose tab: TerminalTab, in workspace: Workspace)
}

/// The right side of the window: a strip in the title bar showing the
/// current workspace's tabs, and the selected tab's terminal below it.
final class TerminalAreaViewController: NSViewController, TabBarViewDelegate {
    weak var delegate: TerminalAreaViewControllerDelegate?
    var agentIndicator: @MainActor (TerminalTab) -> AgentIndicator? = { _ in nil }

    private let titleStrip = TitleStripView()
    private var tabBar: TabBarView { titleStrip.tabBar }

    var backgroundColor: NSColor {
        get { titleStrip.backgroundColor }
        set {
            titleStrip.backgroundColor = newValue
            paneTreeView.backgroundColor = newValue
        }
    }

    /// The title bar buttons at the window's leading edge, which the strip's
    /// title and tabs keep clear of once the sidebar is hidden.
    var titlebarButtons: NSView? {
        get { titleStrip.titlebarButtons }
        set { titleStrip.titlebarButtons = newValue }
    }

    let paneTreeView = PaneTreeView()
    private var workspace: Workspace?

    override func loadView() {
        tabBar.delegate = self
        let view = NSView()
        for subview in [titleStrip, paneTreeView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        // A full screen window has no title bar, so the strip keeps room for
        // the tabs.
        let fillsTitleBar = titleStrip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        fillsTitleBar.priority = .defaultHigh
        NSLayoutConstraint.activate([
            titleStrip.topAnchor.constraint(equalTo: view.topAnchor),
            titleStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fillsTitleBar,
            titleStrip.heightAnchor.constraint(greaterThanOrEqualToConstant: TabBarView.height),
            paneTreeView.topAnchor.constraint(equalTo: titleStrip.bottomAnchor),
            paneTreeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paneTreeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneTreeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
    }

    func show(_ workspace: Workspace?) {
        self.workspace = workspace
        reloadTabs()
        paneTreeView.show(workspace?.selectedTab?.panes)
        paneTreeView.updateDimming(focused: workspace?.selectedTab?.focusedSurface)
    }

    func reloadTabs() {
        let tabs = workspace?.tabs ?? []
        let selectedIndex = workspace?.selectedTab.flatMap { selected in tabs.firstIndex { $0 === selected } }
        tabBar.reload(titles: tabs.map(\.title), indicators: tabs.map(agentIndicator), selectedIndex: selectedIndex)
        titleStrip.showsTabs = tabs.count > 1
        titleStrip.title = workspace?.selectedTab?.title ?? ""
    }

    func updateAgentIndicator(for tab: TerminalTab) {
        guard let index = workspace?.tabs.firstIndex(where: { $0 === tab }) else { return }
        tabBar.updateIndicator(agentIndicator(tab), at: index)
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

/// Sits in the window's title bar: the selected tab's title, or the tabs
/// once there are several. Dragging it moves the window and a double click
/// does what the system's title bar setting says.
private final class TitleStripView: NSView {
    let tabBar = TabBarView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var contentLeading: NSLayoutConstraint!
    weak var titlebarButtons: NSView?

    var backgroundColor: NSColor = .clear {
        didSet {
            tabBar.backgroundColor = backgroundColor
            needsDisplay = true
        }
    }

    var title: String {
        get { titleLabel.stringValue }
        set { if newValue != titleLabel.stringValue { titleLabel.stringValue = newValue } }
    }

    var showsTabs = false {
        didSet {
            tabBar.isHidden = !showsTabs
            titleLabel.isHidden = showsTabs
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabBar.isHidden = true
        for subview in [titleLabel, tabBar] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        contentLeading = tabBar.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            contentLeading,
            // Leaves room for the button that shows all panes again.
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            tabBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: tabBar.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Views no longer clip to their bounds, so the dirty rect can reach
    /// past them and over the sidebar.
    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
    }

    override func layout() {
        let leading = titlebarButtons.map { buttons in
            max(0, convert(buttons.bounds, from: buttons).maxX)
        } ?? 0
        if contentLeading.constant != leading {
            contentLeading.constant = leading
        }
        super.layout()
    }

    /// The title is part of the strip, so dragging it moves the window too.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === titleLabel ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}
