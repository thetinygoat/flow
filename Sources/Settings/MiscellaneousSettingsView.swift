import SwiftUI

struct MiscellaneousSettingsView: View {
    let store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Send anonymous usage telemetry", isOn: store.binding(FlowOption.telemetry))
            } header: {
                Text("Telemetry")
            } footer: {
                Text("Limited to app usage data. Terminal content is never collected.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}
