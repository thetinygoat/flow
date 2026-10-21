import Foundation

extension AgentAdapter {
    static let codex = AgentAdapter(
        name: "codex",
        binary: "codex",
        launch: .flags(Codex.arguments),
        translate: Codex.translate,
        translateNotification: Codex.translateNotification
    )
}

/// Codex reads hooks from `-c` overrides as well as its config files, so Flow
/// hands its hooks to each launch and never touches `~/.codex`. Codex runs a
/// hook only once the user has trusted it with `/hooks`, and remembers that
/// trust by the hook's definition, so a definition that changes between
/// launches asks the user again.
///
/// The hooks are synchronous: Codex starts async ones together, so they reach
/// Flow out of order, and `codex exec` drops any still running when it exits.
///
/// `PermissionRequest` runs before Codex's auto-reviewer decides, and the
/// reviewer approves most requests itself, so the hook cannot say whether the
/// user is needed. Codex notifies its terminal only of the approvals it puts
/// to the user, and that notification is what tells Flow Codex is waiting.
enum Codex {
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]

    /// Codex's notifications for what it puts to the user, sent as the escape
    /// Flow reads whether or not the terminal has focus. They are Flow's sign
    /// that Codex is waiting on the user, and Flow decides itself whether to
    /// tell the user, so forcing them changes nothing the user sees.
    ///
    /// The terminal shows one notification a second across all its panes, and
    /// drops a repeat within five seconds. A turn-complete notification, which
    /// Flow has no use for, would take that slot and could hide another
    /// pane's approval, so Codex sends only the kinds Flow reads.
    static let notificationSettings = [
        (key: "tui.notifications", value: #"["approval-requested","plan-mode-prompt","async-question"]"#),
        (key: "tui.notification_method", value: #""osc9""#),
        (key: "tui.notification_condition", value: #""always""#),
    ]

    /// The starts of the notifications Codex sends when it puts an approval,
    /// an edit, a plan or a question to the user.
    static let waitingNotifications = ["Approval requested", "Codex wants to edit", "Plan mode prompt:", "Question:"]

    static func override(for event: String, flw: String) -> String {
        let command = "\(flw.shellQuoted) hook codex"
        return #"hooks.\#(event)=[{hooks=[{type="command",command=\#(command.tomlQuoted)}]}]"#
    }

    /// Adds Flow's settings and hooks ahead of the user's arguments, so that on
    /// a conflict the user's own override, which Codex reads last, wins. A
    /// setting the user overrides, or an event they already set hooks for, is
    /// left to them.
    static func arguments(_ arguments: [String], flw: String) -> [String] {
        let options = arguments.firstIndex(of: "--").map { arguments[..<$0] } ?? arguments[...]
        let overridden = userOverrides(Array(options))
        let settings = overridden.contains("tui") ? [] : notificationSettings.filter { !overridden.contains($0.key) }
        let events = overridden.contains("hooks") ? [] : hookEvents.filter { event in
            !overridden.contains { $0 == "hooks.\(event)" || $0.hasPrefix("hooks.\(event).") }
        }
        return settings.flatMap { ["-c", "\($0.key)=\($0.value)"] }
            + events.flatMap { ["-c", override(for: $0, flw: flw)] }
            + arguments
    }

    /// The keys of the `-c key=value` overrides in `options`, unquoted.
    private static func userOverrides(_ options: [String]) -> [String] {
        var keys: [String] = []
        var index = options.startIndex
        while index < options.endIndex {
            let option = options[index]
            var value: String?
            if option == "-c" || option == "--config" {
                index += 1
                value = index < options.endIndex ? options[index] : nil
            } else if option.hasPrefix("--config=") {
                value = String(option.dropFirst("--config=".count))
            } else if option.hasPrefix("-c") {
                value = String(option.dropFirst(2))
            }
            if let key = value?.split(separator: "=", maxSplits: 1).first {
                keys.append(key.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces))
            }
            index += 1
        }
        return keys
    }

    static func translate(_ payload: HookPayload) -> AgentEvent? {
        // A subagent's hooks carry its parent's session id, and would make the
        // parent's state flap while it waits on them.
        guard payload.fields["agent_id"] == nil, let name = payload.string("hook_event_name") else { return nil }
        let event = { (kind: AgentEvent.Kind, detail: String?) in
            payload.event(kind, sessionID: payload.string("session_id") ?? "", cwd: payload.string("cwd") ?? "", detail: detail)
        }
        switch name {
        case "SessionStart":
            return event(.sessionStarted, nil)
        case "UserPromptSubmit":
            return event(.turnStarted, nil)
        case "PreToolUse", "PostToolUse":
            return event(.working, payload.string("tool_name"))
        case "PermissionRequest":
            return nil
        case "Stop":
            return event(.turnEnded, payload.summary("last_assistant_message"))
        // Codex sends no Stop for a turn the user cancels.
        case "Interrupt":
            return event(.turnEnded, nil)
        case "SessionEnd":
            return event(.sessionEnded, nil)
        default:
            return nil
        }
    }

    static func translateNotification(_ message: String) -> (kind: AgentEvent.Kind, detail: String?)? {
        guard waitingNotifications.contains(where: message.hasPrefix) else { return nil }
        return (.needsInput, HookPayload.summary(message))
    }
}

private extension String {
    var tomlQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
