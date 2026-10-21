import AppKit

/// The window's content: the workspace sidebar beside the terminal area. The
/// sidebar is a plain view with a width rather than a split view item, whose
/// look AppKit changes between macOS versions, and it has no divider for a
/// translucent window to show through.
final class WindowContentViewController: NSViewController {
    static let widthRange: ClosedRange<CGFloat> = 200...400
    private static let widthKey = "SidebarWidth"
    private static let hiddenKey = "SidebarHidden"

    private let sidebar: NSViewController
    private let content: NSViewController
    private let handle = SidebarResizeHandle()
    private var sidebarWidth: NSLayoutConstraint!
    private var contentAfterSidebar: NSLayoutConstraint!
    private var contentAtEdge: NSLayoutConstraint!
    private var widthAtDragStart: CGFloat = 0
    private var hasPendingWidth = false
    private let defaults: UserDefaults

    init(sidebar: NSViewController, content: NSViewController, defaults: UserDefaults = .standard) {
        self.sidebar = sidebar
        self.content = content
        self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }

    var isSidebarHidden: Bool {
        get { sidebar.view.isHidden }
        set {
            defaults.set(newValue, forKey: Self.hiddenKey)
            sidebar.view.isHidden = newValue
            handle.isHidden = newValue
            // The sidebar keeps its width while hidden, so its own layout is
            // never squeezed; the terminal moves to the window's edge instead.
            contentAfterSidebar.isActive = !newValue
            contentAtEdge.isActive = newValue
        }
    }

    override func loadView() {
        let view = NSView()
        addChild(sidebar)
        addChild(content)
        for child in [sidebar.view, content.view, handle] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }

        let savedWidth = defaults.double(forKey: Self.widthKey)
        sidebarWidth = sidebar.view.widthAnchor.constraint(equalToConstant: Self.clampedWidth(savedWidth > 0 ? savedWidth : 240))
        contentAfterSidebar = content.view.leadingAnchor.constraint(equalTo: sidebar.view.trailingAnchor)
        contentAtEdge = content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        NSLayoutConstraint.activate([
            sidebar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.view.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidth,
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            handle.centerXAnchor.constraint(equalTo: sidebar.view.trailingAnchor),
            handle.widthAnchor.constraint(equalToConstant: 6),
            handle.topAnchor.constraint(equalTo: view.topAnchor),
            handle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view

        handle.onBegin = { [weak self] in
            guard let self else { return }
            widthAtDragStart = sidebarWidth.constant
        }
        handle.onDrag = { [weak self] distance in
            guard let self else { return }
            let width = Self.clampedWidth(widthAtDragStart + distance)
            guard width != sidebarWidth.constant else { return }
            sidebarWidth.constant = width
            hasPendingWidth = true
        }
        handle.onEnd = { [weak self] in
            self?.savePendingWidth()
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(saveWidthBeforeClosing(_:)), name: NSWindow.willCloseNotification, object: nil)
        center.addObserver(self, selector: #selector(saveWidthBeforeClosing(_:)), name: NSApplication.willTerminateNotification, object: nil)
        isSidebarHidden = defaults.bool(forKey: Self.hiddenKey)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func saveWidthBeforeClosing(_ notification: Notification) {
        guard notification.name == NSApplication.willTerminateNotification ||
              (notification.object as? NSWindow) === view.window else { return }
        savePendingWidth()
    }

    private func savePendingWidth() {
        guard hasPendingWidth else { return }
        defaults.set(Double(sidebarWidth.constant), forKey: Self.widthKey)
        hasPendingWidth = false
    }

    func toggleSidebar() {
        isSidebarHidden.toggle()
    }
}

/// A thin strip over the sidebar's edge that resizes it.
private final class SidebarResizeHandle: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var start: CGFloat = 0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow.x
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.locationInWindow.x - start)
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }
}
