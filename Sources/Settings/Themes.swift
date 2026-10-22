import AppKit

/// The `theme` option: one theme, or one for light mode and one for dark.
/// Nil is Ghostty's own colors.
struct ThemeChoice: Equatable {
    var light: String?
    var dark: String?

    init(light: String?, dark: String?) {
        self.light = light
        self.dark = dark
    }

    init(_ value: String?) {
        guard let value, !value.isEmpty else { self.init(light: nil, dark: nil); return }
        guard value.contains(where: { ",:=".contains($0) }) else { self.init(light: value, dark: value); return }
        var light: String?, dark: String?
        for part in value.split(separator: ",") {
            let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            if pair[0] == "light" { light = pair[1] }
            if pair[0] == "dark" { dark = pair[1] }
        }
        self.init(light: light, dark: dark)
    }

    var followsAppearance: Bool { light != dark }

    var value: String? {
        guard followsAppearance else { return light }
        return "light:\(light ?? Themes.light),dark:\(dark ?? Themes.dark)"
    }
}

enum Themes {
    static let light = "Builtin Light"
    static let dark = "Builtin Dark"

    /// The themes Ghostty finds by name: the user's own, then the ones Flow
    /// ships with.
    static let names: [String] = {
        let home = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        let directories = [home.appendingPathComponent("ghostty/themes"), Bundle.main.resourceURL?.appendingPathComponent("ghostty/themes")]
        let names = directories.compactMap { $0 }.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        }.filter { !$0.hasPrefix(".") }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    private static var previews: [String: Colors] = [:]

    struct Colors {
        var background: NSColor
        var foreground: NSColor
        var palette: [NSColor]
    }

    /// The colors libghostty gives a theme, or its own colors for nil.
    static func colors(of theme: String?) -> Colors? {
        let key = theme ?? ""
        if let cached = previews[key] { return cached }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("flow-theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let contents = theme.map { "theme = \($0)\n" } ?? ""
        guard (try? contents.write(to: file, atomically: true, encoding: .utf8)) != nil,
              let config = try? GhosttyConfig(file: file), config.palette.count == 16 else { return nil }
        let colors = Colors(background: config.backgroundColor, foreground: config.foregroundColor, palette: config.palette)
        previews[key] = colors
        return colors
    }
}

enum Fonts {
    /// Font families whose fonts are all one width, which is what a terminal
    /// can use.
    static let monospaced: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            manager.availableMembers(ofFontFamily: family)?.contains { member in
                guard member.count > 3, let traits = member[3] as? UInt else { return false }
                return NSFontTraitMask(rawValue: traits).contains(.fixedPitchFontMask)
            } ?? false
        }.filter { !$0.hasPrefix(".") }
    }()
}
