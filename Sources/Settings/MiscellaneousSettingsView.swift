import SwiftUI

struct MiscellaneousSettingsView: View {
    let store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Send anonymous usage counts", isOn: store.binding(FlowOption.telemetry))
            } header: {
                Text("Telemetry")
            } footer: {
                Text("Counts the installs active each day, week and month, with the Flow and macOS versions. The weekly count includes the week Flow was installed. Counts go to Aptabase, which derives country and region from the IP address.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}
