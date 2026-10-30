import AppKit
import Sparkle
import SwiftUI

/// The Settings window: a pane per toolbar button, like other Mac apps.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let size = CGSize(width: 560, height: 520)
    private let store: SettingsStore

    init(store: SettingsStore, updater: SPUUpdater, reload: @escaping () -> Void) {
        self.store = store
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.pane("General", symbol: "gearshape", store: store, GeneralSettingsView(store: store, updater: updater)))
        tabs.addTabViewItem(Self.pane("Appearance", symbol: "paintpalette", store: store, AppearanceSettingsView(store: store)))
        tabs.addTabViewItem(Self.pane("Notifications", symbol: "bell.badge", store: store, NotificationsSettingsView(store: store)))
        tabs.addTabViewItem(Self.pane("Advanced", symbol: "gearshape.2", store: store, AdvancedSettingsView(store: store, reload: reload)))
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

    /// Every pane is the same size, so the window doesn't jump between tabs
    /// and a long pane scrolls instead of growing past the screen.
    private static func pane(_ title: String, symbol: String, store: SettingsStore, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: VStack(spacing: 0) {
            SaveErrorBanner(store: store)
            view
        }
            .frame(width: size.width, height: size.height))
        controller.sizingOptions = .preferredContentSize
        controller.title = title
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

/// Shown on every pane while the config file cannot be read or written, since
/// the controls would otherwise seem to work.
private struct SaveErrorBanner: View {
    let store: SettingsStore

    var body: some View {
        if let error = store.fileError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.yellow.opacity(0.15))
        }
    }
}
