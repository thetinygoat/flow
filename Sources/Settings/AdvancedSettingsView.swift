import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    let store: SettingsStore
    let reload: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.file])
                        }
                        Button("Open in Editor") {
                            store.saveNow()
                            ConfigFile.openInEditor()
                        }
                    }
                } label: {
                    Text("Config file")
                    Text(store.file.path.abbreviatingHome)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                }
            } footer: {
                Text("Settings in this window are saved to this file. All Ghostty options are supported. Lines added by hand and comments are preserved.")
                    .settingsFooter()
            }

            Section("Problems") {
                LabeledContent {
                    Button("Reload Config", action: reload)
                } label: {
                    Text(store.problems.isEmpty ? "No problems" : store.problems.count == 1 ? "1 problem" : "\(store.problems.count) problems")
                    Text("Reload after editing the file (⇧⌘,).")
                }
                ForEach(store.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
