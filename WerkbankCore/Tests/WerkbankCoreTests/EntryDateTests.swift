import XCTest
@testable import WerkbankCore

final class EntryDateTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Dinsdag 3 november 2026, 16:27.
    private var base: Date { date(2026, 11, 3, 16, 27) }

    func testTextShowsWeekdayDateAndTime() {
        XCTAssertEqual(EntryDateText.text(base, calendar: calendar), "di 3-11-2026 16:27")
        XCTAssertEqual(EntryDateText.text(date(2026, 3, 1, 9, 5), calendar: calendar), "zo 1-3-2026 09:05")
    }

    func testTextReadsBack() {
        let text = EntryDateText.text(base, calendar: calendar)
        XCTAssertEqual(EntryDateText.parse(text, base: date(2025, 1, 1, 0, 0), calendar: calendar), base)
    }

    func testOnlyATimeKeepsTheDay() {
        XCTAssertEqual(EntryDateText.parse("9:05", base: base, calendar: calendar), date(2026, 11, 3, 9, 5))
        XCTAssertEqual(EntryDateText.parse("di 3-11-2026 17:45", base: base, calendar: calendar), date(2026, 11, 3, 17, 45))
    }

    func testOnlyADayKeepsTheTime() {
        XCTAssertEqual(EntryDateText.parse("4-11", base: base, calendar: calendar), date(2026, 11, 4, 16, 27))
        XCTAssertEqual(EntryDateText.parse("2/11/25", base: base, calendar: calendar), date(2025, 11, 2, 16, 27))
        XCTAssertEqual(EntryDateText.parse("2.11.2026", base: base, calendar: calendar), date(2026, 11, 2, 16, 27))
    }

    func testMonthNames() {
        XCTAssertEqual(EntryDateText.parse("4 nov 10:00", base: base, calendar: calendar), date(2026, 11, 4, 10, 0))
        XCTAssertEqual(EntryDateText.parse("ma 2 november 2026 8:30", base: base, calendar: calendar),
                       date(2026, 11, 2, 8, 30))
        XCTAssertEqual(EntryDateText.parse("31 mrt", base: base, calendar: calendar), date(2026, 3, 31, 16, 27))
    }

    func testRelativeDays() {
        let now = date(2026, 11, 5, 12, 0)
        XCTAssertEqual(EntryDateText.parse("gisteren 14:00", base: base, now: now, calendar: calendar),
                       date(2026, 11, 4, 14, 0))
        XCTAssertEqual(EntryDateText.parse("vandaag", base: base, now: now, calendar: calendar), date(2026, 11, 5, 16, 27))
    }

    func testRejectsWhatIsNotADate() {
        XCTAssertNil(EntryDateText.parse("", base: base, calendar: calendar))
        XCTAssertNil(EntryDateText.parse("di", base: base, calendar: calendar))
        XCTAssertNil(EntryDateText.parse("hallo", base: base, calendar: calendar))
        XCTAssertNil(EntryDateText.parse("31-2", base: base, calendar: calendar))
        XCTAssertNil(EntryDateText.parse("25:00", base: base, calendar: calendar))
        XCTAssertNil(EntryDateText.parse("3-11 16:27 later", base: base, calendar: calendar))
        XCTAssertNil(EntryDateText.parse("10:00 11:00", base: base, calendar: calendar))
    }
}
