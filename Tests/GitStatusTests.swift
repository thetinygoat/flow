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
        try shell("git init -q && git config user.email t@t && git config user.name t && echo a > f.txt && git add . && git commit -q -m init", in: repo)
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

    func testNotARepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(GitStatusMonitor.read(directory.path))
    }
}
