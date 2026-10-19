import XCTest

/// Runs the built `flw` the way an agent runs its hooks.
final class FlwTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("flow-test-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    struct Run {
        var status: Int32
        var reason: Process.TerminationReason
        var stdout: Data
        var seconds: TimeInterval
    }

    func hook(socket: URL) throws -> Run {
        let flw = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("flw")
        let process = Process()
        process.executableURL = flw
        process.arguments = ["hook", "claude"]
        process.environment = [AgentEnvironment.socketKey: socket.path, AgentEnvironment.surfaceKey: UUID().uuidString]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        let start = Date()
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"hook_event_name":"Stop","session_id":"s","last_assistant_message":"done"}"#.utf8))
        try input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, reason: process.terminationReason, stdout: stdout, seconds: Date().timeIntervalSince(start))
    }

    func testHookReachesFlowAndPrintsNothing() throws {
        let url = directory.appendingPathComponent("agent.sock")
        var received: [AgentEvent] = []
        let listener = AgentSocketListener(url: url) { received.append($0) }
        try listener.start()
        defer { listener.stop() }

        let run = try hook(socket: url)
        let deadline = Date().addingTimeInterval(2)
        while received.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(run.reason, .exit)
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.stdout, Data())
        XCTAssertEqual(received.map(\.kind), [.turnEnded])
    }

    /// A Flow that is frozen still has its connections accepted by the kernel,
    /// but never reads them or closes its end.
    func testHookGivesUpOnAFlowThatNeverAnswers() throws {
        let url = directory.appendingPathComponent("agent.sock")
        let fd = try XCTUnwrap(UnixSocket.make())
        defer { close(fd) }
        XCTAssertEqual(UnixSocket.withAddress(url.path) { Darwin.bind(fd, $0, $1) }, 0)
        XCTAssertEqual(listen(fd, 16), 0)

        let run = try hook(socket: url)

        XCTAssertEqual(run.reason, .exit)
        XCTAssertEqual(run.status, 0)
        XCTAssertEqual(run.stdout, Data())
        XCTAssertGreaterThan(run.seconds, 0.25)
        XCTAssertLessThan(run.seconds, 2)
    }
}
