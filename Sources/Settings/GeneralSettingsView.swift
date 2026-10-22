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
                TextField("Shell", text: $command, prompt: Text("Your login shell"))
                    .focused($editingCommand)
                    .onSubmit(saveCommand)
                    .onChange(of: editingCommand) { if !editingCommand { saveCommand() } }
            } footer: {
                Text("What new terminals run. Leave it empty to use your login shell.")
                    .settingsFooter()
            }

            Section("Terminals") {
                Toggle("Ask before closing a terminal that is running something", isOn: Binding(
                    get: { store.value(Option.confirmClose) != "false" },
                    set: { store.set(Option.confirmClose, $0 ? "true" : "false") }))
                Toggle("Copy text when you select it", isOn: Binding(
                    get: { store.value(Option.copyOnSelect) == "clipboard" },
                    set: { store.set(Option.copyOnSelect, $0 ? "clipboard" : "true") }))
                Toggle("Hide the pointer while typing", isOn: store.binding(Option.mouseHideWhileTyping))
            }

            Section {
                Toggle("Secure keyboard entry", isOn: $secureKeyboardEntry)
                Toggle("Turn on secure input at password prompts", isOn: store.binding(Option.autoSecureInput))
                Toggle("Show a lock while secure input is on", isOn: store.binding(Option.secureInputIndication))
            } header: {
                Text("Secure Input")
            } footer: {
                Text("Secure input stops other apps from reading what you type in Flow.")
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
                Text("Checking for updates is the only time Flow goes online.")
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
