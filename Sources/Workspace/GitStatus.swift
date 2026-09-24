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

    /// The directories to watch; FSEvents watches each one recursively.
    var watchedPaths: [String] {
        var paths: [String] = []
        for path in [workTree, gitDir, commonDir].sorted(by: { $0.count < $1.count }) where !paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
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

    private var repositories: [String: GitRepository] = [:]
    private var watched: [GitRepository: Watched] = [:]
    private let queue = DispatchQueue(label: "dev.thetinygoat.flow.git", qos: .utility)
    private(set) var finishedChecks = 0

    /// Watches the repositories behind `directories` and stops watching any
    /// others. Directories are resolved again on every call, so a `git init`
    /// or a deleted repository is picked up on the next change of directory.
    func watch(_ directories: [String]) {
        repositories = Dictionary(directories.compactMap { directory in
            GitRepository(containing: directory).map { (directory, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let current = Set(repositories.values)
        for repository in watched.keys where !current.contains(repository) {
            watched.removeValue(forKey: repository)
        }
        for repository in current where watched[repository] == nil {
            let state = Watched(repository: repository)
            state.events = FileEvents(paths: repository.watchedPaths) { [weak self, weak state] paths in
                guard let self, let state else { return }
                self.handle(paths, in: state)
            }
            watched[repository] = state
            requestCheck(state)
        }
    }

    func status(for directory: String) -> GitStatus? {
        guard let repository = repositories[directory], let state = watched[repository],
              let branch = state.branch ?? state.gitBranch else { return nil }
        return GitStatus(branch: branch, isDirty: state.isDirty ?? false)
    }

    private func handle(_ paths: [String], in state: Watched) {
        let relevant = paths.filter(state.repository.isRelevant)
        guard !relevant.isEmpty else { return }
        if relevant.contains(state.repository.gitDir + "/HEAD") {
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
            guard let self, let state, self.watched[state.repository] === state else { return }
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
    /// submodules, whose config is not checked, are not entered.
    static func read(_ directory: String) -> GitStatus? {
        var arguments = ["-C", directory, "--no-optional-locks", "-c", "core.fsmonitor=false"]
        let filters = git(["-C", directory, "config", "--null", "--name-only", "--get-regexp", #"^filter\..*\.(clean|process)$"#])
        for key in (filters ?? "").split(separator: "\0") {
            arguments += ["-c", "\(key)="]
        }
        arguments += ["status", "--porcelain=v1", "--branch", "--ignore-submodules=all"]
        return git(arguments).flatMap(GitStatus.init(porcelain:))
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

    private static func git(_ arguments: [String]) -> String? {
        executable.flatMap { output(of: $0, arguments) }
    }

    /// Standard output of a successful run, or nil. A run that outlasts the
    /// timeout is stopped and counts as failed.
    private static func output(of executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        deadline.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A recursive FSEvents stream delivering changed file paths on the main queue.
private final class FileEvents {
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
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

extension GitStatus {
    /// Parses `git status --porcelain=v1 --branch` output.
    init?(porcelain text: String) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first, header.hasPrefix("## ") else { return nil }
        lines.removeFirst()

        // "## main...origin/main [ahead 1]" or "## HEAD (no branch)" or "## No commits yet on main"
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
        self.init(branch: branch, isDirty: !lines.isEmpty)
    }
}
