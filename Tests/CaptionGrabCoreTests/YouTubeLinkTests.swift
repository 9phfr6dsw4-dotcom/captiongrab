import XCTest
@testable import CaptionGrabCore

final class YouTubeLinkTests: XCTestCase {
    func testWatchLinkDropsPlaylistAndStartParameters() throws {
        let link = try YouTubeLink.parse("https://www.youtube.com/watch?v=A1b2C3d4E5F&list=PLsample&t=42")
        XCTAssertEqual(link.videoID, "A1b2C3d4E5F")
        XCTAssertEqual(link.canonicalURL.absoluteString, "https://www.youtube.com/watch?v=A1b2C3d4E5F")
    }

    func testShortLink() throws {
        let link = try YouTubeLink.parse("https://youtu.be/A1b2C3d4E5F?t=12")
        XCTAssertEqual(link.videoID, "A1b2C3d4E5F")
    }

    func testShortsLink() throws {
        let link = try YouTubeLink.parse("https://www.youtube.com/shorts/A1b2C3d4E5F?feature=share")
        XCTAssertEqual(link.videoID, "A1b2C3d4E5F")
    }

    func testRejectsLookalikeHost() {
        XCTAssertThrowsError(try YouTubeLink.parse("https://youtube.com.example.org/watch?v=A1b2C3d4E5F"))
    }

    func testRejectsNonVideoAndMalformedIDs() {
        XCTAssertThrowsError(try YouTubeLink.parse("https://www.youtube.com/playlist?list=PLsample"))
        XCTAssertThrowsError(try YouTubeLink.parse("https://www.youtube.com/watch?v=short"))
    }
}
