import Foundation

/// Agent hooks call this, so apart from `ping`, `launch` and `shims` it always exits 0:
/// a Flow that is closed or confused must never fail or slow down the agent.
let environment = ProcessInfo.processInfo.environment
/// A hook that gave up on Flow can still reach it after the next one, so
/// events carry when `flw` started, not when it finished reading.
let now = Date()

func debug(_ message: String) {
    guard environment["FLOW_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data("flw: \(message)\n".utf8))
}

/// Outside Flow there is no FLOW_SOCKET, so `flw` talks to the Flow started last.
func resolve(_ socket: String?) -> String? {
    socket ?? AgentEnvironment.newestRunningSocket()?.path
}

func send(_ event: AgentEvent, to socket: String?) throws {
    guard let socket = resolve(socket) else {
        debug("no Flow is running")
        return
    }
    guard let fd = UnixSocket.connect(to: socket) else {
        debug("cannot connect to \(socket)")
        return
    }
    if UnixSocket.write(try event.line(), to: fd) {
        UnixSocket.awaitClose(fd)
    } else {
        debug("cannot write to \(socket): \(String(cString: strerror(errno)))")
    }
    close(fd)
}

/// Agents wait for their hooks, so `flw` gives up on Flow after this long,
/// whatever it is doing, rather than hold one up.
func exitAtDeadline() {
    signal(SIGALRM) { _ in _exit(0) }
    var timer = itimerval(it_interval: timeval(), it_value: timeval(tv_sec: 0, tv_usec: 300_000))
    setitimer(ITIMER_REAL, &timer, nil)
}

/// Hooks and shims name this path, so it must still work after the shell
/// that ran `flw` has changed directory.
let flw = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]

do {
    let command = try FlwCommand.parse(
        Array(CommandLine.arguments.dropFirst()),
        environment: environment,
        currentDirectory: FileManager.default.currentDirectoryPath,
        now: now
    )
    switch command {
    case .usage:
        FileHandle.standardError.write(Data((FlwCommand.usageText + "\n").utf8))
    case let .ping(socket):
        guard let socket = resolve(socket) else {
            FileHandle.standardError.write(Data("flw: no Flow is running\n".utf8))
            exit(1)
        }
        print(socket)
        guard let fd = UnixSocket.connect(to: socket) else { exit(1) }
        close(fd)
    case let .event(event, socket):
        exitAtDeadline()
        try send(event, to: socket)
    case let .hook(name, socket):
        exitAtDeadline()
        guard let adapter = AgentAdapter.named(name) else {
            debug("no agent named \(name)")
            exit(0)
        }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = HookPayload(json: input, agent: adapter.name, environment: environment, now: now) else {
            debug("hook input is not a JSON object")
            exit(0)
        }
        if let event = adapter.translate(payload) {
            try send(event, to: socket)
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
