import XCTest
@testable import WerkbankCore

final class MailComposerTests: XCTestCase {
    private func sample() -> ComposedMail {
        var mail = ComposedMail(from: MailAddress(name: "Gerben Hoogendam", address: "gh@example.nl"),
                                subject: "Vergadering – café", bodyText: "Hoi,\n\nTot morgen & groet.")
        mail.to = [MailAddress(name: "Jos, de Vries", address: "jos@example.nl")]
        mail.cc = [MailAddress(address: "cc@example.nl")]
        mail.bcc = [MailAddress(address: "bcc@example.nl")]
        return mail
    }

    func testParsesAddressLists() {
        let result = MailAddress.parse("Jan <jan@x.nl>, \"Piet, de\" <piet@y.nl>; kapot@, los@z.nl")
        XCTAssertEqual(result.valid.map(\.address), ["jan@x.nl", "piet@y.nl", "los@z.nl"])
        XCTAssertEqual(result.valid[1].name, "Piet, de")
        XCTAssertEqual(result.invalid, ["kapot@"])
    }

    func testRoundTripThroughParser() {
        var mail = sample()
        mail.attachments = [MailAttachment(name: "rapport é.pdf", mediaType: "application/pdf",
                                           data: Data(repeating: 7, count: 5000), contentID: nil)]
        mail.signatureHTML = "<div>Groet<br><img src=\"cid:ABC123\"></div>"
        mail.signatureImage = MailAttachment(name: "logo.png", mediaType: "image/png",
                                             data: Data(repeating: 1, count: 4000), contentID: nil)
        let raw = MailComposer.build(mail)
        let parsed = MailContentParser.parse(raw)
        XCTAssertEqual(parsed.subject, "Vergadering – café")
        XCTAssertEqual(parsed.to, "\"Jos, de Vries\" <jos@example.nl>")
        XCTAssertEqual(parsed.cc, "cc@example.nl")
        XCTAssertTrue(parsed.quotableText.contains("Tot morgen & groet."))
        let text = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("Bcc: bcc@example.nl"))
        XCTAssertTrue(text.contains("Content-ID: <\(MailComposer.signatureContentID)>"))
        XCTAssertFalse(text.contains("cid:ABC123"))
        XCTAssertTrue(text.contains("name*=UTF-8''rapport%20%C3%A9.pdf"))
        // Het logo staat in de tekst (cid), de pdf is een echte bijlage.
        XCTAssertEqual(parsed.files.map(\.name), ["rapport é.pdf"])
        XCTAssertEqual(parsed.files.first?.data.count, 5000)
    }

    /// De afzendernaam uit Voorkeuren: met een streepje ertussen gaat hij tussen aanhalingstekens mee.
    func testSenderNameWithBarIsQuoted() {
        var mail = sample()
        mail.from = MailAddress(name: "Gerben | ITG Solutions", address: "gh@example.nl")
        let text = String(data: MailComposer.build(mail), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("From: \"Gerben | ITG Solutions\" <gh@example.nl>"), text)
        XCTAssertEqual(MailComposer.encodePhrase("Gerben Hoogendam"), "Gerben Hoogendam")
        XCTAssertEqual(MailComposer.encodePhrase("O'Brien-Smith"), "O'Brien-Smith")
        XCTAssertEqual(MailComposer.encodePhrase("Jos, de Vries"), "\"Jos, de Vries\"")
    }

    func testForwardHeaderOnOwnLinesAndOlderMessagesNested() {
        var mail = sample()
        mail.quoteIntro = ReplyBuilder.quoteIntro(date: "1 nov 2026", from: "Jan Jansen", forward: true, subject: "Offerte")
        mail.quote = "Hi,\nDank\n\nOn Sep 18, 2026, Support wrote:\nDag Jan"
        let raw = MailComposer.build(mail)
        let parsed = MailContentParser.parse(raw)
        XCTAssertTrue(parsed.displayHTML.contains("Doorgestuurd bericht ----------<br>"))
        XCTAssertTrue(parsed.displayHTML.contains("Van: Jan Jansen<br>"))
        XCTAssertEqual(parsed.displayHTML.components(separatedBy: "<blockquote").count - 1, 2)
        // De tekstversie: het oudere bericht met twee ">".
        XCTAssertTrue(parsed.quotableText.contains(">> Dag Jan"), parsed.quotableText)
    }

    func testForwardWithHTMLKeepsImages() {
        var mail = sample()
        mail.quoteIntro = ReplyBuilder.quoteIntro(date: "1 nov 2026", from: "Jan Jansen", forward: true, subject: "Offerte")
        mail.quote = "Zie bijlage"
        mail.quoteHTML = #"<p class=MsoNormal>Zie <b>bijlage</b></p><img src="cid:shot@x">"#
        mail.inlineImages = [MailAttachment(name: "shot.png", mediaType: "image/png", data: Data(repeating: 1, count: 4000),
                                            contentID: "shot@x")]
        let raw = MailComposer.build(mail)
        let text = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("Content-ID: <shot@x>"))
        let parsed = MailContentParser.parse(raw)
        XCTAssertTrue(parsed.displayHTML.contains("Zie <b>bijlage</b>"), parsed.displayHTML)
        XCTAssertTrue(parsed.displayHTML.contains("data:image/png;base64,"))
        // De tekstversie blijft de tekst.
        XCTAssertTrue(parsed.quotableText.contains("> Zie bijlage"), parsed.quotableText)
    }

    /// Een antwoord met het origineel als HTML: de afbeelding uit de oorspronkelijke mail gaat mee, de aanhef staat erboven.
    func testReplyWithHTMLQuoteKeepsImages() {
        var mail = sample()
        mail.quoteIntro = ReplyBuilder.quoteIntro(date: "2 okt 2026", from: "Matthijs <m@x.nl>", forward: false)
        mail.quote = "Graag toegang\n[cid:image001.png@01DD]"
        mail.quoteHTML = #"<p>Graag <i>toegang</i></p><img src="cid:image001.png@01DD">"#
        mail.inlineImages = [MailAttachment(name: "image001.png", mediaType: "image/png",
                                            data: Data(repeating: 2, count: 4000), contentID: "image001.png@01DD")]
        let parsed = MailContentParser.parse(MailComposer.build(mail))
        XCTAssertTrue(parsed.displayHTML.contains("Op 2 okt 2026 schreef Matthijs &lt;m@x.nl&gt;:"), parsed.displayHTML)
        XCTAssertTrue(parsed.displayHTML.contains("Graag <i>toegang</i>"), parsed.displayHTML)
        XCTAssertTrue(parsed.displayHTML.contains("data:image/png;base64,"))
        XCTAssertFalse(parsed.displayHTML.contains("[cid:image001"))
    }

    func testIntroHTMLEscapesAndBreaksLines() {
        XCTAssertEqual(MailComposer.introHTML("Van: A <a@x.nl>\nDatum: 1 nov\n"), "Van: A &lt;a@x.nl&gt;<br>\nDatum: 1 nov")
    }

    func testBodyHTMLReplacesPlainParagraphs() {
        var mail = sample()
        mail.bodyText = "Hoi,\n•\tpunt"
        mail.bodyHTML = "<div>Hoi,</div><ul><li><b>punt</b></li></ul>"
        let parsed = MailContentParser.parse(MailComposer.build(mail))
        XCTAssertTrue(parsed.displayHTML.contains("<ul><li><b>punt</b></li></ul>"))
        XCTAssertFalse(parsed.displayHTML.contains("•"))
        XCTAssertTrue(parsed.quotableText.contains("punt"))
    }

    func testInlineImagesInBody() {
        var mail = sample()
        mail.bodyHTML = "<div>Zie <img src=\"cid:afbeelding-1@werkbank\" width=\"200\" height=\"100\"></div>"
        mail.inlineImages = [MailAttachment(name: "scherm.png", mediaType: "image/png",
                                            data: Data(repeating: 3, count: 3000), contentID: "afbeelding-1@werkbank")]
        mail.signatureHTML = "<div>Groet<img src=\"cid:LOGO\"></div>"
        mail.signatureImage = MailAttachment(name: "logo.png", mediaType: "image/png",
                                             data: Data(repeating: 1, count: 2000), contentID: nil)
        let raw = MailComposer.build(mail)
        let text = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("multipart/related"))
        XCTAssertTrue(text.contains("Content-ID: <afbeelding-1@werkbank>"))
        XCTAssertTrue(text.contains("Content-ID: <\(MailComposer.signatureContentID)>"))
        let parsed = MailContentParser.parse(raw)
        // In de tekst, niet als losse bijlage; de weergave zet ze op hun plek.
        XCTAssertTrue(parsed.files.isEmpty)
        XCTAssertEqual(parsed.displayHTML.components(separatedBy: "data:image/png;base64,").count - 1, 2)
    }

    func testSignatureImageDroppedWithoutLogo() {
        var mail = sample()
        mail.signatureHTML = "<div>Groet<img src=\"cid:ABC\"></div>"
        let raw = MailComposer.build(mail)
        let parsed = MailContentParser.parse(raw)
        XCTAssertEqual(parsed.imageCount, 0)
        XCTAssertFalse((String(data: raw, encoding: .utf8) ?? "").contains("multipart/related"))
    }

    func testLongNonASCIISubjectIsEncodedInShortWords() {
        var mail = sample()
        mail.subject = String(repeating: "é", count: 80)
        let raw = String(data: MailComposer.build(mail), encoding: .utf8) ?? ""
        for line in raw.components(separatedBy: "\r\n") where line.hasPrefix("Subject:") || line.hasPrefix(" =?") {
            XCTAssertLessThanOrEqual(line.count, 78)
        }
        XCTAssertEqual(MailContentParser.parse(Data(raw.utf8)).subject, mail.subject)
    }

    func testReplyHelpers() {
        XCTAssertEqual(ReplyBuilder.subject("Re: hallo", forward: false), "Re: hallo")
        XCTAssertEqual(ReplyBuilder.subject("hallo", forward: false), "Re: hallo")
        XCTAssertEqual(ReplyBuilder.subject("hallo", forward: true), "Fwd: hallo")
        let all = ReplyBuilder.recipients(from: "A <a@x.nl>", replyTo: "", to: "me@x.nl, b@x.nl", cc: "c@x.nl, A <a@x.nl>",
                                          replyingAs: "me@x.nl", myAddresses: ["ME@x.nl"], replyAll: true)
        XCTAssertEqual(all.to.map(\.address), ["a@x.nl"])
        XCTAssertEqual(all.cc.map(\.address), ["b@x.nl", "c@x.nl"])
        XCTAssertEqual(ReplyBuilder.references(old: "<1@x>", messageID: "<2@x>"), "<1@x> <2@x>")
        // Eigen verzonden mail: antwoord gaat naar de oorspronkelijke ontvangers.
        let own = ReplyBuilder.recipients(from: "Ik <me@x.nl>", replyTo: "", to: "klant@y.nl", cc: "collega@x.nl",
                                          replyingAs: "me@x.nl", myAddresses: ["me@x.nl"], replyAll: true)
        XCTAssertEqual(own.to.map(\.address), ["klant@y.nl"])
        XCTAssertEqual(own.cc.map(\.address), ["collega@x.nl"])
    }

    /// Mail tussen twee eigen mailboxen: vanuit de ontvangende mailbox gaat het antwoord terug naar de afzender,
    /// vanuit de verzendende mailbox naar de ontvanger. Nooit een leeg Aan-veld.
    func testReplyBetweenOwnMailboxes() {
        let accounts = ["gh@itg.nl", "support@itg.nl"]
        for replyAll in [false, true] {
            let received = ReplyBuilder.recipients(from: "gh <gh@itg.nl>", replyTo: "", to: "support@itg.nl", cc: "",
                                                   replyingAs: "support@itg.nl", myAddresses: accounts, replyAll: replyAll)
            XCTAssertEqual(received.to.map(\.address), ["gh@itg.nl"])
            XCTAssertEqual(received.cc.map(\.address), [])
            let sent = ReplyBuilder.recipients(from: "gh <gh@itg.nl>", replyTo: "", to: "support@itg.nl", cc: "",
                                               replyingAs: "gh@itg.nl", myAddresses: accounts, replyAll: replyAll)
            XCTAssertEqual(sent.to.map(\.address), ["support@itg.nl"])
        }
        // Allen: andere eigen mailboxen niet in Cc.
        let all = ReplyBuilder.recipients(from: "klant@y.nl", replyTo: "", to: "support@itg.nl, gh@itg.nl",
                                          cc: "collega@y.nl", replyingAs: "support@itg.nl", myAddresses: accounts,
                                          replyAll: true)
        XCTAssertEqual(all.to.map(\.address), ["klant@y.nl"])
        XCTAssertEqual(all.cc.map(\.address), ["collega@y.nl"])
        // Aan jezelf: terug naar dat adres.
        let selfMail = ReplyBuilder.recipients(from: "support@itg.nl", replyTo: "", to: "support@itg.nl", cc: "",
                                               replyingAs: "support@itg.nl", myAddresses: accounts, replyAll: false)
        XCTAssertEqual(selfMail.to.map(\.address), ["support@itg.nl"])
    }
}
