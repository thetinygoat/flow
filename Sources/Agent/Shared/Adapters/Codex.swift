import Foundation

extension AgentAdapter {
    static let codex = AgentAdapter(
        name: "codex",
        binary: "codex",
        launch: .flags(Codex.arguments),
        translate: Codex.translate
    )
}

/// Codex reads hooks from `-c` overrides as well as its config files, so Flow
/// hands its hooks to each launch and never touches `~/.codex`. Codex runs a
/// hook only once the user has trusted it with `/hooks`, and remembers that
/// trust by the hook's definition, so the definitions must not change between
/// launches or the user is asked again.
enum Codex {
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]

    /// Codex waits on SessionEnd hooks whatever they ask, and warns when asked
    /// not to.
    static let synchronousEvents: Set = ["SessionEnd"]

    static func override(for event: String, flw: String) -> String {
        let command = "\(flw.shellQuoted) hook codex"
        let async = synchronousEvents.contains(event) ? "" : ",async=true"
        return #"hooks.\#(event)=[{hooks=[{type="command",command=\#(command.tomlQuoted)\#(async)}]}]"#
    }

    /// Adds Flow's hooks ahead of the user's arguments, so that on a conflict
    /// the user's own override, which Codex reads last, wins. An event the user
    /// already sets hooks for is left to them.
    static func arguments(_ arguments: [String], flw: String) -> [String] {
        let options = arguments.firstIndex(of: "--").map { arguments[..<$0] } ?? arguments[...]
        let overridden = userOverrides(Array(options))
        guard !overridden.contains("hooks") else { return arguments }
        let events = hookEvents.filter { event in
            !overridden.contains { $0 == "hooks.\(event)" || $0.hasPrefix("hooks.\(event).") }
        }
        return events.flatMap { ["-c", override(for: $0, flw: flw)] } + arguments
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
            return event(.needsInput, "permission")
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
}

private extension String {
    var tomlQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
