import AppKit
import GhosttyKit
import UniformTypeIdentifiers

/// One representation of the clipboard, such as its text or an image.
struct ClipboardContent {
    let mime: String
    let data: Data

    /// Copies contents that libghostty lends only for the duration of a callback.
    static func copy(_ contents: UnsafePointer<ghostty_clipboard_content_s>?, count: Int) -> [ClipboardContent] {
        guard let contents else { return [] }
        return (0..<count).compactMap { index in
            let content = contents[index]
            guard let mime = content.mime else { return nil }
            let data = content.data.map { Data(bytes: $0, count: content.len) } ?? Data()
            return ClipboardContent(mime: String(cString: mime), data: data)
        }
    }

    /// The text when there is some, since a confirmation sheet can only show text.
    static func summary(_ contents: [ClipboardContent]) -> String {
        if let text = contents.first(where: { $0.mime == "text/plain" }), let string = String(data: text.data, encoding: .utf8) {
            return string
        }
        return contents.map { "\($0.mime) (\($0.data.count) bytes)" }.joined(separator: "\n")
    }

    static func complete(
        _ surface: ghostty_surface_t,
        state: UnsafeMutableRawPointer?,
        contents: [ClipboardContent],
        available: [String],
        confirmed: Bool = false
    ) {
        var allocations: [UnsafeMutableRawPointer] = []
        defer { allocations.forEach { free($0) } }
        func cString(_ string: String) -> UnsafePointer<CChar> {
            let pointer = strdup(string)!
            allocations.append(pointer)
            return UnsafePointer(pointer)
        }

        let cContents = contents.map { content in
            let buffer = malloc(max(content.data.count, 1))!
            allocations.append(buffer)
            content.data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: content.data.count)
            return ghostty_clipboard_content_s(
                mime: cString(content.mime),
                data: buffer.assumingMemoryBound(to: CChar.self),
                len: content.data.count)
        }
        let cAvailable: [UnsafePointer<CChar>?] = available.map(cString)

        cContents.withUnsafeBufferPointer { contentsBuffer in
            cAvailable.withUnsafeBufferPointer { availableBuffer in
                var complete = ghostty_clipboard_complete_s(
                    contents: contentsBuffer.baseAddress,
                    contents_len: contentsBuffer.count,
                    available: availableBuffer.baseAddress,
                    available_len: availableBuffer.count,
                    confirmed: confirmed,
                    remember: false)
                ghostty_surface_complete_clipboard_request(surface, &complete, state)
            }
        }
    }
}

extension NSPasteboard.PasteboardType {
    init?(mimeType: String) {
        if mimeType == "text/plain" {
            self = .string
            return
        }
        guard let utType = UTType(mimeType: mimeType) else {
            self.init(mimeType)
            return
        }
        self.init(utType.identifier)
    }
}

extension NSPasteboard {
    /// The pasteboard used for Ghostty's selection clipboard (middle-click paste style).
    static let ghosttySelection = NSPasteboard(name: .init("dev.thetinygoat.flow.selection"))

    static func ghostty(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD: return .general
        case GHOSTTY_CLIPBOARD_SELECTION: return ghosttySelection
        default: return nil
        }
    }

    /// File URLs become escaped paths, anything else falls back to the plain string.
    func getOpinionatedStringContents() -> String? {
        if let urls = readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls
                .map { $0.isFileURL ? Ghostty.shellEscape($0.path) : $0.absoluteString }
                .joined(separator: " ")
        }
        return string(forType: .string)
    }

    /// Text is what a paste would type, so copied files read as their escaped
    /// paths. Copied files are also served as a URI list, as on Linux.
    func ghosttyData(forMime mime: String) -> Data? {
        switch mime {
        case "text/plain":
            return getOpinionatedStringContents().map { Data($0.utf8) }
        case "text/uri-list":
            let urls = readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.isEmpty ? nil : Data(urls.map { $0.absoluteString + "\r\n" }.joined().utf8)
        default:
            return NSPasteboard.PasteboardType(mimeType: mime).flatMap { data(forType: $0) }
        }
    }

    /// Worked out from the declared types alone, because listing the
    /// clipboard must not make the apps that own it produce their contents.
    func ghosttyAvailableMimes() -> [String] {
        let types = types ?? []
        let hasFiles = types.contains(.fileURL)
        let mimes = types.compactMap { type -> String? in
            guard let mime = UTType(type.rawValue)?.preferredMIMEType else { return nil }
            return mime == "text/plain;charset=utf-8" ? "text/plain" : mime
        }

        var leading: [String] = []
        if hasFiles || mimes.contains("text/plain") { leading.append("text/plain") }
        if hasFiles { leading.append("text/uri-list") }
        var seen = Set<String>()
        return (leading + mimes).filter { seen.insert($0).inserted }
    }
}
