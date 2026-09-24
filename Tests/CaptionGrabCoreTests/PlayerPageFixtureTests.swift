import XCTest
@testable import CaptionGrabCore

final class PlayerPageFixtureTests: XCTestCase {
    func testRejectsHTMLWithoutPlayerResponseAsChangedYouTubePage() {
        XCTAssertThrowsError(try YouTubePlayerPageParser.parse("<html>synthetic unrelated page</html>"))
    }
}
