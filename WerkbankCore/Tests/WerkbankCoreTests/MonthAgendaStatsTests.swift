import XCTest
@testable import WerkbankCore

final class MonthAgendaStatsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func slot(_ day: Int, _ from: Int, _ to: Int, allDay: Bool = false) -> MonthAgendaStats.Slot {
        MonthAgendaStats.Slot(start: date(day, from), end: date(day, to), isAllDay: allDay)
    }

    private var week: [Date] { (16...20).map { date($0, 0) } }

    func testCountsAppointmentsHoursAndFreeDays() {
        let result = MonthAgendaStats.compute([slot(16, 10, 12), slot(17, 9, 10), slot(19, 13, 15)],
                                              days: week, startHour: 8, endHour: 18, calendar: calendar)
        XCTAssertEqual(result.appointments, 3)
        XCTAssertEqual(result.plannedHours, 5, accuracy: 0.001)
        XCTAssertEqual(result.freeDays, 2)
    }

    func testOverlapCountsOnce() {
        let result = MonthAgendaStats.compute([slot(16, 10, 12), slot(16, 11, 13)],
                                              days: week, startHour: 8, endHour: 18, calendar: calendar)
        XCTAssertEqual(result.appointments, 2)
        XCTAssertEqual(result.plannedHours, 3, accuracy: 0.001)
    }

    func testOnlyWithinWorkingHours() {
        let result = MonthAgendaStats.compute([slot(16, 7, 9), slot(17, 19, 21)],
                                              days: week, startHour: 8, endHour: 18, calendar: calendar)
        XCTAssertEqual(result.appointments, 1)
        XCTAssertEqual(result.plannedHours, 1, accuracy: 0.001)
        XCTAssertEqual(result.freeDays, 4)
    }

    func testAllDayDoesNotMakeADayBusy() {
        let holiday = MonthAgendaStats.Slot(start: date(20, 0), end: date(21, 0), isAllDay: true)
        let result = MonthAgendaStats.compute([holiday], days: week, startHour: 8, endHour: 18, calendar: calendar)
        XCTAssertEqual(result, MonthAgendaStats.Result(appointments: 0, plannedHours: 0, freeDays: 5))
    }

    func testAppointmentOverSeveralDaysCountsOnce() {
        let trip = MonthAgendaStats.Slot(start: date(16, 14), end: date(17, 12), isAllDay: false)
        let result = MonthAgendaStats.compute([trip], days: week, startHour: 8, endHour: 18, calendar: calendar)
        XCTAssertEqual(result.appointments, 1)
        XCTAssertEqual(result.plannedHours, 8, accuracy: 0.001)
        XCTAssertEqual(result.freeDays, 3)
    }

    func testHoursText() {
        XCTAssertEqual(MonthAgendaStats.hoursText(0), "0")
        XCTAssertEqual(MonthAgendaStats.hoursText(7.4), "7,5")
        XCTAssertEqual(MonthAgendaStats.hoursText(8), "8")
        XCTAssertEqual(MonthAgendaStats.hoursText(41.4), "41")
    }
}
