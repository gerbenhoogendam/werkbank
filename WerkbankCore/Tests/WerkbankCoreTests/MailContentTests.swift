import XCTest
@testable import WerkbankCore

final class MailContentTests: XCTestCase {
    private func b64(_ byte: UInt8, count: Int = 4_000) -> String {
        Data(repeating: byte, count: count).base64EncodedString()
    }

    /// Antwoord met twee inline afbeeldingen: de volgorde van tekst en plaatjes moet die van de mail zijn.
    func testInlineImagesStayWhereTheyAre() {
        let raw = """
        From: Klant <klant@example.com>
        To: Support <support@itg.example>
        Subject: =?UTF-8?Q?Kanaal_delen?=
        Date: Tue, 20 Oct 2026 15:26:21 +0000
        MIME-Version: 1.0
        Content-Type: multipart/related; boundary="REL"

        --REL
        Content-Type: multipart/alternative; boundary="ALT"

        --ALT
        Content-Type: text/plain; charset=utf-8

        Platte tekst die niet gebruikt wordt.
        --ALT
        Content-Type: text/html; charset=utf-8

        <html><body><p>Eerst de stappen:</p><img src="cid:AAA"><p>Dan de fout:</p><img src="cid:BBB"><p>Groet</p></body></html>
        --ALT--
        --REL
        Content-Type: image/png; name="image.png"
        Content-ID: <AAA>
        Content-Disposition: inline; filename="image.png"
        Content-Transfer-Encoding: base64

        \(b64(1))
        --REL
        Content-Type: image/png; name="image.png"
        Content-ID: <BBB>
        Content-Disposition: inline; filename="image.png"
        Content-Transfer-Encoding: base64

        \(b64(2))
        --REL--
        """
        let mail = MailContentParser.parse(Data(raw.utf8))
        XCTAssertEqual(mail.subject, "Kanaal delen")
        XCTAssertEqual(mail.from, "Klant <klant@example.com>")
        XCTAssertEqual(mail.blocks.count, 5)
        guard mail.blocks.count == 5 else { return }
        XCTAssertEqual(mail.blocks[0], .text("Eerst de stappen:"))
        if case let .image(type, data, _) = mail.blocks[1] {
            XCTAssertEqual(type, "image/png")
            XCTAssertEqual(data, Data(repeating: 1, count: 4_000))
        } else { XCTFail("blok 1 moet een afbeelding zijn") }
        XCTAssertEqual(mail.blocks[2], .text("Dan de fout:"))
        if case let .image(_, data, _) = mail.blocks[3] {
            XCTAssertEqual(data, Data(repeating: 2, count: 4_000))
        } else { XCTFail("blok 3 moet een afbeelding zijn") }
        XCTAssertEqual(mail.blocks[4], .text("Groet"))
        XCTAssertEqual(mail.imageCount, 2)
    }

    func testPlainMailWithPDFAndUnsupportedAttachment() {
        let raw = """
        From: a@example.com
        Subject: Rapport
        Content-Type: multipart/mixed; boundary="MIX"

        --MIX
        Content-Type: text/plain; charset=utf-8

        Zie bijlagen.
        --MIX
        Content-Type: application/pdf; name="log.pdf"
        Content-Disposition: attachment; filename="log.pdf"
        Content-Transfer-Encoding: base64

        \(b64(3, count: 600))
        --MIX
        Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document; name="nota.docx"
        Content-Disposition: attachment; filename="nota.docx"
        Content-Transfer-Encoding: base64

        \(b64(4, count: 600))
        --MIX--
        """
        let mail = MailContentParser.parse(Data(raw.utf8))
        XCTAssertEqual(mail.blocks.first, .text("Zie bijlagen."))
        XCTAssertEqual(mail.pdfCount, 1)
        XCTAssertEqual(mail.omitted.map(\.name), ["nota.docx"])
    }

    func testTinyImagesAndWebImagesAreIgnored() {
        let raw = """
        From: a@example.com
        Subject: Nieuwsbrief
        Content-Type: multipart/related; boundary="R"

        --R
        Content-Type: text/html; charset=utf-8

        <p>Hallo</p><img src="cid:logo"><img src="https://tracker.example/pixel.gif"><p>Einde</p>
        --R
        Content-Type: image/png
        Content-ID: <logo>
        Content-Transfer-Encoding: base64

        \(b64(5, count: 500))
        --R--
        """
        let mail = MailContentParser.parse(Data(raw.utf8))
        XCTAssertEqual(mail.imageCount, 0)
        XCTAssertEqual(mail.blocks, [.text("Hallo"), .text("Einde")])
    }

    func testTextAttachmentIsIncludedAsText() {
        let log = Data("fout 42 op regel 3".utf8).base64EncodedString()
        let raw = """
        From: a@example.com
        Subject: Log
        Content-Type: multipart/mixed; boundary="M"

        --M
        Content-Type: text/plain

        Zie log.
        --M
        Content-Type: text/plain; name="error.log"
        Content-Disposition: attachment; filename="error.log"
        Content-Transfer-Encoding: base64

        \(log)
        --M--
        """
        let mail = MailContentParser.parse(Data(raw.utf8))
        XCTAssertEqual(mail.blocks.count, 2)
        XCTAssertEqual(mail.blocks.last, .text("[Inhoud van bijlage error.log]\nfout 42 op regel 3"))
    }

