import XCTest
@testable import WerkbankCore

final class MailLinksTests: XCTestCase {
    /// Een link die als tekst in een mail van de iPhone staat (Mail.app, platte tekst): beide adressen klikbaar,
    /// de tags eromheen blijven tekst.
    func testPlainTextWithLiteralAnchor() {
        let plain = "<a href=\"https://x.com/e/status/1?s=43\">https://x.com/e/status/1?s=43</a>\n\nMobiel verzonden"
        let html = MailContentParser.displayHTML(html: nil, plain: plain, attachments: [])
        XCTAssertEqual(html.components(separatedBy: "<a href=\"https://x.com/e/status/1?s=43\">").count - 1, 2)
        XCTAssertTrue(html.hasPrefix("<pre class=\"plain\">&lt;a href=\""))
        XCTAssertTrue(html.contains("&lt;/a&gt;\n\nMobiel verzonden</pre>"))
    }

    /// Dezelfde mail als HTML-deel: de tekst is ge-escapet, het adres stopt bij `&quot;` en `&lt;`.
    func testEscapedTextInHTML() {
        let html = MailLinks.linkify(html: "<div>&lt;a href=&quot;https://x.com/a?s=43&quot;&gt;https://x.com/a?s=43&lt;/a&gt;</div>")
        XCTAssertEqual(html, "<div>&lt;a href=&quot;<a href=\"https://x.com/a?s=43\">https://x.com/a?s=43</a>&quot;&gt;"
                       + "<a href=\"https://x.com/a?s=43\">https://x.com/a?s=43</a>&lt;/a&gt;</div>")
    }

    func testExistingLinksStyleAndTagsUntouched() {
        XCTAssertEqual(MailLinks.linkify(html: "<p><a href=\"https://a.nl\">https://a.nl</a> en https://b.nl.</p>"),
                       "<p><a href=\"https://a.nl\">https://a.nl</a> en <a href=\"https://b.nl\">https://b.nl</a>.</p>")
        let untouched = "<style>a{background:url(https://c.nl/x.png)}</style><img src=\"https://g.nl/x.png\">"
        XCTAssertEqual(MailLinks.linkify(html: untouched), untouched)
    }

    func testPunctuationBracketsAndWWW() {
        XCTAssertEqual(MailLinks.linkify(text: "zie (www.d.nl/pad) of https://e.nl/a_(b)"),
                       "zie (<a href=\"https://www.d.nl/pad\">www.d.nl/pad</a>) of "
                       + "<a href=\"https://e.nl/a_(b)\">https://e.nl/a_(b)</a>")
        XCTAssertEqual(MailLinks.linkify(text: "alleen https:// zonder meer"), "alleen https:// zonder meer")
    }

    func testQueryWithAmpersandAndNonBreakingSpace() {
        let plain = MailContentParser.displayHTML(html: nil, plain: "https://f.nl/?a=1&b=2 klaar", attachments: [])
        XCTAssertEqual(plain, "<pre class=\"plain\"><a href=\"https://f.nl/?a=1&amp;b=2\">https://f.nl/?a=1&amp;b=2</a> klaar</pre>")
        XCTAssertEqual(MailLinks.linkify(html: "<p>https://h.nl&nbsp;tekst</p>"),
                       "<p><a href=\"https://h.nl\">https://h.nl</a>&nbsp;tekst</p>")
    }
}
