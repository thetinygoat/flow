import AppKit

/// The palette that floats over the window: a search field above the items
/// matching it. Up and down move through the items, Return chooses one and
/// Escape or a click outside cancels. As in VS Code, pressing the palette's
/// shortcut again or an arrow while holding ⌘ steps through the list and
/// letting go of ⌘ chooses the item, so a quick ⌘P P goes back to the previous
/// place and ⌘I I to the agent that has waited longest.
final class CommandPaletteView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let mode: CommandPalette.Mode
    /// The terminal the palette was opened from. Its menu commands, such as
    /// Find or a font size change, stay enabled while the palette has the
    /// keyboard; the palette is cancelled before they are sent, which puts
    /// the keyboard back with this terminal for them.
    weak var commandTarget: NSResponder?
    /// Nil when nothing is selected.
    var onSelect: ((CommandPalette.Item?) -> Void)?
    var onChoose: ((CommandPalette.Item) -> Void)?
    var onCancel: (() -> Void)?

    private static let rowHeight: CGFloat = 50
    private static let visibleRows = 9

    private var items: [CommandPalette.Item]
    private let agentIndicator: @MainActor (UUID) -> AgentIndicator?
    private var shown: [CommandPalette.Item] = []
    /// The selected item's terminal, so a search that keeps the same best
    /// match previews nothing again.
    private var selectedTerminal: UUID?
    private var isUpdating = false
    private var commandReleaseMonitor: Any?
    private var titleBarClickMonitor: Any?

    private let field = NSTextField()
    private let message = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let panel = PalettePanel()
    private var tableHeight: NSLayoutConstraint!

    init(_ mode: CommandPalette.Mode, items: [CommandPalette.Item], agentIndicator: @escaping @MainActor (UUID) -> AgentIndicator?) {
        self.mode = mode
        self.items = items
        self.agentIndicator = agentIndicator
        super.init(frame: .zero)

        field.placeholderString = mode.placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false

        let column = NSTableColumn(identifier: .init("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.rowHeight = Self.rowHeight
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(chooseClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false

        let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        searchIcon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        searchIcon.contentTintColor = .secondaryLabelColor

        let divider = PaletteDivider()

        message.font = .systemFont(ofSize: 14)
        message.textColor = .secondaryLabelColor

        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        for view in [searchIcon, field, divider, scrollView, message] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.content.addSubview(view)
        }
        tableHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        // A short window shrinks the list, which then scrolls, rather than
        // the list growing the window.
        tableHeight.priority = .dragThatCannotResizeWindow
        // Above what any view inside asks for, so only a narrow window makes
        // the panel narrower.
        let preferredWidth = panel.widthAnchor.constraint(equalToConstant: 720)
        preferredWidth.priority = .defaultHigh + 1
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor, constant: 72),
            preferredWidth,
            panel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            // As wide as a row's icon, so the field lines up with the titles below.
            searchIcon.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            searchIcon.widthAnchor.constraint(equalToConstant: 22),
            searchIcon.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            divider.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            divider.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 18),
            divider.heightAnchor.constraint(equalToConstant: 1),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            tableHeight,
            message.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        update()
    }

    deinit {
        commandReleaseMonitor.map(NSEvent.removeMonitor)
        titleBarClickMonitor.map(NSEvent.removeMonitor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func focusField() {
        window?.makeFirstResponder(field)
    }

    func selectNext() {
        step(by: 1)
    }

    func cancel() {
        onCancel?()
    }

    /// For terminals closed in another window, which the agents palette lists
    /// too. The selection stays on its item unless that one closed.
    func removeItems(where isClosed: (CommandPalette.Item) -> Bool) {
        guard items.contains(where: isClosed) else { return }
        items.removeAll(where: isClosed)
        update(keeping: selectedTerminal)
    }

    /// Agents change state far more often than the list changes, so only the
    /// dots are updated.
    func updateAgentIndicators() {
        for row in shown.indices {
            guard let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? PaletteItemView else { continue }
            showAgent(in: view, row: row)
        }
    }

    /// Wraps around at either end. With nothing selected, stepping down starts
    /// at the top and stepping up at the bottom. Stepping with ⌘ held chooses
    /// the item once ⌘ is let go.
    private func step(by offset: Int) {
        guard !shown.isEmpty else { return }
        let from = tableView.selectedRow == -1 ? (offset > 0 ? -1 : 0) : tableView.selectedRow
        select(((from + offset) % shown.count + shown.count) % shown.count)
        guard NSEvent.modifierFlags.contains(.command), commandReleaseMonitor == nil else { return }
        commandReleaseMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self, !event.modifierFlags.contains(.command) {
                choose(tableView.selectedRow)
            }
            return event
        }
    }

    /// The palette covers the window's content but not its title bar, whose
    /// buttons act on the tab in view, so a click there cancels first and the
    /// button then acts on where the palette was opened.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, titleBarClickMonitor == nil else { return }
        titleBarClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if let self, event.window === window, !bounds.contains(convert(event.locationInWindow, from: nil)) {
                cancel()
            }
            return event
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        for monitor in [commandReleaseMonitor, titleBarClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        commandReleaseMonitor = nil
        titleBarClickMonitor = nil
    }

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let commandTarget, commandTarget.responds(to: action) { return commandTarget }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    /// A click anywhere but the panel cancels, with any button.
    override func mouseDown(with event: NSEvent) {
        cancel()
    }

    override func rightMouseDown(with event: NSEvent) {
        cancel()
    }

    override func otherMouseDown(with event: NSEvent) {
        cancel()
    }

    /// The best match is selected, and so previewed, unless the mode starts
    /// on nothing and there is no search, or the terminal to keep is shown.
    private func update(keeping terminal: UUID? = nil) {
        isUpdating = true
        shown = CommandPalette.filter(items, query: field.stringValue)
        tableView.reloadData()
        message.isHidden = !shown.isEmpty
        message.stringValue = items.isEmpty ? mode.emptyMessage : "No matches"
        tableHeight.constant = Self.rowHeight * CGFloat(min(max(shown.count, 1), Self.visibleRows))
        if let row = shown.firstIndex(where: { $0.terminal == terminal }) {
            select(row)
        } else if mode.startsUnselected && field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            tableView.deselectAll(nil)
        } else {
            select(0)
        }
        isUpdating = false
        reportSelection()
    }

    private func reportSelection() {
        let item = shown.indices.contains(tableView.selectedRow) ? shown[tableView.selectedRow] : nil
        guard item?.terminal != selectedTerminal else { return }
        selectedTerminal = item?.terminal
        onSelect?(item)
    }

    private func select(_ row: Int) {
        guard shown.indices.contains(row) else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func choose(_ row: Int) {
        guard shown.indices.contains(row) else { return }
        onChoose?(shown[row])
    }

    @objc private func chooseClicked() {
        choose(tableView.clickedRow)
    }

    private func showAgent(in view: PaletteItemView, row: Int) {
        let indicator = agentIndicator(shown[row].terminal)
        view.agentIndicator = indicator
        view.alphaValue = mode.dimsWorkingAgents && indicator == .working ? 0.5 : 1
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        // With ⌘ held the arrows arrive as moves to either end of the text.
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveToBeginningOfDocument(_:)): step(by: -1)
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveToEndOfDocument(_:)): step(by: 1)
        // With nothing selected, Return goes to the first item.
        case #selector(NSResponder.insertNewline(_:)): choose(max(tableView.selectedRow, 0))
        case #selector(NSResponder.cancelOperation(_:)): cancel()
        default: return false
        }
        return true
    }

    // MARK: NSTableViewDataSource, NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        shown.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = PaletteItemView(item: shown[row])
        showAgent(in: view, row: row)
        return view
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PaletteRowView()
    }

    /// A search reloads the list and selects its best match in steps, which
    /// are reported once it is done.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        reportSelection()
    }
}

