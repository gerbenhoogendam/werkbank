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

    func testPlainQuoteLevelsBecomeNestedBlocks() {
        let html = #"<pre class="plain">Zie hieronder.\#n&gt; Eerste\#n&gt; &gt; Tweede\#n&gt;&gt;&gt; Derde\#n&gt; Terug\#nKlaar</pre>"#
        XCTAssertEqual(QuoteLevels.nestPlainQuotes(html),
                       #"<pre class="plain">Zie hieronder.<blockquote type="cite">Eerste<blockquote type="cite">Tweede"#
                       + #"<blockquote type="cite">Derde</blockquote></blockquote>Terug</blockquote>Klaar</pre>"#)
        // Geen citaat of geen platte tekst: ongewijzigd.
        XCTAssertEqual(QuoteLevels.nestPlainQuotes(#"<pre class="plain">Gewoon</pre>"#), #"<pre class="plain">Gewoon</pre>"#)
        XCTAssertEqual(QuoteLevels.nestPlainQuotes("<div>&gt; html</div>"), "<div>&gt; html</div>")
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

    func testOlderMessagesInAFlatQuoteGetTheirOwnLevel() {
        // Zoals Werkbank (en veel doorgestuurde mail) een citaat maakt: platte tekst met <br>.
        let html = "<div>Zie onder</div><blockquote type=\"cite\" style=\"color: #555\">Hi David,<br>\nDank<br>\n<br>\n"
            + "On Sep 18, 2026, 9:41 AM, Support &lt;<a href=\"mailto:s@x.nl\">s@x.nl</a>&gt; wrote:<br>\nDag Jan David,<br>\n"
            + "Op 15 sep 2026, om 14:34 heeft Jan &lt;jan@x.nl&gt; het volgende geschreven:<br>\nGoedemiddag,</blockquote>"
        let expected = "<div>Zie onder</div><blockquote type=\"cite\" style=\"color: #555\">Hi David,<br>\nDank<br>\n<br>\n"
            + "On Sep 18, 2026, 9:41 AM, Support &lt;<a href=\"mailto:s@x.nl\">s@x.nl</a>&gt; wrote:"
            + "<blockquote type=\"cite\">Dag Jan David,<br>\n"
            + "Op 15 sep 2026, om 14:34 heeft Jan &lt;jan@x.nl&gt; het volgende geschreven:"
            + "<blockquote type=\"cite\">Goedemiddag,</blockquote></blockquote></blockquote>"
        XCTAssertEqual(QuoteLevels.nest(html), expected)
    }

    func testOutlookHeaderStartsTheOlderMessage() {
        let html = "<blockquote type=\"cite\">Prima<br>\n<br>\n-----Oorspronkelijk bericht-----<br>\nVan: Jan<br>\n"
            + "Verzonden: maandag<br>\nOnderwerp: Offerte<br>\n<br>\nOude tekst</blockquote>"
        XCTAssertEqual(QuoteLevels.nest(html),
                       "<blockquote type=\"cite\">Prima<br>\n<blockquote type=\"cite\">-----Oorspronkelijk bericht-----<br>\n"
                       + "Van: Jan<br>\nVerzonden: maandag<br>\nOnderwerp: Offerte<br>\n<br>\nOude tekst</blockquote></blockquote>")
        // Een kop van Outlook zonder streepjesregel.
        let outlook = "<blockquote type=\"cite\">Ja<br>\nVan: Jan<br>\nVerzonden: ma<br>\nAan: Piet<br>\n<br>\nOud</blockquote>"
        XCTAssertEqual(QuoteLevels.nest(outlook),
                       "<blockquote type=\"cite\">Ja<blockquote type=\"cite\">Van: Jan<br>\nVerzonden: ma<br>\nAan: Piet<br>\n<br>\n"
                       + "Oud</blockquote></blockquote>")
    }

    func testQuotesThatAreNotFlatOrHaveNoHeaderStayTheSame() {
        let blocks = "<blockquote type=\"cite\"><div>On Tue, Jan wrote:</div><div>oud</div></blockquote>"
        XCTAssertEqual(QuoteLevels.nest(blocks), blocks)
        let plain = "<blockquote type=\"cite\">Gewoon een citaat<br>\nVan: iemand die iets zei</blockquote>"
        XCTAssertEqual(QuoteLevels.nest(plain), plain)
        XCTAssertEqual(QuoteLevels.nest("<div>Geen citaat</div>"), "<div>Geen citaat</div>")
    }

    func testPlainTextHeadersWithoutQuoteMarks() {
        let html = "<pre class=\"plain\">Prima\nOn Tue, Jan wrote:\nOude tekst</pre>"
        XCTAssertEqual(QuoteLevels.nest(html),
                       "<pre class=\"plain\">Prima\nOn Tue, Jan wrote:<blockquote type=\"cite\">Oude tekst</blockquote></pre>")
        // Staat de tekst na de aanhef al met ">", dan geen extra niveau.
        let quoted = "<pre class=\"plain\">Prima\nOn Tue, Jan wrote:\n&gt; oud</pre>"
        XCTAssertEqual(QuoteLevels.nest(quoted),
                       "<pre class=\"plain\">Prima\nOn Tue, Jan wrote:<blockquote type=\"cite\">oud</blockquote></pre>")
    }

    func testHeaderLevelsForComposing() {
        let lines = ["Hoi", "", "Op 1 nov 2026 schreef Jan <jan@x.nl>:", "Oud", "-----Original Message-----",
                     "From: Piet", "Sent: Monday", "", "Ouder"]
        XCTAssertEqual(QuoteLevels.headerLevels(lines), [0, 0, 0, 1, 2, 2, 2, 2, 2])
    }

    func testOutlookWordHistoryBecomesNestedQuotes() {
        let header1 = #"<div><div style='border:none;border-top:solid #E1E1E1 1.0pt;padding:3.0pt 0cm 0cm 0cm'>"#
            + #"<p class=MsoNormal><b>Van:</b> Jan<br><b>Verzonden:</b> maandag<br><b>Onderwerp:</b> X</p></div></div>"#
        let header2 = #"<div><div style="border:none;border-top:solid #E1E1E1 1.0pt"><p class=MsoNormal>"#
            + #"<b>From:</b> Piet<br><b>Sent:</b> Monday</p></div></div>"#
        let html = "<html><body><div class=WordSection1><p class=MsoNormal>Nieuw</p>" + header1
            + "<p class=MsoNormal>Oud</p>" + header2 + "<p class=MsoNormal>Ouder</p></div></body></html>"
        let quote = #"<blockquote type="cite">"#
        XCTAssertEqual(QuoteLevels.nest(html),
                       "<html><body><div class=WordSection1><p class=MsoNormal>Nieuw</p>" + quote + header1
                       + "<p class=MsoNormal>Oud</p>" + quote + header2
                       + "<p class=MsoNormal>Ouder</p></blockquote></blockquote></div></body></html>")
    }

    func testOutlookWebHistoryBecomesAQuote() {
        let header = #"<div id="divRplyFwdMsg" dir="ltr"><font face="Calibri"><b>From:</b> Jan<br><b>Sent:</b> Monday"#
            + #"<br><b>Subject:</b> X</font><div>&nbsp;</div></div>"#
        let html = #"<div>Nieuw</div><hr style="display:inline-block;width:98%" tabindex="-1">"# + header + "<div>Oud</div>"
        XCTAssertEqual(QuoteLevels.nest(html),
                       #"<div>Nieuw</div><hr style="display:inline-block;width:98%" tabindex="-1"><blockquote type="cite">"#
                       + header + "<div>Oud</div></blockquote>")
    }

    func testBorderTopWithoutHeaderStaysTheSame() {
        let html = #"<div style="border-top: solid 1px #ccc">Nieuwsbrief</div><div>Tekst</div>"#
        XCTAssertEqual(QuoteLevels.nest(html), html)
        // In een tabelcel: het citaat sluit aan het einde van de cel.
        let cell = #"<table><tr><td><div style="border-top:solid #ccc 1pt">Van: Jan<br>Verzonden: ma</div>"#
            + "<p>Oud</p></td></tr></table>"
        XCTAssertEqual(QuoteLevels.nest(cell),
                       #"<table><tr><td><blockquote type="cite"><div style="border-top:solid #ccc 1pt">Van: Jan<br>"#
                       + "Verzonden: ma</div><p>Oud</p></blockquote></td></tr></table>")
    }
}
