import XCTest
@testable import CaptionGrabCore

final class ChromeCompanionConstantsTests: XCTestCase {
    func testTranscriptInboxSharesTheUserGrantedChromeProfileFolder() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let inbox = ChromeCompanionConstants.inboxDirectory(homeURL: home)
        XCTAssertEqual(
            inbox.path,
            "/Users/example/Library/Application Support/Google/Chrome/CaptionGrab/ChromeInbox"
        )
    }

    func testNativeMessagingHostRegistrationUsesChromeProfileFolder() {
        let chromeRoot = URL(fileURLWithPath: "/Users/example/Library/Application Support/Google/Chrome", isDirectory: true)
        XCTAssertEqual(
            ChromeCompanionConstants.chromeNativeMessagingDirectory(chromeRootURL: chromeRoot).path,
            "/Users/example/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        )
    }
}
