import XCTest

final class RowDropTests: XCTestCase {
    func testDropOnRowInsertsAboveTopHalfAndBelowBottomHalf() {
        let rect = NSRect(x: 0, y: 104, width: 200, height: 52)

        XCTAssertEqual(insertionIndex(forDropOn: 2, pointerY: 104, rowRect: rect), 2)
        XCTAssertEqual(insertionIndex(forDropOn: 2, pointerY: 120, rowRect: rect), 2)
        XCTAssertEqual(insertionIndex(forDropOn: 2, pointerY: 130, rowRect: rect), 2)
        XCTAssertEqual(insertionIndex(forDropOn: 2, pointerY: 131, rowRect: rect), 3)
        XCTAssertEqual(insertionIndex(forDropOn: 2, pointerY: 156, rowRect: rect), 3)
    }

    func testDropOnFirstAndLastRows() {
        XCTAssertEqual(insertionIndex(forDropOn: 0, pointerY: 10, rowRect: NSRect(x: 0, y: 0, width: 200, height: 52)), 0)
        XCTAssertEqual(insertionIndex(forDropOn: 3, pointerY: 200, rowRect: NSRect(x: 0, y: 156, width: 200, height: 68)), 4)
    }
}
