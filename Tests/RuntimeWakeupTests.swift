import XCTest

final class RuntimeWakeupTests: XCTestCase {
    func testConcurrentBurstRequiresOneTick() {
        let queue = DispatchQueue(label: "runtime-wakeup-test")
        let ticked = expectation(description: "runtime ticked")
        var ticks = 0
        let wakeup = RuntimeWakeup(queue: queue) {
            ticks += 1
            ticked.fulfill()
        }
        queue.sync {
            DispatchQueue.concurrentPerform(iterations: 10_000) { _ in wakeup.schedule() }
        }
        wait(for: [ticked], timeout: 2)
        queue.sync { XCTAssertEqual(ticks, 1) }
        withExtendedLifetime(wakeup) {}
    }

    func testWakeupsDuringTickAreNotLost() {
        let queue = DispatchQueue(label: "runtime-wakeup-test")
        let ticked = expectation(description: "runtime ticks again")
        ticked.expectedFulfillmentCount = 2
        var ticks = 0
        var wakeup: RuntimeWakeup!
        wakeup = RuntimeWakeup(queue: queue) {
            ticks += 1
            if ticks == 1 {
                DispatchQueue.concurrentPerform(iterations: 10_000) { _ in wakeup.schedule() }
            }
            ticked.fulfill()
        }
        wakeup.schedule()
        wait(for: [ticked], timeout: 2)
        queue.sync { XCTAssertEqual(ticks, 2) }
        wakeup = nil
    }

    func testLaterBurstStillTicksOnMainQueue() {
        let first = expectation(description: "first tick")
        let second = expectation(description: "second tick")
        var ticks = 0
        let wakeup = RuntimeWakeup {
            XCTAssertTrue(Thread.isMainThread)
            ticks += 1
            (ticks == 1 ? first : second).fulfill()
        }
        wakeup.schedule()
        wait(for: [first], timeout: 2)
        wakeup.schedule()
        wait(for: [second], timeout: 2)
        XCTAssertEqual(ticks, 2)
        withExtendedLifetime(wakeup) {}
    }

    func testReleaseCancelsPendingWakeup() {
        let queue = DispatchQueue(label: "runtime-wakeup-test")
        let ticked = expectation(description: "released runtime must not tick")
        ticked.isInverted = true
        queue.sync {
            let wakeup = RuntimeWakeup(queue: queue) { ticked.fulfill() }
            wakeup.schedule()
        }
        wait(for: [ticked], timeout: 0.1)
    }
}
