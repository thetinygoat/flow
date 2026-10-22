import AppKit

enum TempSnapshot {
    static func run(_ window: NSWindow, into directory: String) {
        guard let tabs = window.contentViewController as? NSTabViewController else { return }
        func shoot(_ index: Int) {
            guard index < tabs.tabViewItems.count else { return }
            tabs.selectedTabViewItemIndex = index
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let view = window.contentView!.superview!
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(directory)/pane\(index).png"))
                }
                shoot(index + 1)
            }
        }
        shoot(0)
    }
}
