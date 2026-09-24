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
}
