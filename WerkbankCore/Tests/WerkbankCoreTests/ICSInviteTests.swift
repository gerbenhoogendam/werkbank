import XCTest
@testable import WerkbankCore

final class ICSInviteTests: XCTestCase {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                      zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testOutlookInviteWithWindowsZoneFoldingAndEscapes() {
        let text = """
        BEGIN:VCALENDAR\r
        METHOD:REQUEST\r
        BEGIN:VTIMEZONE\r
        TZID:W. Europe Standard Time\r
        END:VTIMEZONE\r
        BEGIN:VEVENT\r
        UID:abc-123\r
        SUMMARY:Overleg\\, kort\r
        ORGANIZER;CN="Jansen, Piet":mailto:piet@example.com\r
        DTSTART;TZID=W. Europe Standard Time:20261203T140000\r
        DTEND;TZID=W. Europe Standard Time:20261203T153000\r
        LOCATION:Kamer 2\; boven\r
        DESCRIPTION:Eerste regel\\nTweede regel die heel lang is en daarom gevou\r
         wen wordt\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let document = ICSParser.parse(text, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(document.method, "REQUEST")
        XCTAssertEqual(document.events.count, 1)
        let event = document.events[0]
        XCTAssertEqual(event.uid, "abc-123")
        XCTAssertEqual(event.title, "Overleg, kort")
        XCTAssertEqual(event.location, "Kamer 2; boven")
        XCTAssertEqual(event.notes, "Eerste regel\nTweede regel die heel lang is en daarom gevouwen wordt")
        XCTAssertEqual(event.organizerName, "Jansen, Piet")
        XCTAssertEqual(event.organizerEmail, "piet@example.com")
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.start, date(2026, 12, 3, 14, zone: amsterdam))
        XCTAssertEqual(event.end, date(2026, 12, 3, 15, 30, zone: amsterdam))
    }

    func testUTCAndDuration() {
        let text = "BEGIN:VEVENT\nSUMMARY:Bel\nDTSTART:20261127T090000Z\nDURATION:PT45M\nEND:VEVENT"
        let event = ICSParser.parse(text).events.first
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(event?.start, date(2026, 11, 27, 9, zone: utc))
        XCTAssertEqual(event?.end, date(2026, 11, 27, 9, 45, zone: utc))
    }

    func testAllDayAndFloatingTime() {
        let allDay = ICSParser.parse("BEGIN:VEVENT\nDTSTART;VALUE=DATE:20261224\nEND:VEVENT", timeZone: amsterdam)
            .events.first
        XCTAssertEqual(allDay?.isAllDay, true)
        XCTAssertEqual(allDay?.start, date(2026, 12, 24, zone: amsterdam))
        XCTAssertEqual(allDay?.end, date(2026, 12, 25, zone: amsterdam))

        let floating = ICSParser.parse("BEGIN:VEVENT\nDTSTART:20261127T100000\nEND:VEVENT", timeZone: amsterdam)
            .events.first
        XCTAssertEqual(floating?.start, date(2026, 11, 27, 10, zone: amsterdam))
        XCTAssertEqual(floating?.end, floating?.start)
    }

    func testDurationValues() {
        XCTAssertEqual(ICSParser.duration("PT1H30M"), 5400)
        XCTAssertEqual(ICSParser.duration("P1D"), 86_400)
        XCTAssertEqual(ICSParser.duration("P1W"), 604_800)
        XCTAssertEqual(ICSParser.duration("-PT15M"), -900)
        XCTAssertNil(ICSParser.duration("1H"))
    }

    func testFileWithoutEventIsEmpty() {
        XCTAssertTrue(ICSParser.parse("BEGIN:VCALENDAR\nEND:VCALENDAR").events.isEmpty)
    }
}
