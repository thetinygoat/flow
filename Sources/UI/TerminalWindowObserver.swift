import AppKit

/// Detached terminals do not need window notifications, and another window's
/// activity must not wake every terminal in the app.
final class TerminalWindowObserver {
    private let center: NotificationCenter
    private let screenChanged: () -> Void
    private let focusChanged: () -> Void
    private let occlusionChanged: () -> Void
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default, screenChanged: @escaping () -> Void,
         focusChanged: @escaping () -> Void, occlusionChanged: @escaping () -> Void) {
        self.center = center
        self.screenChanged = screenChanged
        self.focusChanged = focusChanged
        self.occlusionChanged = occlusionChanged
    }

    func observe(_ window: NSWindow?) {
        observers.forEach(center.removeObserver)
        observers.removeAll()
        self.window = window
        guard let window else { return }
        let handlers: [(Notification.Name, () -> Void)] = [
            (NSWindow.didChangeScreenNotification, screenChanged),
            (NSWindow.didBecomeKeyNotification, focusChanged),
            (NSWindow.didResignKeyNotification, focusChanged),
            (NSWindow.didChangeOcclusionStateNotification, occlusionChanged),
        ]
        observers = handlers.map { name, handler in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                guard let self, let window = self.window, notification.object as? NSWindow === window else { return }
                handler()
            }
        }
    }

    deinit {
        observers.forEach(center.removeObserver)
    }
}
