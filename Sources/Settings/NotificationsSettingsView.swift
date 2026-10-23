import AppKit
import SwiftUI

struct NotificationsSettingsView: View {
    let store: SettingsStore
    @AppStorage(Preferences.needsInputNotification) private var needsInputNotification = true
    @AppStorage(Preferences.needsInputSound) private var needsInputSound = ""
    @AppStorage(Preferences.finishedNotification) private var finishedNotification = true
    @AppStorage(Preferences.finishedSound) private var finishedSound = ""

    private var commandActions: Binding<CommandFinish.Actions> { store.binding(Option.notifyOnCommandFinishAction) }

    var body: some View {
        Form {
            Section("Agent needs input") {
                Toggle("Notification", isOn: $needsInputNotification)
                SoundPicker(selection: $needsInputSound)
            }

            Section {
                Toggle("Notification", isOn: $finishedNotification)
                SoundPicker(selection: $finishedSound)
            } header: {
                Text("Agent finished")
            } footer: {
                Text("Agent alerts are only for terminals that are not visible.")
                    .settingsFooter()
            }

            Section {
                Picker("Notify", selection: store.binding(Option.notifyOnCommandFinish)) {
                    Text("Never").tag(CommandFinish.When.never)
                    Text("When the terminal is not visible").tag(CommandFinish.When.unfocused)
                    Text("Always").tag(CommandFinish.When.always)
                }
                Group {
                    LabeledContent("Minimum duration") {
                        Stepper(value: Binding(
                            get: { Int(store.value(Option.notifyOnCommandFinishAfter).components.seconds) },
                            set: { store.set(Option.notifyOnCommandFinishAfter, .seconds($0)) }), in: 1...3600) {
                            Text(store.value(Option.notifyOnCommandFinishAfter).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                        }
                    }
                    Toggle("Notification", isOn: action(.notify))
                    Toggle("Bell", isOn: action(.bell))
                }
                .disabled(store.value(Option.notifyOnCommandFinish) == .never)
            } header: {
                Text("Command finished")
            }
        }
        .formStyle(.grouped)
    }

    private func action(_ action: CommandFinish.Actions) -> Binding<Bool> {
        Binding(get: { commandActions.wrappedValue.contains(action) },
                set: { on in
                    var actions = commandActions.wrappedValue
                    if on { actions.insert(action) } else { actions.remove(action) }
                    commandActions.wrappedValue = actions
                })
    }
}

/// The macOS alert sounds, played as they are picked.
private struct SoundPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Sound", selection: $selection) {
            Text("None").tag("")
            Divider()
            ForEach(Preferences.sounds, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .onChange(of: selection) {
            NSSound(named: selection)?.play()
        }
    }
}
