import XCTest
@testable import WerkbankCore

final class DateProposalsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        calendar.locale = Locale(identifier: "nl_NL")
        return calendar
    }()

    /// Zaterdag 31 oktober 2026, 12:00.
    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testDayMonthWithTime() {
        let found = DateProposals.find(in: "Kunnen we dinsdag 3 november om 14:00 even bellen?", reference: reference,
                                       calendar: calendar)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.start, date(11, 3, 14))
        XCTAssertEqual(found.first?.end, date(11, 3, 15))
        XCTAssertEqual(found.first?.hasTime, true)
        XCTAssertEqual(found.first?.text, "3 november om 14:00")
    }

    func testRelativeDayWithRange() {
        let found = DateProposals.find(in: "Kan het morgen tussen 9.30 en 11 uur?", reference: reference, calendar: calendar)
        XCTAssertEqual(found.first?.start, date(11, 1, 9, 30))
        XCTAssertEqual(found.first?.end, date(11, 1, 11))
    }

    func testNextWeekWeekdayAndNumericDate() {
        let nextWeek = DateProposals.find(in: "Zullen we volgende week donderdag om 15u afspreken?", reference: reference,
                                          calendar: calendar)
        XCTAssertEqual(nextWeek.first?.start, date(11, 5, 15))
        let numeric = DateProposals.find(in: "Lukt het op 12-11 om 16.30 uur?", reference: reference, calendar: calendar)
        XCTAssertEqual(numeric.first?.start, date(11, 12, 16, 30))
    }

    func testPastDatesAndDurationsAreNoProposals() {
        XCTAssertTrue(DateProposals.find(in: "De factuur van 3 oktober is betaald.", reference: reference,
                                         calendar: calendar).isEmpty)
        let dateOnly = DateProposals.find(in: "Ik ben woensdag op kantoor.", reference: reference, calendar: calendar)
        XCTAssertEqual(dateOnly.first?.start, date(11, 4, 10))
        XCTAssertEqual(dateOnly.first?.hasTime, false)
    }

    func testFreeSlotsSkipBusyTimeAndWeekends() {
        // Maandag 2 november 9:00–12:00 bezet: het eerste vrije uur is 12:00.
        let busy = [DateInterval(start: date(11, 2, 9), end: date(11, 2, 12))]
        let slots = FreeSlots.find(busy: busy, from: reference, limit: 2, calendar: calendar)
        XCTAssertEqual(slots.map(\.start), [date(11, 2, 12), date(11, 3, 9)])
    }

    func testInviteIsValidICalendar() {
        let ics = CalendarInvite.ics(uid: "abc@werkbank", start: date(11, 3, 14), end: date(11, 3, 15),
                                     title: "Bellen: koppeling, voorraad",
                                     organizer: MailAddress(name: "Gerben", address: "gerben@werk.nl"),
                                     attendees: [MailAddress(name: "Eva van Dijk", address: "eva@vandijk.nl")],
                                     now: date(10, 31, 12))
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("METHOD:REQUEST\r\n"))
        XCTAssertTrue(ics.contains("DTSTART:20261103T130000Z\r\n"))
        XCTAssertTrue(ics.contains("SUMMARY:Bellen: koppeling\\, voorraad\r\n"))
        // Lange regels worden gevouwen: na 75 bytes verder op een regel die met een spatie begint.
        let lines = ics.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 75 })
        XCTAssertTrue(lines.contains { $0.hasPrefix("ATTENDEE;CN=\"Eva van Dijk\";ROLE=REQ-PARTICIPANT") })
        XCTAssertTrue(lines.joined(separator: "\r\n").replacingOccurrences(of: "\r\n ", with: "")
            .contains("RSVP=TRUE:mailto:eva@vandijk.nl\r\n"))
    }
}
