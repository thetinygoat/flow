import AppKit

/// Every shortcut in one window, in two columns of sections.
final class KeyboardShortcutsWindowController: NSWindowController {
    private static let width: CGFloat = 680
    private static let inset: CGFloat = 24
    private static let columnSpacing: CGFloat = 36

    init() {
        let window = KeyboardShortcutsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ sections: [KeyboardShortcuts.Section]) {
        guard let window else { return }
        let wasVisible = window.isVisible
        let content = Self.content(for: sections)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = content
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        window.contentView = scrollView
        let maximumHeight = (window.screen ?? NSScreen.main).map { $0.visibleFrame.height * 0.85 } ?? 640
        window.setContentSize(NSSize(width: Self.width, height: min(content.fittingSize.height, maximumHeight)))
        if !wasVisible { window.center() }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private static func content(for sections: [KeyboardShortcuts.Section]) -> NSView {
        let columnWidth = (width - 2 * inset - columnSpacing) / 2
        let (left, right) = columns(sections)
        let columns = NSStackView(views: [column(left, width: columnWidth), column(right, width: columnWidth)])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = columnSpacing

        let note = NSTextField(wrappingLabelWithString: "Keybindings in your Ghostty config also work in Flow.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [columns, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 20, left: inset, bottom: 20, right: inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalToConstant: width - 2 * inset).isActive = true

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
        ])
        return document
    }

    /// Splits the sections where the left column holds about half the rows,
    /// keeping their order.
    private static func columns(_ sections: [KeyboardShortcuts.Section]) -> ([KeyboardShortcuts.Section], [KeyboardShortcuts.Section]) {
        let weight = { (section: KeyboardShortcuts.Section) in section.shortcuts.count + 2 }
        let half = sections.map(weight).reduce(0, +) / 2
        var count = 0
        let split = sections.firstIndex { section in
            defer { count += weight(section) }
            return count > 0 && count + weight(section) / 2 > half
        } ?? sections.endIndex
        return (Array(sections[..<split]), Array(sections[split...]))
    }

    private static func column(_ sections: [KeyboardShortcuts.Section], width: CGFloat) -> NSView {
        let stack = NSStackView(views: sections.map { section($0, width: width) })
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        return stack
    }

    private static func section(_ section: KeyboardShortcuts.Section, width: CGFloat) -> NSView {
        let header = NSTextField(labelWithString: section.title)
        header.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        header.textColor = .secondaryLabelColor

        let grid = NSGridView(views: section.shortcuts.map { [title($0.title), keycaps($0.keys)] })
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.rowAlignment = .none
        grid.column(at: 1).xPlacement = .trailing
        for row in 0..<grid.numberOfRows {
            grid.row(at: row).yPlacement = .center
        }
        grid.widthAnchor.constraint(equalToConstant: width).isActive = true

        let stack = NSStackView(views: [header, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private static func title(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private static func keycaps(_ keys: [String]) -> NSView {
        let stack = NSStackView(views: keys.map(KeycapView.init))
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }
}

/// One key of a shortcut, drawn as a small cap.
private final class KeycapView: NSView {
    init(_ key: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        let label = NSTextField(labelWithString: key)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    }
}

/// Esc closes the window, as it does other windows that only show information.
private final class KeyboardShortcutsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Lays the shortcuts out from the top of the scroll view down.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
