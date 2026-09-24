import XCTest
@testable import CaptionGrabCore

final class RecentHistoryTests: XCTestCase {
    func testHistoryIsLocalAndCanBeCleared() {
        let suiteName = "CaptionGrabTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RecentHistoryStore(defaults: defaults)
        let video = RecentVideo(
            videoID: "A1b2C3d4E5F",
            title: "Fictional sample",
            videoURL: URL(string: "https://www.youtube.com/watch?v=A1b2C3d4E5F")!,
            lastFetchedAt: Date(timeIntervalSince1970: 100)
        )

        store.record(video)
        XCTAssertEqual(store.load(), [video])
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }
}
