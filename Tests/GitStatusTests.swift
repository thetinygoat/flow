import XCTest

final class GitStatusTests: XCTestCase {
    func testCleanBranchWithUpstream() {
        let status = GitStatus(porcelain: "## main...origin/main [ahead 1]\n")
        XCTAssertEqual(status, GitStatus(branch: "main", isDirty: false))
    }

    func testDirtyWhenAnyFileListed() {
        let status = GitStatus(porcelain: "## feature\n M Sources/a.swift\n?? new.txt\n")
        XCTAssertEqual(status, GitStatus(branch: "feature", isDirty: true))
    }

    func testDetachedHead() {
        XCTAssertEqual(GitStatus(porcelain: "## HEAD (no branch)\n")?.branch, "detached")
    }

    func testNoCommitsYet() {
        XCTAssertEqual(GitStatus(porcelain: "## No commits yet on main\n")?.branch, "main")
    }

    func testNotARepositoryOutputIsNil() {
        XCTAssertNil(GitStatus(porcelain: ""))
        XCTAssertNil(GitStatus(porcelain: "fatal: not a git repository\n"))
    }

    // MARK: Untrusted repositories

    private func makeRepository() throws -> (repo: URL, sentinels: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try shell("git init -q -b main && git config user.email t@t && git config user.name t && echo a > f.txt && git add . && git commit -q -m init", in: repo)
        return (repo, root)
    }

