import XCTest
@testable import WerkbankCore

final class GmailHistoryTests: XCTestCase {
    private func item(_ id: String, labels: [String]) -> GmailMailItem {
        GmailMailItem(id: id, threadID: "t-" + id, subject: "Onderwerp", labels: labels)
    }

    func testPageGivesTheChangesInOrder() throws {
        let json = """
        {
          "history": [
            { "id": "101", "messages": [{ "id": "a", "threadId": "ta" }],
              "labelsRemoved": [{ "message": { "id": "a", "threadId": "ta", "labelIds": ["INBOX"] }, "labelIds": ["UNREAD"] }] },
            { "id": "102",
              "labelsAdded": [{ "message": { "id": "b", "threadId": "tb" }, "labelIds": ["Label_7", "STARRED"] }] },
            { "id": "103", "messagesDeleted": [{ "message": { "id": "c", "threadId": "tc" } }] }
          ],
          "nextPageToken": "volgende",
          "historyId": "110"
        }
        """
        let page = try XCTUnwrap(GmailHistory.page(fromJSON: Data(json.utf8)))
        XCTAssertEqual(page.changes, [
            .labelsRemoved(id: "a", labels: ["UNREAD"]),
            .labelsAdded(id: "b", labels: ["Label_7", "STARRED"]),
            .deleted(id: "c"),
        ])
        XCTAssertEqual(page.nextPageToken, "volgende")
        XCTAssertEqual(page.historyID, "110")
    }

    func testPageWithoutChanges() throws {
        let page = try XCTUnwrap(GmailHistory.page(fromJSON: Data(#"{ "historyId": "42" }"#.utf8)))
        XCTAssertTrue(page.changes.isEmpty)
        XCTAssertNil(page.nextPageToken)
        XCTAssertEqual(page.historyID, "42")
    }

    func testHistoryIDAsNumber() throws {
        let page = try XCTUnwrap(GmailHistory.page(fromJSON: Data(#"{ "historyId": 42 }"#.utf8)))
        XCTAssertEqual(page.historyID, "42")
        XCTAssertEqual(GmailHistory.historyID(fromProfileJSON: Data(#"{ "emailAddress": "a@voorbeeld.nl", "historyId": "9001" }"#.utf8)), "9001")
        XCTAssertNil(GmailHistory.historyID(fromProfileJSON: Data(#"{ "emailAddress": "a@voorbeeld.nl" }"#.utf8)))
    }

    func testNoJSONIsNoPage() {
        XCTAssertNil(GmailHistory.page(fromJSON: Data("geen json".utf8)))
    }

    func testApplyUpdatesLabelsInOrder() {
        var items = ["a": item("a", labels: ["INBOX", "UNREAD"]), "b": item("b", labels: ["INBOX"])]
        GmailHistory.apply([
            .labelsRemoved(id: "a", labels: ["UNREAD"]),
            .labelsAdded(id: "b", labels: ["UNREAD"]),
            .labelsRemoved(id: "b", labels: ["INBOX"]),
            .labelsAdded(id: "a", labels: ["UNREAD"]),
            .labelsRemoved(id: "a", labels: ["UNREAD", "INBOX"]),
        ], to: &items)
        XCTAssertEqual(items["a"]?.labels, [])
        XCTAssertEqual(items["b"]?.labels, ["UNREAD"])
    }

    func testApplyIsSafeToRepeat() {
        let changes: [GmailHistory.Change] = [
            .labelsAdded(id: "a", labels: ["UNREAD"]),
            .labelsRemoved(id: "a", labels: ["INBOX"]),
        ]
        var once = ["a": item("a", labels: ["INBOX"])]
        GmailHistory.apply(changes, to: &once)
        var twice = once
        GmailHistory.apply(changes, to: &twice)
        XCTAssertEqual(once["a"]?.labels, ["UNREAD"])
        XCTAssertEqual(twice, once)
    }

    func testApplySkipsUnknownMailAndRemovesDeleted() {
        var items = ["a": item("a", labels: ["INBOX"])]
        GmailHistory.apply([.labelsAdded(id: "onbekend", labels: ["UNREAD"]), .deleted(id: "a")], to: &items)
        XCTAssertTrue(items.isEmpty)
    }
}
