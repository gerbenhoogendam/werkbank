import XCTest
@testable import WerkbankCore

final class RecipientTokensTests: XCTestCase {
    func testFieldBecomesTokensInOrder() {
        let tokens = RecipientTokens.tokens(from: "Sanne de Boer <sanne@x.nl>, kapot@, mila@y.nl; \"Vries, Jos de\" <jos@z.nl>")
        XCTAssertEqual(tokens.map(\.label), ["Sanne de Boer", "kapot@", "mila@y.nl", "Vries, Jos de"])
        XCTAssertEqual(tokens.map(\.isValid), [true, false, true, true])
        XCTAssertEqual(tokens[0].address, "sanne@x.nl")
        XCTAssertNil(tokens[2].name)
    }

    func testTextRoundTripsAndQuotesNamesWithCommas() {
        let text = "Sanne de Boer <sanne@x.nl>, \"Vries, Jos de\" <jos@z.nl>, mila@y.nl"
        let tokens = RecipientTokens.tokens(from: text)
        XCTAssertEqual(RecipientTokens.text(tokens), text)
        XCTAssertEqual(RecipientTokens.text(tokens, draft: " sup "), text + ", sup")
        // Wat versturen ermee doet: drie geldige adressen, en wat nog getypt wordt telt als ongeldig.
        XCTAssertEqual(MailAddress.parse(RecipientTokens.text(tokens)).valid.count, 3)
        XCTAssertEqual(MailAddress.parse(RecipientTokens.text(tokens, draft: "sup")).invalid, ["sup"])
    }

    func testCommaClosesWhatWasTyped() {
        let typed = RecipientTokens.absorb("support@itgsolutions.nl,")
        XCTAssertEqual(typed.tokens.map(\.address), ["support@itgsolutions.nl"])
        XCTAssertEqual(typed.draft, "")
        // Nog geen adres: het blokje is te herkennen als ongeldig.
        let partial = RecipientTokens.absorb("sup;")
        XCTAssertEqual(partial.tokens.map(\.isValid), [false])
        XCTAssertEqual(partial.tokens.first?.label, "sup")
    }

    func testSpaceClosesOnlyACompleteAddress() {
        XCTAssertEqual(RecipientTokens.absorb("sanne de").tokens.count, 0)
        XCTAssertEqual(RecipientTokens.absorb("sanne de ").draft, "sanne de ")
        let address = RecipientTokens.absorb("sanne@x.nl ")
        XCTAssertEqual(address.tokens.map(\.address), ["sanne@x.nl"])
        XCTAssertEqual(address.draft, "")
        let named = RecipientTokens.absorb("Sanne de Boer <sanne@x.nl> ")
        XCTAssertEqual(named.tokens.first?.name, "Sanne de Boer")
        // Zonder spatie erachter blijft het staan om aan verder te typen.
        XCTAssertEqual(RecipientTokens.absorb("sanne@x.nl").tokens.count, 0)
    }

    func testPastedListBecomesTokensAndKeepsTheRest() {
        let pasted = RecipientTokens.absorb("a@x.nl, Bas <b@y.nl>\nc@z.nl; do")
        XCTAssertEqual(pasted.tokens.map(\.label), ["a@x.nl", "Bas", "c@z.nl"])
        XCTAssertEqual(pasted.draft, "do")
        XCTAssertEqual(RecipientTokens.absorb(", ,").tokens.count, 0)
    }

    func testCommaInsideQuotesOrBracketsDoesNotSplit() {
        XCTAssertEqual(RecipientTokens.absorb("\"Vries, Jos").tokens.count, 0)
        XCTAssertEqual(RecipientTokens.pieces("\"Vries, Jos de\" <jos@z.nl>").count, 1)
    }

    func testIsComplete() {
        XCTAssertTrue(RecipientTokens.isComplete("a@b.nl"))
        XCTAssertTrue(RecipientTokens.isComplete(" Jan <a@b.nl> "))
        XCTAssertFalse(RecipientTokens.isComplete("a@b"))
        XCTAssertFalse(RecipientTokens.isComplete("jan jansen"))
        XCTAssertFalse(RecipientTokens.isComplete(""))
    }
}
