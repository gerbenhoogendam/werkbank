import XCTest
@testable import WerkbankCore

final class EMLParserTests: XCTestCase {
    func testSimpleHeaders() {
        let eml = "From: Jan de Vries <jan@studio-noord.nl>\r\nSubject: Offerte website\r\n\r\nBody hier"
        let mail = EMLParser.parse(eml)
        XCTAssertEqual(mail.subject, "Offerte website")
        XCTAssertEqual(mail.fromName, "Jan de Vries")
        XCTAssertEqual(mail.fromAddress, "jan@studio-noord.nl")
        XCTAssertEqual(mail.senderLine, "Jan de Vries · jan@studio-noord.nl")
    }

    func testEmptySubject() {
        XCTAssertEqual(EMLParser.parse("From: a@b.nl\n\n").subject, "(geen onderwerp)")
        XCTAssertEqual(EMLParser.parse("Subject:   \nFrom: a@b.nl\n\n").subject, "(geen onderwerp)")
    }

    func testFoldedSubject() {
        let eml = "Subject: Dit is een heel lange\r\n onderwerpregel die doorloopt\r\n\tover drie regels\r\nFrom: a@b.nl\r\n\r\n"
        XCTAssertEqual(EMLParser.parse(eml).subject,
                       "Dit is een heel lange onderwerpregel die doorloopt over drie regels")
    }

    func testHeaderStopsAtBlankLine() {
        let eml = "From: a@b.nl\n\nSubject: staat in de body\n"
        XCTAssertEqual(EMLParser.parse(eml).subject, "(geen onderwerp)")
    }

    func testEncodedWordBase64() {
        // "Café bestelling" in UTF-8, base64
        let eml = "Subject: =?UTF-8?B?Q2Fmw6kgYmVzdGVsbGluZw==?=\nFrom: a@b.nl\n\n"
        XCTAssertEqual(EMLParser.parse(eml).subject, "Café bestelling")
    }

    func testEncodedWordQuotedPrintable() {
        let eml = "Subject: =?ISO-8859-1?Q?Caf=E9_bestelling?=\nFrom: a@b.nl\n\n"
        XCTAssertEqual(EMLParser.parse(eml).subject, "Café bestelling")
    }

    func testAdjacentEncodedWordsDropWhitespaceBetween() {
        let eml = "Subject: =?UTF-8?Q?Hallo_?= =?UTF-8?Q?w=C3=A9reld?=\nFrom: a@b.nl\n\n"
        XCTAssertEqual(EMLParser.parse(eml).subject, "Hallo wéreld")
    }

    func testEncodedWordMixedWithPlainText() {
        let eml = "Subject: Re: =?UTF-8?B?w4Vuc3ZhcmVu?= voor u\nFrom: a@b.nl\n\n"
        XCTAssertEqual(EMLParser.parse(eml).subject, "Re: Ånsvaren voor u")
    }

    func testEncodedFromName() {
        let eml = "From: =?UTF-8?B?SsO8cmdlbiBCw7ZocQ==?= <Jurgen@Firma.DE>\nSubject: x\n\n"
        let mail = EMLParser.parse(eml)
        XCTAssertEqual(mail.fromName, "Jürgen Böhq")
        XCTAssertEqual(mail.fromAddress, "jurgen@firma.de")
    }

    func testQuotedFromNameAndBareAddress() {
        XCTAssertEqual(EMLParser.parse("From: \"Vries, Jan\" <j@x.nl>\n\n").fromName, "Vries, Jan")
        let bare = EMLParser.parse("From: j@x.nl\n\n")
        XCTAssertNil(bare.fromName)
        XCTAssertEqual(bare.fromAddress, "j@x.nl")
        XCTAssertEqual(bare.senderLine, "j@x.nl")
    }

    func testDataInputWithInvalidUTF8Body() {
        var data = Data("From: a@b.nl\nSubject: Test\n\n".utf8)
        data.append(contentsOf: [0xFF, 0xFE, 0xFD])
        XCTAssertEqual(EMLParser.parse(data).subject, "Test")
    }
}
