import XCTest
@testable import WerkbankCore

final class DictationParserTests: XCTestCase {
    func testAllFieldsWithTrailingDuration() {
        let entry = DictationParser.parse(
            "Klant Willegom, case printer doet het niet, uitgevoerd driver opnieuw geïnstalleerd, kwartier.")
        XCTAssertEqual(entry, DictatedTimeEntry(client: "Willegom", caseTitle: "Printer doet het niet",
                                                performed: "Driver opnieuw geïnstalleerd", minutes: 15))
    }

    func testColonsKeesAndDurationKeyword() {
        let entry = DictationParser.parse("klant: Aiva, kees: mailbox vol. Uitgevoerd: archief ingesteld. Duur 20 minuten")
        XCTAssertEqual(entry, DictatedTimeEntry(client: "Aiva", caseTitle: "Mailbox vol",
                                                performed: "Archief ingesteld", minutes: 20))
    }

    func testTextBeforeFirstKeywordIsClient() {
        let entry = DictationParser.parse("Willegom case wifi valt weg uitgevoerd access point vervangen half uur")
        XCTAssertEqual(entry, DictatedTimeEntry(client: "Willegom", caseTitle: "Wifi valt weg",
                                                performed: "Access point vervangen", minutes: 30))
    }

    func testWithoutKeywordsIsNil() {
        XCTAssertNil(DictationParser.parse("Ik heb bij de bakker de printer gerepareerd"))
    }

    func testCaseWinsOverKeesInName() {
        let entry = DictationParser.parse("Klant Kees de Vries case laptop traag uitgevoerd opgeschoond")
        XCTAssertEqual(entry, DictatedTimeEntry(client: "Kees de Vries", caseTitle: "Laptop traag",
                                                performed: "Opgeschoond"))
    }

    func testKlantInsidePerformedText() {
        let entry = DictationParser.parse(
            "Klant Bakkerij Smit case scanner uitgevoerd klant gebeld en driver geïnstalleerd, drie kwartier")
        XCTAssertEqual(entry, DictatedTimeEntry(client: "Bakkerij Smit", caseTitle: "Scanner",
                                                performed: "Klant gebeld en driver geïnstalleerd", minutes: 45))
    }

    func testDurationInsideTextIsKept() {
        let entry = DictationParser.parse("klant X case Y uitgevoerd 20 minuten gebeld met leverancier")
        XCTAssertEqual(entry?.performed, "20 minuten gebeld met leverancier")
        XCTAssertNil(entry?.minutes)
    }

    func testFillerAfterKeyword() {
        let entry = DictationParser.parse("klant is Ecom, case nieuwe gebruiker, uitgevoerd account aangemaakt")
        XCTAssertEqual(entry?.client, "Ecom")
    }

    func testSpokenDurations() {
        let cases: [(String, Int)] = [
            ("anderhalf uur.", 90), ("1,5 uur", 90), ("twee uur", 120), (", een half uur", 30),
            ("twintig minuten", 20), ("45 minuten", 45), ("drie kwartier", 45), ("twee en een half uur", 150),
        ]
        for (spoken, minutes) in cases {
            let entry = DictationParser.parse("klant Z case backup uitgevoerd controle gedaan \(spoken)")
            XCTAssertEqual(entry?.minutes, minutes, spoken)
            XCTAssertEqual(entry?.performed, "Controle gedaan", spoken)
        }
    }
}
