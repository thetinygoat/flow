import AppKit

/// Finder's "New Flow Workspace Here" and "New Flow Window Here" services.
/// A selected file opens its folder.
final class ServiceProvider: NSObject {
    private let open: (_ directory: String, _ newWindow: Bool) -> Void

    init(open: @escaping (_ directory: String, _ newWindow: Bool) -> Void) {
        self.open = open
    }

    @objc func openWorkspace(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(from: pasteboard, newWindow: false, error: error)
    }

    @objc func openWindow(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(from: pasteboard, newWindow: true, error: error)
    }

    private func open(from pasteboard: NSPasteboard, newWindow: Bool, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else {
            error.pointee = "No folder was selected."
            return
        }
        for directory in Self.directories(for: urls) {
            open(directory, newWindow)
        }
    }

    static func directories(for urls: [URL]) -> [String] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            let path = directory.path(percentEncoded: false)
            return seen.insert(path).inserted ? path : nil
        }
    }
}
