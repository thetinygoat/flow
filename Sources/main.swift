import AppKit
import GhosttyKit

// libghostty keeps the environment it sees at init, and setenv can free that
// copy, so the environment must be final before ghostty_init.
if let resources = Bundle.main.resourcePath {
    let directory = (resources as NSString).appendingPathComponent("shell-integration")
    for (key, value) in ShellIntegration.environment(directory: directory, current: ProcessInfo.processInfo.environment) {
        setenv(key, value, 1)
    }
}

if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    FileHandle.standardError.write(Data("ghostty_init failed\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
