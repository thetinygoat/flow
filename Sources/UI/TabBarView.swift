import AppKit

protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelectTabAt index: Int)
    func tabBar(_ tabBar: TabBarView, didCloseTabAt index: Int)
}

/// A row of closable tabs. Hidden by its owner when there is only one tab.
final class TabBarView: NSView {
    weak var delegate: TabBarViewDelegate?
    var backgroundColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    private let stack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
    }

    private var items: [TabItemView] {
        stack.arrangedSubviews.compactMap { $0 as? TabItemView }
    }

    func setShortcutHintsVisible(_ visible: Bool) {
        for (index, item) in items.enumerated() {
            item.showShortcutHint(visible && index < 9 ? "⌃\(index + 1)" : nil)
        }
    }

    /// Titles change with every shell prompt, so items are kept and updated;
    /// views are only added or removed when the number of tabs changes.
    func reload(titles: [String], selectedIndex: Int?) {
        while items.count > titles.count {
            items.last?.removeFromSuperview()
        }
        while items.count < titles.count {
            let item = TabItemView()
            item.onSelect = { [weak self, weak item] in
                guard let self, let item, let index = self.items.firstIndex(of: item) else { return }
                self.delegate?.tabBar(self, didSelectTabAt: index)
            }
            item.onClose = { [weak self, weak item] in
                guard let self, let item, let index = self.items.firstIndex(of: item) else { return }
                self.delegate?.tabBar(self, didCloseTabAt: index)
            }
            stack.addArrangedSubview(item)
        }
        for (index, item) in items.enumerated() {
            item.title = titles[index]
            item.isSelected = index == selectedIndex
        }
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let close: NSButton
    private let hint = ShortcutHintView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            updateClose()
            needsDisplay = true
        }
    }

    var title: String {
        get { label.stringValue }
        set { if newValue != label.stringValue { label.stringValue = newValue } }
    }

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateStyle()
            needsDisplay = true
        }
    }

    init() {
        self.close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")!,
                              target: nil, action: nil)
        super.init(frame: .zero)

        updateStyle()
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        close.target = self
        close.action = #selector(closeTapped)
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        close.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [label, hint, close])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || isHovered {
            NSColor.white.withAlphaComponent(isSelected ? 0.06 : 0.04).setFill()
            bounds.fill()
        }
        if isSelected {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 2).fill()
        } else {
            NSColor.white.withAlphaComponent(isHovered ? 0.25 : 0.1).setFill()
            NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        }
        NSColor.white.withAlphaComponent(0.1).setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func updateStyle() {
        label.font = .systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        updateClose()
    }

    private func updateClose() {
        close.isHidden = hint.text != nil || !(isSelected || isHovered)
    }

    func showShortcutHint(_ text: String?) {
        hint.text = text
        updateClose()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
