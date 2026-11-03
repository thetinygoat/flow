import AppKit
import XCTest

final class PastedImageTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var savedPaths: [String] = []

    override func setUp() {
        pasteboard = NSPasteboard(name: .init("dev.thetinygoat.flowTests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        savedPaths.forEach { try? FileManager.default.removeItem(atPath: $0) }
    }

    /// A random image, so no other test or earlier run already saved it.
    private func pngData() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<2 {
            for y in 0..<2 {
                rep.setColor(NSColor(deviceRed: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1), atX: x, y: y)
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }

    private func pastedPath() throws -> String {
        let path = try XCTUnwrap(pasteboard.getOpinionatedStringContents())
        savedPaths.append(path)
        return path
    }

    private func copy(_ data: Data, as type: NSPasteboard.PasteboardType) {
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
    }

    func testImagePastesAsPathOfItsFile() throws {
        let png = pngData()
        copy(png, as: .png)

        let path = try pastedPath()
        XCTAssertTrue(path.hasPrefix(PastedImage.folder.path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), png)
        XCTAssertEqual(try pastedPath(), path)
        XCTAssertEqual(pasteboard.ghosttyAvailableMimes().first, "text/plain")
    }

    func testSameImageCopiedAgainReusesItsFile() throws {
        let png = pngData()
        copy(png, as: .png)
        let first = try pastedPath()
        copy(png, as: .png)

        XCTAssertEqual(try pastedPath(), first)
    }

    func testDeletedFileIsSavedAgain() throws {
        copy(pngData(), as: .png)
        let path = try pastedPath()
        try FileManager.default.removeItem(atPath: path)

        XCTAssertEqual(try pastedPath(), path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testTIFFIsSavedAsPNG() throws {
        copy(try XCTUnwrap(NSBitmapImageRep(data: pngData())?.tiffRepresentation), as: .tiff)

        let saved = try Data(contentsOf: URL(fileURLWithPath: try pastedPath()))
        XCTAssertEqual(saved.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(pasteboard.ghosttyAvailableMimes().first, "text/plain")
    }

    func testUndecodableTypeGivesWayToTheNext() throws {
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: pngData())?.tiffRepresentation)
        pasteboard.declareTypes([.init("public.jpeg"), .tiff], owner: nil)
        pasteboard.setData(Data("not a jpeg".utf8), forType: .init("public.jpeg"))
        pasteboard.setData(tiff, forType: .tiff)

        XCTAssertTrue(try pastedPath().hasPrefix(PastedImage.folder.path))
    }

    func testDataLabelledPNGThatIsNotGivesWayToTheNext() throws {
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: pngData())?.tiffRepresentation)
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(Data("not a png".utf8), forType: .png)
        pasteboard.setData(tiff, forType: .tiff)

        let saved = try Data(contentsOf: URL(fileURLWithPath: try pastedPath()))
        XCTAssertNotNil(NSBitmapImageRep(data: saved))
        XCTAssertEqual(saved.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testEmptyTextGivesWayToImage() throws {
        pasteboard.declareTypes([.string, .png], owner: nil)
        pasteboard.setString("", forType: .string)
        pasteboard.setData(pngData(), forType: .png)

        XCTAssertTrue(try pastedPath().hasPrefix(PastedImage.folder.path))
    }

    func testImageWinsOverWebAddress() throws {
        pasteboard.declareTypes([.URL, .png], owner: nil)
        pasteboard.setString("https://example.com/a.png", forType: .URL)
        pasteboard.setData(pngData(), forType: .png)

        XCTAssertTrue(try pastedPath().hasPrefix(PastedImage.folder.path))
    }

    func testTextWinsOverImageWithWebAddress() {
        pasteboard.declareTypes([.URL, .string, .png], owner: nil)
        pasteboard.setString("https://example.com/a.png", forType: .URL)
        pasteboard.setString("hello", forType: .string)
        pasteboard.setData(pngData(), forType: .png)

        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), "hello")
    }

    func testWebAddressWithoutImagePastes() {
        pasteboard.declareTypes([.URL], owner: nil)
        pasteboard.setString("https://example.com/", forType: .URL)

        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), "https://example.com/")
    }

    func testTextWinsOverImage() {
        copy(pngData(), as: .png)
        pasteboard.setString("hello", forType: .string)

        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), "hello")
    }

    /// Finder puts the file's icon on the clipboard along with its URL.
    func testCopiedFileWinsOverImage() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try pngData().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.addTypes([.tiff], owner: nil)
        pasteboard.setData(try XCTUnwrap(NSBitmapImageRep(data: pngData())?.tiffRepresentation), forType: .tiff)

        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), Ghostty.shellEscape(file.path))
    }

    func testPDFIsNotAnImage() {
        copy(Data("%PDF-1.4".utf8), as: .pdf)

        XCTAssertNil(pasteboard.getOpinionatedStringContents())
        XCTAssertFalse(pasteboard.ghosttyAvailableMimes().contains("text/plain"))
    }

    func testEmptyClipboardHasNoText() {
        pasteboard.clearContents()

        XCTAssertNil(pasteboard.getOpinionatedStringContents())
        XCTAssertEqual(pasteboard.ghosttyAvailableMimes(), [])
    }
}
