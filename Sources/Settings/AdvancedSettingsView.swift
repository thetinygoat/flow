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
                Text("The settings in this window are saved to this file. Every Ghostty option works in it, and the lines you add yourself are kept as you wrote them. Reload with ⇧⌘, after editing it.")
                    .settingsFooter()
            }

            Section {
                if store.problems.isEmpty {
                    Label("No problems found", systemImage: "checkmark.circle")
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