/// The blurred material has to clip to its rounded corners, which would clip
/// a shadow too, so the shadow is cast by this view around it.
private final class PalettePanel: NSView {
    private static let cornerRadius: CGFloat = 14
    let content = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 24
        layer?.shadowOffset = NSSize(width: 0, height: -8)

        content.material = .popover
        content.blendingMode = .withinWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            content.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    /// Clicks inside the panel stay in it rather than reaching the backdrop.
    override func mouseDown(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {}
}

/// A separator box turns vertical whenever a layout pass makes it taller than
/// wide, and then holds the panel to its own width. The colour is set in each
/// layer update so it follows the window turning light or dark.
private final class PaletteDivider: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

/// Selected the way the sidebar's rows are, edge to edge in grey.
private final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        bounds.fill()
    }
}

private final class PaletteItemView: NSTableCellView {
    private let icon: PaneLayoutIcon
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let location = NSTextField(labelWithString: "")
    private let zoomIcon = NSImageView()
    private let agentDot = AgentDotView()

    var agentIndicator: AgentIndicator? {
        get { agentDot.indicator }
        set { agentDot.indicator = newValue }
    }

    init(item: CommandPalette.Item) {
        icon = PaneLayoutIcon(layout: item.layout)
        super.init(frame: .zero)
        title.stringValue = item.title
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        detail.stringValue = item.detail
        detail.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.isHidden = item.detail.isEmpty
        location.stringValue = item.location
        location.font = .systemFont(ofSize: 13)
        location.textColor = .secondaryLabelColor
        location.lineBreakMode = .byTruncatingHead
        location.alignment = .right
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if let zoom = item.layout.zoom {
            // The same arrows as zooming a pane and the title bar's Reset zoom.
            let (symbol, label) = switch zoom {
            case .zoomed: ("arrow.up.left.and.arrow.down.right", "Zoomed")
            case .hidden: ("arrow.down.right.and.arrow.up.left", "Hidden by zoom")
            }
            zoomIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            zoomIcon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
            zoomIcon.toolTip = label
            zoomIcon.contentTintColor = .secondaryLabelColor
        }

        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        // Fixed columns, so every row's parts line up whatever it holds. The
        // zoom and agent columns are kept on rows without them for the same
        // reason. The agent dot sits at the trailing edge, as in the sidebar.
        for view in [icon, text, location, zoomIcon, agentDot] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: location.leadingAnchor, constant: -16),
            location.trailingAnchor.constraint(equalTo: zoomIcon.leadingAnchor, constant: -10),
            location.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomIcon.trailingAnchor.constraint(equalTo: agentDot.leadingAnchor, constant: -10),
            zoomIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomIcon.widthAnchor.constraint(equalToConstant: 16),
            agentDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            agentDot.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// A tab's split drawn small, with the item's own pane filled in.
private final class PaneLayoutIcon: NSView {
    private let layout: CommandPalette.PaneLayout

    init(layout: CommandPalette.PaneLayout) {
        self.layout = layout
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.insetBy(dx: 1, dy: 1)
        for (index, frame) in layout.frames.enumerated() {
            let rect = CGRect(
                x: area.minX + frame.minX * area.width,
                y: area.minY + frame.minY * area.height,
                width: frame.width * area.width,
                height: frame.height * area.height
            ).insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if index == layout.highlighted {
                NSColor.secondaryLabelColor.setFill()
                path.fill()
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }
}
