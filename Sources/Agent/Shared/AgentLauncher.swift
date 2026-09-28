import Foundation

/// What `flw launch` runs in place of the agent the user typed: the real
/// binary, found on PATH past the shim that called it, with the adapter's
/// changes to its arguments or environment.
struct AgentLauncher: Equatable {
    var executable: String
    /// Including `argv[0]`.
    var arguments: [String]
    var environment: [String: String]

    /// Nil when the agent's binary is nowhere on PATH but in the shim directory.
    init?(_ adapter: AgentAdapter, arguments: [String], environment: [String: String], flw: String) {
        var environment = environment
        let shims = environment.removeValue(forKey: AgentEnvironment.shimDirectoryKey)
        guard let executable = Self.resolve(adapter.binary, path: environment["PATH"], excluding: shims) else { return nil }
        self.executable = executable
        var arguments = arguments
        if environment[AgentEnvironment.disabledKey] == nil {
            switch adapter.launch {
            case let .flags(rewrite):
                arguments = rewrite(arguments, flw)
            case let .environment(variables):
                environment.merge(variables(environment, flw)) { $1 }
            case .none:
                break
            }
        }
        self.arguments = [adapter.binary] + arguments
        self.environment = environment
    }

    /// The first executable file named `binary` in `path`, skipping `excluding`
    /// and the empty entries a shell would read as the current directory.
    static func resolve(_ binary: String, path: String?, excluding: String? = nil) -> String? {
        let excluded = excluding.map(standardized)
        for directory in (path ?? "").split(separator: ":").map(String.init) where standardized(directory) != excluded {
            let candidate = (directory as NSString).appendingPathComponent(binary)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func standardized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    func exec() -> Never {
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        execve(executable, argv, envp)
        FileHandle.standardError.write(Data("flw: \(executable): \(String(cString: strerror(errno)))\n".utf8))
        exit(126)
    }
}

/// The per-terminal directory of scripts that stand in for agent binaries,
/// so typing an agent's name runs it through `flw launch`.
enum AgentShims {
    static let rootName = "flow-shims"

    static func directory(surface: String, temporaryDirectory: String) -> String {
        (temporaryDirectory as NSString).appendingPathComponent("\(rootName)/\(surface)")
    }

    /// `path` without the shim directories of any Flow terminal, so that what
    /// runs from it reaches the real agents.
    static func removingShims(from path: String) -> String {
        path.split(separator: ":", omittingEmptySubsequences: false)
            .filter { ((String($0) as NSString).deletingLastPathComponent as NSString).lastPathComponent != rootName }
            .joined(separator: ":")
    }

    static func script(for adapter: AgentAdapter, directory: String, flw: String) -> String {
        """
        #!/bin/sh
        \(AgentEnvironment.shimDirectoryKey)=\(directory.shellQuoted) exec \(flw.shellQuoted) launch \(adapter.name) "$@"

        """
    }

    /// Writes a shim for each adapter whose binary is on `path`, and removes
    /// shims for binaries that have gone. Other files in `directory` are left alone.
    static func install(in directory: String, path: String?, flw: String, adapters: [AgentAdapter] = AgentAdapter.all) throws {
        let files = FileManager.default
        try files.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for adapter in adapters {
            let shim = (directory as NSString).appendingPathComponent(adapter.binary)
            guard AgentLauncher.resolve(adapter.binary, path: path, excluding: directory) != nil else {
                if files.fileExists(atPath: shim) { try files.removeItem(atPath: shim) }
                continue
            }
            let contents = Data(script(for: adapter, directory: directory, flw: flw).utf8)
            if files.contents(atPath: shim) != contents {
                try contents.write(to: URL(fileURLWithPath: shim), options: .atomic)
            }
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim)
        }
    }

    /// Removes the shim directories of terminals that no longer exist.
    static func removeStale(temporaryDirectory: String, isLive: (UUID) -> Bool) {
        let root = (temporaryDirectory as NSString).appendingPathComponent(rootName)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where !(UUID(uuidString: name).map(isLive) ?? false) {
            try? FileManager.default.removeItem(atPath: (root as NSString).appendingPathComponent(name))
        }
    }
}
