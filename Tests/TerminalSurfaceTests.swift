import AppKit
import GhosttyKit
import XCTest

@MainActor
final class TerminalSurfaceTests: XCTestCase {
    private static let initialized = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)

    private func withRuntime(_ body: (GhosttyRuntime) throws -> Void) throws {
        _ = NSApplication.shared
        XCTAssertEqual(Self.initialized, GHOSTTY_SUCCESS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "shell-integration = none\n".write(to: config, atomically: true, encoding: .utf8)
        let runtime = try GhosttyRuntime(configFile: config)
        try autoreleasepool { try body(runtime) }
    }

    private func terminal(_ runtime: GhosttyRuntime, id: UUID = UUID(), directory: String? = nil, startImmediately: Bool = false) -> TerminalSurfaceView {
        var config = TerminalSurfaceConfiguration()
        config.command = "/bin/sleep 60"
        config.workingDirectory = directory
        return TerminalSurfaceView(runtime: runtime, id: id, configuration: config, startImmediately: startImmediately)
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testUnopenedTerminalKeepsMetadataWithoutCreatingTerminalOrControls() throws {
        try withRuntime { runtime in
            let id = UUID()
            var view: TerminalSurfaceView? = terminal(runtime, id: id, directory: "/tmp")
            weak let released = view
            XCTAssertEqual(view?.id, id)
            XCTAssertEqual(view?.workingDirectory, "/tmp")
            XCTAssertNil(view?.surface)
            XCTAssertEqual(view?.subviews.count, 0)
            XCTAssertEqual(view?.needsConfirmQuit, false)
            runtime.reloadConfig()
            view?.setDimColor(nil)
            XCTAssertNil(view?.surface)
            XCTAssertEqual(view?.subviews.count, 0)
            view = nil
            XCTAssertNil(released)
        }
    }

    func testAttachingStartsOnceAndDetachingKeepsTheSession() throws {
        try withRuntime { runtime in
            let view = terminal(runtime)
            let window = window()
            defer { window.contentView = nil; window.close() }
            window.contentView = view
            let surface = try XCTUnwrap(view.surface)
            XCTAssertFalse(view.subviews.isEmpty)
            let controls = view.subviews.count
            window.contentView = nil
            XCTAssertEqual(view.surface, surface)
            window.contentView = view
            XCTAssertEqual(view.surface, surface)
            XCTAssertEqual(view.subviews.count, controls)
        }
    }

    func testNewTerminalStillStartsImmediately() throws {
        try withRuntime { runtime in
            let view = terminal(runtime, startImmediately: true)
            XCTAssertNotNil(view.surface)
            XCTAssertNil(view.window)
        }
    }

    func testDeferredDimmingIsAppliedWhenTerminalStarts() throws {
        try withRuntime { runtime in
            for clearBeforeStarting in [false, true] {
                let view = terminal(runtime)
                let color = NSColor.black.withAlphaComponent(0.2)
                view.setDimColor(color)
                if clearBeforeStarting { view.setDimColor(nil) }
                XCTAssertNil(view.surface)
                XCTAssertTrue(view.subviews.isEmpty)

                let window = window()
                defer { window.contentView = nil; window.close() }
                window.contentView = view
                let overlay = try XCTUnwrap(view.subviews.first)
                XCTAssertEqual(overlay.isHidden, clearBeforeStarting)
                XCTAssertEqual(overlay.layer?.backgroundColor, clearBeforeStarting ? nil : color.cgColor)
                view.setDimColor(nil)
                XCTAssertTrue(overlay.isHidden)
                XCTAssertNil(overlay.layer?.backgroundColor)
            }
        }
    }

    func testUnattachedTerminalDoesNotRender() throws {
        try withRuntime { runtime in
            var config = TerminalSurfaceConfiguration()
            config.command = "/bin/sh -c 'printf ready; sleep 60'"
            let view = TerminalSurfaceView(runtime: runtime, configuration: config)
            XCTAssertNotNil(view.surface)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            XCTAssertNil(view.layer?.contents)
        }
    }

    func testDeferredTerminalUsesConfigReloadedBeforeItStarts() throws {
        try withRuntime { runtime in
            let view = terminal(runtime)
            let path = runtime.configFile.path
            try "shell-integration = none\nfont-size = 24\nscrollbar = never\n".write(toFile: path, atomically: true, encoding: .utf8)
            runtime.reloadConfig()
            XCTAssertNil(view.surface)

            let window = window()
            defer { window.contentView = nil; window.close() }
            window.contentView = view
            let surface = try XCTUnwrap(view.surface)
            XCTAssertEqual(ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_SPLIT).font_size, 24)
            let scrollbar = try XCTUnwrap(view.subviews.first { $0 is TerminalScrollbar })
            XCTAssertTrue(scrollbar.isHidden)
        }
    }

    func testRunningTerminalTakesUpReloadedConfig() throws {
        try withRuntime { runtime in
            let view = terminal(runtime)
            let window = window()
            defer { window.contentView = nil; window.close() }
            window.contentView = view
            let surface = try XCTUnwrap(view.surface)
            var changes = 0
            runtime.onConfigChange = { changes += 1 }

            let path = runtime.configFile.path
            try "shell-integration = none\nfont-size = 24\nscrollbar = never\n".write(toFile: path, atomically: true, encoding: .utf8)
            runtime.reloadConfig()

            XCTAssertEqual(ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_SPLIT).font_size, 24)
            XCTAssertTrue(try XCTUnwrap(view.subviews.first { $0 is TerminalScrollbar }).isHidden)
            XCTAssertEqual(changes, 1)
        }
    }

    func testRestoreStartsOnlyDisplayedPanesAndPreservesUnopenedLayout() throws {
        try withRuntime { runtime in
            let a = UUID(), b = UUID(), c = UUID(), d = UUID()
            let saved = Session.Window(workspaces: [
                .init(id: UUID(), customName: "first", tabs: [
                    .init(layout: .split(axis: .horizontal, ratio: 0.3,
                                        first: .terminal(id: a, workingDirectory: "/tmp"),
                                        second: .terminal(id: b, workingDirectory: "/")), zoomedPane: 1),
                    .init(layout: .terminal(id: c, workingDirectory: "/tmp"), zoomedPane: nil),
                ], selectedTab: 0),
                .init(id: UUID(), customName: "second", tabs: [
                    .init(layout: .terminal(id: d, workingDirectory: "/"), zoomedPane: nil),
                ], selectedTab: 0),
            ], selectedWorkspace: 0, frame: nil)
            let store = WorkspaceStore()
            store.restore(saved) { id, directory, _ in terminal(runtime, id: id, directory: directory) }
            let views = store.workspaces.flatMap(\.surfaces)
            @MainActor func started() -> Set<UUID> { Set(views.filter { $0.surface != nil }.map(\.id)) }
            XCTAssertEqual(started(), [])
            XCTAssertEqual(store.snapshot(), saved)
            XCTAssertEqual(store.workspaces[0].tabs.map(\.title), ["/", "/tmp"])
            XCTAssertEqual(store.workspaces[1].tabs.map(\.title), ["/"])

            let window = window()
            let panes = PaneTreeView()
            window.contentView = panes
            defer { panes.show(nil); window.contentView = nil; window.close() }
            let first = store.workspaces[0]
            let tab = first.tabs[0]
            panes.show(tab.panes)
            XCTAssertEqual(started(), [b])
            XCTAssertEqual(store.snapshot(), saved)

            tab.panes.unzoom()
            panes.show(tab.panes)
            XCTAssertEqual(started(), [a, b])
            first.select(first.tabs[1])
            panes.show(first.selectedTab?.panes)
            XCTAssertEqual(started(), [a, b, c])
            XCTAssertNil(views.first { $0.id == d }?.surface)

            store.remove(store.workspaces[1])
            XCTAssertEqual(started(), [a, b, c])
            XCTAssertEqual(store.snapshot().workspaces.count, 1)
        }
    }
}
