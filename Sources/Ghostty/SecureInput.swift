import AppKit
import Carbon

/// Secure event input keeps other apps from reading keystrokes through event
/// taps. The system state is global and reference counted, so every enable
/// must be balanced, and it has to be released while Flow is in the background
/// or it would block input monitoring for every other app.
///
/// Adapted from Ghostty's SecureInput.swift.
final class SecureInput {
    static let shared = SecureInput()
    static let didChangeNotification = Notification.Name("FlowSecureInputDidChange")

    /// Set by the Secure Keyboard Entry menu item.
    var global = false {
        didSet { apply() }
    }

    private(set) var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Terminals at a password prompt, and whether each one has focus.
    private var scoped: [ObjectIdentifier: Bool] = [:]

    private var desired: Bool {
        global || scoped.values.contains(true)
    }

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        }
    }

    func setScoped(_ object: ObjectIdentifier, focused: Bool) {
        scoped[object] = focused
        apply()
    }

    func removeScoped(_ object: ObjectIdentifier) {
        scoped[object] = nil
        apply()
    }

    private func apply() {
        let wanted = desired && NSApp.isActive
        guard wanted != enabled else { return }
        let status = wanted ? EnableSecureEventInput() : DisableSecureEventInput()
        if status == noErr {
            enabled = wanted
        } else {
            logger.warning("secure input change to \(wanted) failed: \(status)")
        }
    }
}
