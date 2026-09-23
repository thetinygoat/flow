import XCTest

final class CommandFinishTests: XCTestCase {
    private let threshold = Duration.seconds(5)

    func testNeverAlerts() {
        let finish = CommandFinish(exitCode: 0, duration: .seconds(60))
        XCTAssertFalse(finish.shouldAlert(when: .never, inView: false, minimumDuration: threshold))
    }

    func testUnfocusedSkipsTerminalsInView() {
        let finish = CommandFinish(exitCode: 0, duration: .seconds(60))
        XCTAssertFalse(finish.shouldAlert(when: .unfocused, inView: true, minimumDuration: threshold))
        XCTAssertTrue(finish.shouldAlert(when: .unfocused, inView: false, minimumDuration: threshold))
    }

    func testAlwaysAlertsInView() {
        let finish = CommandFinish(exitCode: 0, duration: .seconds(60))
        XCTAssertTrue(finish.shouldAlert(when: .always, inView: true, minimumDuration: threshold))
    }

    func testShortCommandsAreQuiet() {
        let quick = CommandFinish(exitCode: 0, duration: .milliseconds(4999))
        let exact = CommandFinish(exitCode: 0, duration: .seconds(5))
        XCTAssertFalse(quick.shouldAlert(when: .always, inView: false, minimumDuration: threshold))
        XCTAssertTrue(exact.shouldAlert(when: .always, inView: false, minimumDuration: threshold))
    }

    func testTitles() {
        XCTAssertEqual(CommandFinish(exitCode: 0, duration: .seconds(1)).title, "Command Succeeded")
        XCTAssertEqual(CommandFinish(exitCode: 2, duration: .seconds(1)).title, "Command Failed")
        XCTAssertEqual(CommandFinish(exitCode: nil, duration: .seconds(1)).title, "Command Finished")
    }

    func testBodies() {
        XCTAssertEqual(CommandFinish(exitCode: 1, duration: .seconds(12)).body, "Command took 12 sec and exited with code 1.")
        XCTAssertEqual(CommandFinish(exitCode: nil, duration: .seconds(65)).body, "Command took 1 min, 5 sec.")
    }
}
