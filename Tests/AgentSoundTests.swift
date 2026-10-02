import AppKit
import XCTest

@MainActor
final class AgentSoundTests: XCTestCase {
    let surface = UUID()

    func update(_ kind: AgentEvent.Kind, from previous: AgentSessionStore.State? = .working, previousDetail: String? = nil,
                state: AgentSessionStore.State, detail: String? = nil, attention: String? = nil) -> AgentSessionStore.Update {
        let at = Date()
        let old = previous.map { AgentSessionStore.Session(agent: "test", sessionID: "s", state: $0, detail: previousDetail, startedAt: at, updatedAt: at) }
        let new = AgentSessionStore.Session(agent: "test", sessionID: "s", state: state, detail: detail, attention: attention, startedAt: at, updatedAt: at)
        return AgentSessionStore.Update(surface: surface, kind: kind, previous: old, session: new)
    }

    func testWaitingSoundsOnlyOutOfView() {
        XCTAssertEqual(AgentSound.make(for: update(.needsInput, state: .waiting, detail: "permission_prompt"), isVisible: false), .needsInput)
        XCTAssertNil(AgentSound.make(for: update(.needsInput, state: .waiting, detail: "permission_prompt"), isVisible: true))
    }

    func testTheSameWaitIsSilent() {
        XCTAssertNil(AgentSound.make(for: update(.needsInput, from: .waiting, previousDetail: "permission_prompt", state: .waiting, detail: "permission_prompt"), isVisible: false))
        XCTAssertEqual(AgentSound.make(for: update(.needsInput, from: .waiting, previousDetail: "agent_needs_input", state: .waiting, detail: "permission_prompt"), isVisible: false),
                       .needsInput)
    }

    func testAFinishedTurnSoundsOnlyOutOfView() {
        XCTAssertEqual(AgentSound.make(for: update(.turnEnded, state: .idle), isVisible: false), .finished)
        XCTAssertNil(AgentSound.make(for: update(.turnEnded, state: .idle), isVisible: true))
    }

    func testAttentionSoundsOnlyOutOfViewWithAMessage() {
        XCTAssertEqual(AgentSound.make(for: update(.attention, state: .working, attention: "look here"), isVisible: false), .finished)
        XCTAssertNil(AgentSound.make(for: update(.attention, state: .working, attention: "look here"), isVisible: true))
        XCTAssertNil(AgentSound.make(for: update(.attention, state: .working), isVisible: false))
    }

    func testOtherEventsAreSilent() {
        for kind in [AgentEvent.Kind.sessionStarted, .turnStarted, .working, .sessionEnded, .unknown] {
            XCTAssertNil(AgentSound.make(for: update(kind, state: .working), isVisible: false))
        }
    }

    func testABurstPlaysOnce() {
        var throttle = AgentSoundThrottle()
        let start = Date()
        XCTAssertTrue(throttle.allows(.finished, at: start))
        XCTAssertFalse(throttle.allows(.finished, at: start.addingTimeInterval(0.1)))
        XCTAssertTrue(throttle.allows(.needsInput, at: start.addingTimeInterval(0.1)))
        XCTAssertTrue(throttle.allows(.finished, at: start.addingTimeInterval(0.5)))
    }

    func testTheSoundsExist() {
        XCTAssertNotNil(NSSound(named: AgentSound.needsInput.name))
        XCTAssertNotNil(NSSound(named: AgentSound.finished.name))
    }
}
