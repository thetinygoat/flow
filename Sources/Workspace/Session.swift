import Foundation

/// What survives a relaunch: workspace names, their tabs' working directories,
/// and which of each is selected. Shell processes and screen contents do not.
struct Session: Codable {
    struct Workspace: Codable {
        var customName: String?
        var tabs: [Tab]
        var selectedTab: Int
    }

    struct Tab: Codable {
        var layout: Layout
    }

    indirect enum Layout: Codable {
        case terminal(workingDirectory: String?)
        case split(axis: SplitAxis, ratio: Double, first: Layout, second: Layout)

        init(pane: Pane) {
            if let surface = pane.surface {
                self = .terminal(workingDirectory: surface.workingDirectory)
            } else {
                self = .split(axis: pane.axis ?? .horizontal, ratio: pane.ratio,
                              first: Layout(pane: pane.first!), second: Layout(pane: pane.second!))
            }
        }

        func makePane(_ makeSurface: (String?) -> TerminalSurfaceView) -> Pane {
            switch self {
            case .terminal(let workingDirectory):
                return Pane(surface: makeSurface(workingDirectory))
            case .split(let axis, let ratio, let first, let second):
                return Pane(axis: axis, first: first.makePane(makeSurface), second: second.makePane(makeSurface), ratio: ratio)
            }
        }
    }

    var workspaces: [Workspace]
    var selectedWorkspace: Int

    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("flow", isDirectory: true).appendingPathComponent("session.json")
    }()

    static func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
        } catch {
            logger.error("failed to save session: \(error)")
        }
    }
}

extension WorkspaceStore {
    func session() -> Session {
        Session(
            workspaces: workspaces.map { workspace in
                Session.Workspace(
                    customName: workspace.customName,
                    tabs: workspace.tabs.map { Session.Tab(layout: Session.Layout(pane: $0.panes.root)) },
                    selectedTab: workspace.tabs.firstIndex { $0 === workspace.selectedTab } ?? 0)
            },
            selectedWorkspace: workspaces.firstIndex { $0 === selected } ?? 0)
    }
}
