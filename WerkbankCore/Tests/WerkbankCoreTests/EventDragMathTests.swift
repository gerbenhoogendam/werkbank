import XCTest
@testable import WerkbankCore

final class EventDragMathTests: XCTestCase {
    private let visible = 8 * 60 ... 18 * 60

    func testMoveSnapsStartAndKeepsDuration() {
        let result = EventDragMath.moved(start: 10 * 60, end: 11 * 60, delta: 58, visible: visible)
        XCTAssertEqual(result.start, 11 * 60)
        XCTAssertEqual(result.end, 12 * 60)
        let offGrid = EventDragMath.moved(start: 10 * 60 + 5, end: 10 * 60 + 50, delta: 12, visible: visible)
        XCTAssertEqual(offGrid.start, 10 * 60 + 15)
        XCTAssertEqual(offGrid.end, 11 * 60)
    }

    func testMoveStaysWithinVisibleHours() {
        let early = EventDragMath.moved(start: 9 * 60, end: 10 * 60, delta: -180, visible: visible)
        XCTAssertEqual(early.start, 8 * 60)
        let late = EventDragMath.moved(start: 16 * 60, end: 17 * 60, delta: 240, visible: visible)
        XCTAssertEqual(late.start, 18 * 60 - 15)
        XCTAssertEqual(late.end, 18 * 60 + 45)
        // Lag het begin al vóór de zichtbare uren, dan springt het niet naar 8:00.
        let before = EventDragMath.moved(start: 7 * 60, end: 8 * 60, delta: 15, visible: visible)
        XCTAssertEqual(before.start, 7 * 60 + 15)
    }

    func testMoveMultiDayIsFree() {
        let result = EventDragMath.moved(start: -120, end: 10 * 60, delta: 60, visible: visible)
        XCTAssertEqual(result.start, -60)
        XCTAssertEqual(result.end, 11 * 60)
    }

    func testResizeEdges() {
        let later = EventDragMath.resized(start: 10 * 60, end: 11 * 60, edge: .end, pointer: 12 * 60 + 8, visible: visible)
        XCTAssertEqual(later.start, 10 * 60)
        XCTAssertEqual(later.end, 12 * 60 + 15)
        let earlier = EventDragMath.resized(start: 10 * 60, end: 11 * 60, edge: .start, pointer: 9 * 60 + 22,
                                            visible: visible)
        XCTAssertEqual(earlier.start, 9 * 60 + 15)
        XCTAssertEqual(earlier.end, 11 * 60)
    }

    func testResizeKeepsAQuarterAndVisibleHours() {
        let crossed = EventDragMath.resized(start: 10 * 60, end: 11 * 60, edge: .end, pointer: 9 * 60, visible: visible)
        XCTAssertEqual(crossed.end, 10 * 60 + 15)
        let top = EventDragMath.resized(start: 10 * 60, end: 11 * 60, edge: .start, pointer: 12 * 60, visible: visible)
        XCTAssertEqual(top.start, 10 * 60 + 45)
        let above = EventDragMath.resized(start: 10 * 60, end: 11 * 60, edge: .start, pointer: 6 * 60, visible: visible)
        XCTAssertEqual(above.start, 8 * 60)
        let below = EventDragMath.resized(start: 10 * 60, end: 11 * 60, edge: .end, pointer: 20 * 60, visible: visible)
        XCTAssertEqual(below.end, 18 * 60)
    }
}
