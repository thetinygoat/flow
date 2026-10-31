import AppKit

/// Opens a link from terminal output as `UntrustedLink` decides: directly,
/// after asking, or not at all. Adapted from Ghostty's UntrustedURLAlert.swift.
enum UntrustedLinkAlert {
    static func open(_ link: UntrustedLink, in window: NSWindow?) {
        switch link.decision {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .confirm(let url):
            let app = NSWorkspace.shared.urlForApplication(toOpen: url)
                .map { "\u{201C}\($0.deletingPathExtension().lastPathComponent)\u{201D}" } ?? "the default app"
            let alert = makeAlert("Open Link from Terminal Output?", "The link opens in \(app).", target: link.displayString)
            // Cancel comes first, so Return doesn't open the link.
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Open Link")
            present(alert, in: window) { response in
                if response == .alertSecondButtonReturn { NSWorkspace.shared.open(url) }
            }
        case .block(let refusal):
            let alert = makeAlert("Link Blocked", refusal.message, target: link.displayString)
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Copy Link")
            present(alert, in: window) { response in
                guard response == .alertSecondButtonReturn else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.displayString, forType: .string)
            }
        }
    }

    private static func makeAlert(_ title: String, _ message: String, target: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 96))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = target
        textView.autoresizingMask = .width
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        return alert
    }

    /// Shown on the next turn of the run loop, because the request arrives
    /// while libghostty holds the terminal's lock.
    private static func present(_ alert: NSAlert, in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        DispatchQueue.main.async {
            if let window {
                alert.beginSheetModal(for: window, completionHandler: completion)
            } else {
                completion(alert.runModal())
            }
        }
    }
}
