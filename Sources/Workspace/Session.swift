import Foundation

/// What survives a relaunch: workspace names, their tabs' working directories,
/// and which of each is selected. Shell processes and screen contents do not.
struct Session: Codable {
    struct Workspace: Codable {
        var name: String
        var tabs: [Tab]
        var selectedTab: Int
    }

    struct Tab: Codable {
        var workingDirectory: String?
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
                    name: workspace.name,
                    tabs: workspace.tabs.map { Session.Tab(workingDirectory: $0.surface.pwd) },
                    selectedTab: workspace.tabs.firstIndex { $0 === workspace.selectedTab } ?? 0)
            },
            selectedWorkspace: workspaces.firstIndex { $0 === selected } ?? 0)
    }
}
