import SwiftUI

struct MiscellaneousSettingsView: View {
    let store: SettingsStore

    var body: some View {
        Form {
            Section("Telemetry") {
                Toggle("Send anonymous usage telemetry", isOn: store.binding(FlowOption.telemetry))
            }
        }
        .formStyle(.grouped)
    }
}
