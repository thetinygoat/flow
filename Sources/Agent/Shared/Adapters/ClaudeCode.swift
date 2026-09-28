import Foundation

extension AgentAdapter {
    static let claudeCode = AgentAdapter(
        name: "claude",
        binary: "claude",
        launch: .flags(ClaudeCode.arguments),
        translate: ClaudeCode.translate
    )
}

/// Claude Code reads hooks from a `--settings` flag as well as its settings
/// files, so Flow hands its hooks to each launch and never touches `~/.claude`.
enum ClaudeCode {
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// The notification types where Claude is blocked on the user. Others need
    /// nothing from them: `idle_prompt` is only a reminder, sent a minute after
    /// a turn has already ended.
    static let needsInputTypes: Set = ["permission_prompt", "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog"]

    static let detailLimit = 200

    static func settings(flw: String) -> [String: Any] {
        let hook: [String: Any] = ["type": "command", "command": "\(flw.shellQuoted) hook claude", "async": true]
        return [
            "hooks": Dictionary(uniqueKeysWithValues: hookEvents.map { ($0, [["hooks": [hook]]]) }),
            // Flow notifies from the hooks, so Claude's own terminal
            // notifications would only duplicate them.
            "preferredNotifChannel": "notifications_disabled",
        ]
    }

    /// Adds Flow's settings to the user's arguments. Claude honours only one
    /// `--settings`, so one the user passed is merged into Flow's rather than
    /// shadowed by it. Settings Flow cannot read are left for Claude to report,
    /// without Flow's hooks.
    static func arguments(_ arguments: [String], flw: String) -> [String] {
        var arguments = arguments
        var settings = settings(flw: flw)
        let options = arguments.firstIndex(of: "--").map { arguments[..<$0] } ?? arguments[...]
        if let index = options.firstIndex(where: { $0 == "--settings" || $0.hasPrefix("--settings=") }) {
            let joined = arguments[index] != "--settings"
            let valueIndex = joined ? index : index + 1
            guard valueIndex < arguments.count else { return arguments }
            let value = joined ? String(arguments[index].dropFirst("--settings=".count)) : arguments[valueIndex]
            guard let user = userSettings(value) else { return arguments }
            settings = merge(settings, into: user)
            arguments.removeSubrange(index...valueIndex)
        }
        guard let json = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return arguments
        }
        return ["--settings", String(decoding: json, as: UTF8.self)] + arguments
    }

    /// `--settings` takes inline JSON or the path of a JSON file.
    private static func userSettings(_ value: String) -> [String: Any]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.hasPrefix("{") ? Data(trimmed.utf8) : FileManager.default.contents(atPath: value)
        return data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    /// The user's hooks run as well as Flow's; for any other key Flow's value wins.
    static func merge(_ flow: [String: Any], into user: [String: Any]) -> [String: Any] {
        var merged = user
        for (key, value) in flow where key != "hooks" {
            merged[key] = value
        }
        var hooks = user["hooks"] as? [String: Any] ?? [:]
        for (event, entries) in flow["hooks"] as? [String: [Any]] ?? [:] {
            hooks[event] = (hooks[event] as? [Any] ?? []) + entries
        }
        merged["hooks"] = hooks
        return merged
    }

    static func translate(_ payload: HookPayload) -> AgentEvent? {
        // A subagent's hooks carry its parent's session id, and would make the
        // parent's state flap while it waits on them.
        guard payload.fields["agent_id"] == nil, let name = payload.string("hook_event_name") else { return nil }
        let tool = payload.string("tool_name")
        let event = { (kind: AgentEvent.Kind, detail: String?) in
            payload.event(kind, sessionID: payload.string("session_id") ?? "", cwd: payload.string("cwd") ?? "", detail: detail)
        }
        switch name {
        case "SessionStart":
            return event(.sessionStarted, nil)
        case "UserPromptSubmit":
            return event(.turnStarted, nil)
        case "PostToolUse" where tool == "PushNotification":
            return event(.attention, payload.object("tool_input")?["message"] as? String)
        case "PreToolUse", "PostToolUse":
            return event(.working, tool)
        case "Notification":
            guard let type = payload.string("notification_type"), needsInputTypes.contains(type) else { return nil }
            return event(.needsInput, type)
        case "Stop":
            return event(.turnEnded, payload.string("last_assistant_message").map(summary))
        case "SessionEnd":
            return event(.sessionEnded, nil)
        default:
            return nil
        }
    }

    static func summary(_ message: String) -> String {
        let line = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > detailLimit ? line.prefix(detailLimit - 1) + "…" : line
    }
}
