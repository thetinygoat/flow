import Foundation

struct GitStatus: Equatable {
    var branch: String
    var isDirty: Bool
}

/// Looks up the git branch and dirty state for directories, off the main
/// thread, with a short cache so sidebar refreshes don't spawn git each time.
final class GitStatusMonitor {
    var onUpdate: (() -> Void)?

    private struct Entry {
        var status: GitStatus?
        var fetchedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "dev.thetinygoat.flow.git", qos: .utility)
    private let maxAge: TimeInterval = 5

    /// Returns the last known status and refreshes it in the background when stale.
    func status(for directory: String) -> GitStatus? {
        let entry = cache[directory]
        if entry == nil || Date().timeIntervalSince(entry!.fetchedAt) > maxAge {
            fetch(directory)
        }
        return entry?.status
    }

    private func fetch(_ directory: String) {
        guard !inFlight.contains(directory) else { return }
        inFlight.insert(directory)
        queue.async {
            let status = Self.run(in: directory)
            DispatchQueue.main.async {
                self.inFlight.remove(directory)
                let changed = self.cache[directory]?.status != status
                self.cache[directory] = Entry(status: status, fetchedAt: Date())
                if changed { self.onUpdate?() }
            }
        }
    }

    private static func run(in directory: String) -> GitStatus? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "--no-optional-locks", "status", "--porcelain=v1", "--branch"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }

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
        return GitStatus(branch: branch, isDirty: !lines.isEmpty)
    }
}
