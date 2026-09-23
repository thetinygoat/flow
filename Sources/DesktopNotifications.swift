import AppKit
import UserNotifications

/// Posts the notifications programs send with OSC 9 and OSC 777. Clicking one
/// brings the terminal that sent it to the front, and focusing that terminal
/// clears whatever it had posted.
final class DesktopNotifications: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the id of the terminal whose notification was clicked.
    var onOpen: ((UUID) -> Void)?
    /// True when the terminal is already in front of the user, in which case
    /// its notifications are dropped.
    var isInView: ((UUID) -> Bool)?

    private let center = UNUserNotificationCenter.current()
    private var delivered: [UUID: Set<String>] = [:]

    override init() {
        super.init()
        center.delegate = self
    }

    func post(title: String, body: String, subtitle: String, from terminal: UUID) {
        guard isInView?(terminal) != true else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error { logger.warning("notification permission failed: \(error)") }
            guard granted, let self else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
            content.sound = .default
            content.userInfo = ["terminal": terminal.uuidString]
            let id = UUID().uuidString
            self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                if let error {
                    logger.warning("notification failed: \(error)")
                    return
                }
                DispatchQueue.main.async { self.delivered[terminal, default: []].insert(id) }
            }
        }
    }

    func clear(for terminal: UUID) {
        guard let ids = delivered.removeValue(forKey: terminal) else { return }
        center.removeDeliveredNotifications(withIdentifiers: Array(ids))
    }

    private static func terminal(of notification: UNNotification) -> UUID? {
        (notification.request.content.userInfo["terminal"] as? String).flatMap(UUID.init(uuidString:))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Without this, macOS hides notifications while Flow is the active app,
    /// even when they come from a workspace that is not on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
               let terminal = Self.terminal(of: response.notification) {
                self.onOpen?(terminal)
            }
            completionHandler()
        }
    }
}
