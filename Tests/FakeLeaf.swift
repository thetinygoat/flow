import Foundation

/// Stands in for a terminal surface in model tests.
final class FakeLeaf: PaneLeaf {
    var title: String
    var workingDirectory: String?
    var needsConfirmQuit = false
    var needsAttention = false
    var isBusy = false
    var frame = CGRect.zero

    init(_ title: String = "", workingDirectory: String? = nil) {
        self.title = title
        self.workingDirectory = workingDirectory
    }
}

typealias TestTree = PaneTreeModel<FakeLeaf>
typealias TestStore = WorkspaceStoreModel<FakeLeaf>
typealias TestTab = TabModel<FakeLeaf>
