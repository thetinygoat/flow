import AppKit

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
