import Foundation

public enum YouTubeTranscriptParser {
    public static func parse(_ data: Data) throws -> [TranscriptCue] {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           root["events"] is [[String: Any]] {
            return try parseJSON3(data)
        }
        return try parseXML(data)
    }

    public static func parseJSON3(_ data: Data) throws -> [TranscriptCue] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            throw CaptionGrabError.youtubeChanged
        }

        return events.compactMap { event in
            guard let start = (event["tStartMs"] as? NSNumber)?.intValue,
                  let segments = event["segs"] as? [[String: Any]] else { return nil }
            let rawText = segments.compactMap { $0["utf8"] as? String }.joined()
            let text = visibleCaptionText(rawText)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranscriptCue(startTimeMilliseconds: start, text: text)
        }
    }

    public static func parseXML(_ data: Data) throws -> [TranscriptCue] {
        let parser = XMLParser(data: data)
        let delegate = CaptionXMLDelegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw CaptionGrabError.youtubeChanged }
        return delegate.cues
    }

    private static func visibleCaptionText(_ source: String) -> String {
        var text = source
        if let breaks = try? NSRegularExpression(pattern: "(?i)<br\\s*/?>") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = breaks.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
        }
        if let tags = try? NSRegularExpression(pattern: "(?i)</?(?:font|b|i|u|s|ruby|rt|c)(?:\\s[^>]*)?>") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = tags.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        text = decodeNumericEntities(text)
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: "\u{00a0}")
    }

    private static func decodeNumericEntities(_ source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(?:x([0-9a-fA-F]+)|([0-9]+));") else { return source }
        var result = source
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source))
        for match in matches.reversed() {
            let numberRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard let range = Range(match.range, in: result),
                  let numberTextRange = Range(numberRange, in: source) else { continue }
            let radix = match.range(at: 1).location != NSNotFound ? 16 : 10
            guard let value = UInt32(source[numberTextRange], radix: radix),
                  let scalar = UnicodeScalar(value) else { continue }
            result.replaceSubrange(range, with: String(scalar))
        }
        return result
    }
}

private final class CaptionXMLDelegate: NSObject, XMLParserDelegate {
    private var currentStart: Int?
    private var currentText = ""
    fileprivate var cues: [TranscriptCue] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "text", let seconds = Double(attributeDict["start"] ?? "") {
            currentStart = Int((seconds * 1_000).rounded(.down))
            currentText = ""
        } else if currentStart != nil && elementName == "br" {
            currentText.append("\n")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentStart != nil { currentText.append(string) }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if currentStart != nil, let text = String(data: CDATABlock, encoding: .utf8) { currentText.append(text) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "text", let start = currentStart else { return }
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cues.append(TranscriptCue(startTimeMilliseconds: start, text: currentText))
        }
        currentStart = nil
        currentText = ""
    }
}