    func testDisplayHTMLInlinesCidImagesAndEscapesPlainText() {
        let png = b64(7)
        let html = """
        From: a@example.com
        Subject: Scherm
        Content-Type: multipart/related; boundary="R"

        --R
        Content-Type: text/html; charset=utf-8

        <p>Kijk:</p><img src="cid:shot">
        --R
        Content-Type: image/png
        Content-ID: <shot>
        Content-Transfer-Encoding: base64

        \(png)
        --R--
        """
        let mail = MailContentParser.parse(Data(html.utf8))
        XCTAssertTrue(mail.displayHTML.contains("data:image/png;base64,\(png)"))
        XCTAssertFalse(mail.displayHTML.contains("cid:"))

        let plain = MailContentParser.parse(Data("From: a@b.nl\nSubject: x\n\n1 < 2 & 3 > 2".utf8))
        XCTAssertEqual(plain.displayHTML, "<pre class=\"plain\">1 &lt; 2 &amp; 3 &gt; 2</pre>")
    }

    /// Doorsturen: de inhoud van <body> met de stijlen uit de kop, zonder scripts; cid-afbeeldingen gaan mee, een
    /// afbeelding met alleen een naam krijgt een Content-ID.
    func testForwardableHTMLKeepsImagesAndStyles() {
        let png = b64(7)
        let gif = b64(9)
        let raw = """
        From: a@example.com
        Subject: Offerte
        Content-Type: multipart/related; boundary="R"

        --R
        Content-Type: text/html; charset=utf-8

        <html><head><style>p.MsoNormal{margin:0}</style><title>x</title></head><body lang=NL><p class=MsoNormal>Zie:</p><img src="cid:shot"><img src="logo.gif"><script>alert(1)</script></body></html>
        --R
        Content-Type: image/png
        Content-ID: <shot>
        Content-Transfer-Encoding: base64

        \(png)
        --R
        Content-Type: image/gif
        Content-Location: logo.gif
        Content-Transfer-Encoding: base64

        \(gif)
        --R--
        """
        let mail = MailContentParser.parse(Data(raw.utf8))
        let html = mail.forwardHTML ?? ""
        XCTAssertTrue(html.hasPrefix("<style>p.MsoNormal{margin:0}</style><p class=MsoNormal>Zie:</p>"), html)
        XCTAssertTrue(html.contains(#"<img src="cid:shot">"#))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<title>"))
        XCTAssertEqual(mail.forwardImages.count, 2)
        let logo = mail.forwardImages.first { $0.mediaType == "image/gif" }
        XCTAssertNotNil(logo?.contentID)
        XCTAssertTrue(html.contains("src=\"cid:\(logo?.contentID ?? "-")\""), html)
        // Platte tekst: niets om door te sturen als HTML.
        XCTAssertNil(MailContentParser.parse(Data("From: a@b.nl\nSubject: x\n\nHoi".utf8)).forwardHTML)
    }

    /// Een handtekening die met de bestandsnaam naar zijn plaatje verwijst (Content-Location, geen cid): in de tekst, geen
    /// bijlage. Een klein ingesloten plaatje met cid waar de tekst niet naar verwijst: ook geen bijlage. Een gewone
    /// bijlage blijft.
    func testSignatureImagesAreNotAttachments() {
        let logo = b64(3)
        let raw = """
        From: a@example.com
        Subject: Groet
        Content-Type: multipart/mixed; boundary="M"

        --M
        Content-Type: multipart/related; boundary="R"

        --R
        Content-Type: text/html; charset=utf-8

        <p>Groet,</p><img src="image001.png" width="120">
        --R
        Content-Type: image/png; name="image001.png"
        Content-Location: image001.png
        Content-Disposition: inline; filename="image001.png"
        Content-Transfer-Encoding: base64

        \(logo)
        --R
        Content-Type: image/png; name="telefoon.png"
        Content-ID: <telefoon@x>
        Content-Disposition: inline; filename="telefoon.png"
        Content-Transfer-Encoding: base64

        \(b64(4, count: 900))
        --R--
        --M
        Content-Type: application/pdf; name="factuur.pdf"
        Content-Disposition: attachment; filename="factuur.pdf"
        Content-Transfer-Encoding: base64

        \(b64(5))
        --M--
        """
        let mail = MailContentParser.parse(Data(raw.utf8))
        XCTAssertEqual(mail.files.map(\.name), ["factuur.pdf"])
        XCTAssertTrue(mail.displayHTML.contains("data:image/png;base64,\(logo)"))
        XCTAssertFalse(mail.displayHTML.contains("src=\"image001.png\""))
    }

    func testHeaderTextOmitsEmptyFields() {
        let mail = MailContentParser.parse(Data("From: a@b.nl\nSubject: Hoi\n\nTekst".utf8))
        XCTAssertEqual(mail.headerText, "Van: a@b.nl\nOnderwerp: Hoi")
        XCTAssertEqual(mail.blocks, [.text("Tekst")])
    }
}
