import Foundation

/// What an invocation of `flw` asks for, worked out from its arguments and
/// environment alone so it can be tested without running the tool.
enum FlwCommand: Equatable {
    /// `excerpts` are for naming the session, and are not sent.
    case event(AgentEvent, excerpts: [Excerpt] = [], socket: String)
    case hook(adapter: String, socket: String)
    /// Names a session from what `flw` kept of its conversation.
    case title(adapter: String, sessionID: String, surfaceID: UUID?, workspaceID: UUID?, socket: String)
    case launch(adapter: String, arguments: [String])
    case shims(directory: String)
    case refreshAgents(script: String)
    case ping(socket: String)
    case usage

    struct UsageError: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    static let usageText = """
        usage: flw event <kind> [--agent NAME] [--session ID] [--detail TEXT] [--title TEXT]
                                [--cwd PATH] [--surface UUID] [--workspace UUID]
                                [--excerpt 'user|assistant: TEXT']...
               flw hook <agent>              (reads the agent's hook JSON on stdin)
               flw title <agent> --session ID [--surface UUID] [--workspace UUID]
               flw launch <agent> [args...]
               flw shims <dir>
               flw agents refresh
               flw ping

        kinds: sessionStarted turnStarted working needsInput turnEnded sessionEnded attention titleChanged
        """

    static func parse(_ arguments: [String], environment: [String: String], currentDirectory: String, now: Date) throws -> FlwCommand {
        let socket = environment[AgentEnvironment.socketKey].flatMap { $0.isEmpty ? nil : $0 } ?? AgentEnvironment.socketURL.path
        switch (arguments.first, arguments.dropFirst().first) {
        case ("event", _):
            let (event, excerpts) = try event(Array(arguments.dropFirst()), environment: environment, currentDirectory: currentDirectory, now: now)
            return .event(event, excerpts: excerpts, socket: socket)
        case let ("hook", adapter?):
            return .hook(adapter: adapter, socket: socket)
        case let ("title", adapter?):
            let options = try options(arguments.dropFirst(2), allowed: ["--session", "--surface", "--workspace"])
            guard let session = options["--session"] else { throw UsageError(description: "--session is required") }
            return .title(
                adapter: adapter,
                sessionID: session,
                surfaceID: try uuid(options["--surface"], flag: "--surface") ?? environment[AgentEnvironment.surfaceKey].flatMap(UUID.init),
                workspaceID: try uuid(options["--workspace"], flag: "--workspace") ?? environment[AgentEnvironment.workspaceKey].flatMap(UUID.init),
                socket: socket
            )
        case let ("launch", adapter?):
            return .launch(adapter: adapter, arguments: Array(arguments.dropFirst(2)))
        case let ("shims", directory?):
            return .shims(directory: directory)
        case ("agents", "refresh"):
            return .refreshAgents(script: refreshScript(environment: environment))
        case ("ping", _):
            return .ping(socket: socket)
        default:
            return .usage
        }
    }

    /// What the shell integration runs at the first prompt, for the user to
    /// run again after installing an agent, written for their shell.
    static func refreshScript(environment: [String: String]) -> String {
        let posix = #""$FLOW_FLW" shims "$dir" && PATH="$dir:$PATH""#
        guard environment["SHELL"].map({ ($0 as NSString).lastPathComponent }) == "fish" else {
            return #"dir="${TMPDIR:-/tmp}/flow-shims/$FLOW_SURFACE_ID""# + "\n" + posix
        }
        return """
            set dir (set -q TMPDIR; and echo $TMPDIR; or echo /tmp)/flow-shims/$FLOW_SURFACE_ID
            "$FLOW_FLW" shims $dir; and set -gx --prepend PATH $dir
            """
    }

    private static func event(_ arguments: [String], environment: [String: String], currentDirectory: String, now: Date) throws -> (AgentEvent, [Excerpt]) {
        guard let name = arguments.first else { throw UsageError(description: "missing event kind") }
        guard let kind = AgentEvent.Kind(rawValue: name), kind != .unknown else {
            throw UsageError(description: "unknown event kind \(name)")
        }
        var excerpts: [Excerpt] = []
        let options = try options(arguments.dropFirst(), allowed: ["--agent", "--session", "--detail", "--title", "--cwd", "--surface", "--workspace"]) { flag, value in
            guard flag == "--excerpt" else { return false }
            guard let excerpt = Excerpt(value) else { throw UsageError(description: "--excerpt needs 'user: TEXT' or 'assistant: TEXT'") }
            excerpts.append(excerpt)
            return true
        }
        let event = AgentEvent(
            agent: options["--agent"] ?? "",
            kind: kind,
            sessionID: options["--session"] ?? "",
            surfaceID: try uuid(options["--surface"], flag: "--surface") ?? environment[AgentEnvironment.surfaceKey].flatMap(UUID.init),
            workspaceID: try uuid(options["--workspace"], flag: "--workspace") ?? environment[AgentEnvironment.workspaceKey].flatMap(UUID.init),
            cwd: options["--cwd"] ?? currentDirectory,
            at: now,
            detail: options["--detail"],
            title: options["--title"]
        )
        return (event, excerpts)
    }

    /// Each option takes one value. `repeated` takes the ones that may be
    /// given more than once, and returns false for those it does not know.
    private static func options(
        _ arguments: ArraySlice<String>, allowed: Set<String>,
        repeated: (String, String) throws -> Bool = { _, _ in false }
    ) throws -> [String: String] {
        var options: [String: String] = [:]
        var rest = arguments
        while let flag = rest.popFirst() {
            guard let value = rest.popFirst() else {
                throw UsageError(description: allowed.contains(flag) ? "\(flag) needs a value" : "unknown option \(flag)")
            }
            if try repeated(flag, value) { continue }
            guard allowed.contains(flag) else { throw UsageError(description: "unknown option \(flag)") }
            options[flag] = value
        }
        return options
    }

    private static func uuid(_ value: String?, flag: String) throws -> UUID? {
        guard let value else { return nil }
        guard let uuid = UUID(uuidString: value) else { throw UsageError(description: "\(flag) is not a UUID: \(value)") }
        return uuid
    }
}
