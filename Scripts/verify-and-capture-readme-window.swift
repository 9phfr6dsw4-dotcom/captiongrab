import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Vision

private struct AppWindow {
    let id: CGWindowID
    let title: String
    let width: CGFloat
    let height: CGFloat
}

private enum CaptureFailure: Error {
    case noMainWindow
    case invalidWindow
    case screenshotFailed
    case transcriptNotVisible
}

private let transcriptURLLabel = "YouTube Video url"

private func normalized(_ value: String) -> String {
    value.filter(\.isLetter).lowercased()
}

private func mainWindow() throws -> AppWindow {
    let ownerKey = kCGWindowOwnerName as String
    let layerKey = kCGWindowLayer as String
    let numberKey = kCGWindowNumber as String
    let boundsKey = kCGWindowBounds as String
    let nameKey = kCGWindowName as String
    let alphaKey = kCGWindowAlpha as String
    let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let candidates = rows.compactMap { row -> AppWindow? in
        guard normalized(row[ownerKey] as? String ?? "") == "captiongrab",
              (row[layerKey] as? NSNumber)?.intValue == 0,
              ((row[alphaKey] as? NSNumber)?.doubleValue ?? 1) > 0,
              let id = (row[numberKey] as? NSNumber)?.uint32Value,
              let bounds = row[boundsKey] as? [String: Any],
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return AppWindow(
            id: id,
            title: row[nameKey] as? String ?? "",
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
    guard let candidate = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
        throw CaptureFailure.noMainWindow
    }
    guard candidate.width >= 680,
          candidate.height >= 620,
          candidate.title.isEmpty || normalized(candidate.title).contains("captiongrab") else {
        throw CaptureFailure.invalidWindow
    }
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.captiongrab.app" else {
        throw CaptureFailure.invalidWindow
    }
    return candidate
}

private func captureWindow(_ id: CGWindowID, to url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l", String(id), url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width > 0,
          image.height > 0 else {
        throw CaptureFailure.screenshotFailed
    }
}

private func verifyTranscript(in imageURL: URL, expectedVideoID: String) throws -> Bool {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    try VNImageRequestHandler(url: imageURL, options: [:]).perform([request])

    let observations: [(y: CGFloat, text: String)] = (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        return (observation.boundingBox.midY, text)
    }
    let lines = observations.sorted { $0.y > $1.y }.map(\.text)
    let recognized = lines.joined(separator: " ").lowercased()
    guard recognized.contains("captiongrab"),
          recognized.contains("transcript"),
          !recognized.contains("no transcript yet"),
          !recognized.contains("fetching captions") else {
        return false
    }

    guard let transcriptIndex = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("transcript") }),
          let urlIndex = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(transcriptURLLabel) }),
          transcriptIndex < urlIndex else {
        return false
    }
    let expectedIDText = String(expectedVideoID.filter { $0.isLetter || $0.isNumber }).lowercased()
    let visibleURLText = String(lines[urlIndex..<min(urlIndex + 4, lines.count)].joined().filter { $0.isLetter || $0.isNumber }).lowercased()
    guard expectedIDText.count >= 8, visibleURLText.contains(expectedIDText) else {
        return false
    }

    let titleText = lines[(transcriptIndex + 1)..<urlIndex].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard titleText.count >= 3,
          titleText.rangeOfCharacter(from: .letters) != nil,
          !titleText.localizedCaseInsensitiveContains("paste a youtube link") else {
        return false
    }

    let cueLines = Array(lines.dropFirst(urlIndex + 1))
    let cueText = cueLines.joined(separator: " ")
    let timestampPattern = try NSRegularExpression(pattern: #"(?<!\d)\d{1,2}:[0-5]\d(?!\d)"#)
    let range = NSRange(cueText.startIndex..<cueText.endIndex, in: cueText)
    guard timestampPattern.numberOfMatches(in: cueText, range: range) >= 2,
          cueLines.contains(where: { $0.rangeOfCharacter(from: .letters) != nil }) else {
        return false
    }
    return true
}

private func run() throws {
    guard CommandLine.arguments.count == 4 else {
        throw CaptureFailure.invalidWindow
    }
    let appPath = CommandLine.arguments[1]
    let videoID = CommandLine.arguments[2]
    let finalURL = URL(fileURLWithPath: CommandLine.arguments[3])
    guard appPath.hasSuffix("/CaptionGrab.app"),
          videoID.range(of: #"\A[A-Za-z0-9_-]{11}\z"#, options: .regularExpression) != nil else {
        throw CaptureFailure.invalidWindow
    }

    let window = try mainWindow()
    try captureWindow(window.id, to: finalURL)
    guard try verifyTranscript(in: finalURL, expectedVideoID: videoID) else {
        throw CaptureFailure.transcriptNotVisible
    }
    print("Verified CaptionGrab 1.2.17 app window (\(Int(window.width)) × \(Int(window.height)) points) with the requested title and visible nonempty transcript.")
}

do {
    try run()
} catch {
    fputs("Capture failed closed: CaptionGrab's app window or a visible nonempty transcript could not be verified.\n", stderr)
    exit(1)
}
