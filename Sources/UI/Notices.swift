import AppKit

/// A message shown once, at launch, to people who used Flow before a change
/// they would otherwise wonder about.
struct Notice: Equatable {
    /// Recorded once shown, so it must never change or be reused.
    let id: String
    let title: String
    let message: String
    /// Shows the app's icon in the notice, for a notice about the icon itself.
    var showsAppIcon = false

    /// Every notice, oldest first. Add one here when a release changes
    /// something people already know.
    static let all = [
        Notice(id: "new-app-icon", title: "Flow Has a Fresh New Look!",
               message: "A brand-new icon arrives with this release. Same Flow, now with a little more personality.",
               showsAppIcon: true),
    ]
}

enum Notices {
    static let seenKey = "SeenNotices"

    /// The notices not seen yet. All of them count as seen from now on, and a
    /// new install gets none: it never knew Flow before the changes.
    static func due(_ notices: [Notice] = Notice.all, isNewInstall: Bool, defaults: UserDefaults = .standard) -> [Notice] {
        let seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let unseen = notices.filter { !seen.contains($0.id) }
        defaults.set(seen.union(notices.map(\.id)).sorted(), forKey: seenKey)
        return isNewInstall ? [] : unseen
    }

    /// Shows the notices one after another, starting once the restored
    /// windows are on screen.
    static func show(_ notices: [Notice], in window: NSWindow?) {
        guard let notice = notices.first else { return }
        let alert = NSAlert()
        alert.messageText = notice.title
        alert.informativeText = notice.message
        alert.addButton(withTitle: "OK")
        if notice.showsAppIcon {
            alert.icon = NSApp.applicationIconImage
        }
        let showRest = { (_: NSApplication.ModalResponse) in show(Array(notices.dropFirst()), in: window) }
        DispatchQueue.main.async {
            if let window {
                alert.beginSheetModal(for: window, completionHandler: showRest)
            } else {
                showRest(alert.runModal())
            }
        }
    }
}
