import AppKit

/// The overlay scroller shown on a terminal.
///
/// libghostty scrolls the terminal itself, so this scroll view holds an empty
/// document sized to the scrollback and only mirrors the terminal's position,
/// letting AppKit draw, fade and hover the scroller natively. Everything except
/// the scroller passes through to the terminal underneath.
final class TerminalScrollbar: NSScrollView {
    /// Called with the scrollback row the user dragged to, counted from the top.
    var onScrollToRow: ((Int) -> Void)?
    var cellHeight: CGFloat = 0 {
        didSet { sync() }
    }

    private var total = 0
    private var offset = 0
    private var visibleRows = 0
    private var isLiveScrolling = false
    private var lastSentRow: Int?
    private var observers: [NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true
        scrollerStyle = .overlay
        autohidesScrollers = true
        drawsBackground = false
        documentView = NSView()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                self?.isLiveScrolling = true
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                self?.isLiveScrolling = false
            },
            center.addObserver(forName: NSScrollView.didLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                self?.liveScrolled()
            },
            // Overlay is forced even when the system prefers always-visible
            // scrollers, since a legacy scroller would take width from the grid.
            center.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scrollerStyle = .overlay
            },
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let scroller = verticalScroller, let hit = super.hitTest(point), hit.isDescendant(of: scroller) else { return nil }
        return hit
    }

    override func layout() {
        super.layout()
        sync()
    }

    func update(total: Int, offset: Int, visibleRows: Int) {
        let rowsBelowBefore = self.total - self.offset - self.visibleRows
        self.total = total
        self.offset = offset
        self.visibleRows = visibleRows
        sync()
        // Output arriving at the bottom keeps the distance to the bottom at
        // zero, so only a real scroll reveals the scroller.
        if total - offset - visibleRows != rowsBelowBefore {
            flashScrollers()
        }
    }

    private func sync() {
        guard let documentView else { return }
        let height = contentSize.height
        guard cellHeight > 0, total > 0 else {
            documentView.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: height)
            return
        }
        let padding = max(0, height - CGFloat(visibleRows) * cellHeight)
        documentView.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: CGFloat(total) * cellHeight + padding)
        guard !isLiveScrolling else { return }
        contentView.scroll(to: NSPoint(x: 0, y: CGFloat(total - offset - visibleRows) * cellHeight))
        reflectScrolledClipView(contentView)
        lastSentRow = offset
    }

    private func liveScrolled() {
        guard cellHeight > 0, let documentView else { return }
        let visible = contentView.documentVisibleRect
        let fromTop = documentView.frame.height - visible.maxY
        let row = max(0, Int((fromTop / cellHeight).rounded()))
        guard row != lastSentRow else { return }
        lastSentRow = row
        onScrollToRow?(row)
    }
}
