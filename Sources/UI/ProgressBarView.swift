import AppKit

/// What a program last reported with OSC 9;4.
struct ProgressReport: Equatable {
    enum State {
        case set, error, indeterminate, pause
    }

    let state: State
    /// Percent complete, when the program gave one.
    let percent: Int?

    /// Errors and pauses mean the program has stopped making progress.
    var isWorking: Bool {
        state == .set || state == .indeterminate
    }
}

/// A thin bar across the top of a terminal showing a program's progress:
/// filled to the percentage when one is known, otherwise a segment sliding
/// back and forth. Adapted from Ghostty's SurfaceProgressBar.
final class ProgressBarView: NSView {
    static let height: CGFloat = 2

    var report: ProgressReport? {
        didSet {
            guard report != oldValue else { return }
            isHidden = report == nil
            needsLayout = true
        }
    }

    private let track = CALayer()
    private let fill = CALayer()
    private let segmentWidthRatio: CGFloat = 0.25

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        guard let report else { return }
        let color: NSColor = switch report.state {
        case .error: .systemRed
        case .pause: .systemOrange
        default: .controlAccentColor
        }
        // A paused report without a percentage reads as finished work on hold.
        let percent = report.percent ?? (report.state == .pause ? 100 : nil)

        fill.removeAnimation(forKey: "slide")
        withoutAnimation {
            track.frame = bounds
            track.backgroundColor = percent == nil ? color.withAlphaComponent(0.3).cgColor : nil
            fill.backgroundColor = color.cgColor
        }
        if let percent {
            // Sublayers animate frame changes on their own, which eases the
            // bar between reported percentages.
            fill.frame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(min(max(percent, 0), 100)) / 100, height: bounds.height)
        } else {
            let width = bounds.width * segmentWidthRatio
            withoutAnimation {
                fill.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
            }
            fill.add(slideAnimation(segmentWidth: width), forKey: "slide")
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private func slideAnimation(segmentWidth: CGFloat) -> CAAnimation {
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = segmentWidth / 2
        slide.toValue = bounds.width - segmentWidth / 2
        slide.duration = 1.2
        slide.autoreverses = true
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return slide
    }
}
