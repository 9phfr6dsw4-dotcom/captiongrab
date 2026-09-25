import Foundation

/// Keeps actionable filesystem failure details available to the UI and user screenshots.
public struct FileSystemDiagnostic: Error, LocalizedError {
    public let operation: String
    public let path: String
    public let underlyingDomain: String
    public let underlyingCode: Int
    public let underlyingDescription: String
    public let failureReason: String?
    public let recoverySuggestion: String?
    public let underlyingFilePath: String?

    public init(operation: String, path: String, underlyingError: Error) {
        let error = underlyingError as NSError
        self.operation = operation
        self.path = path
        self.underlyingDomain = error.domain
        self.underlyingCode = error.code
        self.underlyingDescription = error.localizedDescription
        self.failureReason = error.localizedFailureReason
        self.recoverySuggestion = error.localizedRecoverySuggestion
        self.underlyingFilePath = error.userInfo[NSFilePathErrorKey] as? String
    }

    public var errorDescription: String? {
        var lines = [
            "Setup failed: \(operation)",
            "Path: \(path)",
            "Underlying error: \(underlyingDescription)",
            "Error domain: \(underlyingDomain)",
            "Error code: \(underlyingCode)"
        ]
        if let underlyingFilePath, underlyingFilePath != path {
            lines.append("Underlying error path: \(underlyingFilePath)")
        }
        if let failureReason, !failureReason.isEmpty {
            lines.append("Reason: \(failureReason)")
        }
        if let recoverySuggestion, !recoverySuggestion.isEmpty {
            lines.append("Suggested action: \(recoverySuggestion)")
        }
        return lines.joined(separator: "\n")
    }
}
