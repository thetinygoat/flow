import AppKit
import XCTest

final class PastedImageTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: .init("dev.thetinygoat.flowTests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    private func pngData() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testImagePastesAsPathOfItsFile() throws {
        let png = pngData()
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        let path = try XCTUnwrap(pasteboard.getOpinionatedStringContents())
        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), png)
        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), path)
        XCTAssertEqual(pasteboard.ghosttyAvailableMimes().first, "text/plain")
    }

    func testTIFFIsSavedAsPNG() throws {
        let tiff = try XCTUnwrap(NSImage(data: pngData())?.tiffRepresentation)
        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: .tiff)

        let path = try XCTUnwrap(pasteboard.getOpinionatedStringContents())
        let saved = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(saved.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testTextWinsOverImage() {
        pasteboard.clearContents()
        pasteboard.setData(pngData(), forType: .png)
        pasteboard.setString("hello", forType: .string)

        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), "hello")
    }

    func testEmptyClipboardHasNoText() {
        pasteboard.clearContents()

        XCTAssertNil(pasteboard.getOpinionatedStringContents())
        XCTAssertEqual(pasteboard.ghosttyAvailableMimes(), [])
    }
}
