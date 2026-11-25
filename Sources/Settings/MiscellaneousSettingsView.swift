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
                Text("Sent on the first use of each day, week and month, with the Flow and macOS versions. The weekly event includes the week Flow was installed. Telemetry goes to Aptabase, which derives country and region from the IP address.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}
