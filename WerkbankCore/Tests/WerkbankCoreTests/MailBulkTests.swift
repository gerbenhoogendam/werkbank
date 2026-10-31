import XCTest
@testable import WerkbankCore

final class MailBulkTests: XCTestCase {
    private func item(_ id: String, from: String, minutesAgo: Double = 0) -> GmailMailItem {
        GmailMailItem(id: id, threadID: "t\(id)", fromAddress: from, subject: id,
                      date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
    }

    func testRulesMatchSenderDomainAndKind() {
        let mail = item("1", from: "Status@Mail.Leverancier.nl")
        XCTAssertTrue(BulkRule.sender("status@mail.leverancier.nl").matches(mail, kind: .notification))
        XCTAssertTrue(BulkRule.domain("leverancier.nl").matches(mail, kind: .notification))
        XCTAssertFalse(BulkRule.domain("verancier.nl").matches(mail, kind: .notification))
        XCTAssertTrue(BulkRule.kind(.notification).matches(mail, kind: .notification))
        XCTAssertFalse(BulkRule.kind(.newsletter).matches(mail, kind: .notification))
        XCTAssertTrue(MailBulk.isExcluded(mail, kind: .notification, rules: [.sender("x@y.nl"), .domain("leverancier.nl")]))
        XCTAssertFalse(MailBulk.isExcluded(mail, kind: .notification, rules: []))
    }

    func testRulesRoundTrip() {
        let rules: [BulkRule] = [.sender("a@b.nl"), .domain("c.nl"), .kind(.newsletter)]
        XCTAssertEqual(MailBulk.decode(MailBulk.encode(rules)), rules)
        XCTAssertEqual(MailBulk.decode(nil), [])
        XCTAssertEqual(BulkRule.kind(.newsletter).title, "Alle nieuwsbrieven")
    }

    func testGroupsBySenderLargestFirst() {
        let items = [
            item("1", from: "news@winkel.nl", minutesAgo: 1),
            item("2", from: "alert@dienst.nl", minutesAgo: 2),
            item("3", from: "NEWS@winkel.nl", minutesAgo: 3),
            item("4", from: "info@vereniging.nl", minutesAgo: 0),
        ]
        let groups = MailBulk.groups(items)
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["1", "3"], ["4"], ["2"]])
    }
}
