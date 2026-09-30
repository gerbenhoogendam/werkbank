import XCTest
@testable import WerkbankCore

final class BillingTests: XCTestCase {
    func testRoundUpTo15() {
        XCTAssertEqual(Billing.billedMinutes(seconds: 0, unitMinutes: 15), 0)
        XCTAssertEqual(Billing.billedMinutes(seconds: 1, unitMinutes: 15), 15)
        XCTAssertEqual(Billing.billedMinutes(seconds: 15 * 60, unitMinutes: 15), 15)
        XCTAssertEqual(Billing.billedMinutes(seconds: 15 * 60 + 1, unitMinutes: 15), 30)
        XCTAssertEqual(Billing.billedMinutes(seconds: 67 * 60, unitMinutes: 15), 75)
    }

    func testRoundUpTo6And1() {
        XCTAssertEqual(Billing.billedMinutes(seconds: 7 * 60, unitMinutes: 6), 12)
        XCTAssertEqual(Billing.billedMinutes(seconds: 6 * 60, unitMinutes: 6), 6)
        XCTAssertEqual(Billing.billedMinutes(seconds: 61, unitMinutes: 1), 2)
        XCTAssertEqual(Billing.billedMinutes(seconds: 60, unitMinutes: 1), 1)
    }

    func testHoursAndFormatting() {
        XCTAssertEqual(Billing.billedHours(seconds: 10 * 60, unitMinutes: 15), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Billing.formatHours(0.25), "0,25")
        XCTAssertEqual(Billing.formatHours(1.5), "1,50")
        XCTAssertEqual(Billing.formatHMS(4027), "1:07:07")
        XCTAssertEqual(Billing.formatHM(4027), "1:07")
        XCTAssertEqual(Billing.formatHM(59), "0:00")
    }

    func testCSVQuotesWindowsLineEndings() {
        XCTAssertEqual(CSVBillingExporter.escape("a\r\nb"), "\"a\r\nb\"")
    }

    func testCSV() throws {
        let line = BillingLine(date: Date(timeIntervalSince1970: 1_790_000_000),
                               client: "Acme", title: "SSL; vernieuwen", workDescription: "Zei \"klaar\"",
                               minutes: 40, billedHours: 0.75, source: "To-do")
        let data = try CSVBillingExporter().export([line])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        let rows = text.components(separatedBy: "\r\n")
        XCTAssertEqual(rows[0], "datum;klant;titel;omschrijving;minuten;afgeronde uren;bron")
        XCTAssertTrue(rows[1].hasSuffix(";Acme;\"SSL; vernieuwen\";\"Zei \"\"klaar\"\"\";40;0,75;To-do"), rows[1])
    }
}
