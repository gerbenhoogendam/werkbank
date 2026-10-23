import XCTest
@testable import WerkbankCore

final class ClientListTests: XCTestCase {
    func testSemicolonWithHeaderAndQuotes() {
        let csv = "\u{FEFF}Debiteur;Naam;Plaats\r\n1001;\"Bakkerij de Korenschoof\";Barneveld\r\n1002;\"Smit \"\"&\"\" Zn\";Ede\r\n\r\n"
        let records = ClientList.parseCSV(csv)
        XCTAssertEqual(records, [
            ClientRecord(name: "Bakkerij de Korenschoof", details: ["1001", "Barneveld"]),
            ClientRecord(name: "Smit \"&\" Zn", details: ["1002", "Ede"]),
        ])
    }

    func testCommaWithoutHeaderUsesFirstColumn() {
        let records = ClientList.parseCSV("Acme BV,acme.nl\nStudio Noord,studionoord.nl\nAcme BV,dubbel\n")
        XCTAssertEqual(records.map(\.name), ["Acme BV", "Studio Noord"])
        XCTAssertEqual(records[1].details, ["studionoord.nl"])
    }

    func testCommaInsideQuotedCell() {
        let records = ClientList.parseCSV("klant,plaats\n\"Jansen, Pietersen & Co\",Utrecht\n")
        XCTAssertEqual(records, [ClientRecord(name: "Jansen, Pietersen & Co", details: ["Utrecht"])])
    }

    func testSearchRanking() {
        let records = [
            ClientRecord(name: "Noordhoek Installatie", details: ["2001"]),
            ClientRecord(name: "Studio Noord", details: ["2002"]),
            ClientRecord(name: "Café Noorderlicht", details: []),
            ClientRecord(name: "Bakkerij West", details: ["Noordwijk"]),
            ClientRecord(name: "Noord", details: []),
            ClientRecord(name: "Zuidnoordbouw", details: []),
        ]
        // Gelijk, begint ermee, een woord begint ermee (alfabetisch), bevat het, andere kolom.
        let names = ClientList.search("noord", in: records).map(\.name)
        XCTAssertEqual(names, ["Noord", "Noordhoek Installatie", "Café Noorderlicht", "Studio Noord", "Zuidnoordbouw",
                               "Bakkerij West"])
    }

    func testSearchIgnoresAccentsAndMatchesDetails() {
        let records = [ClientRecord(name: "Café de Zon", details: ["3001", "Ede"])]
        XCTAssertEqual(ClientList.search("cafe", in: records).count, 1)
        XCTAssertEqual(ClientList.search("3001", in: records).count, 1)
        XCTAssertEqual(ClientList.search("zon ede", in: records).count, 1)
        XCTAssertTrue(ClientList.search("utrecht", in: records).isEmpty)
        XCTAssertTrue(ClientList.search("  ", in: records).isEmpty)
    }
}
