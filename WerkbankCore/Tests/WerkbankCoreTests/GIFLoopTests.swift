import XCTest
@testable import WerkbankCore
#if canImport(ImageIO)
import ImageIO
#endif

final class GIFLoopTests: XCTestCase {
    /// Twee beelden van 1×1 met een globale kleurtabel; `loop`: de NETSCAPE2.0-extensie (0 = eindeloos).
    private func gif(loop: Bool) -> Data {
        var bytes: [UInt8] = Array("GIF89a".utf8) + [0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF]
        if loop {
            bytes += [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [0x03, 0x01, 0x00, 0x00, 0x00]
        }
        let frame: [UInt8] = [0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00,
                              0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
                              0x02, 0x02, 0x44, 0x01, 0x00]
        bytes += frame + frame + [0x3B]
        return Data(bytes)
    }

    func testLoopExtensionIsRemoved() {
        XCTAssertEqual(GIFLoop.playOnce(gif(loop: true)), gif(loop: false))
    }

    func testWithoutLoopOrNotAGIFIsUnchanged() {
        XCTAssertEqual(GIFLoop.playOnce(gif(loop: false)), gif(loop: false))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 20))
        XCTAssertEqual(GIFLoop.playOnce(png), png)
    }

    func testTruncatedGIFIsUnchanged() {
        let truncated = gif(loop: true).prefix(30)
        XCTAssertEqual(GIFLoop.playOnce(Data(truncated)), Data(truncated))
    }

    func testDataURLsInHTML() {
        let looping = gif(loop: true).base64EncodedString()
        let once = gif(loop: false).base64EncodedString()
        let html = #"<p>Groet</p><img src="data:image/gif;base64,\#(looping)"><img src="https://example.com/a.gif">"#
        XCTAssertEqual(GIFLoop.playOnce(inHTML: html),
                       #"<p>Groet</p><img src="data:image/gif;base64,\#(once)"><img src="https://example.com/a.gif">"#)
        XCTAssertEqual(GIFLoop.playOnce(inHTML: "<p>Geen afbeelding</p>"), "<p>Geen afbeelding</p>")
    }

    #if canImport(ImageIO)
    /// ImageIO (waar WebKit op de Mac GIF's mee leest): eerst 0 (eindeloos), daarna 1 (één keer afspelen), nog
    /// steeds twee beelden.
    func testImageIOPlaysOnce() throws {
        func properties(_ data: Data) throws -> (frames: Int, loop: Any?) {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let all = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
            let gif = all?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return (CGImageSourceGetCount(source), gif?[kCGImagePropertyGIFLoopCount])
        }
        let before = try properties(gif(loop: true))
        let after = try properties(GIFLoop.playOnce(gif(loop: true)))
        XCTAssertEqual(before.frames, 2)
        XCTAssertEqual(before.loop as? Int, 0)
        XCTAssertEqual(after.frames, 2)
        XCTAssertEqual(after.loop as? Int, 1)
    }
    #endif
}
