import XCTest

final class AgentSocketListenerTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("flow-test-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDeliversValidLinesAndDropsGarbage() throws {
        let url = directory.appendingPathComponent("agent.sock")
        var received: [AgentEvent] = []
        let delivered = expectation(description: "event delivered")
        let listener = AgentSocketListener(url: url) { event in
            received.append(event)
            delivered.fulfill()
        }
        try listener.start()
        defer { listener.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSocket)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        let event = AgentEvent(agent: "test", kind: .turnEnded, surfaceID: UUID(), workspaceID: nil, cwd: "/", at: Date(timeIntervalSince1970: 0))
        let fd = try XCTUnwrap(UnixSocket.connect(to: url.path))
        XCTAssertTrue(UnixSocket.write(Data("this is not json\n".utf8) + (try event.line()), to: fd))
        close(fd)

        wait(for: [delivered], timeout: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(received, [event])
    }

    func testStopRemovesTheSocketFile() throws {
        let url = directory.appendingPathComponent("agent.sock")
        let listener = AgentSocketListener(url: url) { _ in }
        try listener.start()
        listener.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(UnixSocket.connect(to: url.path))
    }

    func testRemovesOnlyTheSocketsOfFlowsThatAreGone() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let live = AgentEnvironment.socketURL(pid: getpid(), in: directory)
        let dead = AgentEnvironment.socketURL(pid: deadPID(), in: directory)
        let other = directory.appendingPathComponent("notes.txt")
        for url in [live, dead, other] {
            try Data().write(to: url)
        }
        AgentSocketListener.removeStaleSockets(in: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dead.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }
}
