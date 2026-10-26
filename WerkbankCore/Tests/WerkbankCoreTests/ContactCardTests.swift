import XCTest
@testable import WerkbankCore

final class ContactCardTests: XCTestCase {
    func testNameAndAddressFromHeader() {
        let card = ContactCard.fromHeader("Jan van der Berg <Jan@Voorbeeld.nl>")
        XCTAssertEqual(card.givenName, "Jan")
        XCTAssertEqual(card.familyName, "van der Berg")
        XCTAssertEqual(card.email, "jan@voorbeeld.nl")
    }

    func testCommaNameAndBareAddress() {
        XCTAssertEqual(ContactCard.splitName("Berg, Jan").given, "Jan")
        XCTAssertEqual(ContactCard.splitName("Berg, Jan").family, "Berg")
        XCTAssertEqual(ContactCard.splitName("Marieke").given, "Marieke")
        XCTAssertEqual(ContactCard.splitName("Marieke").family, "")
        let bare = ContactCard.fromHeader("info@voorbeeld.nl")
        XCTAssertEqual(bare.email, "info@voorbeeld.nl")
        XCTAssertEqual(bare.displayName, "")
    }

    func testSignatureTextLeavesOutQuotedHistory() {
        let html = """
        <div>Hoi, zie bijlage.<br><br>Met vriendelijke groet,<br>Jan van der Berg<br>Voorbeeld BV<br>06 12345678</div>
        <div class="gmail_quote">Op ma schreef iemand:<blockquote>Oude mail met 020 7654321</blockquote></div>
        """
        let text = ContactCard.signatureText(html: html, subject: "Re: offerte")
        XCTAssertTrue(text.contains("06 12345678"))
        XCTAssertFalse(text.contains("020 7654321"))
    }
}
