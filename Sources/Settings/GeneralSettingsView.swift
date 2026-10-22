import Sparkle
import SwiftUI

struct GeneralSettingsView: View {
    let store: SettingsStore
    let updater: SPUUpdater
    @AppStorage(Preferences.secureKeyboardEntry) private var secureKeyboardEntry = false
    @State private var command = ""
    @State private var checksForUpdates = false
    @FocusState private var editingCommand: Bool

    var body: some View {
        Form {
            Section {
                TextField("Shell", text: $command, prompt: Text("Login shell"))
                    .focused($editingCommand)
                    .onSubmit(saveCommand)
                    .onChange(of: editingCommand) { if !editingCommand { saveCommand() } }
            } footer: {
                Text("Command run in new terminals. Empty uses the login shell.")
                    .settingsFooter()
            }

            Section("Terminals") {
                Toggle("Confirm closing terminals with running processes", isOn: Binding(
                    get: { store.value(Option.confirmClose) != "false" },
                    set: { store.set(Option.confirmClose, $0 ? "true" : "false") }))
                Toggle("Copy on select", isOn: Binding(
                    get: { store.value(Option.copyOnSelect) == "clipboard" },
                    set: { store.set(Option.copyOnSelect, $0 ? "clipboard" : "true") }))
                Toggle("Hide mouse pointer while typing", isOn: store.binding(Option.mouseHideWhileTyping))
            }

            Section {
                Toggle("Secure keyboard entry", isOn: $secureKeyboardEntry)
                Toggle("Enable at password prompts", isOn: store.binding(Option.autoSecureInput))
                Toggle("Show lock icon when enabled", isOn: store.binding(Option.secureInputIndication))
            } header: {
                Text("Secure Input")
            } footer: {
                Text("Prevents other apps from reading keyboard input to Flow.")
                    .settingsFooter()
            }

            Section {
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { updater.automaticallyChecksForUpdates = checksForUpdates }
                LabeledContent("") {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Update checks are Flow's only network access.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            command = store.value(Option.command)
            checksForUpdates = updater.automaticallyChecksForUpdates
        }
        .onChange(of: store.value(Option.command)) { command = store.value(Option.command) }
    }

    private func saveCommand() {
        store.set(Option.command, command.trimmingCharacters(in: .whitespaces))
    }
}

extension Text {
    func settingsFooter() -> some View {
        font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
