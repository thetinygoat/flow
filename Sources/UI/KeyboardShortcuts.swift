/// What the Keyboard Shortcuts window lists: Flow's own shortcuts, named for
/// what they do and grouped by task, without the standard macOS ones such as
/// Copy or Quit.
enum KeyboardShortcuts {
    struct Shortcut: Equatable {
        var title: String
        /// Each modifier and the key, one per keycap.
        var keys: [String]
        /// The command whose key the row shows, for a key Settings can change.
        var action: String?
        /// Shows the command's key pressed twice, which the palettes take as
        /// going back.
        var repeats = false
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
            Shortcut(title: "Rename workspace", keys: ["⇧", "⌘", "R"], action: "rename_workspace"),
            Shortcut(title: "Show or hide the sidebar", keys: ["⌘", "B"]),
        ]),
        Section(title: "Go to", shortcuts: [
            Shortcut(title: "Go to a workspace", keys: ["⌘", "P"], action: "toggle_workspace_palette"),
            Shortcut(title: "Go back to the previous workspace", keys: ["⌘", "P", "P"], action: "toggle_workspace_palette", repeats: true),
            Shortcut(title: "Go to a tab or pane", keys: ["⇧", "⌘", "P"], action: "toggle_command_palette"),
            Shortcut(title: "Go back to the previous tab or pane", keys: ["⇧", "⌘", "P", "P"], action: "toggle_command_palette", repeats: true),
            Shortcut(title: "Go to an agent", keys: ["⌘", "I"], action: "toggle_agent_palette"),
            Shortcut(title: "Go to the agent waiting longest", keys: ["⌘", "I", "I"], action: "toggle_agent_palette", repeats: true),
            Shortcut(title: "Step up the list, going there on letting go of ⌘", keys: ["⌘", "↑"]),
            Shortcut(title: "Step down the list, going there on letting go of ⌘", keys: ["⌘", "↓"]),
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
            Shortcut(title: "Open Settings", keys: ["⌘", ","]),
            Shortcut(title: "Reload configuration", keys: ["⇧", "⌘", ","]),
        ]),
    ]

    /// The list with the keys in effect for the commands Settings can
    /// change. A row whose command has no key is left out.
    static func current(_ bindings: KeyBindings) -> [Section] {
        all.map { section in
            Section(title: section.title, shortcuts: section.shortcuts.compactMap { shortcut in
                guard let action = shortcut.action else { return shortcut }
                guard let key = bindings.shortcut(for: action) else { return nil }
                var shortcut = shortcut
                shortcut.keys = key.symbols + (shortcut.repeats ? [key.keySymbol] : [])
                return shortcut
            })
        }
    }

    /// The commands whose key Settings can change, with their default.
    struct Command: Identifiable, Equatable {
        var title: String
        /// The `keybind` action: Ghostty's for the tab and pane palette,
        /// Flow's own for the others.
        var action: String
        var defaultKey: KeyTrigger
        /// Flow runs it from its menu. libghostty has no such action.
        var isFlows: Bool

        var id: String { action }
    }

    static let changeable: [Command] = [
        Command(title: "Go to a workspace", action: "toggle_workspace_palette", defaultKey: KeyTrigger("super+p")!, isFlows: true),
        Command(title: "Go to a tab or pane", action: "toggle_command_palette", defaultKey: KeyTrigger("super+shift+p")!, isFlows: false),
        Command(title: "Go to an agent", action: "toggle_agent_palette", defaultKey: KeyTrigger("super+i")!, isFlows: true),
        Command(title: "Rename workspace", action: "rename_workspace", defaultKey: KeyTrigger("super+shift+r")!, isFlows: true),
    ]

    static func command(for action: String) -> Command? {
        changeable.first { $0.action == action }
    }
}
