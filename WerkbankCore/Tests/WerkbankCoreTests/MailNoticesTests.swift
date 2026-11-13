import XCTest
@testable import WerkbankCore

final class MailNoticesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func mail(_ id: String, minutesAgo: Double?, from: String = "Jan") -> GmailMailItem {
        GmailMailItem(id: id, threadID: "t" + id, fromName: from, fromAddress: "\(from.lowercased())@x.nl",
                      subject: "Onderwerp \(id)", snippet: "Begin \(id)",
                      date: minutesAgo.map { now.addingTimeInterval(-$0 * 60) }, labels: ["INBOX", "UNREAD"])
    }

    func testOnlyMailSinceTheLastCheckIsNew() {
        let since = now.addingTimeInterval(-60)   // een minuut geleden gekeken
        let items = [mail("nieuw", minutesAgo: 0.5), mail("net", minutesAgo: 2.5), mail("oud", minutesAgo: 30),
                     mail("geen-datum", minutesAgo: nil)]
        // "net" valt binnen de speling van twee minuten; "oud" is weer op ongelezen gezet en geen nieuwe mail.
        XCTAssertEqual(MailNotices.fresh(items, notified: [], since: since).map(\.id), ["net", "nieuw"])
    }

    func testAlreadyNotifiedMailIsSkipped() {
        let items = [mail("a", minutesAgo: 0.2), mail("b", minutesAgo: 0.1)]
        XCTAssertEqual(MailNotices.fresh(items, notified: ["a"], since: now.addingTimeInterval(-60)).map(\.id), ["b"])
    }

    func testTextNamesTheMailboxOnlyWhenGiven() {
        let item = mail("1", minutesAgo: 0, from: "Ester")
        XCTAssertEqual(MailNotices.text(for: item, mailbox: nil).title, "Ester")
        XCTAssertEqual(MailNotices.text(for: item, mailbox: "support").title, "Ester · support")
        XCTAssertEqual(MailNotices.text(for: item, mailbox: nil).subtitle, "Onderwerp 1")
        var empty = item
        empty.subject = ""
        XCTAssertEqual(MailNotices.text(for: empty, mailbox: nil).subtitle, "(geen onderwerp)")
    }

    func testSummaryNamesTheNewestSenders() {
        let items = [mail("1", minutesAgo: 5, from: "Anna"), mail("2", minutesAgo: 4, from: "Bas"),
                     mail("3", minutesAgo: 3, from: "Bas"), mail("4", minutesAgo: 2, from: "Cor"),
                     mail("5", minutesAgo: 1, from: "Dirk")]
        let summary = MailNotices.summary(items, mailbox: "support")
        XCTAssertEqual(summary.title, "5 nieuwe mails · support")
        XCTAssertEqual(summary.body, "Dirk, Cor, Bas en anderen")
    }

    func testBadge() {
        XCTAssertNil(MailNotices.badge(0))
        XCTAssertEqual(MailNotices.badge(7), "7")
        XCTAssertEqual(MailNotices.badge(250), "99+")
    }
}
