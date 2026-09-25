import AppKit
import CaptionGrabCore
import Foundation

private struct ChromeNativeMessagingManifest: Codable {
    let name: String
    let description: String
    let path: String
    let type: String
    let allowed_origins: [String]
}

enum ChromeCompanionSetup {
    static func isRegistered(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        registrationProblem(bundleURL: bundleURL) == nil
    }

    static func registrationProblem(bundleURL: URL = Bundle.main.bundleURL) -> String? {
        let fileManager = FileManager.default
        let appURL = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let hostURL = ChromeCompanionConstants.nativeHostExecutable(bundleURL: appURL)
        let extensionManifestURL = ChromeCompanionConstants.extensionDirectory(bundleURL: appURL)
            .appendingPathComponent("manifest.json")
        let registrationURL = ChromeCompanionConstants.chromeNativeMessagingDirectory()
            .appendingPathComponent(ChromeCompanionConstants.nativeHostManifestFileName)
        let allowedOrigin = "chrome-extension://\(ChromeCompanionConstants.extensionID)/"

        guard fileManager.isExecutableFile(atPath: hostURL.path) else {
            return missingFileDiagnostic("Check CaptionGrab's Native Messaging executable", at: hostURL).localizedDescription
        }
        guard fileManager.fileExists(atPath: extensionManifestURL.path) else {
            return missingFileDiagnostic("Check CaptionGrab's Chrome extension files", at: extensionManifestURL).localizedDescription
        }
        guard fileManager.fileExists(atPath: registrationURL.path) else {
            return missingFileDiagnostic("Check Chrome's Native Messaging registration", at: registrationURL).localizedDescription
        }

        let data: Data
        do {
            data = try Data(contentsOf: registrationURL)
        } catch {
            return FileSystemDiagnostic(operation: "Read Chrome's Native Messaging registration", path: registrationURL.path, underlyingError: error).localizedDescription
        }
        let manifest: ChromeNativeMessagingManifest
        do {
            manifest = try JSONDecoder().decode(ChromeNativeMessagingManifest.self, from: data)
        } catch {
            return FileSystemDiagnostic(operation: "Parse Chrome's Native Messaging registration", path: registrationURL.path, underlyingError: error).localizedDescription
        }

        guard manifest.name == ChromeCompanionConstants.nativeHostName,
              manifest.path == hostURL.path,
              manifest.type == "stdio",
              manifest.allowed_origins == [allowedOrigin] else {
            return diagnostic(
                "Validate Chrome's Native Messaging registration",
                at: registrationURL,
                description: "The registration does not point to this CaptionGrab installation and its fixed Chrome extension ID.",
                reason: "Expected host path: \(hostURL.path)\nActual host path: \(manifest.path)\nExpected extension origin: \(allowedOrigin)\nActual extension origins: \(manifest.allowed_origins.joined(separator: ", "))"
            ).localizedDescription
        }
        return nil
    }

