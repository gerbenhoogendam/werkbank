import XCTest
@testable import WerkbankCore

final class EndTimeCorrectionTests: XCTestCase {
    private var cal = Calendar(identifier: .gregorian)
    private func t(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: h, minute: m, second: s))!
    }

    func testUnchangedEndSubtractsNothing() {
        let r = EndTimeCorrection.evaluate(lastStart: t(9, 12), defaultEnd: t(10, 19, 32), requestedEnd: t(10, 19))
        XCTAssertEqual(r.subtractedSeconds, 0)     // 32 s < 1 min
        XCTAssertFalse(r.isOutOfRange)
        XCTAssertEqual(r.end, t(10, 19, 32))
    }

    func testEarlierEndSubtractsDifference() {
        let r = EndTimeCorrection.evaluate(lastStart: t(9, 12), defaultEnd: t(10, 40), requestedEnd: t(10, 12))
        XCTAssertEqual(r.subtractedSeconds, 28 * 60)
        XCTAssertEqual(r.end, t(10, 12))
        XCTAssertFalse(r.isOutOfRange)
        XCTAssertFalse(r.showsLongRunWarning)
    }

    func testDifferenceUnderOneMinuteIgnored() {
        let r = EndTimeCorrection.evaluate(lastStart: t(9, 0), defaultEnd: t(10, 0, 50), requestedEnd: t(10, 0, 0))
        XCTAssertEqual(r.subtractedSeconds, 0)
    }

    func testOutOfRangeIsClamped() {
        let late = EndTimeCorrection.evaluate(lastStart: t(9, 0), defaultEnd: t(10, 0), requestedEnd: t(11, 0))
        XCTAssertTrue(late.isOutOfRange)
        XCTAssertEqual(late.end, t(10, 0))
        XCTAssertEqual(late.subtractedSeconds, 0)

        let early = EndTimeCorrection.evaluate(lastStart: t(9, 0), defaultEnd: t(10, 0), requestedEnd: t(8, 0))
        XCTAssertTrue(early.isOutOfRange)
        XCTAssertEqual(early.end, t(9, 0))
        XCTAssertEqual(early.subtractedSeconds, 3600)
    }

    func testSameMinuteAsLastStartIsNotOutOfRange() {
        let r = EndTimeCorrection.evaluate(lastStart: t(9, 0, 30), defaultEnd: t(10, 0), requestedEnd: t(9, 0))
        XCTAssertFalse(r.isOutOfRange)
        XCTAssertEqual(r.end, t(9, 0, 30))
    }

    func testLongRunWarning() {
        let r = EndTimeCorrection.evaluate(lastStart: t(9, 33), defaultEnd: t(10, 40), requestedEnd: t(10, 40))
        XCTAssertEqual(r.continuousSeconds, 67 * 60)
        XCTAssertTrue(r.showsLongRunWarning)
        // Aangepast → geen waarschuwing meer
        let adjusted = EndTimeCorrection.evaluate(lastStart: t(9, 33), defaultEnd: t(10, 40), requestedEnd: t(10, 0))
        XCTAssertFalse(adjusted.showsLongRunWarning)
        // Drempel is instelbaar
        let strict = EndTimeCorrection.evaluate(lastStart: t(10, 0), defaultEnd: t(10, 40), requestedEnd: t(10, 40),
                                                warningThresholdMinutes: 30)
        XCTAssertTrue(strict.showsLongRunWarning)
    }

    func testDateFromHourMinute() {
        let d = EndTimeCorrection.date(hour: 10, minute: 15, near: t(10, 40), notBefore: t(9, 0), calendar: cal)
        XCTAssertEqual(d, t(10, 15))
    }
}
