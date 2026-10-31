import XCTest
@testable import WerkbankCore

final class MailFoldersTests: XCTestCase {
    func testLabelsFromJSONAndTree() {
        let json = """
        {"labels":[
          {"id":"INBOX","name":"INBOX","type":"system"},
          {"id":"CATEGORY_UPDATES","name":"CATEGORY_UPDATES","type":"system"},
          {"id":"Label_3","name":"Klanten/Van Dijk","type":"user","labelListVisibility":"labelShow"},
          {"id":"Label_1","name":"Klanten","type":"user"},
          {"id":"Label_4","name":"Archief 2019","type":"user","labelListVisibility":"labelHide"},
          {"id":"Label_2","name":"Facturen","type":"user"},
          {"id":"Label_5","name":"Klanten/Bakkerij Smit","type":"user"}
        ]}
        """
        let labels = GmailAPI.labels(fromJSON: Data(json.utf8))
        XCTAssertEqual(labels.count, 7)
        XCTAssertEqual(labels.first?.isSystem, true)
        let tree = MailFolders.userTree(labels)
        XCTAssertEqual(tree.map(\.id), ["Label_2", "Label_1", "Label_5", "Label_3"])
        XCTAssertEqual(tree.map(\.depth), [0, 0, 1, 1])
        XCTAssertEqual(tree.last?.leaf, "Van Dijk")
        XCTAssertEqual(MailFolder.label(account: "a", id: "Label_3", name: "Klanten/Van Dijk").title, "Van Dijk")
    }

    func testRequestPerFolder() {
        XCTAssertEqual(MailSearch.request(text: "", folder: .inbox),
                       MailListRequest(query: "", labelIDs: ["INBOX"], includeSpamTrash: false))
        XCTAssertEqual(MailSearch.request(text: "", folder: .all),
                       MailListRequest(query: "", labelIDs: [], includeSpamTrash: false))
        XCTAssertEqual(MailSearch.request(text: "", folder: .trash, unread: true),
                       MailListRequest(query: "is:unread", labelIDs: ["TRASH"], includeSpamTrash: true))
        // Zoeken in Postvak IN zoekt in alle mail; in een andere map in die map.
        XCTAssertEqual(MailSearch.request(text: " offerte ", folder: .inbox),
                       MailListRequest(query: "offerte", labelIDs: [], includeSpamTrash: false))
        XCTAssertEqual(MailSearch.request(text: "offerte", folder: .sent, attachment: true),
                       MailListRequest(query: "offerte has:attachment", labelIDs: ["SENT"], includeSpamTrash: false))
        // Een klant: al zijn mail, ook als er een map open staat.
        XCTAssertEqual(MailSearch.request(text: "", folder: .label(account: "a", id: "Label_1", name: "Klanten"),
                                          clientDomains: ["vandijk.nl"]),
                       MailListRequest(query: "{from:vandijk.nl to:vandijk.nl cc:vandijk.nl}", labelIDs: [],
                                       includeSpamTrash: false))
    }

    func testMailtoLink() {
        let link = MailtoLink.parse("mailto:eva@vandijk.nl,jan@vandijk.nl?subject=Offerte%20dak&cc=piet@vandijk.nl&body=Hoi%0D%0Aregel%202+3")
        XCTAssertEqual(link, MailPrefill(to: "eva@vandijk.nl, jan@vandijk.nl", cc: "piet@vandijk.nl",
                                         subject: "Offerte dak", body: "Hoi\nregel 2+3"))
        XCTAssertEqual(MailtoLink.parse("MAILTO:?to=a@b.nl&bcc=c@d.nl")?.to, "a@b.nl")
        XCTAssertEqual(MailtoLink.parse("MAILTO:?to=a@b.nl&bcc=c@d.nl")?.bcc, "c@d.nl")
        XCTAssertEqual(MailtoLink.parse("mailto:%22Eva%22%20%3Ceva@vandijk.nl%3E")?.to, "\"Eva\" <eva@vandijk.nl>")
        XCTAssertNil(MailtoLink.parse("https://voorbeeld.nl"))
    }
}
