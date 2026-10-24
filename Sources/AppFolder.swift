import Foundation

/// The folder name Flow keeps its config and session under. A debug build
/// keeps its own, so running one beside the installed Flow never changes the
/// installed Flow's settings or windows.
enum AppFolder {
    static let isDebugBuild = Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true
    static let name = isDebugBuild ? "flow-debug" : "flow"
}
