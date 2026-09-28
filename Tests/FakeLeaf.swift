import Foundation

/// Stands in for a terminal surface in model tests.
final class FakeLeaf: PaneLeaf {
    let id: UUID
    var title: String
    var workingDirectory: String?
    var needsConfirmQuit = false
    var frame = CGRect.zero

    init(_ title: String = "", id: UUID = UUID(), workingDirectory: String? = nil) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
    }
}

typealias TestTree = PaneTreeModel<FakeLeaf>
typealias TestStore = WorkspaceStoreModel<FakeLeaf>
typealias TestTab = TabModel<FakeLeaf>
