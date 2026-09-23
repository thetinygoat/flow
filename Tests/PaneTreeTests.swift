import XCTest

final class PaneTreeTests: XCTestCase {
    func testSplitRightPutsNewLeafSecond() {
        let a = FakeLeaf("a"), b = FakeLeaf("b")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)

        XCTAssertEqual(tree.root.axis, .horizontal)
        XCTAssertTrue(tree.root.first?.leaf === a)
        XCTAssertTrue(tree.root.second?.leaf === b)
        XCTAssertTrue(tree.root.first?.parent === tree.root)
        XCTAssertEqual(tree.leaves.map(\.title), ["a", "b"])
    }

    func testSplitLeftAndUpPutNewLeafFirst() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .left, with: b)
        XCTAssertEqual(tree.root.axis, .horizontal)
        XCTAssertEqual(tree.leaves.map(\.title), ["b", "a"])

        tree.split(a, direction: .up, with: c)
        let aNode = tree.node(for: a)
        XCTAssertEqual(aNode?.parent?.axis, .vertical)
        XCTAssertEqual(tree.leaves.map(\.title), ["b", "c", "a"])
    }

    func testSplitBumpsVersion() {
        let a = FakeLeaf("a")
        let tree = TestTree(leaf: a)
        let before = tree.version
        tree.split(a, direction: .down, with: FakeLeaf("b"))
        XCTAssertEqual(tree.version, before + 1)
    }

    func testRemoveCollapsesSiblingIntoParent() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.split(b, direction: .down, with: c)

        let next = tree.remove(b)
        XCTAssertTrue(next === c)
        XCTAssertEqual(tree.leaves.map(\.title), ["a", "c"])
        XCTAssertTrue(tree.root.second?.leaf === c)
        XCTAssertTrue(tree.root.second?.parent === tree.root)
    }

    func testRemoveNestedSplitReparentsChildren() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.split(b, direction: .down, with: c)

        _ = tree.remove(a)
        XCTAssertEqual(tree.root.axis, .vertical)
        XCTAssertTrue(tree.root.first?.leaf === b)
        XCTAssertTrue(tree.root.second?.leaf === c)
        XCTAssertTrue(tree.root.first?.parent === tree.root)
        XCTAssertTrue(tree.root.second?.parent === tree.root)
    }

    func testRemoveLastLeafReturnsNil() {
        let a = FakeLeaf("a")
        let tree = TestTree(leaf: a)
        XCTAssertNil(tree.remove(a))
        XCTAssertTrue(tree.contains(a))
    }

    func testEqualizeResetsRatios() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.split(b, direction: .down, with: c)
        tree.root.ratio = 0.2
        tree.root.second?.ratio = 0.9

        tree.equalize()
        XCTAssertEqual(tree.root.ratio, 0.5)
        XCTAssertEqual(tree.root.second?.ratio, 0.5)
    }

    func testPreviousAndNextWrapAround() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.split(b, direction: .right, with: c)
        let frame: (FakeLeaf) -> CGRect = { $0.frame }

        XCTAssertTrue(tree.neighbor(of: c, direction: .next, frame: frame) === a)
        XCTAssertTrue(tree.neighbor(of: a, direction: .previous, frame: frame) === c)
    }

    func testSpatialNeighborPrefersOverlappingClosestPane() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.split(b, direction: .down, with: c)
        a.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        b.frame = CGRect(x: 100, y: 50, width: 100, height: 50)
        c.frame = CGRect(x: 100, y: 0, width: 100, height: 50)
        let frame: (FakeLeaf) -> CGRect = { $0.frame }

        XCTAssertTrue(tree.neighbor(of: b, direction: .left, frame: frame) === a)
        XCTAssertTrue(tree.neighbor(of: b, direction: .down, frame: frame) === c)
        XCTAssertTrue(tree.neighbor(of: c, direction: .up, frame: frame) === b)
        XCTAssertNil(tree.neighbor(of: a, direction: .left, frame: frame))
    }

    func testSingleLeafHasNoNeighbors() {
        let a = FakeLeaf("a")
        let tree = TestTree(leaf: a)
        XCTAssertNil(tree.neighbor(of: a, direction: .next, frame: { $0.frame }))
    }

    func testToggleZoomNeedsSplits() {
        let a = FakeLeaf("a")
        let tree = TestTree(leaf: a)
        tree.toggleZoom(a)
        XCTAssertNil(tree.zoomed)
    }

    func testToggleZoomZoomsAndUnzooms() {
        let a = FakeLeaf("a"), b = FakeLeaf("b")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        let before = tree.version

        tree.toggleZoom(b)
        XCTAssertTrue(tree.zoomed === b)
        XCTAssertEqual(tree.version, before + 1)

        tree.toggleZoom(a)
        XCTAssertTrue(tree.zoomed === a, "zooming another pane moves the zoom")

        tree.toggleZoom(a)
        XCTAssertNil(tree.zoomed)
    }

    func testToggleZoomIgnoresForeignLeaf() {
        let a = FakeLeaf("a"), b = FakeLeaf("b")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.toggleZoom(FakeLeaf("elsewhere"))
        XCTAssertNil(tree.zoomed)
    }

    func testLayoutChangesClearZoom() {
        let a = FakeLeaf("a"), b = FakeLeaf("b"), c = FakeLeaf("c")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)

        tree.toggleZoom(a)
        tree.split(b, direction: .down, with: c)
        XCTAssertNil(tree.zoomed, "splitting unzooms")

        tree.toggleZoom(a)
        _ = tree.remove(c)
        XCTAssertNil(tree.zoomed, "closing a pane unzooms")
    }

    func testUnzoom() {
        let a = FakeLeaf("a"), b = FakeLeaf("b")
        let tree = TestTree(leaf: a)
        tree.split(a, direction: .right, with: b)
        tree.toggleZoom(a)
        let before = tree.version
        tree.unzoom()
        XCTAssertNil(tree.zoomed)
        XCTAssertEqual(tree.version, before + 1)
        tree.unzoom()
        XCTAssertEqual(tree.version, before + 1, "unzooming twice changes nothing")
    }
}
