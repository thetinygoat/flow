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
}
