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
                                          myAddresses: ["ME@x.nl"], replyAll: true)
        XCTAssertEqual(all.to.map(\.address), ["a@x.nl"])
        XCTAssertEqual(all.cc.map(\.address), ["b@x.nl", "c@x.nl"])
        XCTAssertEqual(ReplyBuilder.references(old: "<1@x>", messageID: "<2@x>"), "<1@x> <2@x>")
    }
}
