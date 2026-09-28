import Foundation

/// Agent hooks call this, so apart from `ping` it always exits 0: a Flow that
/// is closed or confused must never fail or slow down the agent.
let environment = ProcessInfo.processInfo.environment

func debug(_ message: String) {
    guard environment["FLOW_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data("flw: \(message)\n".utf8))
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
    case let .event(event, socket):
        guard let fd = UnixSocket.connect(to: socket) else {
            debug("cannot connect to \(socket)")
            exit(0)
        }
        if !UnixSocket.write(try event.line(), to: fd) {
            debug("cannot write to \(socket): \(String(cString: strerror(errno)))")
        }
        close(fd)
    }
} catch {
    debug("\(error)")
}
exit(0)
