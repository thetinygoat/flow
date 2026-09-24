import AppKit
import SwiftUI

/// Asks before a paste that looks like it could run commands, or before a
/// program reads or writes the clipboard. Shown as a sheet on the terminal's
/// window, one at a time. Adapted from Ghostty's ClipboardConfirmationView.
enum ClipboardConfirmation {
    enum Request {
        case paste, read, write

        var title: String {
            switch self {
            case .paste: "Warning: Potentially Unsafe Paste"
            case .read, .write: "Authorize Clipboard Access"
            }
        }

        var message: String {
            switch self {
            case .paste: "Pasting this text to the terminal may be dangerous as it looks like some commands may be executed."
            case .read: "An application is attempting to read from the clipboard.\nThe current clipboard contents are shown below."
            case .write: "An application is attempting to write to the clipboard.\nThe content to write is shown below."
            }
        }

        var cancelTitle: String { self == .paste ? "Cancel" : "Deny" }
        var confirmTitle: String { self == .paste ? "Paste" : "Allow" }
    }

    /// Calls `completion` with the answer. A request made while the window
    /// already shows a sheet is refused, so a program that keeps asking only
    /// ever gets one prompt.
    static func ask(_ request: Request, contents: String, in window: NSWindow?, completion: @escaping (Bool) -> Void) {
        guard let window, window.attachedSheet == nil else { return completion(false) }
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        sheet.title = request.title
        sheet.contentView = NSHostingView(rootView: ConfirmationView(request: request, contents: contents) { confirmed in
            window.endSheet(sheet)
            completion(confirmed)
        })
        window.beginSheet(sheet)
    }
}

private struct ConfirmationView: View {
    let request: ClipboardConfirmation.Request
    let contents: String
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 42))
                    .padding()
                Text(request.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            TextEditor(text: .constant(contents))
                .focusable(false)
                .font(.system(.body, design: .monospaced))

            HStack {
                Spacer()
                Button(request.cancelTitle) { onAnswer(false) }
                    .keyboardShortcut(.cancelAction)
                Button(request.confirmTitle) { onAnswer(true) }
                    .keyboardShortcut(.defaultAction)
                Spacer()
            }
            .padding(.bottom)
        }
    }
}
