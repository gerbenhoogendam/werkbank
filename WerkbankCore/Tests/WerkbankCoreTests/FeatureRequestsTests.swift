import XCTest
@testable import WerkbankCore

final class FeatureRequestsTests: XCTestCase {
    func testSplitsOnConnectivesAndKeepsContinuations() {
        XCTAssertEqual(FeatureRequestSplitter.split(
            "De knop moet groter. Daarnaast wil ik dat de lijst op datum sorteert. Ook mag het menu weg."),
            ["De knop moet groter.", "Daarnaast wil ik dat de lijst op datum sorteert.", "Ook mag het menu weg."])
        XCTAssertEqual(FeatureRequestSplitter.split("De knop moet groter. Hij staat nu te ver naar links."),
                       ["De knop moet groter. Hij staat nu te ver naar links."])
        XCTAssertEqual(FeatureRequestSplitter.split("   "), [])
    }

    func testSplitsEnumerationsAndDropsTheNumbering() {
        XCTAssertEqual(FeatureRequestSplitter.split(
            "Ten eerste de zoekbalk is te klein, ten tweede de kleuren in het donkere thema kloppen niet."),
            ["De zoekbalk is te klein", "De kleuren in het donkere thema kloppen niet."])
        XCTAssertEqual(FeatureRequestSplitter.split("Maak bijv. de knop groter. Punt twee: het menu mag weg."),
                       ["Maak bijv. de knop groter.", "Het menu mag weg."])
        XCTAssertEqual(FeatureRequestSplitter.split("1. Knop groter. 2. Menu weg."), ["Knop groter.", "Menu weg."])
        XCTAssertEqual(FeatureRequestSplitter.split("In de mailmodus wil ik een teller, en daarnaast moet zoeken sneller."),
                       ["In de mailmodus wil ik een teller", "En daarnaast moet zoeken sneller."])
    }

    func testPlatformFromText() {
        XCTAssertEqual(FeatureRequestSplitter.platform(of: "Op de iPhone is de knop te klein"), .mobile)
        XCTAssertEqual(FeatureRequestSplitter.platform(of: "In de iOS-app mist het archief"), .mobile)
        XCTAssertEqual(FeatureRequestSplitter.platform(of: "In de mailmodus op de Mac mist een knop"), .desktop)
        XCTAssertNil(FeatureRequestSplitter.platform(of: "De kleuren kloppen niet"))
        XCTAssertNil(FeatureRequestSplitter.platform(of: "Op de Mac en de iPhone hetzelfde menu"))
    }

    func testPromptSeparatesDesktopAndMobile() {
        let prompt = FeaturePrompt.build([
            .init(text: "Knop groter", platform: .desktop),
            .init(text: "Archief op de iPhone", platform: .mobile),
            .init(text: " Menu weg \n", platform: .desktop),
        ])
        XCTAssertTrue(prompt.contains("(2 desktop, 1 mobiel)"))
        XCTAssertTrue(prompt.contains("## Desktop (macOS)\n1. Knop groter\n2. Menu weg\n"))
        XCTAssertTrue(prompt.contains("## Mobiel (iOS)\n1. Archief op de iPhone\n"))
        XCTAssertFalse(FeaturePrompt.build([.init(text: "A", platform: .desktop)]).contains("## Mobiel"))
    }
}
