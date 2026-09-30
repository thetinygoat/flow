import AppKit

/// A small coloured dot for what the agents in a group of terminals are doing.
/// It pulses while they work, unless the user asked for reduced motion.
final class AgentDotView: NSView {
    static let size: CGFloat = 8
    private static let pulseKey = "pulse"

    var indicator: AgentIndicator? {
        didSet {
            guard indicator != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel(label)
            toolTip = label
            updatePulse()
        }
    }

    private var motionObserver: Any?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updatePulse()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        motionObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private var color: NSColor? {
        switch indicator {
        case .working: .systemBlue
        case .waiting: .systemYellow
        case .done: .systemGreen
        case nil: nil
        }
    }

    private var label: String? {
        switch indicator {
        case .working: "Working"
        case .waiting: "Waiting for input"
        case .done: "Finished"
        case nil: nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let color else { return }
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePulse()
    }

    private func updatePulse() {
        guard let layer else { return }
        let pulses = indicator == .working && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard pulses else {
            layer.removeAnimation(forKey: Self.pulseKey)
            return
        }
        guard layer.animation(forKey: Self.pulseKey) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: Self.pulseKey)
    }
}
