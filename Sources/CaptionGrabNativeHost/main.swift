import Foundation
import CaptionGrabCore

private enum NativeHostFailure: Error, LocalizedError {
    case malformedFrame
    case unauthorizedExtension
    case invalidRequest
    case invalidStorageLocation

    var errorDescription: String? {
        switch self {
        case .malformedFrame: "The Chrome extension sent an invalid message."
        case .unauthorizedExtension: "The request did not come from the CaptionGrab extension."
        case .invalidRequest: "The Chrome extension sent an invalid transcript response."
        case .invalidStorageLocation: "The Chrome helper is not configured for CaptionGrab's local inbox."
        }
    }
}

private let maximumMessageBytes = 60 * 1_024 * 1_024

func readExactly(_ count: Int) throws -> Data {
    var result = Data()
    while result.count < count {
        guard let next = try FileHandle.standardInput.read(upToCount: count - result.count), !next.isEmpty else {
            throw NativeHostFailure.malformedFrame
        }
        result.append(next)
    }
    return result
}

func readLittleEndianUInt32(_ data: Data) -> UInt32 {
    data.enumerated().reduce(UInt32(0)) { value, item in
        value | (UInt32(item.element) << UInt32(item.offset * 8))
    }
}

func frame(_ data: Data) -> Data {
    var result = Data()
    var length = UInt32(data.count).littleEndian
    withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
    result.append(data)
    return result
}

func writeResponse(_ object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    try? FileHandle.standardOutput.write(contentsOf: frame(body))
}

func requestDataDirectory() throws -> URL {
    guard let inbox = ChromeCompanionConstants.inboxDirectory() else {
        throw NativeHostFailure.invalidStorageLocation
    }
    return inbox
}

func validate(_ message: ChromeTranscriptMessage) throws -> UUID {
    guard let requestID = UUID(uuidString: message.requestID),
          message.videoID.count == 11,
          message.videoID.unicodeScalars.allSatisfy({
              CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
          }) else { throw NativeHostFailure.invalidRequest }

    if message.type == "captiongrab.transcript" {
        let canonicalURL = URL(string: "https://www.youtube.com/watch?v=\(message.videoID)")!
        _ = try message.makeTranscript(
            expectedRequestID: message.requestID,
            expectedVideoID: message.videoID,
            canonicalURL: canonicalURL
        )
    } else if message.type == "captiongrab.error" {
        guard let error = message.error, !error.isEmpty, error.count <= 1_000 else {
            throw NativeHostFailure.invalidRequest
        }
    } else {
        throw NativeHostFailure.invalidRequest
    }
    return requestID
}

func runNativeHost() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let allowedOrigin = "chrome-extension://\(ChromeCompanionConstants.extensionID)/"
    guard arguments.contains(allowedOrigin) else { throw NativeHostFailure.unauthorizedExtension }

    let directory = try requestDataDirectory()
    let size = Int(readLittleEndianUInt32(try readExactly(4)))
    guard size > 0, size <= maximumMessageBytes else { throw NativeHostFailure.malformedFrame }
    let body = try readExactly(size)
    let message = try JSONDecoder().decode(ChromeTranscriptMessage.self, from: body)
    let requestID = try validate(message)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("\(requestID.uuidString.lowercased()).json")
    try body.write(to: destination, options: .atomic)
    writeResponse(["ok": true, "requestID": requestID.uuidString.lowercased()])
}

do {
    try runNativeHost()
} catch {
    let description = (error as? LocalizedError)?.errorDescription ?? "CaptionGrab's Chrome helper could not accept the transcript."
    writeResponse(["ok": false, "error": String(description.prefix(500))])
    exit(EXIT_FAILURE)
}
