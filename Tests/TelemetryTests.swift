import XCTest

@MainActor
final class TelemetryTests: XCTestCase {
    private var domain: String!
    private var defaults: UserDefaults!
    private var date = Date(timeIntervalSince1970: 0)
    private var requests: [URLRequest] = []
    private var failure: Error?

    override func setUp() async throws {
        domain = UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        date = at("2026-11-26T12:00:00Z")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: domain)
    }

    private func at(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func telemetry(enabled: Bool = true) -> Telemetry {
        let telemetry = Telemetry(defaults: defaults, now: { self.date }, send: { request in
            try await MainActor.run {
                self.requests.append(request)
                if let failure = self.failure { throw failure }
            }
        })
        telemetry.isEnabled = enabled
        return telemetry
    }

    private func events(_ request: URLRequest?) throws -> [[String: Any]] {
        let body = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
    }

    private func names(_ request: URLRequest?) throws -> [String] {
        try events(request).map { $0["eventName"] as! String }
    }

    func testSendsEachPeriodOnce() async throws {
        let telemetry = telemetry()
        await telemetry.recordActivity()?.value
        XCTAssertEqual(try names(requests.last), ["active_day", "active_week", "active_month"])

        XCTAssertNil(telemetry.recordActivity())

        date = at("2026-11-27T00:00:01Z")
        await telemetry.recordActivity()?.value
        XCTAssertEqual(try names(requests.last), ["active_day"])

        date = at("2026-11-30T09:00:00Z")
        await telemetry.recordActivity()?.value
        XCTAssertEqual(try names(requests.last), ["active_day", "active_week"])

        date = at("2026-12-01T09:00:00Z")
        await telemetry.recordActivity()?.value
        XCTAssertEqual(try names(requests.last), ["active_day", "active_month"])
        XCTAssertEqual(requests.count, 4)
    }

    func testWeeksAreISOWeeks() {
        XCTAssertEqual(Telemetry.Period.week.name(at: at("2026-11-26T12:00:00Z")), "2026-W48")
        XCTAssertEqual(Telemetry.Period.week.name(at: at("2027-01-01T12:00:00Z")), "2026-W53")
    }

    func testSendsNothingWhileOff() async {
        XCTAssertNil(telemetry(enabled: false).recordActivity())
        XCTAssertTrue(requests.isEmpty)
    }

    func testTurningOffCancelsASendUnderWay() async {
        let telemetry = Telemetry(defaults: defaults, now: { self.date }, send: { _ in
            try await Task.sleep(for: .seconds(60))
        })
        telemetry.isEnabled = true
        let sending = telemetry.recordActivity()
        telemetry.isEnabled = false
        await sending?.value
        XCTAssertNil(defaults.string(forKey: Telemetry.Period.day.defaultsKey))
    }

    func testTriesAgainAnHourAfterAFailure() async throws {
        let telemetry = telemetry()
        failure = URLError(.badServerResponse)
        await telemetry.recordActivity()?.value
        failure = nil
        XCTAssertNil(telemetry.recordActivity())

        date += 3600
        await telemetry.recordActivity()?.value
        XCTAssertEqual(try names(requests.last), ["active_day", "active_week", "active_month"])
    }

    func testSendsNothingElse() async throws {
        let telemetry = telemetry()
        telemetry.recordInstall(isNew: true)
        await telemetry.recordActivity()?.value
        let sent = try events(requests.last)
        for event in sent {
            XCTAssertEqual(Set(event.keys), ["timestamp", "sessionId", "eventName", "systemProps", "props"])
            let system = try XCTUnwrap(event["systemProps"] as? [String: Any])
            XCTAssertEqual(Set(system.keys), ["isDebug", "osName", "osVersion", "appVersion", "sdkVersion"])
        }
        XCTAssertEqual(sent.map { $0["props"] as? [String: String] }, [[:], ["install_week": "2026-W48"], [:]])
    }

    func testNoTwoSendsShareAnIdentifier() async throws {
        let telemetry = telemetry()
        await telemetry.recordActivity()?.value
        date = at("2026-11-27T12:00:00Z")
        await telemetry.recordActivity()?.value
        let sessions = try requests.map { try XCTUnwrap(events($0)[0]["sessionId"] as? String) }
        XCTAssertEqual(Set(sessions).count, 2)
    }

    func testTheInstallWeekIsKept() async throws {
        let telemetry = telemetry()
        telemetry.recordInstall(isNew: false)
        telemetry.recordInstall(isNew: true)
        await telemetry.recordActivity()?.value
        XCTAssertEqual(try events(requests.last)[1]["props"] as? [String: String], ["install_week": "earlier"])
    }
}
