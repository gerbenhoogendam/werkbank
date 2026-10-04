import XCTest
@testable import WerkbankCore

final class ColumnOrderingTests: XCTestCase {
    private let keys = ["a", "b", "c", "d"]

    func testMoveForwardAndBackward() {
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "a", toIndex: 2), ["b", "c", "a", "d"])
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "d", toIndex: 0), ["d", "a", "b", "c"])
    }

    func testMoveToEndAndSamePosition() {
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "b", toIndex: 3), ["a", "c", "d", "b"])
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "b", toIndex: 1), keys)
    }

    func testIndexIsClampedAndUnknownKeyIgnored() {
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "b", toIndex: 99), ["a", "c", "d", "b"])
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "b", toIndex: -5), ["b", "a", "c", "d"])
        XCTAssertEqual(ColumnOrdering.moving(keys, key: "zzz", toIndex: 1), keys)
    }

    func testInsertionIndexFromMidpoints() {
        let others: [Double] = [100, 300, 500]
        XCTAssertEqual(ColumnOrdering.insertionIndex(draggedMidX: 50, otherMidXs: others), 0)
        XCTAssertEqual(ColumnOrdering.insertionIndex(draggedMidX: 301, otherMidXs: others), 2)
        XCTAssertEqual(ColumnOrdering.insertionIndex(draggedMidX: 900, otherMidXs: others), 3)
        XCTAssertEqual(ColumnOrdering.insertionIndex(draggedMidX: 10, otherMidXs: []), 0)
    }
}
