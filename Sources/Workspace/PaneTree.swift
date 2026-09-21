import AppKit
import GhosttyKit

enum SplitAxis: String, Codable {
    /// Panes side by side.
    case horizontal
    /// Panes stacked.
    case vertical
}

/// A node in a tab's split layout: either one terminal, or two child panes
/// divided along an axis.
final class Pane {
    var surface: TerminalSurfaceView?
    var axis: SplitAxis?
    var first: Pane?
    var second: Pane?
    var ratio: CGFloat = 0.5
    weak var parent: Pane?

    init(surface: TerminalSurfaceView) {
        self.surface = surface
    }

    init(axis: SplitAxis, first: Pane, second: Pane, ratio: CGFloat) {
        self.axis = axis
        self.first = first
        self.second = second
        self.ratio = ratio
        first.parent = self
        second.parent = self
    }

    var surfaces: [TerminalSurfaceView] {
        if let surface { return [surface] }
        return (first?.surfaces ?? []) + (second?.surfaces ?? [])
    }

    func pane(for surface: TerminalSurfaceView) -> Pane? {
        if self.surface === surface { return self }
        return first?.pane(for: surface) ?? second?.pane(for: surface)
    }
}

/// The split layout of one tab. `version` changes on every structural edit so
/// views know when to rebuild.
final class PaneTree {
    let root: Pane
    private(set) var version = 0

    init(surface: TerminalSurfaceView) {
        root = Pane(surface: surface)
    }

    init(root: Pane) {
        self.root = root
    }

    var surfaces: [TerminalSurfaceView] {
        root.surfaces
    }

    func contains(_ surface: TerminalSurfaceView) -> Bool {
        root.pane(for: surface) != nil
    }

    func pane(for surface: TerminalSurfaceView) -> Pane? {
        root.pane(for: surface)
    }

    func split(_ surface: TerminalSurfaceView, direction: ghostty_action_split_direction_e, with newSurface: TerminalSurfaceView) {
        guard let pane = root.pane(for: surface) else { return }
        let existing = Pane(surface: surface)
        let added = Pane(surface: newSurface)
        pane.surface = nil
        pane.ratio = 0.5
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT:
            (pane.axis, pane.first, pane.second) = (.horizontal, existing, added)
        case GHOSTTY_SPLIT_DIRECTION_LEFT:
            (pane.axis, pane.first, pane.second) = (.horizontal, added, existing)
        case GHOSTTY_SPLIT_DIRECTION_DOWN:
            (pane.axis, pane.first, pane.second) = (.vertical, existing, added)
        default:
            (pane.axis, pane.first, pane.second) = (.vertical, added, existing)
        }
        existing.parent = pane
        added.parent = pane
        version += 1
    }

    /// Removes a terminal from the layout. Returns the terminal that should take
    /// focus next, or nil when the removed one was the last.
    func remove(_ surface: TerminalSurfaceView) -> TerminalSurfaceView? {
        guard let pane = root.pane(for: surface), let parent = pane.parent,
              let first = parent.first, let second = parent.second else { return nil }
        let sibling = pane === first ? second : first
        parent.surface = sibling.surface
        parent.axis = sibling.axis
        parent.first = sibling.first
        parent.second = sibling.second
        parent.ratio = sibling.ratio
        parent.first?.parent = parent
        parent.second?.parent = parent
        version += 1
        return parent.surfaces.first
    }

    func equalize() {
        func visit(_ pane: Pane) {
            pane.ratio = 0.5
            pane.first.map(visit)
            pane.second.map(visit)
        }
        visit(root)
        version += 1
    }

    func neighbor(of surface: TerminalSurfaceView, direction: ghostty_action_goto_split_e) -> TerminalSurfaceView? {
        let all = surfaces
        guard all.count > 1, let index = all.firstIndex(where: { $0 === surface }) else { return nil }
        switch direction {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: return all[(index + all.count - 1) % all.count]
        case GHOSTTY_GOTO_SPLIT_NEXT: return all[(index + 1) % all.count]
        default: return spatialNeighbor(of: surface, direction: direction, among: all)
        }
    }

    /// Picks the closest pane in the given direction that overlaps the current
    /// one on the other axis, using on-screen frames.
    private func spatialNeighbor(of surface: TerminalSurfaceView, direction: ghostty_action_goto_split_e, among all: [TerminalSurfaceView]) -> TerminalSurfaceView? {
        let frame = surface.convert(surface.bounds, to: nil)
        var best: (surface: TerminalSurfaceView, distance: CGFloat, overlap: CGFloat)?
        for other in all where other !== surface {
            let candidate = other.convert(other.bounds, to: nil)
            let distance: CGFloat
            let overlap: CGFloat
            switch direction {
            case GHOSTTY_GOTO_SPLIT_RIGHT:
                distance = candidate.minX - frame.maxX
                overlap = min(frame.maxY, candidate.maxY) - max(frame.minY, candidate.minY)
            case GHOSTTY_GOTO_SPLIT_LEFT:
                distance = frame.minX - candidate.maxX
                overlap = min(frame.maxY, candidate.maxY) - max(frame.minY, candidate.minY)
            case GHOSTTY_GOTO_SPLIT_UP:
                distance = candidate.minY - frame.maxY
                overlap = min(frame.maxX, candidate.maxX) - max(frame.minX, candidate.minX)
            case GHOSTTY_GOTO_SPLIT_DOWN:
                distance = frame.minY - candidate.maxY
                overlap = min(frame.maxX, candidate.maxX) - max(frame.minX, candidate.minX)
            default:
                return nil
            }
            guard distance >= -1, overlap > 0 else { continue }
            if let current = best, (distance, -overlap) >= (current.distance, -current.overlap) { continue }
            best = (other, distance, overlap)
        }
        return best?.surface
    }
}
