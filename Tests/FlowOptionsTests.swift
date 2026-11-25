import GhosttyKit
import XCTest

final class FlowOptionsTests: XCTestCase {
    private static let initialized = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
    private var directory: URL!
    private var domain: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        domain = UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: domain)
        try FileManager.default.removeItem(at: directory)
    }

    private func config(_ text: String) throws -> URL {
        let url = directory.appendingPathComponent("config")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Ghostty adding an option of the same name would leave it unreachable,
    /// since libghostty never sees Flow's options.
    func testGhosttyHasNoneOfFlowsOptions() throws {
        XCTAssertEqual(Self.initialized, GHOSTTY_SUCCESS)
        let file = try config(FlowOption.keys.sorted().map { "\($0) = 1\n" }.joined())
        let config = try GhosttyConfig(file: file, flowKeys: [])
        XCTAssertEqual(config.diagnostics.count, FlowOption.keys.count, config.diagnostics.joined(separator: "\n"))
        XCTAssertTrue(config.diagnostics.allSatisfy { $0.hasSuffix("unknown field") }, config.diagnostics.joined(separator: "\n"))
    }

    func testSoundsReadNoneAsSilenceAndEmptyAsTheDefault() {
        XCTAssertEqual(FlowOptions(ConfigDocument("agent-finished-sound = none\n")).value(FlowOption.finishedSound), "")
        XCTAssertEqual(FlowOptions(ConfigDocument("agent-finished-sound =\n")).value(FlowOption.finishedSound), "Glass")
        XCTAssertEqual(FlowOption.finishedSound.format(""), "none")
    }

    func testTelemetryIsOnUnlessTurnedOff() {
        func telemetry(_ text: String) -> Bool { FlowOptions(ConfigDocument(text)).value(FlowOption.telemetry) }
        XCTAssertTrue(telemetry(""))
        XCTAssertTrue(telemetry("telemetry =\n"))
        XCTAssertTrue(telemetry("telemetry = true\n"))
        XCTAssertFalse(telemetry("telemetry = false\n"))
        XCTAssertFalse(telemetry("telemetry = off\n"))
    }

    func testMovesChangedSettingsOutOfTheDefaults() throws {
        let file = try config("font-size = 14\n")
        defaults.set(true, forKey: "SecureKeyboardEntry")
        defaults.set("", forKey: "AgentNeedsInputSound")
        defaults.set(false, forKey: "AgentFinishedNotification")
        defaults.set("Glass", forKey: "AgentFinishedSound")
        FlowOption.moveFromDefaults(defaults, domain: domain, to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), """
            font-size = 14
            secure-keyboard-entry = true
            agent-needs-input-sound = none
            agent-finished-notification = false

            """, "the finished sound was the default, so it isn't written")
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?.count ?? 0, 0)
    }

    func testTheFileWinsOverTheDefaults() throws {
        let file = try config("agent-finished-sound = Basso\n")
        defaults.set("Hero", forKey: "AgentFinishedSound")
        FlowOption.moveFromDefaults(defaults, domain: domain, to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "agent-finished-sound = Basso\n")
        XCTAssertNil(defaults.persistentDomain(forName: domain)?["AgentFinishedSound"])
    }

    func testKeepsTheDefaultsWhenTheFileCannotBeRead() throws {
        let file = directory.appendingPathComponent("config")
        try Data([0xFF, 0xFE, 0x00]).write(to: file)
        defaults.set(true, forKey: "SecureKeyboardEntry")
        FlowOption.moveFromDefaults(defaults, domain: domain, to: file)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?["SecureKeyboardEntry"] as? Bool, true)
    }

    func testDoesNothingWithoutSettingsToMove() throws {
        let file = directory.appendingPathComponent("config")
        FlowOption.moveFromDefaults(defaults, domain: domain, to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
