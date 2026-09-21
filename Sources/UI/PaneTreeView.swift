import AppKit
import GhosttyKit

/// Renders a tab's pane tree as nested split views. Rebuilt whenever the tree's
/// structure changes; divider drags write their ratio back into the tree.
final class PaneTreeView: NSView {
    /// Dividers are painted opaque in this color so nothing behind the window shows through them.
    var backgroundColor: NSColor = .black {
        didSet { splitViews.values.forEach { $0.backgroundColor = backgroundColor } }
    }
    /// Color laid over unfocused panes, nil when dimming is disabled.
    var unfocusedFill: NSColor?
    private var tree: PaneTree?
    private var renderedVersion = -1
    private var splitViews: [ObjectIdentifier: PaneSplitView] = [:]

    func show(_ tree: PaneTree?) {
        if tree === self.tree, tree?.version == renderedVersion { return }
        self.tree = tree
        renderedVersion = tree?.version ?? -1
        splitViews.removeAll()
        subviews.forEach { $0.removeFromSuperview() }
        guard let tree else { return }
        let view = build(tree.root)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    func updateDimming(focused: TerminalSurfaceView?) {
        let surfaces = tree?.surfaces ?? []
        for surface in surfaces {
            surface.setDimColor(surfaces.count > 1 && surface !== focused ? unfocusedFill : nil)
        }
    }

    private func build(_ pane: Pane) -> NSView {
        if let surface = pane.surface {
            surface.removeFromSuperview()
            return surface
        }
        let split = PaneSplitView(pane: pane)
        split.backgroundColor = backgroundColor
        splitViews[ObjectIdentifier(pane)] = split
        split.addArrangedSubview(build(pane.first!))
        split.addArrangedSubview(build(pane.second!))
        return split
    }

    /// Moves the divider that borders the pane in the given direction.
    func resize(_ surface: TerminalSurfaceView, direction: ghostty_action_resize_split_direction_e, amount: CGFloat) {
        guard let tree, var child = tree.pane(for: surface) else { return }
        let horizontal = direction == GHOSTTY_RESIZE_SPLIT_LEFT || direction == GHOSTTY_RESIZE_SPLIT_RIGHT
        let towardSecond = direction == GHOSTTY_RESIZE_SPLIT_RIGHT || direction == GHOSTTY_RESIZE_SPLIT_DOWN
        while let parent = child.parent {
            if (parent.axis == .horizontal) == horizontal, (child === parent.first) == towardSecond,
               let split = splitViews[ObjectIdentifier(parent)] {
                split.setPosition(split.dividerPosition + (towardSecond ? amount : -amount), ofDividerAt: 0)
                return
            }
            child = parent
        }
    }
}

private final class PaneSplitView: NSSplitView, NSSplitViewDelegate {
    private let pane: Pane
    private var appliedRatio = false
    var backgroundColor: NSColor = .black {
        didSet { needsDisplay = true }
    }

    init(pane: Pane) {
        self.pane = pane
        super.init(frame: .zero)
        isVertical = pane.axis == .horizontal
        dividerStyle = .thin
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var length: CGFloat {
        isVertical ? bounds.width : bounds.height
    }

    var dividerPosition: CGFloat {
        guard let first = arrangedSubviews.first else { return 0 }
        return isVertical ? first.frame.width : first.frame.height
    }

    override func drawDivider(in rect: NSRect) {
        backgroundColor.setFill()
        rect.fill()
        NSColor.white.withAlphaComponent(0.12).setFill()
        rect.fill(using: .sourceOver)
    }

    override func layout() {
        super.layout()
        guard !appliedRatio, length > 0 else { return }
        setPosition(pane.ratio * length, ofDividerAt: 0)
        appliedRatio = true
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard appliedRatio, length > 0 else { return }
        pane.ratio = dividerPosition / length
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        80
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        length - 80
    }
}
