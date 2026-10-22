import XCTest
@testable import WerkbankCore

final class MailThreadingTests: XCTestCase {
    func testGmailQuoteIsSplitOff() {
        let html = #"<div dir="ltr">Nieuw bericht</div><br><div class="gmail_quote"><div class="gmail_attr">Op di 20 okt schreef Jan:</div><blockquote>oud</blockquote></div>"#
        let (main, history) = QuoteSplitter.split(html: html)
        XCTAssertEqual(main, #"<div dir="ltr">Nieuw bericht</div><br>"#)
        XCTAssertTrue(history?.contains("oud") ?? false)
    }

    func testAppleMailAttributionMovesToHistory() {
        let html = #"<div>Hoi</div><div><br><div>Op 21 okt 2026 om 11:48 heeft Jan het volgende geschreven:</div><br><blockquote type="cite">oud</blockquote></div>"#
        let (main, history) = QuoteSplitter.split(html: html)
        XCTAssertFalse(main.contains("geschreven"))
        XCTAssertTrue(history?.contains("geschreven") ?? false)
    }

    func testOnlyQuoteKeepsEverything() {
        let html = #"<blockquote type="cite">alles</blockquote>"#
        XCTAssertNil(QuoteSplitter.split(html: html).history)
    }

    func testPlainTextQuote() {
        let html = "<pre class=\"plain\">Prima!\n\nOn Tue, Jan wrote:\n&gt; oud</pre>"
        let (main, history) = QuoteSplitter.split(html: html)
        XCTAssertEqual(main, "<pre class=\"plain\">Prima!\n</pre>")
        XCTAssertTrue(history?.contains("oud") ?? false)
    }

    func testForwardsAreNotFolded() {
        let html = #"<div>Kijk even hiernaar</div><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>Van: Jan</div><div>De inhoud</div></div>"#
        XCTAssertNil(QuoteSplitter.split(html: html, subject: "Fwd: Surface").history)
        // Ook zonder Fwd: in het onderwerp herkent hij het doorgestuurde bericht.
        XCTAssertNil(QuoteSplitter.split(html: html, subject: "Surface").history)
        // Een gewoon antwoord blijft ingeklapt.
        let reply = #"<div>Prima</div><div class="gmail_quote"><div class="gmail_attr">Op di 20 okt schreef Jan:</div><blockquote>oud</blockquote></div>"#
        XCTAssertNotNil(QuoteSplitter.split(html: reply, subject: "Re: Surface").history)
    }

    func testSummaryExtraction() {
        let answer = "## Samenvatting\nKlant vraagt om een **offerte** voor\nnieuwe switches.\n\n## Wat zie ik\nIets"
        XCTAssertEqual(ClaudeSummary.extract(from: answer), "Klant vraagt om een offerte voor nieuwe switches.")
        XCTAssertEqual(ClaudeSummary.extract(from: "Gewoon een antwoord.\nMeer."), "Gewoon een antwoord.")
    }

    func testDraftExtraction() {
        let answer = "## Samenvatting\nIets\n\n## Conceptantwoord\nBeste Jan,\n\nDank je.\n\n## Extra\nniet"
        XCTAssertEqual(ClaudeDraft.extract(from: answer), "Beste Jan,\n\nDank je.")
        XCTAssertNil(ClaudeDraft.extract(from: "## Samenvatting\nIets"))
    }
}
