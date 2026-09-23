import Foundation

/// What survives a relaunch: workspace names, their tabs' working directories
/// and zoomed panes, and which of each is selected. Shell processes and screen
/// contents do not.
struct Session: Codable, Equatable {
    struct Workspace: Codable, Equatable {
        var customName: String?
        var tabs: [Tab]
        var selectedTab: Int
    }

    struct Tab: Codable, Equatable {
        var layout: Layout
        /// Index of the zoomed pane among the layout's terminals, in order.
        var zoomedPane: Int?
    }

    indirect enum Layout: Codable, Equatable {
        case terminal(workingDirectory: String?)
        case split(axis: SplitAxis, ratio: Double, first: Layout, second: Layout)

        init<Leaf>(node: PaneNode<Leaf>) {
            if let leaf = node.leaf {
                self = .terminal(workingDirectory: leaf.workingDirectory)
            } else {
                self = .split(axis: node.axis ?? .horizontal, ratio: node.ratio,
                              first: Layout(node: node.first!), second: Layout(node: node.second!))
            }
        }

        func makeNode<Leaf>(_ makeLeaf: (String?) -> Leaf) -> PaneNode<Leaf> {
            switch self {
            case .terminal(let workingDirectory):
                return PaneNode(leaf: makeLeaf(workingDirectory))
            case .split(let axis, let ratio, let first, let second):
                return PaneNode(axis: axis, first: first.makeNode(makeLeaf), second: second.makeNode(makeLeaf), ratio: ratio)
            }
        }
    }

    var workspaces: [Workspace]
    var selectedWorkspace: Int

    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("flow", isDirectory: true).appendingPathComponent("session.json")
    }()

    static func load(from url: URL = fileURL) -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    func save(to url: URL = fileURL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            logger.error("failed to save session: \(error)")
        }
    }
}

extension WorkspaceStoreModel {
    func session() -> Session {
        Session(
            workspaces: workspaces.map { workspace in
                Session.Workspace(
                    customName: workspace.customName,
                    tabs: workspace.tabs.map { tab in
                        Session.Tab(
                            layout: Session.Layout(node: tab.panes.root),
                            zoomedPane: tab.panes.zoomed.flatMap { zoomed in tab.panes.leaves.firstIndex { $0 === zoomed } })
                    },
                    selectedTab: workspace.tabs.firstIndex { $0 === workspace.selectedTab } ?? 0)
            },
            selectedWorkspace: workspaces.firstIndex { $0 === selected } ?? 0)
    }

    /// Rebuilds workspaces from a session. `makeLeaf` creates a terminal for a
    /// saved working directory. Workspaces whose tabs were all lost are skipped.
    func restore(_ session: Session, makeLeaf: (String?) -> Leaf) {
        for saved in session.workspaces {
            let workspace = addWorkspace(customName: saved.customName)
            for tab in saved.tabs {
                let root = tab.layout.makeNode(makeLeaf)
                let leaves = root.leaves
                guard let first = leaves.first else { continue }
                let panes = PaneTreeModel(root: root)
                let zoomed = tab.zoomedPane.flatMap { leaves.indices.contains($0) ? leaves[$0] : nil }
                if let zoomed { panes.toggleZoom(zoomed) }
                workspace.add(TabModel(panes: panes, focused: zoomed ?? first))
            }
            if saved.selectedTab < workspace.tabs.count {
                workspace.select(workspace.tabs[saved.selectedTab])
            }
            if workspace.tabs.isEmpty {
                remove(workspace)
            }
        }
        if session.selectedWorkspace < workspaces.count {
            select(workspaces[session.selectedWorkspace])
        }
    }
}
