import XCTest

final class NoticesTests: XCTestCase {
    private var domain: String!
    private var defaults: UserDefaults!
    private let first = Notice(id: "first", title: "First", message: "")
    private let second = Notice(id: "second", title: "Second", message: "")

    override func setUpWithError() throws {
        domain = UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: domain)
    }

    func testEachNoticeIsDueOnceAfterAnUpdate() {
        XCTAssertEqual(Notices.due([first, second], isNewInstall: false, defaults: defaults), [first, second])
        XCTAssertEqual(Notices.due([first, second], isNewInstall: false, defaults: defaults), [])
    }

    func testANewInstallSeesNoneOfTheExistingNotices() {
        XCTAssertEqual(Notices.due([first], isNewInstall: true, defaults: defaults), [])
        XCTAssertEqual(Notices.due([first], isNewInstall: false, defaults: defaults), [])
    }

    func testANoticeAddedLaterIsDueAfterTheNextUpdate() {
        XCTAssertEqual(Notices.due([first], isNewInstall: true, defaults: defaults), [])
        XCTAssertEqual(Notices.due([first, second], isNewInstall: false, defaults: defaults), [second])
    }
}
