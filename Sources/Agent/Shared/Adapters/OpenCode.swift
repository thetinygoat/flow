import Foundation

extension AgentAdapter {
    static let openCode = AgentAdapter(
        name: "opencode",
        binary: "opencode",
        launch: .environment(OpenCode.environment),
        translate: { _ in nil }
    )
}

/// OpenCode runs no hooks but loads plugins, and adds the ones named in
/// `OPENCODE_CONFIG_CONTENT` to those in the user's own configuration. Flow
/// names its plugin there for each launch and never touches `~/.config/opencode`.
/// The plugin sends its events with `flw event`, so there is nothing to translate.
enum OpenCode {
    static let contentKey = "OPENCODE_CONFIG_CONTENT"

    /// Where the app bundles the plugin, found from the `flw` inside it.
    static func plugin(flw: String) -> String {
        URL(fileURLWithPath: flw)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/agents/opencode/flow.js")
            .path
    }

    /// Configuration the user set in `OPENCODE_CONFIG_CONTENT` is kept, with
    /// Flow's plugin added to theirs. Content Flow cannot read is left for
    /// OpenCode to report, without Flow's plugin.
    static func environment(_ environment: [String: String], flw: String) -> [String: String] {
        var config: [String: Any] = [:]
        if let content = environment[contentKey], !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let user = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [String: Any] else { return [:] }
            config = user
        }
        config["plugin"] = (config["plugin"] as? [Any] ?? []) + [plugin(flw: flw)]
        guard let json = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return [:]
        }
        return [contentKey: String(decoding: json, as: UTF8.self)]
    }
}
