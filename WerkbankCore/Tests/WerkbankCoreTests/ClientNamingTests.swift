import XCTest
@testable import WerkbankCore

final class ClientNamingTests: XCTestCase {
    func testNameFromDomain() {
        let r = ClientNaming.resolve(displayName: "Jan", address: "jan@studio-noord.nl")
        XCTAssertEqual(r?.name, "Studio Noord")
        XCTAssertEqual(r?.logoDomain, "studio-noord.nl")
        XCTAssertEqual(r?.isFreemail, false)
    }

    func testUnderscoreAndSubdomain() {
        let r = ClientNaming.resolve(displayName: nil, address: "info@mail.de_boer.com")
        XCTAssertEqual(r?.name, "De Boer")
        XCTAssertEqual(r?.registrableDomain, "de_boer.com")
    }

    func testTwoLevelSuffix() {
        XCTAssertEqual(ClientNaming.registrableDomain(of: "shop.acme-corp.co.uk"), "acme-corp.co.uk")
        let r = ClientNaming.resolve(displayName: nil, address: "x@shop.acme-corp.co.uk")
        XCTAssertEqual(r?.name, "Acme Corp")
    }

    func testFreemailUsesDisplayNameWithoutLogo() {
        let r = ClientNaming.resolve(displayName: "Piet Jansen", address: "piet@gmail.com")
        XCTAssertEqual(r?.name, "Piet Jansen")
        XCTAssertNil(r?.logoDomain)
        XCTAssertEqual(r?.isFreemail, true)
        for domain in ["outlook.com", "hotmail.com", "live.nl", "icloud.com", "me.com",
                       "yahoo.com", "ziggo.nl", "kpnmail.nl", "hetnet.nl", "planet.nl", "xs4all.nl"] {
            XCTAssertEqual(ClientNaming.resolve(displayName: "X", address: "a@\(domain)")?.isFreemail, true, domain)
        }
    }

    func testMappingWinsOverDerivedName() {
        let r = ClientNaming.resolve(displayName: "Jan", address: "jan@mail.studio-noord.nl",
                                     mapping: ["studio-noord.nl": "Studio Noord BV"])
        XCTAssertEqual(r?.name, "Studio Noord BV")
        XCTAssertEqual(r?.logoDomain, "studio-noord.nl")
    }

    func testMappingOnFullHostWinsOverRegistrable() {
        let r = ClientNaming.resolve(displayName: nil, address: "a@support.acme.nl",
                                     mapping: ["acme.nl": "Acme", "support.acme.nl": "Acme Support"])
        XCTAssertEqual(r?.name, "Acme Support")
    }

    func testNoAddress() {
        XCTAssertNil(ClientNaming.resolve(displayName: "x", address: nil))
        XCTAssertNil(ClientNaming.resolve(displayName: "x", address: "geen-at-teken"))
    }

    func testQuickEntryHashtag() {
        let e = QuickEntryParser.parse("SSL vernieuwen #Acme")
        XCTAssertEqual(e.title, "SSL vernieuwen")
        XCTAssertEqual(e.label, "Acme")
        let mid = QuickEntryParser.parse("  Bel #De-Vries   terug ")
        XCTAssertEqual(mid.title, "Bel terug")
        XCTAssertEqual(mid.label, "De-Vries")
        let none = QuickEntryParser.parse("Alleen titel")
        XCTAssertEqual(none.title, "Alleen titel")
        XCTAssertNil(none.label)
        // '#' midden in een woord is geen label
        XCTAssertNil(QuickEntryParser.parse("issue#42 oplossen").label)
    }
}
