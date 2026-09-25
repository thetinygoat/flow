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

    init(sidebar: NSViewController, content: NSViewController) {
        self.sidebar = sidebar
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var width: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: Self.widthKey)
            return saved > 0 ? min(max(saved, Self.widthRange.lowerBound), Self.widthRange.upperBound) : 240
        }
        set {
            let clamped = min(max(newValue, Self.widthRange.lowerBound), Self.widthRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: Self.widthKey)
            sidebarWidth.constant = clamped
        }
    }

    var isSidebarHidden: Bool {
        get { sidebar.view.isHidden }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hiddenKey)
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

        sidebarWidth = sidebar.view.widthAnchor.constraint(equalToConstant: width)
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
            width = widthAtDragStart + distance
        }
        isSidebarHidden = UserDefaults.standard.bool(forKey: Self.hiddenKey)
    }

    func toggleSidebar() {
        isSidebarHidden.toggle()
    }
}

/// A thin strip over the sidebar's edge that resizes it.
private final class SidebarResizeHandle: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
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
}
