import AppKit

/// The find bar that floats over a terminal. It only collects input and shows
/// the match count; libghostty does the searching and highlighting.
final class SearchBarView: NSView, NSTextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?
    /// Escape with text in the field hands focus back to the terminal but
    /// leaves the matches highlighted.
    var onReturnToTerminal: (() -> Void)?

    private let field = NSTextField()
    private let count = NSTextField(labelWithString: "")

    var needle: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    var total: Int? {
        didSet { updateCount() }
    }

    var selected: Int? {
        didSet { updateCount() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 4
        layer?.shadowOffset = .zero

        field.placeholderString = "Search"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.translatesAutoresizingMaskIntoConstraints = false

        count.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.translatesAutoresizingMaskIntoConstraints = false

        let fieldBox = FieldBackground()
        fieldBox.addSubview(field)
        fieldBox.addSubview(count)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -50),
            field.topAnchor.constraint(equalTo: fieldBox.topAnchor, constant: 6),
            field.bottomAnchor.constraint(equalTo: fieldBox.bottomAnchor, constant: -6),
            field.widthAnchor.constraint(equalToConstant: 180),
            count.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -8),
            count.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
        ])

        let stack = NSStackView(views: [
            fieldBox,
            // Ghostty searches from the bottom of the scrollback, so the next
            // match is further up.
            SearchButton(symbol: "chevron.up", label: "Next match", target: self, action: #selector(nextTapped)),
            SearchButton(symbol: "chevron.down", label: "Previous match", target: self, action: #selector(previousTapped)),
            SearchButton(symbol: "xmark", label: "Close", target: self, action: #selector(closeTapped)),
        ])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    func focusField() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func updateCount() {
        switch (selected, total) {
        case let (selected?, total?): count.stringValue = "\(selected + 1)/\(total)"
        case let (nil, total?): count.stringValue = "–/\(total)"
        default: count.stringValue = ""
        }
    }

    @objc private func previousTapped() { onPrevious?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func closeTapped() { onClose?() }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty {
                onClose?()
            } else {
                onReturnToTerminal?()
            }
            return true
        default:
            return false
        }
    }
}

private final class FieldBackground: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }
}

/// An icon that brightens and gains a soft backing on hover, and darkens that
/// backing while pressed.
private final class SearchButton: NSButton {
    private var hovering = false {
        didSet { updateAppearance() }
    }

    init(symbol: String, label: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = label
        self.target = target
        self.action = action
        symbolConfiguration = .init(pointSize: 13, weight: .regular)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateAppearance() {
        contentTintColor = hovering || isHighlighted ? .labelColor : .secondaryLabelColor
        let alpha: CGFloat = isHighlighted ? 0.2 : hovering ? 0.1 : 0
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }
}
