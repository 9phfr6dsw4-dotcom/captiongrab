import Foundation

public struct TranscriptFallbackSegment: Equatable, Sendable {
    public let timestamp: String
    public let text: String

    public init(timestamp: String, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

public enum TranscriptFallbackValidationError: Error, Equatable, LocalizedError, Sendable {
    case sourceTooLarge
    case emptyOutput
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .sourceTooLarge:
            "The visible YouTube transcript is too large for on-device recovery."
        case .emptyOutput:
            "Apple Intelligence could not recover any transcript captions from the visible YouTube panel."
        case .invalidOutput:
            "Apple Intelligence returned captions that could not be verified against the visible YouTube transcript."
        }
    }
}

public enum TranscriptFallbackValidator {
    public static let maximumSourceBytes = 20_000
    public static let maximumCueCount = 10_000
    private static let maximumCaptionCharacters = 10_000_000
    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"(?<![0-9:])(?:[0-9]{1,3}:)?[0-9]{1,2}:[0-9]{2}(?![0-9:])"#
    )

    public static func validate(
        _ generated: [TranscriptFallbackSegment],
        sourceText: String
    ) throws -> [TranscriptCue] {
        guard sourceText.utf8.count <= maximumSourceBytes else {
            throw TranscriptFallbackValidationError.sourceTooLarge
        }
        guard !generated.isEmpty else { throw TranscriptFallbackValidationError.emptyOutput }
        guard generated.count <= maximumCueCount else { throw TranscriptFallbackValidationError.invalidOutput }

        let normalizedSource = normalizeWhitespace(sourceText)
        guard timestamps(in: normalizedSource).count == generated.count else {
            throw TranscriptFallbackValidationError.invalidOutput
        }
        var cursor = normalizedSource.startIndex
        var previousTimestamp = -1
        var totalCaptionCharacters = 0
        var cues: [TranscriptCue] = []
        cues.reserveCapacity(generated.count)

        for segment in generated {
            let timestampText = normalizeWhitespace(segment.timestamp)
            let captionText = normalizeWhitespace(segment.text)
            guard let milliseconds = parseTimestamp(timestampText),
                  milliseconds >= previousTimestamp,
                  !captionText.isEmpty,
                  let captionRange = normalizedSource.range(of: captionText, range: cursor..<normalizedSource.endIndex)
            else { throw TranscriptFallbackValidationError.invalidOutput }

            let beforeCaption = String(normalizedSource[cursor..<captionRange.lowerBound])
            guard let nearestTimestamp = timestamps(in: beforeCaption).last,
                  nearestTimestamp.milliseconds == milliseconds,
                  beforeCaption.distance(from: nearestTimestamp.range.upperBound, to: beforeCaption.endIndex) <= 2_000
            else { throw TranscriptFallbackValidationError.invalidOutput }

            totalCaptionCharacters += captionText.count
            guard totalCaptionCharacters <= maximumCaptionCharacters else {
                throw TranscriptFallbackValidationError.invalidOutput
            }
            cues.append(TranscriptCue(startTimeMilliseconds: milliseconds, text: captionText))
            previousTimestamp = milliseconds
            cursor = captionRange.upperBound
        }
        return cues
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func parseTimestamp(_ value: String) -> Int? {
        let pieces = value.split(separator: ":")
        guard pieces.count == 2 || pieces.count == 3,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let seconds = Int(pieces.last!), seconds <= 59,
              let finalMinutes = Int(pieces[pieces.count - 2]) else { return nil }

        if pieces.count == 2 {
            guard finalMinutes <= 999 else { return nil }
            return finalMinutes * 60_000 + seconds * 1_000
        }
        guard finalMinutes <= 59,
              let hours = Int(pieces[0]), hours <= 999 else { return nil }
        return hours * 3_600_000 + finalMinutes * 60_000 + seconds * 1_000
    }

    private static func timestamps(in text: String) -> [(milliseconds: Int, range: Range<String.Index>)] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return timestampExpression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let milliseconds = parseTimestamp(String(text[range])) else { return nil }
            return (milliseconds, range)
        }
    }
}

public struct ChromeTranscriptFallbackInput: Equatable, Sendable {
    public static let maximumSourceBytes = TranscriptFallbackValidator.maximumSourceBytes

    public let title: String
    public let sourceText: String

    public init(title: String, sourceText: String) {
        self.title = title
        self.sourceText = sourceText
    }
}
