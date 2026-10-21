import AppKit
import XCTest

final class SessionPerformanceTests: XCTestCase {
    func testRestorePublishesOnlyTheCompletedWindow() {
        let original = TestStore()
        for index in 0..<30 {
            original.addWorkspace(customName: "w\(index)").add(TestTab(leaf: FakeLeaf()))
        }
        original.select(original.workspaces[7])
        let saved = original.snapshot()
        let restored = TestStore()
        var snapshots: [Session.Window] = []
        restored.onChange = { snapshots.append(restored.snapshot()) }
        restored.restore(saved) { id, directory, _ in FakeLeaf(id: id, workingDirectory: directory) }
        XCTAssertEqual(snapshots, [saved])
    }

    func testNestedBatchesPublishOnceAndEmptyBatchesDoNotPublish() {
        let store = TestStore()
        var changes = 0
        store.onChange = { changes += 1 }
        store.performBatch {
            store.addWorkspace()
            store.performBatch { store.addWorkspace() }
            XCTAssertEqual(changes, 0)
        }
        XCTAssertEqual(changes, 1)
        store.performBatch {}
        XCTAssertEqual(changes, 1)
    }

    func testSlowWriterKeepsOnlyTheLatestPendingSnapshot() {
        let began = expectation(description: "first write started")
        let resume = DispatchSemaphore(value: 0)
        let first = Session(windows: [])
        let intermediate = Session(windows: [.init(workspaces: [], selectedWorkspace: 1)])
        let last = Session(windows: [.init(workspaces: [], selectedWorkspace: 2)])
        var written: [Session] = []
        let writer = SessionWriter { session in
            XCTAssertFalse(Thread.isMainThread)
            written.append(session)
            if written.count == 1 {
                began.fulfill()
                XCTAssertEqual(resume.wait(timeout: .now() + 5), .success)
            }
            return true
        }
        writer.save(first)
        wait(for: [began], timeout: 2)
        writer.save(intermediate)
        writer.save(last)
        resume.signal()
        writer.flush(last)
        XCTAssertEqual(written, [first, last])
    }

    func testFailedWritesAreRetriedAndSuccessfulWritesAreDeduplicated() {
        var attempts = 0
        let writer = SessionWriter { _ in
            attempts += 1
            return attempts > 1
        }
        let session = Session(windows: [])
        writer.flush(session)
        writer.flush(session)
        writer.flush(session)
        XCTAssertEqual(attempts, 2)
    }
}

@MainActor
final class AgentRefreshTests: XCTestCase {
    func testRepeatedWorkingEventsKeepDetailsWithoutRefreshingIndicators() {
        let id = UUID()
        let store = AgentSessionStore(isLive: { $0 == id })
        var changes: [UUID] = []
        var updates: [AgentSessionStore.Update] = []
        store.onChange = { changes.append($0) }
        store.onUpdate = { updates.append($0) }
        func send(_ kind: AgentEvent.Kind, detail: String? = nil) {
            store.apply(AgentEvent(agent: "test", kind: kind, surfaceID: id, workspaceID: nil,
                                   cwd: "/", at: Date(), detail: detail))
        }
        send(.sessionStarted)
        send(.turnStarted)
        for index in 0..<100 { send(.working, detail: "tool\(index)") }
        send(.attention, detail: "look here")
        XCTAssertEqual(changes, [id])
        XCTAssertEqual(updates.count, 103)
        XCTAssertEqual(store.sessions[id]?.detail, "tool99")
        XCTAssertEqual(store.sessions[id]?.attention, "look here")
        send(.needsInput)
        send(.working)
        send(.turnEnded)
        store.markSeen(id)
        XCTAssertEqual(changes, Array(repeating: id, count: 5))
    }
}

final class GitStatusParserTests: XCTestCase {
    func testEveryChunkBoundaryPreservesBranchAndDirtyStatus() {
        for text in ["## main...origin/main [ahead 1]\n", "## feature/日本語\n M file\n?? new\n"] {
            let bytes = Array(text.utf8)
            for split in 0...bytes.count {
                var parser = GitStatusParser()
                parser.append(Data(bytes[..<split]))
                parser.append(Data(bytes[split...]))
                XCTAssertEqual(parser.status, GitStatus(porcelain: text))
            }
        }
    }

    func testLargeStatusOutputOnlyNeedsOneDirtyFlag() {
        var parser = GitStatusParser()
        parser.append(Data("## main\n".utf8))
        let chunk = Data(String(repeating: " M file\n", count: 1024).utf8)
        for _ in 0..<1024 { parser.append(chunk) }
        XCTAssertEqual(parser.status, GitStatus(branch: "main", isDirty: true))
    }

    func testInvalidAndOversizedHeadersAreRejected() {
        var parser = GitStatusParser()
        parser.append(Data("fatal: no repository\n".utf8))
        XCTAssertNil(parser.status)
        parser = GitStatusParser()
        parser.append(Data(("## " + String(repeating: "x", count: 65536)).utf8))
        parser.append(Data("\n M file\n".utf8))
        XCTAssertNil(parser.status)
    }
}

@MainActor
final class MenuReuseTests: XCTestCase {
    func testUnchangedMenuKeepsItemsAndSelectionChangesStillApply() {
        let menu = WorkspaceMenu(title: "Workspace", fixedItems: [], target: NSObject(),
                                 selectWorkspace: Selector(("workspace:")), selectTab: Selector(("tab:")))
        var selection = 0
        menu.contents = {
            .init(workspaces: .init(names: ["one", "two"], selected: selection),
                  tabs: .init(names: [], selected: nil))
        }
        menu.menuNeedsUpdate(menu.menu)
        let original = menu.menu.items
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertTrue(zip(original, menu.menu.items).allSatisfy { $0 === $1 })
        selection = 1
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertEqual(menu.menu.items.filter { !$0.isSeparatorItem }.map(\.state), [.off, .on])
        menu.contents = { nil }
        menu.menuNeedsUpdate(menu.menu)
        XCTAssertTrue(menu.menu.items.isEmpty)
    }
}

final class HookSummaryTests: XCTestCase {
    func testSummaryMatchesWhitespaceAndUnicodeBoundaries() throws {
        for message in ["  one\n\t two  ", String(repeating: "é", count: 200),
                        String(repeating: "👩🏽‍💻 ", count: 10000), String(repeating: "a", count: 199) + " b"] {
            let input = try JSONSerialization.data(withJSONObject: ["message": message])
            let payload = try XCTUnwrap(HookPayload(json: input, agent: "test", environment: [:], now: Date()))
            let normalized = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let expected = normalized.count > HookPayload.detailLimit
                ? String(normalized.prefix(HookPayload.detailLimit - 1)) + "…" : normalized
            XCTAssertEqual(payload.summary("message"), expected)
        }
    }
}
