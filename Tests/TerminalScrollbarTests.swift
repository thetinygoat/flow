import AppKit
import XCTest

@MainActor
final class TerminalScrollbarTests: XCTestCase {
    func testEndingLiveScrollWaitsForThePendingTerminalReport() {
        _ = NSApplication.shared
        let bar = TerminalScrollbar(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        bar.cellHeight = 10
        bar.update(total: 100, offset: 21, visibleRows: 10)
        bar.layoutSubtreeIfNeeded()
        var rows: [Int] = []
        bar.onScrollToRow = { rows.append($0) }
        let center = NotificationCenter.default
        center.post(name: NSScrollView.willStartLiveScrollNotification, object: bar)
        bar.contentView.scroll(to: NSPoint(x: 0, y: 703))
        center.post(name: NSScrollView.didLiveScrollNotification, object: bar)
        XCTAssertEqual(rows, [20])

        center.post(name: NSScrollView.didEndLiveScrollNotification, object: bar)

        XCTAssertEqual(bar.contentView.bounds.origin.y, 703, accuracy: 0.01)
        bar.update(total: 100, offset: 20, visibleRows: 10)
        XCTAssertEqual(bar.contentView.bounds.origin.y, 700, accuracy: 0.01)
        XCTAssertEqual(rows, [20])
    }

    func testEndingLiveScrollSnapsToTheLastReportedRow() {
        _ = NSApplication.shared
        let bar = TerminalScrollbar(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        bar.cellHeight = 10
        bar.update(total: 100, offset: 21, visibleRows: 10)
        bar.layoutSubtreeIfNeeded()
        var rows: [Int] = []
        bar.onScrollToRow = { rows.append($0) }
        let center = NotificationCenter.default
        center.post(name: NSScrollView.willStartLiveScrollNotification, object: bar)
        bar.contentView.scroll(to: NSPoint(x: 0, y: 703))
        center.post(name: NSScrollView.didLiveScrollNotification, object: bar)
        XCTAssertEqual(rows, [20])
        bar.update(total: 100, offset: 20, visibleRows: 10)
        XCTAssertEqual(bar.contentView.bounds.origin.y, 703, accuracy: 0.01)

        center.post(name: NSScrollView.didEndLiveScrollNotification, object: bar)

        XCTAssertEqual(bar.contentView.bounds.origin.y, 700, accuracy: 0.01)
        bar.update(total: 100, offset: 20, visibleRows: 10)
        XCTAssertEqual(bar.contentView.bounds.origin.y, 700, accuracy: 0.01)
        XCTAssertEqual(rows, [20])
    }
}
