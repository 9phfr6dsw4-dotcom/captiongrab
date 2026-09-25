import AppKit
import CaptionGrabCore
import Foundation

private enum ChromeTranscriptBridgeError: Error, LocalizedError {
    case setupRequired(String)
    case chromeMissing
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .setupRequired(details):
            "Chrome helper setup is incomplete.\n\n\(details)"
        case .chromeMissing:
            "Google Chrome is not installed. Install Chrome, then try again."
        case .timedOut:
            "CaptionGrab didn't receive a transcript from Chrome. At chrome://extensions, confirm the extension is loaded, Developer mode is on, and the extension can access youtube.com."
        case .invalidResponse:
            "Chrome returned a transcript response that didn't match the requested video. Try again."
        }
    }
}

@MainActor
enum ChromeTranscriptBridge {
    static func fetch(
        link: YouTubeLink,
        timeout: Duration = .seconds(90),
        onDebugLog: @MainActor (String?) -> Void = { _ in }
    ) async throws -> TranscriptData {
        if let problem = ChromeCompanionSetup.registrationProblem() {
            throw ChromeTranscriptBridgeError.setupRequired(problem)
        }
        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            throw ChromeTranscriptBridgeError.chromeMissing
        }

        let requestID = UUID().uuidString.lowercased()
        onDebugLog("CaptionGrab Chrome debug log\n[app] Native host setup is valid; preparing the requested Chrome video.\n")
        let inbox = ChromeCompanionConstants.transcriptInboxDirectory()
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        } catch {
            throw FileSystemDiagnostic(operation: "Create CaptionGrab transcript inbox", path: inbox.path, underlyingError: error)
        }
        let resultURL = inbox.appendingPathComponent("\(requestID).json")
        try? FileManager.default.removeItem(at: resultURL)

        guard var components = URLComponents(url: link.canonicalURL, resolvingAgainstBaseURL: false) else {
            throw CaptionGrabError.invalidLink
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == ChromeCompanionConstants.requestQueryName }
        queryItems.append(URLQueryItem(name: ChromeCompanionConstants.requestQueryName, value: requestID))
        components.queryItems = queryItems
        guard let requestURL = components.url else { throw CaptionGrabError.invalidLink }

        NSWorkspace.shared.open(
            [requestURL],
            withApplicationAt: chromeURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: resultURL) {
                try? FileManager.default.removeItem(at: resultURL)
                guard let message = try? JSONDecoder().decode(ChromeTranscriptMessage.self, from: data) else {
                    throw ChromeTranscriptBridgeError.invalidResponse
                }
                onDebugLog(message.debugLog)
                do {
                    return try message.makeTranscript(
                        expectedRequestID: requestID,
                        expectedVideoID: link.videoID,
                        canonicalURL: link.canonicalURL
                    )
                } catch let error as ChromeTranscriptMessageError {
                    throw error
                } catch {
                    throw ChromeTranscriptBridgeError.invalidResponse
                }
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ChromeTranscriptBridgeError.timedOut
    }
}
