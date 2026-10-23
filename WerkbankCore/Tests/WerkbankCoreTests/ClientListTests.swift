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

    func testTypoFindsClient() {
        let records = [
            ClientRecord(name: "Interface Communicatie"),
            ClientRecord(name: "Schildersbedrijf Willegom"),
            ClientRecord(name: "Combo Design"),
            ClientRecord(name: "Bakkerij West"),
            ClientRecord(name: "Aiva Corporate", details: ["aivacorporate.com"]),
        ]
        // "ecom": één verkeerde letter in "egom" gaat vóór een ontbrekende letter ("com"); een domein op ".com"
        // telt niet als "ecom".
        let names = ClientList.search("ecom", in: records).map(\.name)
        XCTAssertEqual(names.first, "Schildersbedrijf Willegom")
        XCTAssertFalse(names.contains("Bakkerij West"))
        // Korte zoektermen: geen tikfouten.
        XCTAssertTrue(ClientList.search("wst", in: records).isEmpty)
    }

    func testPunctuationIgnored() {
        let records = [ClientRecord(name: "Paula’s Choice Europe B.V."), ClientRecord(name: "J.V.I. Holding B.V.")]
        XCTAssertEqual(ClientList.search("paulas", in: records).map(\.name), ["Paula’s Choice Europe B.V."])
        XCTAssertEqual(ClientList.search("jvi", in: records).map(\.name), ["J.V.I. Holding B.V."])
    }

    func testStatusMarkersAndDomains() {
        let csv = "Klantnaam,Domeinnaam\r\nFAILLIET Romex Benelux,romexbenelux.nl\r\nRomex Nieuw,www.romex.nl\r\n"
            + "Voorbeeld NIET GEBRUIKEN,voorbeeld.nl\r\n\"Brink, Coaching & Advies\",brink.nl\r\nZonder Domein,\r\n"
        let records = ClientList.parseCSV(csv)
        XCTAssertEqual(records.map(\.name), ["Romex Benelux", "Romex Nieuw", "Voorbeeld", "Brink, Coaching & Advies",
                                             "Zonder Domein"])
        XCTAssertEqual(records[0].status, "failliet")
        XCTAssertEqual(records[2].status, "niet gebruiken")
        XCTAssertNil(records[1].status)
        XCTAssertEqual(records[1].domains, ["romex.nl"])
        XCTAssertEqual(records[4].domains, [])
        // Niet meer actief: achteraan.
        XCTAssertEqual(ClientList.search("romex", in: records).map(\.name), ["Romex Nieuw", "Romex Benelux"])
    }

    func testDomainMapSkipsFreemailAndShared() {
        let records = [
            ClientRecord(name: "Alpha", domains: ["alpha.nl"]),
            ClientRecord(name: "Beta", domains: ["gmail.com"]),
            ClientRecord(name: "Gamma", domains: ["gedeeld.nl"]),
            ClientRecord(name: "Delta", domains: ["gedeeld.nl"]),
            ClientRecord(name: "Oud", domains: ["over.nl"], status: "failliet"),
            ClientRecord(name: "Nieuw", domains: ["over.nl"]),
        ]
        XCTAssertEqual(ClientList.domainMap(records), ["alpha.nl": "Alpha", "over.nl": "Nieuw"])
    }
}
