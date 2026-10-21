import AppKit
import XCTest

@MainActor
final class WindowContentViewControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        _ = NSApplication.shared
        suite = "flow-sidebar-test-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
        defaults.set(240.0, forKey: "SidebarWidth")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private func makeWindow() -> NSWindow {
        let sidebar = NSViewController()
        sidebar.view = NSView()
        let content = NSViewController()
        content.view = NSView()
        let controller = WindowContentViewController(sidebar: sidebar, content: content, defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        return window
    }

    private func drag(in window: NSWindow, distance: CGFloat, end: Bool = false) throws {
        let handle = try XCTUnwrap(window.contentViewController?.view.subviews.last)
        func event(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 100),
                                             modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        handle.mouseDown(with: try event(.leftMouseDown, x: 240))
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 240 + distance))
        if end { handle.mouseUp(with: try event(.leftMouseUp, x: 240 + distance)) }
    }

    func testClosingDuringDragSavesThePendingWidth() throws {
        let window = makeWindow()
        try drag(in: window, distance: 57)
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 240)
        window.close()
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 297)
    }

    func testQuittingDuringDragSavesThePendingWidth() throws {
        let window = makeWindow()
        defer { window.close() }
        try drag(in: window, distance: 81)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 321)
    }

    func testClosingAnotherWindowDoesNotFlushOrOverwriteWidth() throws {
        let window = makeWindow()
        let other = makeWindow()
        defer { window.close() }
        try drag(in: window, distance: 57)
        other.close()
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 240)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 297)
    }

    func testMouseUpSavesClampedWidthWithoutLaterOverwritingNewerPreferences() throws {
        let window = makeWindow()
        try drag(in: window, distance: 1000, end: true)
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 400)
        defaults.set(300.0, forKey: "SidebarWidth")
        window.close()
        XCTAssertEqual(defaults.double(forKey: "SidebarWidth"), 300)
    }
}
