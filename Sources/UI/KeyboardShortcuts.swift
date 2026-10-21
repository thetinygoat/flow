/// What the Keyboard Shortcuts window lists: Flow's own shortcuts, named for
/// what they do and grouped by task, without the standard macOS ones such as
/// Copy or Quit.
enum KeyboardShortcuts {
    struct Shortcut: Equatable {
        var title: String
        /// Each modifier and the key, one per keycap.
        var keys: [String]
    }

    struct Section: Equatable {
        var title: String
        var shortcuts: [Shortcut]
    }

    static let all: [Section] = [
        Section(title: "Workspaces", shortcuts: [
            Shortcut(title: "New workspace", keys: ["⌘", "N"]),
            Shortcut(title: "Switch workspace", keys: ["⌘", "1–8"]),
            Shortcut(title: "Last workspace", keys: ["⌘", "9"]),
            Shortcut(title: "Previous workspace", keys: ["⇧", "⌘", "["]),
            Shortcut(title: "Next workspace", keys: ["⇧", "⌘", "]"]),
            Shortcut(title: "Rename workspace", keys: ["⇧", "⌘", "R"]),
            Shortcut(title: "Show or hide the sidebar", keys: ["⌘", "B"]),
        ]),
        Section(title: "Tabs and panes", shortcuts: [
            Shortcut(title: "New tab", keys: ["⌘", "T"]),
            Shortcut(title: "Switch tab", keys: ["⌃", "1–9"]),
            Shortcut(title: "Split right", keys: ["⌘", "D"]),
            Shortcut(title: "Split down", keys: ["⇧", "⌘", "D"]),
            Shortcut(title: "Zoom pane", keys: ["⇧", "⌘", "↩"]),
            Shortcut(title: "Close pane", keys: ["⌘", "W"]),
            Shortcut(title: "Close tab", keys: ["⌥", "⌘", "W"]),
        ]),
        Section(title: "Windows", shortcuts: [
            Shortcut(title: "New window", keys: ["⇧", "⌘", "N"]),
            Shortcut(title: "Close window", keys: ["⇧", "⌘", "W"]),
            Shortcut(title: "Full screen", keys: ["⌃", "⌘", "F"]),
        ]),
        Section(title: "Terminal", shortcuts: [
            Shortcut(title: "Find", keys: ["⌘", "F"]),
            Shortcut(title: "Find next", keys: ["⌘", "G"]),
            Shortcut(title: "Find previous", keys: ["⇧", "⌘", "G"]),
            Shortcut(title: "Find the selection", keys: ["⌘", "E"]),
            Shortcut(title: "Bigger text", keys: ["⌘", "="]),
            Shortcut(title: "Smaller text", keys: ["⌘", "-"]),
            Shortcut(title: "Reset text size", keys: ["⌘", "0"]),
        ]),
        Section(title: "Settings", shortcuts: [
            Shortcut(title: "Open your config", keys: ["⌘", ","]),
            Shortcut(title: "Reload your config", keys: ["⇧", "⌘", ","]),
        ]),
    ]
}
