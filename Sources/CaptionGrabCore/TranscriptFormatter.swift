import Foundation

public enum TranscriptFormatter {
    public static func markdown(for transcript: TranscriptData) -> String {
        let title = transcript.videoTitle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
        let header = "**\(title)**\n\nYouTube Video url: \(transcript.videoURL.absoluteString)"
        let captionPairs = transcript.cues.map { "\($0.displayTimestamp)\n\($0.text)" }
        guard !captionPairs.isEmpty else { return header }
        return header + "\n\n" + captionPairs.joined(separator: "\n\n")
    }

    public static func markdownFile(for transcript: TranscriptData) -> String {
        let url = transcript.videoURL.absoluteString
        let header = "# \(transcript.videoTitle)\n\n**YouTube Video url:** [\(url)](<\(url)>)"
        let captions = transcript.cues.map { "\($0.displayTimestamp) – \($0.text)" }
        guard !captions.isEmpty else { return header }
        return header + "\n\n" + captions.joined(separator: "  \n")
    }
}
