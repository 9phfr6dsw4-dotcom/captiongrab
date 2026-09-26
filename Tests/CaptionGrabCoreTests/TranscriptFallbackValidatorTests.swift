import XCTest
@testable import CaptionGrabCore

final class TranscriptFallbackValidatorTests: XCTestCase {
    func testAcceptsOnlyTimestampedCaptionTextPresentInTheVisiblePanel() throws {
        let source = """
        Transcript
        0:00
        A synthetic first caption.
        0:04
        A second synthetic caption.
        """
        let generated = [
            TranscriptFallbackSegment(timestamp: "0:00", text: "A synthetic first caption."),
            TranscriptFallbackSegment(timestamp: "0:04", text: "A second synthetic caption.")
        ]

        let cues = try TranscriptFallbackValidator.validate(generated, sourceText: source)

        XCTAssertEqual(cues, [
            TranscriptCue(startTimeMilliseconds: 0, text: "A synthetic first caption."),
            TranscriptCue(startTimeMilliseconds: 4_000, text: "A second synthetic caption.")
        ])
    }

    func testRejectsCaptionTextNotPresentInTheVisiblePanel() {
        let generated = [TranscriptFallbackSegment(timestamp: "0:00", text: "A fabricated caption.")]
        XCTAssertThrowsError(try TranscriptFallbackValidator.validate(generated, sourceText: "0:00\nOnly source text."))
    }

    func testRejectsTimestampNotPresentBeforeItsCaption() {
        let generated = [TranscriptFallbackSegment(timestamp: "0:05", text: "A synthetic caption.")]
        XCTAssertThrowsError(try TranscriptFallbackValidator.validate(generated, sourceText: "0:00\nA synthetic caption."))
    }

    func testRejectsOutOfOrderOrMalformedGeneratedCues() {
        let source = "0:00\nFirst caption.\n0:04\nSecond caption."
        let outOfOrder = [
            TranscriptFallbackSegment(timestamp: "0:04", text: "Second caption."),
            TranscriptFallbackSegment(timestamp: "0:00", text: "First caption.")
        ]
        XCTAssertThrowsError(try TranscriptFallbackValidator.validate(outOfOrder, sourceText: source))
        XCTAssertThrowsError(try TranscriptFallbackValidator.validate(
            [TranscriptFallbackSegment(timestamp: "0:99", text: "First caption.")],
            sourceText: source
        ))
    }

    func testRejectsOversizedSourceAndEmptyOutput() {
        XCTAssertThrowsError(try TranscriptFallbackValidator.validate(
            [TranscriptFallbackSegment(timestamp: "0:00", text: "Caption.")],
            sourceText: String(repeating: "x", count: TranscriptFallbackValidator.maximumSourceBytes + 1)
        ))
        XCTAssertThrowsError(try TranscriptFallbackValidator.validate([], sourceText: "0:00\nCaption."))
    }
}
