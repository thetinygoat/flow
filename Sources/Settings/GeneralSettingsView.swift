import Sparkle
import SwiftUI

struct GeneralSettingsView: View {
    let store: SettingsStore
    let updater: SPUUpdater
    @AppStorage(Preferences.secureKeyboardEntry) private var secureKeyboardEntry = false
    @State private var command = ""
    @State private var choosesCustomCommand = false
    @State private var checksForUpdates = false
    @State private var canCheckForUpdates = false
    @State private var lastUpdateCheck: Date?
    /// What copy on select goes back to when turned off, since the file may
    /// have said `false` or nothing.
    @State private var copyOnSelectOff = Option.copyOnSelect.defaultValue
    @FocusState private var editingCommand: Bool

    var body: some View {
        Form {
            Section {
                Picker("Shell", selection: shell) {
                    Text("Login shell (\(Shells.login.lastPathComponent))").tag(ShellChoice.login)
                    Divider()
                    ForEach(Shells.installed, id: \.self) { path in
                        Text(path).tag(ShellChoice.shell(path))
                    }
                    Divider()
                    Text("Custom…").tag(ShellChoice.custom)
                }
                if shell.wrappedValue == .custom {
                    TextField("Command", text: $command, prompt: Text("/usr/bin/env nu"))
                        .textFieldStyle(.roundedBorder)
                        .focused($editingCommand)
                        .onSubmit(saveCommand)
                        .onChange(of: editingCommand) { if !editingCommand { saveCommand() } }
                }
            }

            Section("Terminals") {
                Picker("Confirm closing terminals", selection: store.binding(Option.confirmClose)) {
                    Text("Never").tag("false")
                    Text("With a running process").tag("true")
                    Text("Always").tag("always")
                }
                Toggle("Copy on select", isOn: Binding(
                    get: { store.value(Option.copyOnSelect) == "clipboard" },
                    set: { on in
                        if on { copyOnSelectOff = store.value(Option.copyOnSelect) }
                        store.set(Option.copyOnSelect, on ? "clipboard" : copyOnSelectOff)
                    }))
                Toggle("Hide mouse pointer while typing", isOn: store.binding(Option.mouseHideWhileTyping))
            }

            Section {
                Picker("Secure keyboard entry", selection: secureInput) {
                    Text("Off").tag(SecureInputChoice.off)
                    Text("At password prompts").tag(SecureInputChoice.passwordPrompts)
                    Text("Always").tag(SecureInputChoice.always)
                }
            } footer: {
                Text("Blocks other apps from reading keystrokes typed into Flow.")
                    .settingsFooter()
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { checksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }))
                LabeledContent {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!canCheckForUpdates)
                } label: {
                    Text("Last checked")
                    Text(lastUpdateCheck?.formatted(.relative(presentation: .named)) ?? "Never")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            command = store.value(Option.command)
        }
        .onChange(of: store.value(Option.command)) { command = store.value(Option.command) }
        .onReceive(updater.publisher(for: \.lastUpdateCheckDate)) { lastUpdateCheck = $0 }
        .onReceive(updater.publisher(for: \.automaticallyChecksForUpdates)) { checksForUpdates = $0 }
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheckForUpdates = $0 }
    }

    private func saveCommand() {
        store.set(Option.command, command.trimmingCharacters(in: .whitespaces))
    }

    private var secureInput: Binding<SecureInputChoice> {
        Binding(
            get: {
                if secureKeyboardEntry { return .always }
                return store.value(Option.autoSecureInput) ? .passwordPrompts : .off
            },
            set: { choice in
                secureKeyboardEntry = choice == .always
                store.set(Option.autoSecureInput, choice != .off)
            })
    }

    /// A command that is one of the installed shells shows as that shell;
    /// anything else is a custom command.
    private var shell: Binding<ShellChoice> {
        Binding(
            get: {
                let command = store.value(Option.command)
                if choosesCustomCommand || (!command.isEmpty && !Shells.installed.contains(command)) { return .custom }
                return command.isEmpty ? .login : .shell(command)
            },
            set: { choice in
                choosesCustomCommand = choice == .custom
                switch choice {
                case .login: store.set(Option.command, "")
                case .shell(let path): store.set(Option.command, path)
                case .custom: editingCommand = true
                }
            })
    }
}

/// Always is the app-wide secure keyboard entry; password prompts is
/// Ghostty's automatic secure input.
private enum SecureInputChoice: Hashable {
    case off, passwordPrompts, always
}

private enum ShellChoice: Hashable {
    case login, shell(String), custom
}

enum Shells {
    /// The shells listed in /etc/shells that exist.
    static let installed: [String] = {
        let list = (try? String(contentsOfFile: "/etc/shells", encoding: .utf8)) ?? ""
        return list.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var login: URL {
        let path = getpwuid(getuid())?.pointee.pw_shell.map { String(cString: $0) } ?? "/bin/zsh"
        return URL(fileURLWithPath: path)
    }
}

extension Text {
    func settingsFooter() -> some View {
        font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
