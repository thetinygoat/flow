import Foundation
import os

/// Naming runs in the background, where nobody sees stderr.
let titleLogger = Logger(subsystem: "dev.thetinygoat.flow", category: "titles")

enum Naming {
    static let timeout: TimeInterval = 60
    static let killGrace: TimeInterval = 2

    /// Starts `flw title` in a session of its own with nothing open, so the
    /// hook that calls this returns at once and the agent never waits on it.
    static func start(_ event: AgentEvent, flw: String) {
        var arguments = ["flw", "title", event.agent, "--session", event.sessionID]
        if let surface = event.surfaceID { arguments += ["--surface", surface.uuidString] }
        if let workspace = event.workspaceID { arguments += ["--workspace", workspace.uuidString] }
        if let pid = spawn(flw, arguments, input: "/dev/null", output: "/dev/null", flags: POSIX_SPAWN_SETSID, environment: nil) {
            titleLogger.debug("naming \(event.agent, privacy: .public) session in process \(pid)")
        }
    }

    /// Asks the agent's model for a title and sends it to Flow if it is new.
    static func run(adapter: AgentAdapter, sessionID: String, surfaceID: UUID?, workspaceID: UUID?, environment: [String: String],
                    send: (AgentEvent) -> Void) {
        let store = TitleStore.standard
        let prompt = store.update(agent: adapter.name, session: sessionID, create: false) { context -> String in
            context.inFlightSince = Date()
            return context.prompt
        }
        let reply = prompt.flatMap { ask(adapter, prompt: $0, environment: environment) }
        let title = store.update(agent: adapter.name, session: sessionID, create: false) { context -> String? in
            context.inFlightSince = nil
            context.lastAttempt = Date()
            guard let title = reply.flatMap({ TitleReply.clean($0, current: context.title) }) else { return nil }
            context.title = title
            return title
        } ?? nil
        guard let title else { return }
        send(AgentEvent(agent: adapter.name, kind: .titleChanged, sessionID: sessionID, surfaceID: surfaceID, workspaceID: workspaceID,
                        cwd: FileManager.default.currentDirectoryPath, at: Date(), title: title))
    }

    /// The model's reply, or nil when the agent is missing, fails or runs out of time.
    private static func ask(_ adapter: AgentAdapter, prompt: String, environment: [String: String]) -> String? {
        let summarizer = adapter.summarizer
        let scrubbed = summarizer.environment(from: environment)
        guard let executable = AgentLauncher.resolve(adapter.binary, path: scrubbed["PATH"]) else {
            titleLogger.error("naming skipped: no \(adapter.binary, privacy: .public) on PATH")
            return nil
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flow-title-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        let promptFile = directory.appendingPathComponent("prompt").path
        let replyFile = directory.appendingPathComponent("reply").path
        guard FileManager.default.createFile(atPath: promptFile, contents: Data(prompt.utf8), attributes: [.posixPermissions: 0o600]) else { return nil }

        let arguments = summarizer.arguments(replyFile: replyFile, environment: environment)
        let output = summarizer.output == .standardOutput ? replyFile : "/dev/null"
        let started = Date()
        guard let pid = spawn(executable, [adapter.binary] + arguments, input: promptFile, output: output, directory: directory.path,
                              flags: POSIX_SPAWN_SETPGROUP, environment: scrubbed) else {
            titleLogger.error("naming failed to start \(executable, privacy: .public)")
            return nil
        }
        let status = wait(for: pid)
        let command = ([executable] + arguments.map { $0.shellQuoted }).joined(separator: " ")
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        guard let status, status == 0 else {
            titleLogger.notice("naming \(adapter.name, privacy: .public) failed after \(seconds, privacy: .public)s (\(status.map(String.init) ?? "timed out", privacy: .public)): \(command, privacy: .public)")
            return nil
        }
        titleLogger.notice("naming \(adapter.name, privacy: .public) took \(seconds, privacy: .public)s: \(command, privacy: .public)")
        return FileManager.default.contents(atPath: replyFile).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The exit status, or nil when the process group had to be stopped.
    private static func wait(for pid: pid_t) -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        if let status = reap(pid, until: deadline) { return status }
        kill(-pid, SIGTERM)
        if reap(pid, until: Date().addingTimeInterval(killGrace)) == nil {
            kill(-pid, SIGKILL)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
        return nil
    }

    private static func reap(_ pid: pid_t, until deadline: Date) -> Int32? {
        var status: Int32 = 0
        while Date() < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                return (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            }
            if result < 0, errno != EINTR { return -1 }
            usleep(100_000)
        }
        return nil
    }

    /// Only the three standard descriptors reach the child, whatever the
    /// parent has open. A nil `environment` passes the parent's own.
    private static func spawn(_ executable: String, _ arguments: [String], input: String, output: String, directory: String? = nil,
                              flags: Int32, environment: [String: String]?) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, input, O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        if let directory { posix_spawn_file_actions_addchdir_np(&actions, directory) }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(flags | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { $0.map { strdup("\($0.key)=\($0.value)") } + [nil] }
        defer {
            argv.forEach { free($0) }
            envp?.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = envp.map { posix_spawn(&pid, executable, &actions, &attributes, argv, $0) }
            ?? posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        return result == 0 ? pid : nil
    }
}
