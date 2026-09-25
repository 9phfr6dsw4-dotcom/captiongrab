import Foundation
import XCTest
@testable import CaptionGrabCore

final class ChromeCompanionConstantsTests: XCTestCase {
    func testNativeMessagingManifestUsesChromeInstallationDirectoryWithoutFolderSelection() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(
            ChromeCompanionConstants.chromeNativeMessagingDirectory(homeURL: home).path,
            "/Users/example/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        )
    }

    func testTranscriptInboxUsesCaptionGrabApplicationSupportNotChromeProfile() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(
            ChromeCompanionConstants.transcriptInboxDirectory(homeURL: home).path,
            "/Users/example/Library/Application Support/CaptionGrab/ChromeInbox"
        )
        XCTAssertFalse(
            ChromeCompanionConstants.transcriptInboxDirectory(homeURL: home).path.contains("Google/Chrome")
        )
    }

    func testLegacyChromeFolderBookmarkIsRemovedWithoutClearingOtherPreferences() {
        let suiteName = "CaptionGrabMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyBookmark = Data([1, 2, 3])
        let unrelatedBookmark = Data([4, 5, 6])
        defaults.set(legacyBookmark, forKey: ChromeCompanionConstants.legacyChromeFolderBookmarkKey)
        defaults.set(unrelatedBookmark, forKey: "CaptionGrab.lastSaveFolderBookmark")

        ChromeCompanionConstants.clearLegacyChromeFolderBookmark(from: defaults)

        XCTAssertNil(defaults.data(forKey: ChromeCompanionConstants.legacyChromeFolderBookmarkKey))
        XCTAssertEqual(defaults.data(forKey: "CaptionGrab.lastSaveFolderBookmark"), unrelatedBookmark)
    }

    func testSetupFileErrorIncludesOperationExactPathAndUnderlyingDetails() {
        let path = "/Users/example/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.captiongrab.host.json"
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: 513,
            userInfo: [
                NSLocalizedDescriptionKey: "You don’t have permission to save the file.",
                NSLocalizedFailureReasonErrorKey: "The folder is not writable."
            ]
        )
        let error = FileSystemDiagnostic(operation: "Write Native Messaging manifest", path: path, underlyingError: underlying)

        XCTAssertTrue(error.localizedDescription.contains("Write Native Messaging manifest"))
        XCTAssertTrue(error.localizedDescription.contains(path))
        XCTAssertTrue(error.localizedDescription.contains("NSCocoaErrorDomain"))
        XCTAssertTrue(error.localizedDescription.contains("513"))
        XCTAssertTrue(error.localizedDescription.contains("You don’t have permission to save the file."))
        XCTAssertTrue(error.localizedDescription.contains("The folder is not writable."))
    }
}
