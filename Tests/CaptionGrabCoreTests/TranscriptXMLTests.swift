import XCTest
@testable import CaptionGrabCore

final class TranscriptXMLTests: XCTestCase {
    func testParsesXMLCaptionsAndEntityText() throws {
        let fixture = #"<transcript><text start="3.25" dur="1.5">A &amp; B&lt;sample&gt;</text><text start="62.0" dur="2"><![CDATA[Next synthetic cue.]]></text></transcript>"#
        let cues = try YouTubeTranscriptParser.parseXML(Data(fixture.utf8))
        XCTAssertEqual(cues, [
            TranscriptCue(startTimeMilliseconds: 3_250, text: "A & B<sample>"),
            TranscriptCue(startTimeMilliseconds: 62_000, text: "Next synthetic cue.")
        ])
    }
}
