import Foundation

/// What the layout model needs from a terminal. The app's surface view
/// conforms; tests use a stand-in.
protocol PaneLeaf: AnyObject {
    var title: String { get }
    var workingDirectory: String? { get }
    var needsConfirmQuit: Bool { get }
    /// Set when the terminal alerted while the user was not looking at it.
    var needsAttention: Bool { get }
}

enum SplitAxis: String, Codable {
    /// Panes side by side.
    case horizontal
    /// Panes stacked.
    case vertical
}

enum SplitDirection {
    case right, left, down, up
}

enum PaneNavigation {
    case previous, next, up, left, down, right
}

enum ResizeDirection {
    case up, down, left, right
}

/// A node in a tab's split layout: either one terminal, or two child panes
/// divided along an axis.
final class PaneNode<Leaf: PaneLeaf> {
    var leaf: Leaf?
    var axis: SplitAxis?
    var first: PaneNode?
    var second: PaneNode?
    var ratio: CGFloat = 0.5
    weak var parent: PaneNode?

    init(leaf: Leaf) {
        self.leaf = leaf
    }

    init(axis: SplitAxis, first: PaneNode, second: PaneNode, ratio: CGFloat) {
        self.axis = axis
        self.first = first
        self.second = second
        self.ratio = ratio
        first.parent = self
        second.parent = self
    }

    var leaves: [Leaf] {
        if let leaf { return [leaf] }
        return (first?.leaves ?? []) + (second?.leaves ?? [])
    }

    func node(for leaf: Leaf) -> PaneNode? {
        if self.leaf === leaf { return self }
        return first?.node(for: leaf) ?? second?.node(for: leaf)
    }
}

/// The split layout of one tab. `version` changes on every structural edit so
/// views know when to rebuild.
final class PaneTreeModel<Leaf: PaneLeaf> {
    let root: PaneNode<Leaf>
    private(set) var version = 0
    /// The pane filling the whole tab while the others are hidden. Any change
    /// to the layout clears it.
    private(set) var zoomed: Leaf?

    init(leaf: Leaf) {
        root = PaneNode(leaf: leaf)
    }

    init(root: PaneNode<Leaf>) {
        self.root = root
    }

    var leaves: [Leaf] {
        root.leaves
    }

    func contains(_ leaf: Leaf) -> Bool {
        root.node(for: leaf) != nil
    }

    func node(for leaf: Leaf) -> PaneNode<Leaf>? {
        root.node(for: leaf)
    }

    func split(_ leaf: Leaf, direction: SplitDirection, with newLeaf: Leaf) {
        guard let node = root.node(for: leaf) else { return }
        let existing = PaneNode(leaf: leaf)
        let added = PaneNode(leaf: newLeaf)
        node.leaf = nil
        node.ratio = 0.5
        switch direction {
        case .right: (node.axis, node.first, node.second) = (.horizontal, existing, added)
        case .left: (node.axis, node.first, node.second) = (.horizontal, added, existing)
        case .down: (node.axis, node.first, node.second) = (.vertical, existing, added)
        case .up: (node.axis, node.first, node.second) = (.vertical, added, existing)
        }
        existing.parent = node
        added.parent = node
        zoomed = nil
        version += 1
    }

    /// Removes a terminal from the layout. Returns the terminal that should take
    /// focus next, or nil when the removed one was the last.
    func remove(_ leaf: Leaf) -> Leaf? {
        guard let node = root.node(for: leaf), let parent = node.parent,
              let first = parent.first, let second = parent.second else { return nil }
        let sibling = node === first ? second : first
        parent.leaf = sibling.leaf
        parent.axis = sibling.axis
        parent.first = sibling.first
        parent.second = sibling.second
        parent.ratio = sibling.ratio
        parent.first?.parent = parent
        parent.second?.parent = parent
        zoomed = nil
        version += 1
        return parent.leaves.first
    }

    /// Zooms the pane, or unzooms it when it is the zoomed one. A tab without
    /// splits has nothing to zoom.
    func toggleZoom(_ leaf: Leaf) {
        if zoomed === leaf {
            zoomed = nil
        } else {
            guard root.leaf == nil, contains(leaf) else { return }
            zoomed = leaf
        }
        version += 1
    }

    func unzoom() {
        guard zoomed != nil else { return }
        zoomed = nil
        version += 1
    }

    func equalize() {
        func visit(_ node: PaneNode<Leaf>) {
            node.ratio = 0.5
            node.first.map(visit)
            node.second.map(visit)
        }
        visit(root)
        zoomed = nil
        version += 1
    }

    /// `frame` supplies each leaf's on-screen rectangle, in a shared coordinate
    /// space with y pointing up, for the directional cases.
    func neighbor(of leaf: Leaf, direction: PaneNavigation, frame: (Leaf) -> CGRect) -> Leaf? {
        let all = leaves
        guard all.count > 1, let index = all.firstIndex(where: { $0 === leaf }) else { return nil }
        switch direction {
        case .previous: return all[(index + all.count - 1) % all.count]
        case .next: return all[(index + 1) % all.count]
        default: return spatialNeighbor(of: leaf, direction: direction, among: all, frame: frame)
        }
    }

    /// Picks the closest pane in the given direction that overlaps the current
    /// one on the other axis.
    private func spatialNeighbor(of leaf: Leaf, direction: PaneNavigation, among all: [Leaf], frame: (Leaf) -> CGRect) -> Leaf? {
        let origin = frame(leaf)
        var best: (leaf: Leaf, distance: CGFloat, overlap: CGFloat)?
        for other in all where other !== leaf {
            let candidate = frame(other)
            let distance: CGFloat
            let overlap: CGFloat
            switch direction {
            case .right:
                distance = candidate.minX - origin.maxX
                overlap = min(origin.maxY, candidate.maxY) - max(origin.minY, candidate.minY)
            case .left:
                distance = origin.minX - candidate.maxX
                overlap = min(origin.maxY, candidate.maxY) - max(origin.minY, candidate.minY)
            case .up:
                distance = candidate.minY - origin.maxY
                overlap = min(origin.maxX, candidate.maxX) - max(origin.minX, candidate.minX)
            case .down:
                distance = origin.minY - candidate.maxY
                overlap = min(origin.maxX, candidate.maxX) - max(origin.minX, candidate.minX)
            default:
                return nil
            }
            guard distance >= -1, overlap > 0 else { continue }
            if let current = best, (distance, -overlap) >= (current.distance, -current.overlap) { continue }
            best = (other, distance, overlap)
        }
        return best?.leaf
    }
}
