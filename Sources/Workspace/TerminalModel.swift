import Foundation

typealias TerminalTab = TabModel<TerminalSurfaceView>
typealias Workspace = WorkspaceModel<TerminalSurfaceView>
typealias WorkspaceStore = WorkspaceStoreModel<TerminalSurfaceView>
typealias PaneTree = PaneTreeModel<TerminalSurfaceView>
typealias Pane = PaneNode<TerminalSurfaceView>

extension TerminalSurfaceView: PaneLeaf {}

extension TerminalTab {
    var focusedSurface: TerminalSurfaceView { focusedLeaf }
}

extension Workspace {
    var surfaces: [TerminalSurfaceView] { tabs.flatMap(\.panes.surfaces) }
}

extension PaneTree {
    var surfaces: [TerminalSurfaceView] { leaves }
}

extension Pane {
    var surface: TerminalSurfaceView? { leaf }
    var surfaces: [TerminalSurfaceView] { leaves }
}
