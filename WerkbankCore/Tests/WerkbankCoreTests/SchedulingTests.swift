import XCTest
@testable import WerkbankCore

final class SchedulingTests: XCTestCase {
    private var cal = Calendar(identifier: .gregorian)
    private func t(_ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: h, minute: m))!
    }

    func testSnapDownTo15() {
        XCTAssertEqual(Scheduling.snapDown(minutes: 0), 0)
        XCTAssertEqual(Scheduling.snapDown(minutes: 14), 0)
        XCTAssertEqual(Scheduling.snapDown(minutes: 15), 15)
        XCTAssertEqual(Scheduling.snapDown(minutes: 8 * 60 + 29), 8 * 60 + 15)
        XCTAssertEqual(Scheduling.snapDown(t(9, 29), calendar: cal), t(9, 15))
        XCTAssertEqual(Scheduling.start(onDayOf: t(15, 0), minutesFromMidnight: 9 * 60 + 44, calendar: cal), t(9, 30))
    }

    func testSnapNearest() {
        XCTAssertEqual(Scheduling.snapNearest(minutes: 7), 0)
        XCTAssertEqual(Scheduling.snapNearest(minutes: 8), 15)
        XCTAssertEqual(Scheduling.snapNearest(minutes: 59), 60)
    }

    func testDefaultEndIsOneHourCappedAtDayEnd() {
        XCTAssertEqual(Scheduling.defaultEnd(start: t(9, 15), dayEnd: t(18, 0)), t(10, 15))
        XCTAssertEqual(Scheduling.defaultEnd(start: t(17, 30), dayEnd: t(18, 0)), t(18, 0))
    }

    func testClampEnd() {
        let start = t(9, 0)
        XCTAssertEqual(Scheduling.clampEnd(start: start, proposedMinutesAfterStart: -30, dayEnd: t(18, 0)), t(9, 15))
        XCTAssertEqual(Scheduling.clampEnd(start: start, proposedMinutesAfterStart: 0, dayEnd: t(18, 0)), t(9, 15))
        XCTAssertEqual(Scheduling.clampEnd(start: start, proposedMinutesAfterStart: 100, dayEnd: t(18, 0)), t(10, 45))
        XCTAssertEqual(Scheduling.clampEnd(start: start, proposedMinutesAfterStart: 24 * 60, dayEnd: t(18, 0)), t(18, 0))
    }

    func testDefaultPrefix() {
        XCTAssertEqual(Scheduling.defaultPrefix(forStart: t(8, 0), calendar: cal), .vdm)
        XCTAssertEqual(Scheduling.defaultPrefix(forStart: t(12, 45), calendar: cal), .vdm)
        XCTAssertEqual(Scheduling.defaultPrefix(forStart: t(13, 0), calendar: cal), .ndm)
        XCTAssertEqual(Scheduling.defaultPrefix(forStart: t(16, 30), calendar: cal), .ndm)
    }

    func testTitleBuilding() {
        XCTAssertEqual(Scheduling.timeLabel(t(8, 30), calendar: cal), "8:30")
        XCTAssertEqual(Scheduling.timeLabel(t(13, 5), calendar: cal), "13:05")
        XCTAssertEqual(Scheduling.eventTitle(choice: .vdm, start: t(9, 0), todoTitle: "Offerte nieuwe website De Vries", calendar: cal),
                       "GH: vdm Offerte nieuwe website De Vries")
        XCTAssertEqual(Scheduling.eventTitle(choice: .ndm, start: t(14, 0), todoTitle: "X", calendar: cal), "GH: ndm X")
        XCTAssertEqual(Scheduling.eventTitle(choice: .time, start: t(8, 30), todoTitle: "Offerte nieuwe website De Vries", calendar: cal),
                       "GH: 8:30 Offerte nieuwe website De Vries")
    }

    func testEventLayout() {
        let a = (start: t(9, 0), end: t(10, 0))
        let b = (start: t(9, 30), end: t(10, 30))
        let c = (start: t(11, 0), end: t(12, 0))
        let d = (start: t(9, 0), end: t(9, 45))
        let slots = EventLayout.assign([a, b, c, d])
        // Bij gelijke start gaat de kortste afspraak eerst (d → baan 0, a → baan 1).
        XCTAssertEqual(slots[3], .init(lane: 0, laneCount: 3))
        XCTAssertEqual(slots[0], .init(lane: 1, laneCount: 3))
        XCTAssertEqual(slots[1], .init(lane: 2, laneCount: 3))
        XCTAssertEqual(slots[2], .init(lane: 0, laneCount: 1))
    }
}
