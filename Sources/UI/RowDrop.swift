import Foundation

/// Dropping onto a row puts the dragged row above it from its top half and
/// below it from its bottom half. Rows are laid out top down, as in a table.
func insertionIndex(forDropOn row: Int, pointerY: CGFloat, rowRect: NSRect) -> Int {
    pointerY > rowRect.midY ? row + 1 : row
}
