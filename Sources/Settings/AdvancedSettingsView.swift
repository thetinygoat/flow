import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    let store: SettingsStore
    let reload: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Config file") {
                    Text(store.file.path.abbreviatingHome)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.file])
                    }
                    Button("Open in Editor") {
                        store.saveNow()
                        ConfigFile.openInEditor()
                    }
                }
            } footer: {
                Text("Settings in this window are saved to this file. All Ghostty options are supported. Lines added by hand and comments are preserved. Reload with ⇧⌘, after editing.")
                    .settingsFooter()
            }

            Section {
                if store.problems.isEmpty {
                    Label("No problems", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Spacer()
                    Button("Reload Config", action: reload)
                }
            } header: {
                Text("Problems")
            }
        }
        .formStyle(.grouped)
    }
}
