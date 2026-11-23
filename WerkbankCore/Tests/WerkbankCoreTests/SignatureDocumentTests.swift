import XCTest
@testable import WerkbankCore

final class SignatureDocumentTests: XCTestCase {
    private var sample: SignatureDocument {
        var document = SignatureDocument()
        let address = SignatureBlock(kind: .text, spaceAbove: 18, runs: [
            SignatureRun(text: "Havenkade 14 - "),
            SignatureRun(text: "support@kade.example", underline: true, link: "mailto:support@kade.example"),
        ], fontSize: 11)
        document.blocks = [
            .text([SignatureRun(text: "Met vriendelijke groet,")]),
            .text([SignatureRun(text: "Robin Bakker", bold: true), SignatureRun(text: "\nConsultant")], spaceAbove: 16),
            .logo(width: 200, height: 52, spaceAbove: 20, link: "https://kade.example", alt: "Kade"),
            address,
        ]
        return document
    }

    func testHTMLHasSpacersAndInlineStyles() {
        let html = sample.html()
        XCTAssertTrue(html.contains("<td height=\"16\" style=\"height:16px;font-size:0;line-height:0\">&nbsp;</td>"))
        XCTAssertTrue(html.contains("<b>Robin Bakker</b><br>Consultant"))
        XCTAssertTrue(html.contains("src=\"cid:logo\" width=\"200\" height=\"52\""))
        XCTAssertTrue(html.contains("<a href=\"https://kade.example\""))
        XCTAssertTrue(html.contains("font-size:11px;line-height:16px"))
        XCTAssertTrue(html.contains("style=\"color:#1A4FD6;text-decoration:underline\">support@kade.example</a>"))
        XCTAssertTrue(html.contains("max-width:600px"))
    }

    func testEmptyDocumentHasNoHTML() {
        XCTAssertEqual(SignatureDocument().html(), "")
    }

    func testImportOfOwnHTMLGivesTheSameHTML() {
        let document = sample
        let imported = SignatureImport.document(fromHTML: document.html())
        XCTAssertEqual(imported.blocks.map(\.kind), [.text, .text, .logo, .text])
        XCTAssertEqual(imported.blocks.map(\.spaceAbove), [0, 16, 20, 18])
        XCTAssertEqual(imported.blocks[1].runs, document.blocks[1].runs)
        XCTAssertEqual(imported.blocks[2].width, 200)
        XCTAssertEqual(imported.blocks[2].height, 52)
        XCTAssertEqual(imported.blocks[2].link, "https://kade.example")
        XCTAssertEqual(imported.blocks[2].alt, "Kade")
        XCTAssertEqual(imported.blocks[3].fontSize, 11)
        XCTAssertEqual(imported.blocks[3].runs, document.blocks[3].runs)
        XCTAssertEqual(imported.html(), document.html())
    }

    func testImportOfHandwrittenSignature() {
        let html = """
        <div style="font-family: Arial, sans-serif; font-size: 10pt;">
        <p>Met vriendelijke groet,<br><br><b>Jan Visser</b><br>Adviseur</p>
        <img src="cid:logo123" width="240" height="60" alt="Logo">
        <p style="color: #666666; font-size: 8pt">Straat 1 - 1234 AB Plaats<br>&gt; <a href="https://example.com/hulp">hulp op afstand</a> &lt;</p>
        </div>
        """
        let document = SignatureImport.document(fromHTML: html)
        XCTAssertEqual(document.fontFamily, "Arial")
        XCTAssertEqual(document.blocks.map(\.kind), [.text, .logo, .text])
        XCTAssertEqual(document.blocks[0].plainText, "Met vriendelijke groet,\n\nJan Visser\nAdviseur")
        XCTAssertTrue(document.blocks[0].runs.contains { $0.text == "Jan Visser" && $0.bold })
        XCTAssertEqual(document.blocks[1].width, 240)
        XCTAssertEqual(document.blocks[1].height, 60)
        XCTAssertGreaterThan(document.blocks[1].spaceAbove, 0)
        let last = document.blocks[2]
        XCTAssertEqual(last.plainText, "Straat 1 - 1234 AB Plaats\n> hulp op afstand <")
        XCTAssertEqual(last.runs.first { $0.link != nil }?.link, "https://example.com/hulp")
        XCTAssertEqual(document.color(of: last), "#666666")
        XCTAssertEqual(document.color(of: document.blocks[0]), "#1D1D1F")
    }

    func testEmptyLinesBecomeSpace() {
        let document = SignatureImport.document(fromHTML: "<div>Naam</div><div><br></div><div>Adres</div>")
        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[1].spaceAbove, 16)
    }

    func testOtherImagesStayHTML() {
        let document = SignatureImport.document(fromHTML: "<p>Naam</p><img src=\"https://example.com/a.png\">")
        XCTAssertEqual(document.blocks.last?.kind, .html)
        XCTAssertFalse(document.hasLogo)
    }

    func testLinkKinds() {
        typealias Kind = SignatureDocument.LinkKind
        XCTAssertEqual(Kind.email.href("info@kade.example"), "mailto:info@kade.example")
        XCTAssertEqual(Kind.phone.href("012-345 67 89"), "tel:0123456789")
        XCTAssertEqual(Kind.website.href("kade.example"), "https://kade.example")
        XCTAssertEqual(Kind.website.href("http://kade.example"), "http://kade.example")
        XCTAssertEqual(Kind.of("tel:0123"), .phone)
        XCTAssertEqual(Kind.address(of: "mailto:a@b.nl"), "a@b.nl")
    }

    func testRunsMerge() {
        let runs = SignatureBlock.merged([SignatureRun(text: "a"), SignatureRun(text: ""), SignatureRun(text: "b"),
                                          SignatureRun(text: "c", bold: true)])
        XCTAssertEqual(runs, [SignatureRun(text: "ab"), SignatureRun(text: "c", bold: true)])
    }
}
