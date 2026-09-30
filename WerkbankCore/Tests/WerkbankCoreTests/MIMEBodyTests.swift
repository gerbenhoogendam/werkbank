import XCTest
@testable import WerkbankCore

final class MIMEBodyTests: XCTestCase {
    private func mail(_ text: String) -> ParsedMail { EMLParser.parse(Data(text.utf8)) }

    func testPlainBody() {
        let m = mail("From: a@b.nl\nSubject: x\n\nHallo wereld\n\nGroet")
        XCTAssertEqual(m.bodyText, "Hallo wereld\n\nGroet")
    }

    func testNoBody() {
        XCTAssertNil(mail("From: a@b.nl\nSubject: x\n\n").bodyText)
    }

    func testQuotedPrintableUTF8WithSoftBreak() {
        let m = mail("""
        Subject: x
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Caf=C3=A9 met een lange=
         regel
        """.replacingOccurrences(of: "        ", with: ""))
        XCTAssertEqual(m.bodyText, "Café met een lange regel")
    }

    func testBase64Latin1() {
        // "Café" in ISO-8859-1 = 43 61 66 E9 → Q2Fm6Q==
        let m = mail("Subject: x\nContent-Type: text/plain; charset=iso-8859-1\nContent-Transfer-Encoding: base64\n\nQ2Fm6Q==\n")
        XCTAssertEqual(m.bodyText, "Café")
    }

    func testMultipartAlternativePrefersPlain() {
        let m = mail("""
        Subject: x
        Content-Type: multipart/alternative; boundary="BND"

        --BND
        Content-Type: text/html; charset=utf-8

        <p>HTML <b>versie</b></p>
        --BND
        Content-Type: text/plain; charset=utf-8

        Platte versie
        --BND--
        """.replacingOccurrences(of: "        ", with: ""))
        XCTAssertEqual(m.bodyText, "Platte versie")
    }

    func testHTMLOnlyIsConvertedToText() {
        let m = mail("Subject: x\nContent-Type: text/html; charset=utf-8\n\n<html><head><style>p{}</style></head><body><p>Eerste &amp; tweede</p><p>Derde<br>regel</p></body></html>")
        XCTAssertEqual(m.bodyText, "Eerste & tweede\nDerde\nregel")
    }

    func testAttachmentsAreSkipped() {
        let m = mail("""
        Subject: x
        Content-Type: multipart/mixed; boundary="B1"

        --B1
        Content-Type: text/plain

        De tekst
        --B1
        Content-Type: text/plain; name="notes.txt"
        Content-Disposition: attachment; filename="notes.txt"

        Bijlage-inhoud
        --B1--
        """.replacingOccurrences(of: "        ", with: ""))
        XCTAssertEqual(m.bodyText, "De tekst")
    }

    func testHeadersUnaffected() {
        let m = mail("From: Jan <jan@studio-noord.nl>\nSubject: Onderwerp\n\nInhoud")
        XCTAssertEqual(m.subject, "Onderwerp")
        XCTAssertEqual(m.fromAddress, "jan@studio-noord.nl")
        XCTAssertEqual(m.bodyText, "Inhoud")
    }
}