    @discardableResult
    private func shell(_ command: String, in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testReadsRealRepository() throws {
        let (repo, _) = try makeRepository()
        XCTAssertEqual(GitStatusMonitor.read(repo.path)?.isDirty, false)
        try shell("echo b > f.txt", in: repo)
        XCTAssertEqual(GitStatusMonitor.read(repo.path)?.isDirty, true)
        XCTAssertNotNil(GitStatusMonitor.read(repo.path)?.branch)
    }

    func testRepositoryConfigCannotRunCommands() throws {
        let (repo, sentinels) = try makeRepository()
        let fsmonitor = sentinels.appendingPathComponent("fsmonitor-ran").path
        let clean = sentinels.appendingPathComponent("clean-ran").path
        let process = sentinels.appendingPathComponent("process-ran").path
        // Everything is committed before the traps are set, so only the read
        // under test can trigger them.
        try shell("""
            echo x > notes.md && git add notes.md && git commit -q -m notes
            git config core.fsmonitor 'touch \(fsmonitor); false'
            git config filter.evil.clean 'touch \(clean); cat'
            git config filter.sneaky.process 'touch \(process); false'
            echo '*.txt filter=evil' > .gitattributes
            echo '*.md filter=sneaky' > .git/info/attributes
            echo y > notes.md && echo b > f.txt
            """, in: repo)

        let status = GitStatusMonitor.read(repo.path)

        XCTAssertEqual(status?.isDirty, true, "status still works")
        for sentinel in [fsmonitor, clean, process] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel), "\(sentinel) was executed")
        }
    }

    func testRequiredFilterFailsClosed() throws {
        let (repo, sentinels) = try makeRepository()
        let clean = sentinels.appendingPathComponent("clean-ran").path
        try shell("""
            git config filter.evil.clean 'touch \(clean); cat'
            git config filter.evil.required true
            echo '*.txt filter=evil' > .gitattributes && echo b > f.txt
            """, in: repo)

        XCTAssertNil(GitStatusMonitor.read(repo.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: clean))
    }

    // MARK: Finding the repository

    func testFindsRepositoryFromSubdirectory() throws {
        let (repo, _) = try makeRepository()
        try shell("mkdir -p a/b", in: repo)
        let found = try XCTUnwrap(GitRepository(containing: repo.appendingPathComponent("a/b").path))
        let root = realPath(repo)
        XCTAssertEqual(found, GitRepository(workTree: root, gitDir: root + "/.git", commonDir: root + "/.git"))
        XCTAssertEqual(found.watchedPaths, [root])
        XCTAssertEqual(found.branch, "main")
    }

    func testLinkedWorktreeHasItsOwnHeadAndSharedRefs() throws {
        let (repo, root) = try makeRepository()
        try shell("git worktree add -q -b feature ../wt", in: repo)
        let worktree = try XCTUnwrap(GitRepository(containing: root.appendingPathComponent("wt").path))
        let main = realPath(repo)
        XCTAssertEqual(worktree.workTree, realPath(root) + "/wt")
        XCTAssertEqual(worktree.gitDir, main + "/.git/worktrees/wt")
        XCTAssertEqual(worktree.commonDir, main + "/.git")
        XCTAssertEqual(Set(worktree.watchedPaths), [main + "/.git", realPath(root) + "/wt"])
        XCTAssertEqual(worktree.branch, "feature")
        XCTAssertEqual(GitRepository(containing: repo.path)?.branch, "main")
    }

    func testRelativeGitdirFile() throws {
        let (repo, root) = try makeRepository()
        try shell("mv .git ../moved.git && echo 'gitdir: ../moved.git' > .git", in: repo)
        let found = try XCTUnwrap(GitRepository(containing: repo.path))
        XCTAssertEqual(found.gitDir, realPath(root) + "/moved.git")
        XCTAssertEqual(found.branch, "main")
    }

    func testBranchFromHead() {
        XCTAssertEqual(GitRepository.branch(head: "ref: refs/heads/feature/x"), "feature/x")
        XCTAssertEqual(GitRepository.branch(head: "3f2a9c0e1b7d4a6f8e2c1d0b9a8f7e6d5c4b3a21"), "detached")
        XCTAssertNil(GitRepository.branch(head: "ref: refs/heads/.invalid"), "reftable placeholder")
        XCTAssertNil(GitRepository.branch(head: ""))
    }

    func testOnlyHeadIndexAndRefsMatterInsideGit() {
        let repository = GitRepository(workTree: "/r", gitDir: "/r/.git/worktrees/w", commonDir: "/r/.git")
        for path in ["/r/src/a.swift", "/r", "/r/.git/worktrees/w/HEAD", "/r/.git/worktrees/w/index",
                     "/r/.git/refs/heads/main", "/r/.git/packed-refs"] {
            XCTAssertTrue(repository.isRelevant(path), path)
        }
        for path in ["/r/.git/objects/ab/cdef", "/r/.git/index.lock", "/r/.git/logs/HEAD",
                     "/r/.git/worktrees/other/HEAD", "/r/.git/HEAD", "/elsewhere/a", "/rr/a"] {
            XCTAssertFalse(repository.isRelevant(path), path)
        }
    }

    // MARK: Watching

    private func waitForChecks(_ monitor: GitStatusMonitor, _ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date() + 5
        while monitor.finishedChecks < count, Date() < deadline {
            RunLoop.main.run(until: Date() + 0.05)
        }
        XCTAssertEqual(monitor.finishedChecks, count, file: file, line: line)
    }

    private func waitForStatus(_ monitor: GitStatusMonitor, _ directory: String, toBe expected: GitStatus,
                               file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date() + 5
        while monitor.status(for: directory) != expected, Date() < deadline {
            RunLoop.main.run(until: Date() + 0.05)
        }
        XCTAssertEqual(monitor.status(for: directory), expected, file: file, line: line)
    }

    func testDirtyStateFollowsFileChanges() throws {
        let (repo, _) = try makeRepository()
        let monitor = GitStatusMonitor()
        monitor.watch([repo.path])
        XCTAssertEqual(monitor.status(for: repo.path)?.branch, "main", "branch is known before git runs")
        waitForChecks(monitor, 1)
        XCTAssertEqual(monitor.status(for: repo.path), GitStatus(branch: "main", isDirty: false))

        try shell("echo new > untracked.txt", in: repo)
        waitForStatus(monitor, repo.path, toBe: GitStatus(branch: "main", isDirty: true))

        try shell("rm untracked.txt", in: repo)
        waitForStatus(monitor, repo.path, toBe: GitStatus(branch: "main", isDirty: false))
    }

    func testBranchSwitchInWorktree() throws {
        let (repo, root) = try makeRepository()
        try shell("git worktree add -q -b feature ../wt", in: repo)
        let worktree = root.appendingPathComponent("wt").path
        let monitor = GitStatusMonitor()
        monitor.watch([repo.path, worktree])
        waitForChecks(monitor, 2)
        XCTAssertEqual(monitor.status(for: worktree), GitStatus(branch: "feature", isDirty: false))

        try shell("git switch -q -c other", in: root.appendingPathComponent("wt"))
        waitForStatus(monitor, worktree, toBe: GitStatus(branch: "other", isDirty: false))
        XCTAssertEqual(monitor.status(for: repo.path)?.branch, "main")
    }

    func testQuietRepositoryIsNotCheckedAgain() throws {
        let (repo, _) = try makeRepository()
        let monitor = GitStatusMonitor()
        monitor.watch([repo.path])
        waitForChecks(monitor, 1)
        RunLoop.main.run(until: Date() + 2)
        XCTAssertEqual(monitor.finishedChecks, 1, "git's own reads must not trigger further checks")
    }

    func testStopsWatchingDirectoriesNoLongerShown() throws {
        let (repo, _) = try makeRepository()
        let monitor = GitStatusMonitor()
        monitor.watch([repo.path])
        waitForChecks(monitor, 1)
        monitor.watch([])
        XCTAssertNil(monitor.status(for: repo.path))
        try shell("echo b > f.txt", in: repo)
        RunLoop.main.run(until: Date() + 1.5)
        XCTAssertEqual(monitor.finishedChecks, 1)
    }

    func testSlowRepositoriesAreCheckedLessOften() {
        XCTAssertEqual(GitStatusMonitor.delay(after: 0.01), 1)
        XCTAssertEqual(GitStatusMonitor.delay(after: 0.5), 5)
        XCTAssertEqual(GitStatusMonitor.delay(after: GitStatusMonitor.timeout), 20)
        XCTAssertEqual(GitStatusMonitor.delay(after: 30), 60)
    }

    private func realPath(_ url: URL) -> String {
        let resolved = realpath(url.path, nil)!
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: Finding git

    func testUsesSystemGitWhenDeveloperToolsHaveIt() {
        let present: Set = ["/Library/Developer/CommandLineTools/usr/bin/git", "/opt/homebrew/bin/git"]
        XCTAssertEqual(GitStatusMonitor.findGit(developerDirectory: "/Library/Developer/CommandLineTools", isExecutable: present.contains), "/usr/bin/git")
    }

    func testAvoidsTheInstallPromptWithoutDeveloperTools() {
        let homebrew: Set = ["/opt/homebrew/bin/git"]
        XCTAssertEqual(GitStatusMonitor.findGit(developerDirectory: nil, isExecutable: homebrew.contains), "/opt/homebrew/bin/git")
        XCTAssertEqual(GitStatusMonitor.findGit(developerDirectory: "/Applications/Xcode.app/Contents/Developer", isExecutable: homebrew.contains),
                       "/opt/homebrew/bin/git", "a selected directory that was deleted")
        XCTAssertEqual(GitStatusMonitor.findGit(developerDirectory: nil, isExecutable: ["/usr/local/bin/git"].contains), "/usr/local/bin/git")
        XCTAssertNil(GitStatusMonitor.findGit(developerDirectory: nil, isExecutable: { _ in false }))
    }

    func testFindsGitOnThisMac() {
        XCTAssertNotNil(GitStatusMonitor.executable)
    }

    func testNotARepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(GitStatusMonitor.read(directory.path))
    }
}
