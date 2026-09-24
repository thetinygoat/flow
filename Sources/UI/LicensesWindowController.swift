import AppKit

/// Flow's own license followed by the notices for the software it includes,
/// read from the copies bundled with the app.
final class LicensesWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Licenses"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 300)
        super.init(window: window)

        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textStorage?.setAttributedString(Self.text)
        window.contentView = scrollView
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Markdown headings become titles and code fences are dropped; the
    /// license texts themselves stay monospaced as written.
    private static var text: NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let heading: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let files = ["LICENSE", "THIRD_PARTY_LICENSES.md"].compactMap { name in
            Bundle.main.url(forResource: name, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        let markdown = "## Flow\n\n" + files.joined(separator: "\n\n")
        let result = NSMutableAttributedString()
        for line in markdown.components(separatedBy: "\n") where !line.hasPrefix("```") {
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                result.append(NSAttributedString(string: title + "\n", attributes: heading))
            } else {
                result.append(NSAttributedString(string: line + "\n", attributes: body))
            }
        }
        return result
    }
}
