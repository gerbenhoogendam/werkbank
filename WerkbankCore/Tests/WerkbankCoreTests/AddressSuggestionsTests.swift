import XCTest
@testable import WerkbankCore

final class AddressSuggestionsTests: XCTestCase {
    private let candidates = [
        AddressCandidate(name: "Eva van Dijk", address: "eva@vandijk.nl", client: "Van Dijk Bouw", score: 2),
        AddressCandidate(name: "Jan Smit", address: "jan.smit@vandijk.nl", client: "Van Dijk Bouw", score: 9),
        AddressCandidate(name: "Evert Jansen", address: "e.jansen@voorbeeld.nl", score: 5),
        AddressCandidate(address: "planning@vandijk.nl", client: "Van Dijk Bouw", score: 1),
    ]

    func testCurrentTokenIgnoresCommasInQuotes() {
        XCTAssertEqual(AddressSuggestions.currentToken(in: "eva@vandijk.nl, ja"), "ja")
        XCTAssertEqual(AddressSuggestions.currentToken(in: "\"Dijk, Eva\" <eva@vandijk.nl>"), "\"Dijk, Eva\" <eva@vandijk.nl>")
        XCTAssertEqual(AddressSuggestions.currentToken(in: "a@b.nl; "), "")
    }

    func testReplacingCurrentTokenKeepsEarlierAddresses() {
        let text = AddressSuggestions.replacingCurrentToken(in: "eva@vandijk.nl, ja",
                                                            with: MailAddress(name: "Jan Smit", address: "jan.smit@vandijk.nl"))
        XCTAssertEqual(text, "eva@vandijk.nl, Jan Smit <jan.smit@vandijk.nl>, ")
        let quoted = AddressSuggestions.replacingCurrentToken(in: "di", with: MailAddress(name: "Dijk, Eva", address: "eva@vandijk.nl"))
        XCTAssertEqual(quoted, "\"Dijk, Eva\" <eva@vandijk.nl>, ")
        XCTAssertEqual(MailAddress.parse(quoted).valid.map(\.address), ["eva@vandijk.nl"])
    }

    func testSearchRanksPrefixFirstThenScore() {
        // "ev": Eva en Evert beginnen ermee; Evert mail je vaker.
        XCTAssertEqual(AddressSuggestions.search("ev", in: candidates).map(\.address),
                       ["e.jansen@voorbeeld.nl", "eva@vandijk.nl"])
        // "jan": Jan Smit (begint ermee) vóór Evert Jansen (een woord in de naam), ondanks de score.
        XCTAssertEqual(AddressSuggestions.search("jan", in: candidates).map(\.address),
                       ["jan.smit@vandijk.nl", "e.jansen@voorbeeld.nl"])
    }

    func testClientNameGivesThatClientsPeople() {
        let found = AddressSuggestions.search("van dijk", in: candidates)
        XCTAssertEqual(found.map(\.address), ["jan.smit@vandijk.nl", "eva@vandijk.nl", "planning@vandijk.nl"])
        let excluded = AddressSuggestions.search("bouw", in: candidates, excluding: ["jan.smit@vandijk.nl"])
        XCTAssertEqual(excluded.map(\.address), ["eva@vandijk.nl", "planning@vandijk.nl"])
    }

    func testScoresWeighSentAndRecentMail() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [
            MailActivityRecord(id: "1", date: now, addresses: ["eva@vandijk.nl", "ik@werk.nl"], isSent: true),
            MailActivityRecord(id: "2", date: now, addresses: ["jan@vandijk.nl", "ik@werk.nl"], isSent: false),
            MailActivityRecord(id: "3", date: now.addingTimeInterval(-90 * 86_400), addresses: ["oud@vandijk.nl"], isSent: true),
            MailActivityRecord(id: "4", date: now, addresses: ["noreply@dienst.nl"], isSent: false),
        ]
        let scores = AddressSuggestions.scores(records: records, ownAddresses: ["ik@werk.nl"], now: now)
        XCTAssertEqual(scores["eva@vandijk.nl"], 3)
        XCTAssertEqual(scores["jan@vandijk.nl"], 1)
        XCTAssertEqual(scores["oud@vandijk.nl"] ?? 0, 1.5, accuracy: 0.001)
        XCTAssertNil(scores["ik@werk.nl"])
        XCTAssertNil(scores["noreply@dienst.nl"])
    }
}
