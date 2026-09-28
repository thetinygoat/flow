import Foundation

/// Agent hooks call this, so apart from `ping`, `launch` and `shims` it always exits 0:
/// a Flow that is closed or confused must never fail or slow down the agent.
let environment = ProcessInfo.processInfo.environment

func debug(_ message: String) {
    guard environment["FLOW_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data("flw: \(message)\n".utf8))
}

func send(_ event: AgentEvent, to socket: String) throws {
    guard let fd = UnixSocket.connect(to: socket) else {
        debug("cannot connect to \(socket)")
        return
    }
    if !UnixSocket.write(try event.line(), to: fd) {
        debug("cannot write to \(socket): \(String(cString: strerror(errno)))")
    }
    close(fd)
}

/// Hooks and shims name this path, so it must still work after the shell
/// that ran `flw` has changed directory.
let flw = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]

/// Sends `event`, then keeps what was said for naming the session, and
/// starts naming it when it is due.
func report(_ event: AgentEvent, excerpts: [Excerpt], to socket: String) throws {
    try send(event, to: socket)
    if TitleStore.standard.record(event, excerpts: excerpts, now: Date()) {
        Naming.start(event, flw: flw)
    }
}

do {
    let command = try FlwCommand.parse(
        Array(CommandLine.arguments.dropFirst()),
        environment: environment,
        currentDirectory: FileManager.default.currentDirectoryPath,
        now: Date()
    )
    switch command {
    case .usage:
        FileHandle.standardError.write(Data((FlwCommand.usageText + "\n").utf8))
    case let .ping(socket):
        print(socket)
        guard let fd = UnixSocket.connect(to: socket) else { exit(1) }
        close(fd)
    case let .event(event, excerpts, socket):
        try report(event, excerpts: excerpts, to: socket)
    case let .hook(name, socket):
        guard let adapter = AgentAdapter.named(name) else {
            debug("no agent named \(name)")
            exit(0)
        }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = HookPayload(json: input, agent: adapter.name, environment: environment, now: Date()) else {
            debug("hook input is not a JSON object")
            exit(0)
        }
        if let event = adapter.translate(payload) {
            try report(event, excerpts: adapter.excerpt(payload).map { [$0] } ?? [], to: socket)
        }
    case let .title(name, sessionID, surfaceID, workspaceID, socket):
        guard let adapter = AgentAdapter.named(name) else { exit(0) }
        Naming.run(adapter: adapter, sessionID: sessionID, surfaceID: surfaceID, workspaceID: workspaceID, environment: environment) { event in
            try? send(event, to: socket)
        }
    case let .launch(name, arguments):
        guard let adapter = AgentAdapter.named(name) else {
            FileHandle.standardError.write(Data("flw: no agent named \(name)\n".utf8))
            exit(127)
        }
        guard let launcher = AgentLauncher(adapter, arguments: arguments, environment: environment, flw: flw) else {
            FileHandle.standardError.write(Data("\(adapter.binary): command not found\n".utf8))
            exit(127)
        }
        launcher.exec()
    case let .shims(directory):
        do {
            try AgentShims.install(in: directory, path: environment["PATH"], flw: flw)
        } catch {
            debug("\(error)")
            exit(1)
        }
    case let .refreshAgents(script):
        print(script)
    }
} catch {
    debug("\(error)")
}
exit(0)
