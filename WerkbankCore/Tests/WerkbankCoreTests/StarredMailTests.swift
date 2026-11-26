import XCTest
@testable import WerkbankCore

final class StarredMailTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testAgeTurnsOrangeAfterFourDaysAndRedAfterSix() {
        let now = date(11, 26, 9)
        XCTAssertEqual(StarredMail.age(of: date(11, 26, 8), now: now, calendar: calendar), .fresh)
        XCTAssertEqual(StarredMail.age(of: date(11, 22, 23), now: now, calendar: calendar), .fresh)
        XCTAssertEqual(StarredMail.age(of: date(11, 21), now: now, calendar: calendar), .late)
        XCTAssertEqual(StarredMail.age(of: date(11, 20), now: now, calendar: calendar), .late)
        XCTAssertEqual(StarredMail.age(of: date(11, 19), now: now, calendar: calendar), .overdue)
    }

    func testDayMonth() {
        XCTAssertEqual(StarredMail.dayMonth(date(6, 24), calendar: calendar), "24/6")
        XCTAssertEqual(StarredMail.dayMonth(date(11, 3), calendar: calendar), "3/11")
    }

    func testFirstNameDropsSurnameAndCompany() {
        XCTAssertEqual(StarredMail.firstName("Robin Bakker | Kade Solutions", address: "r@kade.nl"), "Robin")
        XCTAssertEqual(StarredMail.firstName("Helpdesk Noord", address: nil), "Helpdesk")
        XCTAssertEqual(StarredMail.firstName("\"Eva\"", address: nil), "Eva")
        XCTAssertEqual(StarredMail.firstName(" | Bedrijf", address: "info@voorbeeld.nl"), "info")
        XCTAssertEqual(StarredMail.firstName(nil, address: nil), "Onbekend")
    }

    func testOneLine() {
        XCTAssertEqual(StarredMail.oneLine("Hoi,\n\nDank voor de offerte.\r\n  Groet"), "Hoi, Dank voor de offerte. Groet")
    }

    func testStarredLabel() {
        XCTAssertTrue(GmailMailItem(id: "1", threadID: "1", subject: "", labels: ["INBOX", "STARRED"]).isStarred)
        XCTAssertFalse(GmailMailItem(id: "1", threadID: "1", subject: "", labels: ["INBOX"]).isStarred)
    }
}
