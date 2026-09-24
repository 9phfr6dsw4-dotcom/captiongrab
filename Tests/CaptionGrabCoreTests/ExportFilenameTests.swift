import XCTest
@testable import CaptionGrabCore

final class ExportFilenameTests: XCTestCase {
    func testFilenameRemovesFilesystemCharactersAndKeepsNormalTitle() {
        XCTAssertEqual(ExportFilename.safeBaseName("A title: part / two"), "A title- part - two")
    }

    func testFilenameFallsBackWhenTitleContainsNoUsableCharacters() {
        XCTAssertEqual(ExportFilename.safeBaseName("/::?*"), "YouTube Transcript")
    }
}
