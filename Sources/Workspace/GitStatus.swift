import CoreServices
import Foundation

struct GitStatus: Equatable {
    var branch: String
    var isDirty: Bool
}

/// Where a working tree keeps its git data. In a linked worktree `.git` is a
/// file pointing at the worktree's own git directory, which holds its HEAD and
/// index, while refs live in the common directory shared by every worktree.
struct GitRepository: Hashable {
    var workTree: String
    var gitDir: String
    var commonDir: String

    init(workTree: String, gitDir: String, commonDir: String) {
        self.workTree = workTree
        self.gitDir = gitDir
        self.commonDir = commonDir
    }

    /// The repository whose working tree contains `directory`. Paths are
    /// resolved through symlinks so they match the paths FSEvents reports.
    init?(containing directory: String) {
        guard var current = Self.realPath(directory) else { return nil }
        while true {
            let dotGit = current + "/.git"
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                let gitDir = isDirectory.boolValue ? dotGit : Self.linkedGitDir(dotGit, relativeTo: current)
                if let gitDir = gitDir.flatMap(Self.realPath),
                   FileManager.default.fileExists(atPath: gitDir + "/HEAD") {
                    let common = Self.contents(of: gitDir + "/commondir").map { Self.absolute($0, relativeTo: gitDir) }
                    self.init(workTree: current, gitDir: gitDir, commonDir: common.flatMap(Self.realPath) ?? gitDir)
                    return
                }
            }
            guard current != "/" else { return nil }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    /// The checked-out branch, read from HEAD without running git.
    var branch: String? {
        Self.contents(of: gitDir + "/HEAD").flatMap(Self.branch(head:))
    }

    /// "ref: refs/heads/main" names a branch and a bare commit id is a
    /// detached HEAD. Repositories using the reftable format keep a
    /// placeholder ref in HEAD, so their branch has to come from git.
    static func branch(head: String) -> String? {
        guard head.hasPrefix("ref: ") else { return head.isEmpty ? nil : "detached" }
        let ref = String(head.dropFirst("ref: ".count))
        let branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
        return branch == ".invalid" ? nil : branch
    }

    /// The directories to watch; FSEvents watches each one recursively. A
    /// repository at the home directory, as dotfiles are often kept, would
    /// mean watching everything under it, so only its git data is watched.
    func watchedPaths(home: String? = Self.home) -> [String] {
        var paths: [String] = []
        let candidates = workTree == home ? [gitDir, commonDir] : [workTree, gitDir, commonDir]
        for path in candidates.sorted(by: { $0.count < $1.count }) where !paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            paths.append(path)
        }
        return paths
    }

    /// Whether a changed path can change the branch or the dirty state. Inside
    /// git's own directories only HEAD, the index and refs matter; the rest is
    /// objects, logs and lock files that change constantly while git works.
    func isRelevant(_ path: String) -> Bool {
        if path == gitDir || path.hasPrefix(gitDir + "/") || path == commonDir || path.hasPrefix(commonDir + "/") {
            return path == gitDir + "/HEAD" || path == gitDir + "/index"
                || path == commonDir + "/packed-refs" || path.hasPrefix(commonDir + "/refs/")
        }
        return path == workTree || path.hasPrefix(workTree + "/")
    }

    static let home = realPath(NSHomeDirectory())

    private static func linkedGitDir(_ file: String, relativeTo directory: String) -> String? {
        guard let line = contents(of: file), line.hasPrefix("gitdir: ") else { return nil }
        return absolute(String(line.dropFirst("gitdir: ".count)), relativeTo: directory)
    }

    private static func absolute(_ path: String, relativeTo directory: String) -> String {
        path.hasPrefix("/") ? path : directory + "/" + path
    }

