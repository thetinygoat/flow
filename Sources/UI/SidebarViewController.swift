import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelect workspace: Workspace)
    /// The name is nil when the rename was abandoned.
    func sidebar(_ sidebar: SidebarViewController, didFinishRenaming workspace: Workspace, to name: String?)
    func sidebar(_ sidebar: SidebarViewController, wantsClose workspace: Workspace)
}

/// The vertical list of workspaces on the left of the window. Each row shows
/// the workspace name, the working directory of its selected tab, and a dot
/// for what the agents in its terminals are doing.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?
    var agentIndicator: @MainActor (Workspace) -> AgentIndicator? = { _ in nil }

    private let store: WorkspaceStore
    private let tableView = WorkspaceTableView()
    private static let workspacePasteboardType = NSPasteboard.PasteboardType("dev.thetinygoat.flow.workspace")
    private var draggingWorkspace: Workspace?
    private var isReloading = false
    private var hoveredRow = -1
    private let git = GitStatusMonitor()
    /// Its row is left alone by reloads, which would otherwise replace the
    /// cell and discard the name being typed.
    private var renaming: Workspace?

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
        tableView.target = self
        tableView.action = #selector(selectClickedWorkspace)
        tableView.registerForDraggedTypes([Self.workspacePasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask([], forLocal: false)
        git.onUpdate = { [weak self] in self?.reload() }

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
        // Scrolling moves rows under a still pointer, so the hovered row is
        // worked out again from where the pointer is.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updateHoveredRow), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        tableView.onPointerMove = { [weak self] in self?.updateHoveredRow() }

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
        let wasReloading = isReloading
        isReloading = true
        defer { isReloading = wasReloading }
        git.watch(store.workspaces.compactMap { $0.selectedTab?.focusedSurface.workingDirectory })

        if tableView.numberOfRows == store.workspaces.count {
            var rows = IndexSet(0..<store.workspaces.count)
            if let renaming, let row = store.workspaces.firstIndex(where: { $0 === renaming }) {
                rows.remove(row)
            }
            tableView.reloadData(forRowIndexes: rows, columnIndexes: [0])
            // Reloads arrive with every shell prompt. Animated height changes
            // overlap and leave cells taller than their rows, which then snap
            // back on the next full layout.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                tableView.noteHeightOfRows(withIndexesChanged: rows)
            }
        } else {
            // A full reload replaces every cell, so a rename in progress is
            // abandoned rather than saved half typed.
            for row in 0..<tableView.numberOfRows {
                (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? WorkspaceCellView)?.cancelRenaming()
            }
            renaming = nil
            tableView.reloadData()
        }
        if let selected = store.selected,
           let row = store.workspaces.firstIndex(where: { $0 === selected }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    /// Agents change state far more often than rows need rebuilding, so only
    /// the dots are updated.
    func updateAgentIndicators() {
        for row in 0..<min(tableView.numberOfRows, store.workspaces.count) {
            guard let workspace = workspace(at: row),
                  let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? WorkspaceCellView else { continue }
            cell.agentIndicator = agentIndicator(workspace)
        }
    }

    private func workspace(at row: Int) -> Workspace? {
        store.workspaces.indices.contains(row) ? store.workspaces[row] : nil
    }

    private var clickedWorkspace: Workspace? {
        workspace(at: tableView.clickedRow)
    }

    /// The table sends its action when a press ends without becoming a drag
    /// or a context menu, which is when a click means switching workspaces.
    @objc private func selectClickedWorkspace() {
        guard let workspace = clickedWorkspace, workspace !== store.selected else { return }
        delegate?.sidebar(self, didSelect: workspace)
    }

    @objc private func renameClickedWorkspace() {
        guard let workspace = clickedWorkspace else { return }
        beginRename(of: workspace)
    }

    func beginRename(of workspace: Workspace) {
        guard renaming == nil, let row = store.workspaces.firstIndex(where: { $0 === workspace }) else { return }
        tableView.scrollRowToVisible(row)
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? WorkspaceCellView else { return }
        renaming = workspace
        cell.beginRenaming { [weak self] name in
            guard let self else { return }
            self.renaming = nil
            let exists = self.store.workspaces.contains { $0 === workspace }
            self.delegate?.sidebar(self, didFinishRenaming: workspace, to: name.isEmpty || !exists ? nil : name)
        }
    }

    @objc private func closeClickedWorkspace() {
        guard let workspace = clickedWorkspace else { return }
        delegate?.sidebar(self, wantsClose: workspace)
    }

    /// One row at most shows its close button: the row under the pointer.
    @objc private func updateHoveredRow() {
        let row = tableView.hoveredRow
        guard row != hoveredRow else { return }
        hoveredRow = row
        for visible in 0..<tableView.numberOfRows {
            (tableView.view(atColumn: 0, row: visible, makeIfNecessary: false) as? WorkspaceCellView)?.isHovered = visible == row
        }
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.workspaces.count
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard workspace(at: row) != nil else { return nil }
        let item = NSPasteboardItem()
        item.setData(Data(), forType: Self.workspacePasteboardType)
        return item
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        draggingWorkspace = rowIndexes.first.flatMap { workspace(at: $0) }
    }

    private func draggedWorkspace(_ info: NSDraggingInfo) -> Workspace? {
        guard let source = info.draggingSource as? NSTableView, source === tableView,
              let draggingWorkspace, store.workspaces.contains(where: { $0 === draggingWorkspace }) else { return nil }
        return draggingWorkspace
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard draggedWorkspace(info) != nil, (0...store.workspaces.count).contains(row) else { return [] }
        var index = row
        if dropOperation == .on {
            guard store.workspaces.indices.contains(row) else { return [] }
            let pointer = tableView.convert(info.draggingLocation, from: nil)
            index = insertionIndex(forDropOn: row, pointerY: pointer.y, rowRect: tableView.rect(ofRow: row))
        }
        // Dropping a row back where it is stays allowed, as in Finder, and
        // leaves the order alone.
        tableView.setDropRow(index, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard dropOperation == .above, let workspace = draggedWorkspace(info) else { return false }
        return store.move(workspace, toInsertionIndex: row)
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingWorkspace = nil
        self.tableView.refreshPointer(at: screenPoint)
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WorkspaceRowView()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        gitStatus(forRow: row) == nil ? 52 : 68
    }

    private func gitStatus(forRow row: Int) -> GitStatus? {
        guard let directory = workspace(at: row)?.selectedTab?.focusedSurface.workingDirectory else { return nil }
        return git.status(for: directory)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let workspace = workspace(at: row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("workspaceCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? WorkspaceCellView ?? {
            let cell = WorkspaceCellView()
            cell.identifier = identifier
            return cell
        }()
        cell.titleLabel.stringValue = workspace.name
        cell.subtitleLabel.stringValue = workspace.selectedTab?.focusedSurface.workingDirectory?.fishStylePath ?? ""
        cell.gitStatus = gitStatus(forRow: row)
        cell.isHovered = row == hoveredRow
        cell.agentIndicator = agentIndicator(workspace)
        cell.onClose = { [weak self, weak workspace] in
            guard let self, let workspace, self.store.workspaces.contains(where: { $0 === workspace }) else { return }
            self.delegate?.sidebar(self, wantsClose: workspace)
        }
        return cell
    }

    /// Mouse presses may become drags. Accessibility selection can proceed
    /// without waiting for a click action.
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        self.tableView.isHandlingMouseDown ? tableView.selectedRowIndexes : proposedSelectionIndexes
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading, !tableView.isHandlingMouseDown,
              let workspace = workspace(at: tableView.selectedRow) else { return }
        guard workspace !== store.selected else { return }
        delegate?.sidebar(self, didSelect: workspace)
    }
}

/// Tracks the pointer over the whole list rather than row by row, so the
/// hovered row stays right while rows scroll or are reused.
private final class WorkspaceTableView: NSTableView {
    var onPointerMove: (() -> Void)?
    private(set) var isHandlingMouseDown = false

    override func mouseDown(with event: NSEvent) {
        isHandlingMouseDown = true
        defer { isHandlingMouseDown = false }
        super.mouseDown(with: event)
    }

    func refreshPointer(at screenPoint: NSPoint) {
        pointer = window?.convertPoint(fromScreen: screenPoint)
        onPointerMove?()
    }

    private var pointer: NSPoint?
    private var pointerArea: NSTrackingArea?

    /// Clicking a row leaves the keyboard with the terminal, so typing and
    /// arrow keys go on reaching the shell instead of switching workspaces.
    override var acceptsFirstResponder: Bool { false }

    var hoveredRow: Int {
        guard let pointer else { return -1 }
        let point = convert(pointer, from: nil)
        return visibleRect.contains(point) ? row(at: point) : -1
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointer = event.locationInWindow
        onPointerMove?()
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = event.locationInWindow
        onPointerMove?()
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        onPointerMove?()
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
    private let agentDot = AgentDotView()
    private var onRename: ((String) -> Void)?
    private var nameBeforeRenaming = ""
    private var clickMonitor: Any?
    var onClose: (() -> Void)?

    /// The dragged row shows what it is rather than what the pointer or the
    /// command key happen to reveal on it, so the agent dot stays visible.
    override var draggingImageComponents: [NSDraggingImageComponent] {
        let wasHovered = isHovered
        let hintText = hint.text
        isHovered = false
        showShortcutHint(nil)
        layoutSubtreeIfNeeded()
        // Vector rather than bitmap, so it stays sharp on any display the
        // drag crosses.
        let snapshot = NSImage(data: dataWithPDF(inside: bounds))
        isHovered = wasHovered
        showShortcutHint(hintText)

        let appearance = effectiveAppearance
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                let card = NSBezierPath(rect: rect.insetBy(dx: 2, dy: 2))
                NSColor.windowBackgroundColor.setFill()
                card.fill()
                NSColor.separatorColor.setStroke()
                card.lineWidth = 1
                card.stroke()
            }
            snapshot?.draw(in: rect)
            return true
        }
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = image
        component.frame = bounds
        return [component]
    }

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
        addSubview(agentDot)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            hint.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            agentDot.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
            agentDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
        updateCloseButton()
    }

    var isHovered = false {
        didSet { updateCloseButton() }
    }

    var agentIndicator: AgentIndicator? {
        get { agentDot.indicator }
        set {
            agentDot.indicator = newValue
            updateCloseButton()
        }
    }

    /// The dot, the close button and the shortcut hint share one spot at the
    /// end of the name; the hint wins, then the close button under the pointer.
    private func updateCloseButton() {
        closeButton.isHidden = !isHovered || hint.text != nil
        agentDot.isHidden = agentDot.indicator == nil || !closeButton.isHidden || hint.text != nil
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
        updateCloseButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Return or a click anywhere outside the field keeps the new name and
    /// Escape restores the old one, as renaming works in Finder. The completion
    /// gets the new name, or an empty one when the rename was abandoned.
    func beginRenaming(_ completion: @escaping (String) -> Void) {
        onRename = completion
        nameBeforeRenaming = titleLabel.stringValue
        titleLabel.isEditable = true
        titleLabel.isBezeled = true
        titleLabel.bezelStyle = .roundedBezel
        titleLabel.drawsBackground = true
        titleLabel.textColor = .labelColor
        window?.makeFirstResponder(titleLabel)
        titleLabel.currentEditor()?.selectAll(nil)
        // Clicks on the title bar, the tab strip or empty sidebar space do not
        // take keyboard focus, so on their own they would leave the field open.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let inField = event.window === window
                && titleLabel.bounds.contains(titleLabel.convert(event.locationInWindow, from: nil))
            if !inField { window?.makeFirstResponder(nil) }
            return event
        }
    }

    /// Abandons a rename without telling the sidebar, which is reloading.
    func cancelRenaming() {
        onRename = nil
        endRenaming(keepingName: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        let completion = onRename
        onRename = nil
        endRenaming(keepingName: false)
        completion?("")
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let completion = onRename
        onRename = nil
        let name = titleLabel.stringValue.trimmingCharacters(in: .whitespaces)
        endRenaming(keepingName: true)
        completion?(name)
    }

    private func endRenaming(keepingName: Bool) {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if titleLabel.currentEditor() != nil {
            titleLabel.abortEditing()
        }
        if !keepingName {
            titleLabel.stringValue = nameBeforeRenaming
        }
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
    }
}
