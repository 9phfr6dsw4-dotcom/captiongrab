import XCTest
@testable import CaptionGrabCore

final class ChromeCompanionConstantsTests: XCTestCase {
    func testTranscriptInboxSharesTheUserGrantedChromeProfileFolder() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let inbox = try XCTUnwrap(ChromeCompanionConstants.inboxDirectory(homeURL: home))
        XCTAssertEqual(
            inbox.path,
            "/Users/example/Library/Application Support/Google/Chrome/CaptionGrab/ChromeInbox"
        )
    }

    func testChromeFolderValidationUsesRealHomeRatherThanSandboxContainer() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionGrabChromeFolderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let realHome = temporaryRoot.appendingPathComponent("Users/example", isDirectory: true)
        let sandboxHome = temporaryRoot.appendingPathComponent("Containers/CaptionGrab/Data", isDirectory: true)
        let selectedChromeRoot = try XCTUnwrap(ChromeCompanionConstants.chromeProfileDirectory(homeURL: realHome))
        try FileManager.default.createDirectory(at: selectedChromeRoot, withIntermediateDirectories: true)

        XCTAssertTrue(ChromeCompanionConstants.isChromeProfileDirectory(
            selectedURL: selectedChromeRoot,
            homeURL: realHome
        ))
        XCTAssertFalse(ChromeCompanionConstants.isChromeProfileDirectory(
            selectedURL: selectedChromeRoot,
            homeURL: sandboxHome
        ))
    }

    func testChromeFolderValidationResolvesSymlinkAndTrailingSlash() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionGrabChromeFolderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let home = temporaryRoot.appendingPathComponent("Users/example", isDirectory: true)
        let actualChromeRoot = try XCTUnwrap(ChromeCompanionConstants.chromeProfileDirectory(homeURL: home))
        try FileManager.default.createDirectory(at: actualChromeRoot, withIntermediateDirectories: true)

        let aliases = temporaryRoot.appendingPathComponent("Aliases", isDirectory: true)
        let selectedFolder = aliases.appendingPathComponent("Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: aliases, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: selectedFolder, withDestinationURL: actualChromeRoot)
        let selectedWithTrailingSlash = URL(fileURLWithPath: selectedFolder.path + "/", isDirectory: true)

        XCTAssertTrue(ChromeCompanionConstants.isChromeProfileDirectory(
            selectedURL: selectedWithTrailingSlash,
            homeURL: home
        ))
    }

    func testNativeMessagingHostRegistrationUsesChromeProfileFolder() {
        let chromeRoot = URL(fileURLWithPath: "/Users/example/Library/Application Support/Google/Chrome", isDirectory: true)
        XCTAssertEqual(
            ChromeCompanionConstants.chromeNativeMessagingDirectory(chromeRootURL: chromeRoot).path,
            "/Users/example/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        )
    }
}
