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

final class StartTimeCorrectionTests: XCTestCase {
    private var cal = Calendar(identifier: .gregorian)
    private func t(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: h, minute: m, second: s))!
    }

    func testEarlierStartAddsTime() {
        let r = StartTimeCorrection.evaluate(firstStart: t(9, 30), requestedStart: t(9, 10), end: t(10, 30), measuredSeconds: 3600)
        XCTAssertEqual(r.adjustmentSeconds, 20 * 60)
        XCTAssertEqual(r.start, t(9, 10))
        XCTAssertFalse(r.isOutOfRange)
    }

    func testLaterStartRemovesTime() {
        let r = StartTimeCorrection.evaluate(firstStart: t(9, 0), requestedStart: t(9, 15), end: t(10, 0), measuredSeconds: 3600)
        XCTAssertEqual(r.adjustmentSeconds, -15 * 60)
        XCTAssertEqual(r.start, t(9, 15))
    }

    func testDifferenceUnderOneMinuteIgnored() {
        let r = StartTimeCorrection.evaluate(firstStart: t(9, 12, 40), requestedStart: t(9, 12), end: t(10, 0), measuredSeconds: 1800)
        XCTAssertEqual(r.adjustmentSeconds, 0)
        XCTAssertEqual(r.start, t(9, 12, 40))
    }

    func testStartNotBeforeEndIsOutOfRange() {
        let r = StartTimeCorrection.evaluate(firstStart: t(9, 0), requestedStart: t(10, 0), end: t(10, 0), measuredSeconds: 3600)
        XCTAssertTrue(r.isOutOfRange)
        XCTAssertEqual(r.adjustmentSeconds, 0)
        XCTAssertEqual(r.start, t(9, 0))
    }

    func testLaterStartCannotRemoveMoreThanMeasured() {
        let r = StartTimeCorrection.evaluate(firstStart: t(9, 0), requestedStart: t(9, 50), end: t(10, 0), measuredSeconds: 20 * 60)
        XCTAssertEqual(r.adjustmentSeconds, -20 * 60)
        XCTAssertEqual(r.start, t(9, 20))
    }
}
