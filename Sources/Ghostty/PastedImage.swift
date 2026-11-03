import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// A clipboard image pastes as the path of a PNG file holding it, the way a
/// copied image file does, because a terminal can only paste text. Files are
/// named by their contents so copying the same image again reuses its file.
enum PastedImage {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "flow-pasted-images")

    /// Programs can read the clipboard as often as they like, and each read
    /// asks for the image's path, so the file is remembered until the
    /// clipboard changes instead of being encoded again.
    private static var saved: (pasteboard: NSPasteboard.Name, changeCount: Int, url: URL)?

    /// Found from the declared types alone, so asking does not make the app
    /// that owns the clipboard produce the image.
    static func type(in pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType? {
        let types = pasteboard.types ?? []
        if types.contains(.png) { return .png }
        return types.first { UTType($0.rawValue)?.conforms(to: .image) == true }
    }

    static func save(from pasteboard: NSPasteboard) -> URL? {
        if let saved, saved.pasteboard == pasteboard.name, saved.changeCount == pasteboard.changeCount,
           FileManager.default.fileExists(atPath: saved.url.path) {
            return saved.url
        }
        let changeCount = pasteboard.changeCount
        guard let png = png(from: pasteboard) else { return nil }
        let name = SHA256.hash(data: png).prefix(8).map { String(format: "%02x", $0) }.joined()
        let url = folder.appending(path: "\(name).png")
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try png.write(to: url, options: .atomic)
            }
        } catch {
            logger.error("could not save pasted image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        saved = (pasteboard.name, changeCount, url)
        return url
    }

    private static func png(from pasteboard: NSPasteboard) -> Data? {
        guard let type = type(in: pasteboard), let data = pasteboard.data(forType: type) else { return nil }
        if type == .png { return data }
        return NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }
}
