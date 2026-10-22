import AppKit
import Sparkle
import SwiftUI

/// The Settings window: a pane per toolbar button, like other Mac apps.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let width: CGFloat = 560
    private let store: SettingsStore

    init(store: SettingsStore, updater: SPUUpdater, reload: @escaping () -> Void) {
        self.store = store
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.pane("General", symbol: "gearshape", GeneralSettingsView(store: store, updater: updater)))
        tabs.addTabViewItem(Self.pane("Appearance", symbol: "paintpalette", AppearanceSettingsView(store: store)))
        tabs.addTabViewItem(Self.pane("Notifications", symbol: "bell.badge", NotificationsSettingsView(store: store)))
        tabs.addTabViewItem(Self.pane("Advanced", symbol: "gearshape.2", AdvancedSettingsView(store: store, reload: reload)))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func pane(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(width: width, height: 560))
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        store.saveNow()
    }
}
