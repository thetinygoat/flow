import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelect workspace: Workspace)
    func sidebar(_ sidebar: SidebarViewController, didRename workspace: Workspace, to name: String)
}

/// The vertical list of workspaces on the left of the window. Each row shows
/// the workspace name and the working directory of its selected tab.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?

    private let store: WorkspaceStore
    private let tableView = NSTableView()
    private var isReloading = false

    init(store: WorkspaceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("workspace"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 52
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = false

        let menu = NSMenu()
        menu.addItem(withTitle: "Rename Workspace", action: #selector(renameClickedWorkspace), keyEquivalent: "")
        tableView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSVisualEffectView()
        container.material = .sidebar
        container.blendingMode = .behindWindow
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    func reload() {
        isReloading = true
        defer { isReloading = false }

        if tableView.numberOfRows == store.workspaces.count {
            tableView.reloadData(
                forRowIndexes: IndexSet(0..<store.workspaces.count),
                columnIndexes: [0])
        } else {
            tableView.reloadData()
        }
        if let selected = store.selected,
           let row = store.workspaces.firstIndex(where: { $0 === selected }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    @objc private func renameClickedWorkspace() {
        let row = tableView.clickedRow
        guard row >= 0, let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? WorkspaceCellView else { return }
        cell.beginRenaming { [weak self] name in
            guard let self, row < self.store.workspaces.count else { return }
            self.delegate?.sidebar(self, didRename: self.store.workspaces[row], to: name)
        }
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.workspaces.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WorkspaceRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("workspaceCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? WorkspaceCellView ?? {
            let cell = WorkspaceCellView()
            cell.identifier = identifier
            return cell
        }()
        let workspace = store.workspaces[row]
        cell.titleLabel.stringValue = workspace.name
        cell.subtitleLabel.stringValue = workspace.selectedTab?.surface.pwd.map(Self.abbreviateHome) ?? ""
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < store.workspaces.count else { return }
        let workspace = store.workspaces[row]
        guard workspace !== store.selected else { return }
        delegate?.sidebar(self, didSelect: workspace)
    }

    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

private final class WorkspaceRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        bounds.fill()
    }
}

private final class WorkspaceCellView: NSTableCellView, NSTextFieldDelegate {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    private var onRename: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.delegate = self
        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func beginRenaming(_ completion: @escaping (String) -> Void) {
        onRename = completion
        titleLabel.isEditable = true
        titleLabel.isBezeled = true
        titleLabel.bezelStyle = .roundedBezel
        titleLabel.drawsBackground = true
        titleLabel.textColor = .labelColor
        window?.makeFirstResponder(titleLabel)
        titleLabel.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        let name = titleLabel.stringValue.trimmingCharacters(in: .whitespaces)
        let completion = onRename
        onRename = nil
        if !name.isEmpty { completion?(name) }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let selected = backgroundStyle == .emphasized
            titleLabel.textColor = selected ? .white : .labelColor
            subtitleLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        }
    }
}
