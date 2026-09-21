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

    func reload(titles: [String], selectedIndex: Int?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, title) in titles.enumerated() {
            let item = TabItemView(title: title, isSelected: index == selectedIndex)
            item.onSelect = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didSelectTabAt: index)
            }
            item.onClose = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didCloseTabAt: index)
            }
            stack.addArrangedSubview(item)
        }
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private let isSelected: Bool
    private let close: NSButton
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            close.isHidden = !(isSelected || isHovered)
            needsDisplay = true
        }
    }

    init(title: String, isSelected: Bool) {
        self.isSelected = isSelected
        self.close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")!,
                              target: nil, action: nil)
        super.init(frame: .zero)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        close.target = self
        close.action = #selector(closeTapped)
        close.isHidden = !isSelected
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        close.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [label, close])
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

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
