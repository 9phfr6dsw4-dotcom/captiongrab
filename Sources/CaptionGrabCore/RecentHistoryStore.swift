import Foundation

public final class RecentHistoryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String
    private let maximumEntries: Int

    public init(defaults: UserDefaults = .standard, storageKey: String = "CaptionGrab.recentVideos", maximumEntries: Int = 10) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maximumEntries = max(1, maximumEntries)
    }

    public func load() -> [RecentVideo] {
        guard let data = defaults.data(forKey: storageKey),
              let videos = try? JSONDecoder().decode([RecentVideo].self, from: data) else { return [] }
        return videos.sorted { $0.lastFetchedAt > $1.lastFetchedAt }
    }

    public func record(_ video: RecentVideo) {
        var videos = load().filter { $0.videoID != video.videoID }
        videos.insert(video, at: 0)
        videos = Array(videos.prefix(maximumEntries))
        guard let data = try? JSONEncoder().encode(videos) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
