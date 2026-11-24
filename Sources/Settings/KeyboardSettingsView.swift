import AppKit
import SwiftUI

/// The palettes and Rename Workspace, with the key in effect, which a click
/// lets any key and modifiers replace. Changes are `keybind` lines at the end
/// of the config file.
struct KeyboardSettingsView: View {
    let store: SettingsStore
    /// What happened to the last key picked, until the next change.
    @State private var note: String?

    var body: some View {
        let bindings = KeyBindings(document: store.document, includes: store.includes)
        Form {
            Section {
                ForEach(KeyboardShortcuts.changeable) { command in
                    row(command, bindings: bindings)
                }
            } footer: {
                Text(note ?? "Click a shortcut and press the new keys. Esc stops without a change.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ command: KeyboardShortcuts.Command, bindings: KeyBindings) -> some View {
        let key = bindings.shortcut(for: command.action)
        return HStack {
            Text(command.title)
            Spacer()
            HStack(spacing: 4) {
                ShortcutRecorder(shortcut: key) { set($0, for: command, bindings: bindings) }
                    .frame(width: 110, height: 22)
                Button {
                    set(nil, for: command, bindings: bindings)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .help("Remove the shortcut")
                .disabled(key == nil)
                Button {
                    note = nil
                    store.update { $0.resetShortcut(for: command) }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                }
                .help("Use the default shortcut")
                .disabled(!store.document.hasShortcutLines(for: command))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
    }

    /// A key another of these commands had moves to this one. One a menu
    /// item has is refused, since the menu would still run that item.
    private func set(_ key: KeyTrigger?, for command: KeyboardShortcuts.Command, bindings: KeyBindings) {
        note = nil
        if let key, let reason = KeyboardShortcuts.unavailable(key) {
            note = reason
            return
        }
        if let key, let other = bindings.command(using: key), other != command {
            note = "\(key.symbols.joined()) moved from \(other.title) to \(command.title)."
        } else if let key, bindings.command(using: key) == nil, let item = Self.menuItem(using: key) {
            note = "\(key.symbols.joined()) is already the shortcut for \(item)."
            return
        }
        let includes = store.includes
        store.update { $0.setShortcut(key, for: command, includes: includes) }
    }

    private static func menuItem(using key: KeyTrigger) -> String? {
        guard let equivalent = key.menuKeyEquivalent, let menu = NSApp.mainMenu else { return nil }
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        func find(in menu: NSMenu) -> String? {
            for item in menu.items {
                if item.keyEquivalent == equivalent.key, item.keyEquivalentModifierMask.intersection(modifiers) == equivalent.modifiers {
                    return item.title
                }
                if let found = item.submenu.flatMap(find(in:)) { return found }
            }
            return nil
        }
        return find(in: menu)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: KeyTrigger?
    var onRecord: (KeyTrigger) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        ShortcutRecorderView()
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.onRecord = onRecord
    }
}

/// Shows a shortcut. Clicked, it takes the next key pressed, with the
/// modifiers held, as the new one; Esc on its own, a second click or another
/// control taking the keyboard stops without a change.
final class ShortcutRecorderView: NSView {
    var shortcut: KeyTrigger? {
        didSet { refresh() }
    }
    var onRecord: (KeyTrigger) -> Void = { _ in }

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet { refresh() }
    }
    private var held: KeyTrigger.Modifiers = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(isRecording ? nil : self)
    }

    override func becomeFirstResponder() -> Bool {
        held = []
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    /// Keys with ⌘ arrive here before the menus, which would otherwise run
    /// their command instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        record(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        held = KeyTrigger.Modifiers(event.modifierFlags)
        refresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func record(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.keyCode == 53, modifiers.isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        guard let trigger = KeyTrigger(event: event) else { return NSSound.beep() }
        window?.makeFirstResponder(nil)
        onRecord(trigger)
    }

    private func refresh() {
        if isRecording {
            label.stringValue = held.isEmpty ? "Type shortcut" : KeyTrigger(held, "").symbols.dropLast().joined()
        } else {
            label.stringValue = shortcut?.symbols.joined() ?? "None"
        }
        label.textColor = isRecording || shortcut == nil ? .secondaryLabelColor : .labelColor
        setAccessibilityLabel(label.stringValue)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }
}
