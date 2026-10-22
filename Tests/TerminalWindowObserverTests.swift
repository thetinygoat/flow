import AppKit
import XCTest

@MainActor
final class TerminalWindowObserverTests: XCTestCase {
    override func setUp() async throws {
        _ = NSApplication.shared
    }

    func testOnlyTheAttachedWindowDeliversNotifications() {
        let center = NotificationCenter()
        let first = NSWindow(), second = NSWindow()
        var screenChanges = 0, focusChanges = 0, occlusionChanges = 0
        let observer = TerminalWindowObserver(center: center,
            screenChanged: { screenChanges += 1 }, focusChanged: { focusChanges += 1 },
            occlusionChanged: { occlusionChanges += 1 })

        func postAll(_ window: NSWindow) {
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                center.post(name: name, object: window)
            }
        }

        postAll(first)
        XCTAssertEqual(screenChanges + focusChanges + occlusionChanges, 0)
        observer.observe(first)
        postAll(second)
        XCTAssertEqual(screenChanges + focusChanges + occlusionChanges, 0)
        postAll(first)
        XCTAssertEqual(screenChanges, 1)
        XCTAssertEqual(focusChanges, 2)
        XCTAssertEqual(occlusionChanges, 1)

        observer.observe(second)
        postAll(first)
        XCTAssertEqual(screenChanges + focusChanges + occlusionChanges, 4)
        postAll(second)
        XCTAssertEqual(screenChanges, 2)
        XCTAssertEqual(focusChanges, 4)
        XCTAssertEqual(occlusionChanges, 2)

        observer.observe(nil)
        postAll(second)
        XCTAssertEqual(screenChanges + focusChanges + occlusionChanges, 8)
        observer.observe(first)
        observer.observe(first)
        postAll(first)
        XCTAssertEqual(screenChanges, 3)
        XCTAssertEqual(focusChanges, 6)
        XCTAssertEqual(occlusionChanges, 3)
    }

    func testReleaseRemovesObservers() {
        let center = NotificationCenter()
        let window = NSWindow()
        var callbacks = 0
        var observer: TerminalWindowObserver? = TerminalWindowObserver(center: center,
            screenChanged: { callbacks += 1 }, focusChanged: { callbacks += 1 },
            occlusionChanged: { callbacks += 1 })
        observer?.observe(window)
        weak let released = observer
        observer = nil
        XCTAssertNil(released)
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(callbacks, 0)
    }
}
