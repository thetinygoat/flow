import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelect workspace: Workspace)
    func sidebar(_ sidebar: SidebarViewController, didRename workspace: Workspace, to name: String)
    func sidebar(_ sidebar: SidebarViewController, wantsClose workspace: Workspace)
}

/// The vertical list of workspaces on the left of the window. Each row shows
/// the workspace name and the working directory of its selected tab.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?

    private let store: WorkspaceStore
    private let tableView = NSTableView()
    private let git = GitStatusMonitor()
    private var gitTimer: Timer?
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
        git.onUpdate = { [weak self] in self?.reload() }
        gitTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            for row in 0..<self.store.workspaces.count {
                _ = self.gitStatus(forRow: row)
            }
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Rename Workspace", action: #selector(renameClickedWorkspace), keyEquivalent: "")
        menu.addItem(withTitle: "Close Workspace", action: #selector(closeClickedWorkspace), keyEquivalent: "")
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

    func setShortcutHintsVisible(_ visible: Bool) {
        for row in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? WorkspaceCellView else { continue }
            cell.showShortcutHint(visible && row < 9 ? "⌘\(row + 1)" : nil)
        }
    }

    func reload() {
        isReloading = true
        defer { isReloading = false }

        if tableView.numberOfRows == store.workspaces.count {
            let rows = IndexSet(0..<store.workspaces.count)
            tableView.reloadData(forRowIndexes: rows, columnIndexes: [0])
            tableView.noteHeightOfRows(withIndexesChanged: rows)
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

    @objc private func closeClickedWorkspace() {
        let row = tableView.clickedRow
        guard row >= 0, row < store.workspaces.count else { return }
        delegate?.sidebar(self, wantsClose: store.workspaces[row])
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.workspaces.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WorkspaceRowView()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        gitStatus(forRow: row) == nil ? 52 : 68
    }

    private func gitStatus(forRow row: Int) -> GitStatus? {
        guard row < store.workspaces.count,
              let directory = store.workspaces[row].selectedTab?.focusedSurface.workingDirectory else { return nil }
        return git.status(for: directory)
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
        cell.subtitleLabel.stringValue = workspace.selectedTab?.focusedSurface.workingDirectory?.fishStylePath ?? ""
        cell.gitStatus = gitStatus(forRow: row)
        cell.onClose = { [weak self] in
            guard let self, row < self.store.workspaces.count else { return }
            self.delegate?.sidebar(self, wantsClose: self.store.workspaces[row])
        }
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
}

private final class WorkspaceRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        bounds.fill()
    }
}

private final class WorkspaceCellView: NSTableCellView, NSTextFieldDelegate {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    private let gitLabel = NSTextField(labelWithString: "")
    private let hint = ShortcutHintView()
    private let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close workspace")!, target: nil, action: nil)
    private var trackingArea: NSTrackingArea?
    private var onRename: ((String) -> Void)?
    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.delegate = self
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        gitLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        gitLabel.textColor = .secondaryLabelColor
        gitLabel.lineBreakMode = .byTruncatingTail
        gitLabel.isHidden = true

        let stack = NSStackView(views: [titleLabel, subtitleLabel, gitLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.isHidden = true
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            hint.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = hint.text != nil
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    @objc private func closeTapped() {
        onClose?()
    }

    var gitStatus: GitStatus? {
        didSet {
            guard let gitStatus else {
                gitLabel.isHidden = true
                return
            }
            gitLabel.isHidden = false
            gitLabel.stringValue = gitStatus.isDirty ? "\(gitStatus.branch)*" : gitStatus.branch
        }
    }

    func showShortcutHint(_ text: String?) {
        hint.text = text
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
}

/// The small keyboard shortcut badge shown while the command key is held.
final class ShortcutHintView: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String? {
        didSet {
            label.stringValue = text ?? ""
            isHidden = text == nil
        }
    }

    init() {
        super.init(frame: .zero)
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