    private static func contents(of path: String) -> String? {
        (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

/// Keeps the branch and dirty state of the repositories behind a set of
/// directories. The branch is read from HEAD as soon as it changes; the dirty
/// state comes from `git status`, run when FSEvents reports a relevant change
/// and never more often than the repository's last run allows, so a slow
/// repository is checked less often.
final class GitStatusMonitor {
    var onUpdate: (() -> Void)?

    private final class Watched {
        let repository: GitRepository
        var branch: String?
        var gitBranch: String?
        var isDirty: Bool?
        var events: FileEvents?
        var isChecking = false
        var needsCheck = false
        var isScheduled = false
        var nextCheck = Date.distantPast

        init(repository: GitRepository) {
            self.repository = repository
            branch = repository.branch
        }
    }

    /// Nil for a directory outside any repository.
    private var repositories: [String: GitRepository?] = [:]
    private var watched: [GitRepository: Watched] = [:]
    private let queue = DispatchQueue(label: "dev.thetinygoat.flow.git", qos: .utility)
    private(set) var finishedChecks = 0

    /// Watches the repositories behind `directories` and stops watching any
    /// others. Each directory's repository is looked up once, until
    /// `forgetDirectories`.
    func watch(_ directories: [String]) {
        include(directories)
        let current = Set(directories.compactMap { repositories[$0] ?? nil })
        for repository in watched.keys where !current.contains(repository) {
            watched.removeValue(forKey: repository)
        }
    }

    /// Also watches the repositories behind `directories`, leaving the rest
    /// watched until the next `watch`. For directories shown only for a
    /// moment, whose repositories are likely to be shown again.
    func include(_ directories: [String]) {
        for directory in directories {
            if !repositories.keys.contains(directory) {
                repositories[directory] = GitRepository(containing: directory)
            }
            if let repository = repositories[directory] ?? nil {
                startWatching(repository)
            }
        }
    }

    /// A `git init` or a deleted repository changes which repository a
    /// directory is in, so each is looked up again on the next `watch`.
    func forgetDirectories() {
        repositories.removeAll()
    }

    private func startWatching(_ repository: GitRepository) {
        guard watched[repository] == nil else { return }
        let state = Watched(repository: repository)
        // Paths are filtered where they arrive, off the main thread; a build
        // can report thousands at a time.
        state.events = FileEvents(paths: repository.watchedPaths()) { [weak self, weak state] paths in
            guard paths.contains(where: repository.isRelevant) else { return }
            let headChanged = paths.contains(repository.gitDir + "/HEAD")
            DispatchQueue.main.async {
                guard let self, let state, self.isCurrent(state) else { return }
                self.handle(headChanged: headChanged, in: state)
            }
        }
        watched[repository] = state
        requestCheck(state)
    }

    func status(for directory: String) -> GitStatus? {
        guard let repository = repositories[directory] ?? nil, let state = watched[repository],
              let branch = state.branch ?? state.gitBranch else { return nil }
        return GitStatus(branch: branch, isDirty: state.isDirty ?? false)
    }

    private func isCurrent(_ state: Watched) -> Bool {
        watched[state.repository] === state
    }

    private func handle(headChanged: Bool, in state: Watched) {
        if headChanged {
            let branch = state.repository.branch
            if branch != state.branch {
                state.branch = branch
                onUpdate?()
            }
        }
        requestCheck(state)
    }

    private func requestCheck(_ state: Watched) {
        guard !state.isChecking else {
            state.needsCheck = true
            return
        }
        guard !state.isScheduled else { return }
        state.isScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, state.nextCheck.timeIntervalSinceNow)) { [weak self, weak state] in
            guard let self, let state, self.isCurrent(state) else { return }
            state.isScheduled = false
            self.check(state)
        }
    }

    private func check(_ state: Watched) {
        state.isChecking = true
        let workTree = state.repository.workTree
        queue.async {
            let started = Date()
            let status = Self.read(workTree)
            let duration = Date().timeIntervalSince(started)
            DispatchQueue.main.async {
                state.isChecking = false
                self.finishedChecks += 1
                guard self.isCurrent(state) else { return }
                state.nextCheck = Date() + Self.delay(after: duration)
                let changed = state.isDirty != status?.isDirty || state.gitBranch != status?.branch
                state.isDirty = status?.isDirty
                state.gitBranch = status?.branch
                if changed { self.onUpdate?() }
                if state.needsCheck {
                    state.needsCheck = false
                    self.requestCheck(state)
                }
            }
        }
    }

    /// How long to wait before the next check. A typical repository answers
    /// in milliseconds and is checked at most once a second while files
    /// change; one that takes longer waits ten times as long as it took.
    static func delay(after duration: TimeInterval) -> TimeInterval {
        min(max(1, duration * 10), 60)
    }

    static let timeout: TimeInterval = 2

    /// Reads a directory's status without running anything the repository
    /// configures. Flow runs this for any directory a terminal reports, and a
    /// program's output can report any directory, so a repository is untrusted:
    /// its config can name commands that plain `git status` would execute, an
    /// fsmonitor hook and clean or process filters. Both are switched off, and
    /// submodules, whose config is not checked, are not entered. Filters are
    /// also marked optional, or a required one, as git-lfs sets, would fail
    /// every status. When the config cannot be read, nothing is run.
    static func read(_ directory: String) -> GitStatus? {
        guard let keys = git(["-C", directory, "config", "--list", "--null", "--name-only"]) else { return nil }
        let arguments = ["-C", directory, "--no-optional-locks", "-c", "core.fsmonitor=false",
                         "status", "--porcelain=v1", "--branch", "--ignore-submodules=all",
                         "--no-ahead-behind", "--no-renames"]
        var parser = GitStatusParser()
        guard git(arguments, config: filterOverrides(keys.split(separator: "\0").map(String.init)),
                  consume: { parser.append($0) }) != nil else { return nil }
        return parser.status
    }

    /// Settings that switch off every filter named in `keys`. A filter name can
    /// contain `=`, which `-c` would split on, so these are passed in the
    /// environment, where git keeps keys and values apart.
    static func filterOverrides(_ keys: [String]) -> [(key: String, value: String)] {
        var names: [String] = []
        for key in keys where key.hasPrefix("filter.") {
            for suffix in [".clean", ".process"] where key.hasSuffix(suffix) {
                let name = String(key.dropFirst("filter.".count).dropLast(suffix.count))
                if !name.isEmpty, !names.contains(name) { names.append(name) }
            }
        }
        return names.flatMap { name in
            [("filter.\(name).clean", ""), ("filter.\(name).process", ""), ("filter.\(name).required", "false")]
        }
    }

    /// `/usr/bin/git` is only a stub until the command-line tools are
    /// installed, and running it asks the user to install them. It is used
    /// only when the selected developer directory has git, otherwise
    /// Homebrew's git; with neither, only the branch is shown.
    static let executable: String? = findGit(
        developerDirectory: output(of: "/usr/bin/xcode-select", ["-p"])?.trimmingCharacters(in: .whitespacesAndNewlines),
        isExecutable: FileManager.default.isExecutableFile(atPath:))

    static func findGit(developerDirectory: String?, isExecutable: (String) -> Bool) -> String? {
        if let developerDirectory, isExecutable(developerDirectory + "/usr/bin/git") {
            return "/usr/bin/git"
        }
        return ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first(where: isExecutable)
    }

    private static func git(_ arguments: [String], config: [(key: String, value: String)] = [], consume: ((Data) -> Void)? = nil) -> String? {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_COUNT"] = String(config.count)
        for (index, setting) in config.enumerated() {
            environment["GIT_CONFIG_KEY_\(index)"] = setting.key
            environment["GIT_CONFIG_VALUE_\(index)"] = setting.value
        }
        return executable.flatMap { output(of: $0, arguments, environment: environment, consume: consume) }
    }

    /// Standard output of a successful run, or nil. A run that outlasts the
    /// timeout is stopped and counts as failed.
    private static func output(of executable: String, _ arguments: [String], environment: [String: String]? = nil, consume: ((Data) -> Void)? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // waitUntilExit polls, adding about 65 ms to every run.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data: Data
        if let consume {
            while true {
                let chunk = output.fileHandleForReading.readData(ofLength: 64 * 1024)
                guard !chunk.isEmpty else { break }
                consume(chunk)
            }
            data = Data()
        } else {
            data = output.fileHandleForReading.readDataToEndOfFile()
        }
        exited.wait()
        deadline.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A recursive FSEvents stream delivering changed file paths on a background queue.
private final class FileEvents {
    private static let queue = DispatchQueue(label: "dev.thetinygoat.flow.file-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init(paths: [String], handler: @escaping ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let events = Unmanaged<FileEvents>.fromOpaque(info).takeUnretainedValue()
            events.handler(Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? [])
        }
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(flags)) else { return }
        FSEventStreamSetDispatchQueue(stream, Self.queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// Torn down on the stream's own queue, so no callback is still running
    /// when this object goes away.
    deinit {
        guard let stream else { return }
        Self.queue.sync {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

extension GitStatus {
    /// Parses `git status --porcelain=v1 --branch` output.
    init?(porcelain text: String) {
        var parser = GitStatusParser()
        parser.append(Data(text.utf8))
        guard let status = parser.status else { return nil }
        self = status
    }

    static func branch(fromHeader header: String) -> String? {
        guard header.hasPrefix("## ") else { return nil }
        var branch = String(header.dropFirst(3))
        if let range = branch.range(of: "...") {
            branch = String(branch[..<range.lowerBound])
        }
        if branch.hasPrefix("No commits yet on ") {
            branch = String(branch.dropFirst("No commits yet on ".count))
        }
        if branch.hasPrefix("HEAD ") {
            branch = "detached"
        }
        return branch
    }
}

/// The sidebar needs the branch and a dirty bit, regardless of how many files changed.
struct GitStatusParser {
    private var header = Data()
    private var hasHeader = false
    private var isDirty = false
    private var invalid = false

    mutating func append(_ data: Data) {
        guard !invalid else { return }
        var remainder = data[...]
        if !hasHeader {
            if let newline = remainder.firstIndex(of: 10) {
                header.append(contentsOf: remainder[..<newline])
                hasHeader = true
                remainder = remainder[remainder.index(after: newline)...]
            } else {
                header.append(remainder)
                remainder = Data()
            }
            if header.count > 64 * 1024 {
                header.removeAll()
                invalid = true
                return
            }
        }
        isDirty = isDirty || remainder.contains { $0 != 10 }
    }

    var status: GitStatus? {
        guard !invalid, let text = String(data: header, encoding: .utf8),
              let branch = GitStatus.branch(fromHeader: text) else { return nil }
        return GitStatus(branch: branch, isDirty: isDirty)
    }
}
