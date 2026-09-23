import AppKit

/// Replaces the standard About panel so it can show the commit a build came
/// from and link out to the project.
final class AboutWindowController: NSWindowController {
    private static let repository = URL(string: "https://github.com/thetinygoat/flow")!
    private static let ghostty = URL(string: "https://ghostty.org")!

    private let info = Bundle.main.infoDictionary ?? [:]

    init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let content = makeContent()
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 104),
            icon.heightAnchor.constraint(equalToConstant: 104),
        ])

        let name = NSTextField(labelWithString: "Flow")
        name.font = .systemFont(ofSize: 26, weight: .bold)

        let summary = NSTextField(wrappingLabelWithString: "A fast, native terminal built on Ghostty, for everyday work.")
        summary.alignment = .center
        summary.textColor = .secondaryLabelColor
        summary.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let links = NSStackView(views: [
            button("GitHub", action: #selector(openRepository)),
            button("Ghostty", action: #selector(openGhostty)),
        ])
        links.spacing = 10

        let details = details()
        let stack = NSStackView(views: [icon, name, summary, details, links])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(8, after: name)
        stack.setCustomSpacing(26, after: summary)
        stack.setCustomSpacing(26, after: details)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 380),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -32),
        ])
        return container
    }

    private func details() -> NSGridView {
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        let build = info["CFBundleVersion"] as? String ?? "–"
        let rows: [[NSView]] = [
            [key("Version"), value(version)],
            [key("Build"), value(build)],
            [key("Commit"), commitLink()],
        ]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 12
        // Equal columns put the gap between labels and values on the centre line.
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 120
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 1).width = 120
        return grid
    }

    private func key(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func value(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        return label
    }

    private func commitLink() -> NSTextField {
        guard let commit = info["FlowCommit"] as? String else { return value("–") }
        let url = Self.repository.appendingPathComponent("commit").appendingPathComponent(commit)
        let link = value(commit)
        link.attributedStringValue = NSAttributedString(string: commit, attributes: [
            .link: url,
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ])
        return link
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .push
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        return button
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(Self.repository)
    }

    @objc private func openGhostty() {
        NSWorkspace.shared.open(Self.ghostty)
    }
}
