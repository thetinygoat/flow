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
            Section("When an agent needs you") {
                Toggle("Show a notification", isOn: $needsInputNotification)
                SoundPicker(selection: $needsInputSound)
            }

            Section {
                Toggle("Show a notification", isOn: $finishedNotification)
                SoundPicker(selection: $finishedSound)
            } header: {
                Text("When an agent finishes")
            } footer: {
                Text("Flow alerts you only about agents in terminals you can't see.")
                    .settingsFooter()
            }

            Section {
                Picker("Alert me", selection: store.binding(Option.notifyOnCommandFinish)) {
                    Text("Never").tag(CommandFinish.When.never)
                    Text("When I can't see the terminal").tag(CommandFinish.When.unfocused)
                    Text("Always").tag(CommandFinish.When.always)
                }
                Group {
                    LabeledContent("For commands that take") {
                        Stepper(value: Binding(
                            get: { Int(store.value(Option.notifyOnCommandFinishAfter).components.seconds) },
                            set: { store.set(Option.notifyOnCommandFinishAfter, .seconds($0)) }), in: 1...3600) {
                            Text(store.value(Option.notifyOnCommandFinishAfter).formatted(.units(allowed: [.minutes, .seconds], width: .wide)) + " or longer")
                        }
                    }
                    Toggle("Show a notification", isOn: action(.notify))
                    Toggle("Play a sound", isOn: action(.bell))
                }
                .disabled(store.value(Option.notifyOnCommandFinish) == .never)
            } header: {
                Text("When a command finishes")
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
