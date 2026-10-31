import XCTest
@testable import WerkbankCore

final class MailModeTests: XCTestCase {
    func testKindFromCategoriesHeadersAndSender() {
        XCTAssertEqual(MailKind.classify(labels: ["INBOX", "CATEGORY_PROMOTIONS"], fromAddress: "a@shop.nl",
                                         listUnsubscribe: false, bulk: false, isKnownClient: false), .newsletter)
        XCTAssertEqual(MailKind.classify(labels: ["INBOX", "CATEGORY_UPDATES"], fromAddress: "a@bank.nl",
                                         listUnsubscribe: false, bulk: false, isKnownClient: false), .notification)
        XCTAssertEqual(MailKind.classify(labels: ["INBOX"], fromAddress: "nieuws@vakblad.nl",
                                         listUnsubscribe: true, bulk: false, isKnownClient: false), .newsletter)
        XCTAssertEqual(MailKind.classify(labels: ["INBOX"], fromAddress: "noreply@github.com",
                                         listUnsubscribe: false, bulk: false, isKnownClient: false), .notification)
        XCTAssertEqual(MailKind.classify(labels: ["INBOX"], fromAddress: "eva@vandijk.nl",
                                         listUnsubscribe: false, bulk: false, isKnownClient: false), .person)
        // Een klant met een afmeldlink in zijn mail blijft persoonlijk.
        XCTAssertEqual(MailKind.classify(labels: ["INBOX", "CATEGORY_UPDATES"], fromAddress: "eva@vandijk.nl",
                                         listUnsubscribe: true, bulk: false, isKnownClient: true), .person)
    }

    func testMailItemFromMetadata() throws {
        let json = """
        {"id":"m1","threadId":"t1","labelIds":["INBOX","UNREAD"],"snippet":"Kunnen we dinsdag bellen?","internalDate":"1793455260000",
         "payload":{"mimeType":"multipart/mixed","headers":[
           {"name":"From","value":"Eva van Dijk <Eva@VanDijk.nl>"},
           {"name":"To","value":"Gerben <gerben@werk.nl>, \\"Ruud\\" <ruud@vandijk.nl>"},
           {"name":"Cc","value":"sanne@studionoord.nl"},
           {"name":"Subject","value":"=?UTF-8?Q?Koppeling_voorraadsysteem?="},
           {"name":"List-Unsubscribe","value":"<mailto:x@y.nl>"},
           {"name":"Precedence","value":"bulk"}]}}
        """
        let item = try XCTUnwrap(GmailAPI.mailItem(fromMessageJSON: Data(json.utf8)))
        XCTAssertEqual(item.threadID, "t1")
        XCTAssertEqual(item.fromName, "Eva van Dijk")
        XCTAssertEqual(item.subject, "Koppeling voorraadsysteem")
        XCTAssertEqual(item.recipients, ["gerben@werk.nl", "ruud@vandijk.nl", "sanne@studionoord.nl"])
        XCTAssertTrue(item.isUnread)
        XCTAssertTrue(item.isInInbox)
        XCTAssertTrue(item.mayHaveAttachment)
        XCTAssertTrue(item.listUnsubscribe)
        XCTAssertTrue(item.bulk)
        XCTAssertEqual(item.addresses.first, "eva@vandijk.nl")
    }

    func testSearchQuery() {
        XCTAssertEqual(MailSearch.query(text: ""), "in:inbox")
        XCTAssertEqual(MailSearch.query(text: " factuur ", attachment: true, unread: true), "factuur has:attachment is:unread")
        XCTAssertEqual(MailSearch.query(text: "", clientDomains: ["vandijk.nl"]), "{from:vandijk.nl to:vandijk.nl cc:vandijk.nl}")
        XCTAssertEqual(MailSearch.query(text: "offerte", clientDomains: ["a.nl", "b.nl"]),
                       "offerte {from:a.nl from:b.nl to:a.nl to:b.nl cc:a.nl cc:b.nl}")
    }

    func testClientRankingCountsEachMailOncePerClient() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0
        let map = ["vandijk.nl": "Van Dijk", "bakkerijsmit.nl": "Bakkerij Smit"]
        let own: Set<String> = ["gerben@werk.nl"]
        let records = [
            MailActivityRecord(id: "1", date: now.addingTimeInterval(-1 * day), addresses: ["eva@vandijk.nl", "gerben@werk.nl"], isSent: false),
            MailActivityRecord(id: "2", date: now.addingTimeInterval(-2 * day), addresses: ["gerben@werk.nl", "eva@vandijk.nl", "ruud@mail.vandijk.nl"], isSent: true),
            MailActivityRecord(id: "3", date: now.addingTimeInterval(-20 * day), addresses: ["jan@bakkerijsmit.nl"], isSent: false),
            MailActivityRecord(id: "3", date: now.addingTimeInterval(-20 * day), addresses: ["jan@bakkerijsmit.nl"], isSent: false),
            MailActivityRecord(id: "4", date: now.addingTimeInterval(-45 * day), addresses: ["jan@bakkerijsmit.nl"], isSent: false),
            MailActivityRecord(id: "5", date: now.addingTimeInterval(-3 * day), addresses: ["iemand@gmail.com"], isSent: false),
        ]
        let ranking = ClientActivity.ranking(records: records, domainMap: map, ownAddresses: own, now: now)
        XCTAssertEqual(ranking.map(\.name), ["Van Dijk", "Bakkerij Smit"])
        XCTAssertEqual(ranking.map(\.count), [2, 1])
        XCTAssertEqual(ranking[0].weeks, [0, 0, 0, 2])
        XCTAssertEqual(ranking[1].weeks, [0, 1, 0, 0])
        XCTAssertEqual(ClientActivity.client(forAddress: "ruud@mail.vandijk.nl", domainMap: map), "Van Dijk")
    }
}
