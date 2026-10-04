import XCTest
@testable import WerkbankCore

final class IconNameTests: XCTestCase {
    func testSymbolNamesAreNotEmoji() {
        XCTAssertFalse(IconName.isEmoji("tray.fill"))
        XCTAssertFalse(IconName.isEmoji("square.stack.3d.up.fill"))
        XCTAssertFalse(IconName.isEmoji(""))
    }

    func testEmojiIsRecognised() {
        XCTAssertTrue(IconName.isEmoji("🚀"))
        XCTAssertTrue(IconName.isEmoji("📬"))
    }

    func testFirstEmojiFromTypedText() {
        XCTAssertEqual(IconName.firstEmoji(in: "🚀"), "🚀")
        XCTAssertEqual(IconName.firstEmoji(in: "ab🚀x🎯"), "🚀")
        XCTAssertEqual(IconName.firstEmoji(in: "👨‍👩‍👧"), "👨‍👩‍👧")
    }

    func testPlainTextHasNoEmoji() {
        XCTAssertNil(IconName.firstEmoji(in: "abc"))
        XCTAssertNil(IconName.firstEmoji(in: "123"))
        XCTAssertNil(IconName.firstEmoji(in: "é"))
        XCTAssertNil(IconName.firstEmoji(in: ""))
    }
}
