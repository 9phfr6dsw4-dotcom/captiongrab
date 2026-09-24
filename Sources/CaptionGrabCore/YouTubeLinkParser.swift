import Foundation

public enum YouTubeLinkParser {
    public static func parse(_ input: String) throws -> YouTubeLink {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CaptionGrabError.invalidLink }

        let rawURL: String
        if value.contains("://") {
            rawURL = value
        } else if value.hasPrefix("www.") || value.hasPrefix("youtube.com/") || value.hasPrefix("youtu.be/") || value.hasPrefix("m.youtube.com/") || value.hasPrefix("music.youtube.com/") {
            rawURL = "https://\(value)"
        } else {
            throw CaptionGrabError.invalidLink
        }

        guard let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 80 || components.port == 443
        else { throw CaptionGrabError.invalidLink }

        let isYouTubeHost = host == "youtube.com" || host.hasSuffix(".youtube.com")
        let isShortHost = host == "youtu.be"
        let isNoCookieHost = host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
        guard isYouTubeHost || isShortHost || isNoCookieHost else { throw CaptionGrabError.invalidLink }

        let path = components.path.split(separator: "/").map(String.init)
        var candidate: String?
        if isShortHost {
            candidate = path.first
        } else if components.path == "/watch" {
            candidate = components.queryItems?.first(where: { $0.name == "v" })?.value
        } else if path.count >= 2 && ["shorts", "live", "embed", "v"].contains(path[0]) {
            candidate = path[1]
        }

        guard let videoID = candidate,
              videoID.count == 11,
              videoID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
              }),
              let canonicalURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
        else { throw CaptionGrabError.invalidLink }

        return YouTubeLink(videoID: videoID, canonicalURL: canonicalURL)
    }
}
