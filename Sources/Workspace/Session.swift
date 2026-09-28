import Foundation

/// What survives a relaunch: each window's position and workspaces, the
/// workspaces' names, their tabs' working directories and zoomed panes, the
/// ids of workspaces and terminals, and which of each is selected. Shell
/// processes and screen contents do not.
struct Session: Codable, Equatable {
    struct Window: Codable, Equatable {
        var workspaces: [Workspace]
        var selectedWorkspace: Int
        var frame: CGRect?
    }

    struct Workspace: Codable, Equatable {
        /// Agents running in a terminal are told these ids, so they must stay
        /// the same across relaunches.
        var id: UUID
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
        case terminal(id: UUID, workingDirectory: String?)
        case split(axis: SplitAxis, ratio: Double, first: Layout, second: Layout)

        init<Leaf>(node: PaneNode<Leaf>) {
            if let leaf = node.leaf {
                self = .terminal(id: leaf.id, workingDirectory: leaf.workingDirectory)
            } else {
                self = .split(axis: node.axis ?? .horizontal, ratio: node.ratio,
                              first: Layout(node: node.first!), second: Layout(node: node.second!))
            }
        }

        func makeNode<Leaf>(_ makeLeaf: (UUID, String?) -> Leaf) -> PaneNode<Leaf> {
            switch self {
            case .terminal(let id, let workingDirectory):
                return PaneNode(leaf: makeLeaf(id, workingDirectory))
            case .split(let axis, let ratio, let first, let second):
                return PaneNode(axis: axis, first: first.makeNode(makeLeaf), second: second.makeNode(makeLeaf), ratio: ratio)
            }
        }
    }

    var windows: [Window]

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
    func snapshot(frame: CGRect? = nil) -> Session.Window {
        Session.Window(
            workspaces: workspaces.map { workspace in
                Session.Workspace(
                    id: workspace.id,
                    customName: workspace.customName,
                    tabs: workspace.tabs.map { tab in
                        Session.Tab(
                            layout: Session.Layout(node: tab.panes.root),
                            zoomedPane: tab.panes.zoomed.flatMap { zoomed in tab.panes.leaves.firstIndex { $0 === zoomed } })
                    },
                    selectedTab: workspace.tabs.firstIndex { $0 === workspace.selectedTab } ?? 0)
            },
            selectedWorkspace: workspaces.firstIndex { $0 === selected } ?? 0,
            frame: frame)
    }

    /// Rebuilds one window's workspaces. `makeLeaf` recreates a terminal from
    /// its saved id and working directory, given the id of its workspace.
    /// Workspaces whose tabs were all lost are skipped.
    func restore(_ window: Session.Window, makeLeaf: (_ id: UUID, _ workingDirectory: String?, _ workspace: UUID) -> Leaf) {
        for saved in window.workspaces {
            let workspace = addWorkspace(id: saved.id, customName: saved.customName)
            for tab in saved.tabs {
                let root = tab.layout.makeNode { makeLeaf($0, $1, workspace.id) }
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
        if window.selectedWorkspace < workspaces.count {
            select(workspaces[window.selectedWorkspace])
        }
    }
}

extension Session.Window {
    /// A saved frame whose title bar would land on no connected screen, as
    /// when the display it was on is unplugged, is fitted and centred on the
    /// first screen instead. `screens` are visible frames, the menu bar
    /// screen first.
    static func placing(_ frame: CGRect, on screens: [CGRect]) -> CGRect {
        let titleBar = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        guard let screen = screens.first,
              !screens.contains(where: { $0.intersection(titleBar).width >= 80 }) else { return frame }
        let size = CGSize(width: min(frame.width, screen.width), height: min(frame.height, screen.height))
        return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }
}
