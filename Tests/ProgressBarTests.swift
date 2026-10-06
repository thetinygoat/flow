import AppKit
import XCTest

@MainActor
final class ProgressBarTests: XCTestCase {
    private func fill(_ view: ProgressBarView) -> CALayer {
        view.layer!.sublayers!.last!
    }

    func testRepeatedLayoutKeepsTheRunningAnimation() {
        let view = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 2))
        view.report = ProgressReport(state: .indeterminate, percent: nil)
        view.layoutSubtreeIfNeeded()
        let started = fill(view).animation(forKey: "slide")!.beginTime
        XCTAssertGreaterThan(started, 0)
        for _ in 0..<30 {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(fill(view).animation(forKey: "slide")?.beginTime, started)
        }
    }

    func testResizeChangesTheAnimationDestinationWithoutRestartingIt() {
        let view = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 2))
        view.report = ProgressReport(state: .indeterminate, percent: nil)
        view.layoutSubtreeIfNeeded()
        let started = fill(view).animation(forKey: "slide")!.beginTime
        view.frame.size.width = 400
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let animation = fill(view).animation(forKey: "slide") as! CABasicAnimation
        XCTAssertEqual(animation.beginTime, started)
        XCTAssertEqual(animation.toValue as? CGFloat, 350)
        XCTAssertEqual(fill(view).frame.width, 100)
    }

    func testLeavingAndRejoiningTheWindowKeepsTheAnimation() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let view = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 2))
        window.contentView!.addSubview(view)
        view.report = ProgressReport(state: .indeterminate, percent: nil)
        view.layoutSubtreeIfNeeded()
        view.removeFromSuperview()
        fill(view).removeAllAnimations()
        window.contentView!.addSubview(view)
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(fill(view).animation(forKey: "slide"))
    }

    func testClearingAndDeterminateReportsStopTheAnimation() {
        let view = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 800, height: 2))
        view.report = ProgressReport(state: .indeterminate, percent: nil)
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(fill(view).animation(forKey: "slide"))
        view.report = nil
        XCTAssertTrue(view.isHidden)
        XCTAssertNil(fill(view).animation(forKey: "slide"))
        view.report = ProgressReport(state: .indeterminate, percent: nil)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.isHidden)
        XCTAssertNotNil(fill(view).animation(forKey: "slide"))
        view.report = ProgressReport(state: .set, percent: 50)
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(fill(view).animation(forKey: "slide"))
        XCTAssertEqual(fill(view).frame.width, 400)
        view.report = ProgressReport(state: .pause, percent: nil)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(fill(view).frame.width, 800)
        XCTAssertNil(fill(view).animation(forKey: "slide"))
    }
}