    @MainActor
    static func install() throws -> URL {
        ChromeCompanionConstants.clearLegacyChromeFolderBookmark()
        let fileManager = FileManager.default

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else {
            throw diagnostic(
                "Locate Google Chrome",
                path: "Launch Services bundle identifier com.google.Chrome",
                description: "Google Chrome is not installed or could not be located."
            )
        }

        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let hostURL = ChromeCompanionConstants.nativeHostExecutable(bundleURL: appURL)
        let extensionURL = ChromeCompanionConstants.extensionDirectory(bundleURL: appURL)
        let extensionManifestURL = extensionURL.appendingPathComponent("manifest.json")
        guard fileManager.isExecutableFile(atPath: hostURL.path) else {
            throw missingFileDiagnostic("Check CaptionGrab's Native Messaging executable", at: hostURL)
        }
        guard fileManager.fileExists(atPath: extensionManifestURL.path) else {
            throw missingFileDiagnostic("Check CaptionGrab's Chrome extension files", at: extensionManifestURL)
        }

        let chromeDirectory = ChromeCompanionConstants.chromeNativeMessagingDirectory()
        let registrationURL = chromeDirectory.appendingPathComponent(ChromeCompanionConstants.nativeHostManifestFileName)
        let inboxDirectory = ChromeCompanionConstants.transcriptInboxDirectory()
        let allowedOrigin = "chrome-extension://\(ChromeCompanionConstants.extensionID)/"
        let description = "Receives the transcript from CaptionGrab's YouTube-only Chrome extension."

        if fileManager.fileExists(atPath: registrationURL.path) {
            let existingData: Data
            do {
                existingData = try Data(contentsOf: registrationURL)
            } catch {
                throw FileSystemDiagnostic(operation: "Read existing Chrome Native Messaging registration", path: registrationURL.path, underlyingError: error)
            }
            let existing: ChromeNativeMessagingManifest
            do {
                existing = try JSONDecoder().decode(ChromeNativeMessagingManifest.self, from: existingData)
            } catch {
                throw FileSystemDiagnostic(operation: "Parse existing Chrome Native Messaging registration", path: registrationURL.path, underlyingError: error)
            }
            guard existing.name == ChromeCompanionConstants.nativeHostName,
                  existing.type == "stdio",
                  existing.allowed_origins == [allowedOrigin],
                  URL(fileURLWithPath: existing.path).lastPathComponent == "CaptionGrabNativeHost" else {
                throw diagnostic(
                    "Validate existing Chrome Native Messaging registration",
                    at: registrationURL,
                    description: "A different program already uses CaptionGrab's Native Messaging host name. The existing registration was left unchanged.",
                    reason: "Existing host path: \(existing.path)\nExpected host name: \(ChromeCompanionConstants.nativeHostName)\nExpected extension origin: \(allowedOrigin)"
                )
            }
        }

        let manifest = ChromeNativeMessagingManifest(
            name: ChromeCompanionConstants.nativeHostName,
            description: description,
            path: hostURL.path,
            type: "stdio",
            allowed_origins: [allowedOrigin]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData: Data
        do {
            manifestData = try encoder.encode(manifest)
        } catch {
            throw FileSystemDiagnostic(operation: "Encode Chrome Native Messaging registration", path: registrationURL.path, underlyingError: error)
        }

        try performFileOperation("Create Chrome Native Messaging directory", at: chromeDirectory) {
            try fileManager.createDirectory(at: chromeDirectory, withIntermediateDirectories: true)
        }
        try performFileOperation("Create CaptionGrab transcript storage directory", at: inboxDirectory) {
            try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        }
        try performFileOperation("Write Chrome Native Messaging registration", at: registrationURL) {
            try manifestData.write(to: registrationURL, options: .atomic)
        }

        ChromeCompanionConstants.clearLegacyChromeFolderBookmark()
        return extensionURL
    }

    private static func performFileOperation<T>(_ operation: String, at url: URL, body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw FileSystemDiagnostic(operation: operation, path: url.path, underlyingError: error)
        }
    }

    private static func missingFileDiagnostic(_ operation: String, at url: URL) -> FileSystemDiagnostic {
        diagnostic(
            operation,
            at: url,
            description: "The required file does not exist or is not accessible.",
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            reason: "Check that CaptionGrab is installed completely and that this path is readable."
        )
    }

    private static func diagnostic(
        _ operation: String,
        at url: URL,
        description: String,
        domain: String = "CaptionGrab.ChromeSetup",
        code: Int = 1,
        reason: String? = nil
    ) -> FileSystemDiagnostic {
        diagnostic(operation, path: url.path, description: description, domain: domain, code: code, reason: reason)
    }

    private static func diagnostic(
        _ operation: String,
        path: String,
        description: String,
        domain: String = "CaptionGrab.ChromeSetup",
        code: Int = 1,
        reason: String? = nil
    ) -> FileSystemDiagnostic {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
        if let reason { userInfo[NSLocalizedFailureReasonErrorKey] = reason }
        userInfo[NSFilePathErrorKey] = path
        let underlying = NSError(domain: domain, code: code, userInfo: userInfo)
        return FileSystemDiagnostic(operation: operation, path: path, underlyingError: underlying)
    }
}
