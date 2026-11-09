import XCTest
@testable import WerkbankCore

final class ListMarkerTests: XCTestCase {
    func testBullets() {
        XCTAssertEqual(ListMarker.leading("•\tPunt")?.kind, .bullet)
        XCTAssertEqual(ListMarker.leading("•\tPunt")?.length, 2)
        XCTAssertEqual(ListMarker.leading("\t•\tPunt")?.length, 3)
        XCTAssertEqual(ListMarker.leading("\u{F0B7}\tUit Word")?.kind, .bullet)
        XCTAssertEqual(ListMarker.leading("-\tStreepje")?.length, 2)
    }

    func testNumbers() {
        XCTAssertEqual(ListMarker.leading("\t12.\tTwaalf")?.kind, .number)
        XCTAssertEqual(ListMarker.leading("\t12.\tTwaalf")?.length, 5)
        XCTAssertEqual(ListMarker.leading("3)\tDrie")?.kind, .number)
    }

    func testPlainTextIsNoList() {
        XCTAssertNil(ListMarker.leading("1. Inleiding"))
        XCTAssertNil(ListMarker.leading("Gewone tekst\tmet tab"))
        XCTAssertNil(ListMarker.leading("- streepje met spatie"))
        XCTAssertNil(ListMarker.leading(""))
    }

    func testListedMarkerIsAnythingUpToTheTab() {
        XCTAssertEqual(ListMarker.listed("\ta.\tItem"), 4)
        XCTAssertEqual(ListMarker.listed("\t◦\tSub"), 3)
        XCTAssertEqual(ListMarker.listed("\t\t▪\tDieper"), 4)
        XCTAssertEqual(ListMarker.listed("Item zonder teken"), 0)
    }
}
