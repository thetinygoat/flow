import SwiftUI

struct AppearanceSettingsView: View {
    let store: SettingsStore

    private var theme: Binding<ThemeChoice> {
        Binding(get: { ThemeChoice(store.values(for: Option.theme).last) },
                set: { store.setValues($0.value.map { [$0] } ?? [], for: Option.theme) })
    }

    private var fontFamily: Binding<String> {
        Binding(get: { store.values(for: Option.fontFamily).first ?? "" },
                set: { family in
                    // Later families are fallbacks for characters the first
                    // lacks, so only the first is replaced or removed.
                    var families = store.values(for: Option.fontFamily)
                    if family.isEmpty {
                        families = Array(families.dropFirst())
                    } else if families.isEmpty {
                        families = [family]
                    } else {
                        families[0] = family
                    }
                    store.setValues(families, for: Option.fontFamily)
                })
    }

    var body: some View {
        Form {
            Section("Colors") {
                ThemePicker(title: "Light mode", selection: Binding(
                    get: { theme.wrappedValue.light },
                    set: { light in
                        let choice = theme.wrappedValue
                        theme.wrappedValue = ThemeChoice(light: light, dark: choice.followsAppearance ? choice.dark : light)
                    }), none: "Default")
                ThemePicker(title: "Dark mode", selection: Binding(
                    get: { theme.wrappedValue.followsAppearance ? theme.wrappedValue.dark : nil },
                    set: { dark in
                        let light = theme.wrappedValue.light
                        theme.wrappedValue = ThemeChoice(light: light, dark: dark ?? light)
                    }), none: "Same as light mode")
                ThemePreview(choice: theme.wrappedValue)
            }

            Section("Text") {
                Picker("Font", selection: fontFamily) {
                    Text("Default (JetBrains Mono)").tag("")
                    Divider()
                    ForEach(fontChoices, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                LabeledContent("Size") {
                    HStack {
                        TextField("Size", value: store.binding(Option.fontSize), format: .number.precision(.fractionLength(0...1)))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                        Stepper("Size", value: store.binding(Option.fontSize), in: 6...72, step: 1)
                            .labelsHidden()
                    }
                }
                Toggle("Thicken text", isOn: store.binding(Option.fontThicken))
            }

            Section {
                Picker("Shape", selection: store.binding(Option.cursorStyle)) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                    Text("Hollow block").tag("block_hollow")
                }
                Toggle("Blink", isOn: store.binding(Option.cursorBlink))
                Toggle("Bar at shell prompts", isOn: shellSetsCursor)
            } header: {
                Text("Cursor")
            } footer: {
                Text("Bar at shell prompts: the shell shows a blinking bar at its prompt instead of this shape. It affects terminals opened after the change; shape and blink apply immediately.")
                    .settingsFooter()
            }

            Section("Window") {
                LabeledContent("Background opacity") {
                    SavedOnReleaseSlider(value: store.binding(Option.backgroundOpacity), range: 0.2...1)
                }
                LabeledContent("Background blur") {
                    SavedOnReleaseSlider(value: store.binding(Option.backgroundBlur), range: 0...50, step: 1) { radius in
                        radius == 0 ? "Off" : radius.formatted(.number.precision(.fractionLength(0)))
                    }
                }
                .disabled(store.value(Option.backgroundOpacity) >= 1 || store.hasUnknownValue(Option.backgroundBlur))
                LabeledContent("Dim unfocused panes") {
                    SavedOnReleaseSlider(value: Binding(
                        get: { 1 - store.value(Option.unfocusedSplitOpacity) },
                        set: { store.set(Option.unfocusedSplitOpacity, ((1 - $0) * 100).rounded() / 100) }), range: 0...0.85)
                }
                Toggle("Show scroll bar", isOn: Binding(
                    get: { store.value(Option.scrollbar) != "never" },
                    set: { store.set(Option.scrollbar, $0 ? "system" : "never") }))
            }
        }
        .formStyle(.grouped)
    }

    /// Shell integration's `cursor` switch, which overrides the shape and
    /// blink at the prompt.
    private var shellSetsCursor: Binding<Bool> {
        Binding(
            get: { store.value(Option.shellIntegrationFeatures).on.contains("cursor") },
            set: { on in
                var features = store.value(Option.shellIntegrationFeatures)
                if on { features.on.insert("cursor") } else { features.on.remove("cursor") }
                store.set(Option.shellIntegrationFeatures, features)
            })
    }

    /// The installed monospaced fonts, and the configured font even if it is
    /// missing, so the picker can show it.
    private var fontChoices: [String] {
        let current = fontFamily.wrappedValue
        return current.isEmpty || Fonts.monospaced.contains(current) ? Fonts.monospaced : [current] + Fonts.monospaced
    }
}

/// A slider that moves its own copy of the value and saves it once, when the
/// drag ends. Saving at every step would rebuild the whole pane, theme and
/// font menus included, many times a second.
private struct SavedOnReleaseSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var format: (Double) -> String = { $0.formatted(.percent.precision(.fractionLength(0))) }
    @State private var draft: Double?

    var body: some View {
        HStack {
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0 }), in: range, step: step) {
                EmptyView()
            } onEditingChanged: { editing in
                commit(editing)
            }
            .labelsHidden()
            Text(format(draft ?? value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func commit(_ editing: Bool) {
        guard !editing, let draft else { return }
        value = draft
        self.draft = nil
    }
}

/// A theme picker whose first choice, nil, is named by `none`.
private struct ThemePicker: View {
    let title: String
    @Binding var selection: String?
    let none: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text(none).tag(String?.none)
            Divider()
            ForEach(choices, id: \.self) { name in
                Text(name).tag(Optional(name))
            }
        }
    }

    private var choices: [String] {
        guard let selection, !Themes.names.contains(selection) else { return Themes.names }
        return [selection] + Themes.names
    }
}

/// A few lines of a prompt and a listing in the chosen colors.
private struct ThemePreview: View {
    let choice: ThemeChoice

    var body: some View {
        HStack(spacing: 12) {
            if choice.followsAppearance {
                sample(choice.light, label: "Light")
                sample(choice.dark, label: "Dark")
            } else {
                sample(choice.light, label: nil)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sample(_ theme: String?, label: String?) -> some View {
        if let colors = Themes.colors(of: theme) {
            VStack(alignment: .leading, spacing: 2) {
                line([("~/flow ", colors.palette[4]), ("main ", colors.palette[5]), ("$ ", colors.foreground), ("ls", colors.foreground)])
                line([("Sources ", colors.palette[4]), ("README.md ", colors.foreground), ("build.sh", colors.palette[2])])
                line([("✓ ", colors.palette[2]), ("12 passed ", colors.foreground), ("✗ ", colors.palette[1]), ("1 failed", colors.palette[3])])
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: colors.palette[index])).frame(width: 14, height: 8)
                    }
                    Spacer()
                    if let label {
                        Text(label).font(.caption2).foregroundStyle(Color(nsColor: colors.foreground).opacity(0.6))
                    }
                }
                .frame(height: 14)
                .padding(.top, 4)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: colors.background), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
    }

    private func line(_ runs: [(String, NSColor)]) -> Text {
        runs.reduce(Text("")) { text, run in text + Text(run.0).foregroundColor(Color(nsColor: run.1)) }
    }
}
