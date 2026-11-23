import XCTest
@testable import WerkbankCore

final class SendLaterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // 23 nov 2026 is een maandag.

    func testLateEveningOffersTomorrow() {
        let choices = SendLater.choices(now: date(23, 23, 55), calendar: calendar)
        XCTAssertEqual(choices.map(\.title), ["Morgenochtend 07:56", "Morgenmiddag 13:07", "Maandagochtend 07:56"])
        XCTAssertEqual(choices.first?.date, date(24, 7, 56))
        XCTAssertEqual(choices.last?.date, date(30, 7, 56))
    }

    func testAfterMidnightOffersThisMorning() {
        let choices = SendLater.choices(now: date(24, 0, 30), calendar: calendar)
        XCTAssertEqual(choices.first?.title, "Vanochtend 07:56")
        XCTAssertEqual(choices.first?.date, date(24, 7, 56))
        XCTAssertEqual(choices[1].title, "Vanmiddag 13:07")
    }

    func testSundayNightMondayIsTomorrow() {
        let choices = SendLater.choices(now: date(29, 23, 0), calendar: calendar)
        XCTAssertEqual(choices.map(\.title), ["Morgenochtend 07:56", "Morgenmiddag 13:07"])
    }

    func testFridayAfternoonOffersSaturdayAndMonday() {
        let choices = SendLater.choices(now: date(27, 15, 0), calendar: calendar)
        XCTAssertEqual(choices.map(\.title), ["Morgenochtend 07:56", "Morgenmiddag 13:07", "Maandagochtend 07:56"])
    }

    func testLabels() {
        let now = date(23, 23, 55)
        XCTAssertEqual(SendLater.label(date(24, 7, 56), now: now, calendar: calendar), "morgen 07:56")
        XCTAssertEqual(SendLater.label(date(23, 23, 58), now: now, calendar: calendar), "vandaag 23:58")
        XCTAssertEqual(SendLater.label(date(26, 9, 0), now: now, calendar: calendar), "donderdag 09:00")
    }

    func testReplacingDate() {
        var mail = ComposedMail(from: MailAddress(name: nil, address: "a@kade.example"), subject: "Test", bodyText: "Hoi")
        mail.to = [MailAddress(name: nil, address: "b@kade.example")]
        mail.date = date(23, 23, 55)
        let raw = MailComposer.build(mail)
        let changed = MailComposer.replacingDate(in: raw, with: date(24, 7, 56))
        let text = String(data: changed, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("Date: " + MailComposer.dateString(date(24, 7, 56)) + "\r\n"))
        XCTAssertFalse(text.contains(MailComposer.dateString(date(23, 23, 55))))
        XCTAssertTrue(text.contains("Subject: Test"))
    }
}
