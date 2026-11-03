import AppKit
import CryptoKit

/// A clipboard image pastes as the path of a PNG file holding it, the way a
/// copied image file does, because a terminal can only paste text. Files are
/// named by their contents so pasting the same image again reuses its file.
enum PastedImage {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "flow-pasted-images")

    static func save(from pasteboard: NSPasteboard, in folder: URL = folder) -> URL? {
        guard let png = png(from: pasteboard) else { return nil }
        let name = SHA256.hash(data: png).prefix(8).map { String(format: "%02x", $0) }.joined()
        let url = folder.appending(path: "\(name).png")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("could not save pasted image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func png(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = NSImage(pasteboard: pasteboard)?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
