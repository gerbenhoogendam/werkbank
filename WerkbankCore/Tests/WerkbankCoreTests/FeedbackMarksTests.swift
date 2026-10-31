import XCTest
@testable import WerkbankCore

final class FeedbackMarksTests: XCTestCase {
    private let words: [FeedbackTranscript.Word] = [
        .init(text: " Als", start: 0.0, end: 0.3),
        .init(text: " ik", start: 0.3, end: 0.5),
        .init(text: " hier", start: 0.6, end: 0.9),
        .init(text: " klik", start: 1.0, end: 1.3),
        .init(text: ",", start: 1.3, end: 1.3),
        .init(text: " moet", start: 1.5, end: 1.7),
        .init(text: " dit", start: 2.4, end: 2.6),
        .init(text: " groter.", start: 2.7, end: 3.1),
    ]

    func testMarksGoAfterTheWordSpokenAtThatMoment() {
        let marks = [
            FeedbackMark(number: 1, kind: .click, x: 0.9, y: 0.05, time: 0.8),
            FeedbackMark(number: 2, kind: .area, x: 0.1, y: 0.4, width: 0.3, height: 0.2, time: 2.5),
        ]
        XCTAssertEqual(FeedbackTranscript.text(words, marks: marks), "Als ik hier [1] klik, moet dit [2] groter.")
        XCTAssertEqual(FeedbackTranscript.text(words, marks: []), "Als ik hier klik, moet dit groter.")
        let early = [FeedbackMark(number: 1, kind: .click, x: 0.5, y: 0.5, time: -0.2)]
        XCTAssertEqual(FeedbackTranscript.text(words, marks: early), "[1] Als ik hier klik, moet dit groter.")
    }

    func testRegionAndSummary() {
        XCTAssertEqual(FeedbackMark(number: 1, kind: .click, x: 0.9, y: 0.05, time: 4.2).summary,
                       "[1] klik rechtsboven op 0:04")
        XCTAssertEqual(FeedbackMark(number: 2, kind: .area, x: 0.3, y: 0.4, width: 0.4, height: 0.2, time: 65).summary,
                       "[2] kader in het midden op 1:05")
        let marks = [FeedbackMark(number: 3, kind: .click, x: 0.1, y: 0.9, time: 1)]
        XCTAssertEqual(FeedbackMark.decode(FeedbackMark.encode(marks)), marks)
        XCTAssertNil(FeedbackMark.encode([]))
        XCTAssertEqual(marks[0].region, "linksonder")
    }

    func testPromptListsMarksUnderTheRequest() {
        let marks = [FeedbackMark(number: 1, kind: .click, x: 0.9, y: 0.05, time: 4.2)]
        let prompt = FeaturePrompt.build([.init(text: "Als ik hier [1] klik moet het menu openen", platform: .desktop,
                                                hasScreenshot: true, marks: marks)], screenshotsInDocument: true)
        XCTAssertTrue(prompt.contains("D1 (screenshot): Als ik hier [1] klik moet het menu openen\n"
                                      + "   Aangewezen (zelfde nummers op de screenshot): [1] klik rechtsboven op 0:04\n"))
        XCTAssertTrue(prompt.contains("achter het woord dat ik op dat moment zei"))
    }
}
