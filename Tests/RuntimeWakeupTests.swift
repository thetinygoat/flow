import XCTest

final class RuntimeWakeupTests: XCTestCase {
    func testConcurrentBurstPreservesEveryTick() {
        let queue = DispatchQueue(label: "runtime-wakeup-test")
        let ticked = expectation(description: "runtime ticked")
        ticked.expectedFulfillmentCount = 10_000
        var ticks = 0
        let wakeup = RuntimeWakeup(queue: queue) {
            ticks += 1
            ticked.fulfill()
        }
        queue.sync {
            DispatchQueue.concurrentPerform(iterations: 10_000) { _ in wakeup.schedule() }
        }
        wait(for: [ticked], timeout: 2)
        queue.sync { XCTAssertEqual(ticks, 10_000) }
        withExtendedLifetime(wakeup) {}
    }

    func testWakeupsDuringTickAreNotLost() {
        let queue = DispatchQueue(label: "runtime-wakeup-test")
        let ticked = expectation(description: "runtime ticks again")
        ticked.expectedFulfillmentCount = 10_001
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
        queue.sync { XCTAssertEqual(ticks, 10_001) }
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

    func testBurstYieldsToOtherQueuedWork() {
        let queue = DispatchQueue(label: "runtime-wakeup-test")
        let completed = expectation(description: "burst completed")
        let interleaved = expectation(description: "other work ran")
        var ticks = 0
        let wakeup = RuntimeWakeup(queue: queue) {
            ticks += 1
            if ticks == 1 {
                queue.async {
                    XCTAssertLessThan(ticks, 10_000)
                    interleaved.fulfill()
                }
            }
            if ticks == 10_000 { completed.fulfill() }
        }
        queue.sync {
            for _ in 0..<10_000 { wakeup.schedule() }
        }
        wait(for: [completed, interleaved], timeout: 2)
        queue.sync { XCTAssertEqual(ticks, 10_000) }
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
