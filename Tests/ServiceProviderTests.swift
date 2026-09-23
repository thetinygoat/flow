import XCTest

final class ServiceProviderTests: XCTestCase {
    func testFoldersOpenAsThemselves() {
        let urls = [URL(fileURLWithPath: "/tmp/project", isDirectory: true)]
        XCTAssertEqual(ServiceProvider.directories(for: urls), ["/tmp/project/"])
    }

    func testFilesOpenTheirFolder() {
        let urls = [URL(fileURLWithPath: "/tmp/project/README.md", isDirectory: false)]
        XCTAssertEqual(ServiceProvider.directories(for: urls), ["/tmp/project/"])
    }

    func testDuplicatesOpenOnce() {
        let urls = [
            URL(fileURLWithPath: "/tmp/project/a.txt", isDirectory: false),
            URL(fileURLWithPath: "/tmp/project/b.txt", isDirectory: false),
            URL(fileURLWithPath: "/tmp/other", isDirectory: true),
        ]
        XCTAssertEqual(ServiceProvider.directories(for: urls), ["/tmp/project/", "/tmp/other/"])
    }
}
