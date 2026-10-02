import AppKit
import XCTest

@MainActor
final class TabBarTests: XCTestCase {
    func testStatusSelectionAndShortcutHintsKeepTheTabStripHeight() {
        let tabs = TabBarView()
        let content = NSView()
        let root = NSStackView(views: [tabs, content])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        tabs.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        content.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        content.setContentHuggingPriority(.defaultLow, for: .vertical)
        tabs.setContentHuggingPriority(.required, for: .vertical)
        root.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        let titles = ["Create command palette branch", "Suppress false approval alerts"]
        let states: [([AgentIndicator?], Int)] = [
            ([nil, nil], 1), ([nil, .working], 1), ([.working, .waiting], 0),
            ([.done, nil], 1), ([nil, nil], 0),
        ]
        for (indicators, selected) in states {
            tabs.reload(titles: titles, indicators: indicators, selectedIndex: selected)
            for hints in [false, true, false] {
                tabs.setShortcutHintsVisible(hints)
                root.layoutSubtreeIfNeeded()
                XCTAssertEqual(tabs.frame.height, TabBarView.height)
                let items = (tabs.subviews.first as! NSStackView).arrangedSubviews
                XCTAssertEqual(items.count, 2)
                for item in items { XCTAssertEqual(item.frame.height, TabBarView.height) }
                XCTAssertEqual(content.frame.height, root.bounds.height - TabBarView.height)
            }
        }
    }
}
