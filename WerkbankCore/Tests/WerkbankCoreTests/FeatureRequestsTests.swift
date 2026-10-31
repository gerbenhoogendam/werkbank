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

    func testPromptSeparatesDesktopAndMobileWithStamps() {
        let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
        let first = Date(timeIntervalSince1970: 1_793_451_900)    // 31-10-2026 14:05 in Amsterdam
        let second = Date(timeIntervalSince1970: 1_793_608_200)   // 02-11-2026 09:30
        let items: [FeaturePrompt.Item] = [
            .init(text: "Knop groter", platform: .desktop, date: first, device: "Mac", hasScreenshot: true),
            .init(text: "Archief op de iPhone", platform: .mobile, date: second, device: "iPhone", hasScreenshot: true),
            .init(text: " Menu weg \n", platform: .desktop),
        ]
        XCTAssertEqual(FeaturePrompt.numbered(items).map(\.reference), ["D1", "D2", "M1"])
        XCTAssertEqual(FeaturePrompt.numbered(items).map(\.index), [0, 2, 1])

        let plain = FeaturePrompt.build(items, timeZone: amsterdam)
        XCTAssertTrue(plain.contains("(2 desktop, 1 mobiel)"))
        XCTAssertTrue(plain.contains("## Desktop (macOS)\nD1 (31-10-2026 14:05, Mac): Knop groter\nD2: Menu weg\n"))
        XCTAssertTrue(plain.contains("## Mobiel (iOS)\nM1 (02-11-2026 09:30, iPhone): Archief op de iPhone\n"))
        XCTAssertFalse(plain.contains("screenshot"))

        let document = FeaturePrompt.build(items, screenshotsInDocument: true, timeZone: amsterdam)
        XCTAssertTrue(document.contains("D1 (31-10-2026 14:05, Mac, screenshot): Knop groter"))
        XCTAssertTrue(document.contains("eigen pagina met hetzelfde nummer"))
        XCTAssertFalse(FeaturePrompt.build([.init(text: "A", platform: .desktop)]).contains("## Mobiel"))
        XCTAssertEqual(FeaturePrompt.stamp(first, timeZone: amsterdam, seconds: true), "31-10-2026 14:05:00")
    }
}
