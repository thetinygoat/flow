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
                    var families = store.values(for: Option.fontFamily)
                    if family.isEmpty {
                        families = []
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
                if theme.wrappedValue.followsAppearance {
                    ThemePicker(title: "Light mode", selection: theme.light, allowsDefault: false)
                    ThemePicker(title: "Dark mode", selection: theme.dark, allowsDefault: false)
                } else {
                    ThemePicker(title: "Theme", selection: Binding(
                        get: { theme.wrappedValue.light },
                        set: { theme.wrappedValue = ThemeChoice(light: $0, dark: $0) }), allowsDefault: true)
                }
                Toggle("Separate dark mode theme", isOn: Binding(
                    get: { theme.wrappedValue.followsAppearance },
                    set: { different in
                        // Most chosen themes are dark, so the current one is kept for dark mode.
                        let current = theme.wrappedValue
                        theme.wrappedValue = different
                            ? ThemeChoice(light: Themes.light, dark: current.light == Themes.light ? Themes.dark : current.light ?? Themes.dark)
                            : ThemeChoice(light: current.dark, dark: current.dark)
                    }))
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

            Section("Cursor") {
                Picker("Shape", selection: store.binding(Option.cursorStyle)) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                    Text("Hollow block").tag("block_hollow")
                }
                Toggle("Blink", isOn: store.binding(Option.cursorBlink))
            }

            Section("Window") {
                LabeledContent("Background opacity") {
                    Slider(value: store.binding(Option.backgroundOpacity), in: 0.2...1) {
                        Text("Background opacity")
                    } minimumValueLabel: {
                        Image(systemName: "circle.dotted")
                    } maximumValueLabel: {
                        Image(systemName: "circle.fill")
                    }
                    .labelsHidden()
                }
                Toggle("Background blur", isOn: store.binding(Option.backgroundBlur))
                    .disabled(store.value(Option.backgroundOpacity) >= 1)
                LabeledContent("Dim unfocused panes") {
                    Slider(value: Binding(
                        get: { 1 - store.value(Option.unfocusedSplitOpacity) },
                        set: { store.set(Option.unfocusedSplitOpacity, ((1 - $0) * 100).rounded() / 100) }), in: 0...0.85) {
                        Text("Dim unfocused panes")
                    } minimumValueLabel: {
                        Text("None").font(.caption)
                    } maximumValueLabel: {
                        Text("Strong").font(.caption)
                    }
                    .labelsHidden()
                }
                Toggle("Show scroll bar", isOn: Binding(
                    get: { store.value(Option.scrollbar) != "never" },
                    set: { store.set(Option.scrollbar, $0 ? "system" : "never") }))
            }
        }
        .formStyle(.grouped)
    }

    /// The installed monospaced fonts, and the configured font even if it is
    /// missing, so the picker can show it.
    private var fontChoices: [String] {
        let current = fontFamily.wrappedValue
        return current.isEmpty || Fonts.monospaced.contains(current) ? Fonts.monospaced : [current] + Fonts.monospaced
    }
}

private struct ThemePicker: View {
    let title: String
    @Binding var selection: String?
    let allowsDefault: Bool

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsDefault {
                Text("Default").tag(String?.none)
                Divider()
            }
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
