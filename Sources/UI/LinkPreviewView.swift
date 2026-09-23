import AppKit

/// The URL under the mouse, shown in a bottom corner of a terminal. It sits
/// flush against the pane's edge with only its inner corner rounded, and moves
/// to the other side when the mouse reaches it so it never covers the text
/// being pointed at. Adapted from Ghostty's hover URL overlay.
final class LinkPreviewView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private let padding: CGFloat = 5

    var url: String? {
        didSet {
            label.stringValue = url ?? ""
            isHidden = url == nil
        }
    }

    /// Whether the preview sits in the bottom-left corner.
    private(set) var isOnLeft = true {
        didSet {
            guard isOnLeft != oldValue else { return }
            leading.isActive = isOnLeft
            trailing.isActive = !isOnLeft
            layer?.maskedCorners = isOnLeft ? .layerMaxXMaxYCorner : .layerMinXMaxYCorner
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.maskedCorners = .layerMaxXMaxYCorner
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Pins the preview to the bottom corners of `container`, capped so a long
    /// URL leaves most of the pane visible.
    func install(in container: NSView) {
        container.addSubview(self)
        leading = leadingAnchor.constraint(equalTo: container.leadingAnchor)
        trailing = trailingAnchor.constraint(equalTo: container.trailingAnchor)
        NSLayoutConstraint.activate([
            leading,
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.75),
        ])
    }

    /// Moves the preview out from under the mouse. `point` is in the
    /// container's coordinates.
    func avoid(_ point: NSPoint) {
        guard !isHidden else { return }
        let leftFrame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        isOnLeft = !leftFrame.contains(point)
    }
}
