import XCTest

@MainActor
final class AgentNotificationTests: XCTestCase {
    let surface = UUID()

    func update(_ kind: AgentEvent.Kind, from previous: AgentSessionStore.State? = .working, previousDetail: String? = nil,
                state: AgentSessionStore.State, detail: String? = nil, attention: String? = nil) -> AgentSessionStore.Update {
        let at = Date()
        let old = previous.map { AgentSessionStore.Session(agent: "test", sessionID: "s", state: $0, detail: previousDetail, startedAt: at, updatedAt: at) }
        let new = AgentSessionStore.Session(agent: "test", sessionID: "s", state: state, detail: detail, attention: attention, startedAt: at, updatedAt: at)
        return AgentSessionStore.Update(surface: surface, kind: kind, previous: old, session: new)
    }

    func notification(_ update: AgentSessionStore.Update, isVisible: Bool = false) -> AgentNotification? {
        AgentNotification.make(for: update, title: "~/Code/flow", isVisible: isVisible)
    }

    func testWaitingNamesTheReasonWhenItKnowsIt() {
        XCTAssertEqual(notification(update(.needsInput, state: .waiting, detail: "permission_prompt")),
                       AgentNotification(title: "~/Code/flow", body: "Needs permission"))
        XCTAssertEqual(notification(update(.needsInput, state: .waiting, detail: "agent_needs_input"))?.body, "Waiting for your input")
        XCTAssertEqual(notification(update(.needsInput, state: .waiting))?.body, "Waiting for your input")
    }

    func testTheSameWaitIsNotRepeated() {
        XCTAssertNil(notification(update(.needsInput, from: .waiting, previousDetail: "agent_needs_input", state: .waiting, detail: "agent_needs_input")))
        XCTAssertEqual(notification(update(.needsInput, from: .waiting, previousDetail: "agent_needs_input", state: .waiting, detail: "permission_prompt"))?.body,
                       "Needs permission")
    }

    func testAFinishedTurnShowsTheLastMessage() {
        XCTAssertEqual(notification(update(.turnEnded, state: .idle, detail: "All done"))?.body, "All done")
        XCTAssertEqual(notification(update(.turnEnded, state: .idle))?.body, "Finished")
        XCTAssertEqual(notification(update(.turnEnded, state: .idle, detail: "  "))?.body, "Finished")
    }

    func testAttentionShowsItsMessage() {
        XCTAssertEqual(notification(update(.attention, state: .working, attention: "look here"))?.body, "look here")
        XCTAssertNil(notification(update(.attention, state: .working)))
    }

    func testNothingIsPostedForATerminalInView() {
        XCTAssertNil(notification(update(.needsInput, state: .waiting), isVisible: true))
        XCTAssertNil(notification(update(.turnEnded, state: .idle), isVisible: true))
        XCTAssertNil(notification(update(.attention, state: .working, attention: "hi"), isVisible: true))
    }

    func testOtherEventsPostNothing() {
        for kind in [AgentEvent.Kind.sessionStarted, .turnStarted, .working, .sessionEnded] {
            XCTAssertNil(notification(update(kind, state: .working)))
        }
    }
}
