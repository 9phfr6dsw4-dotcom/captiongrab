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

private enum ChromeCompanionSetupError: Error, LocalizedError {
    case chromeNotInstalled
    case userHomeUnavailable
    case nativeHostMissing
    case extensionAssetsMissing
    case wrongChromeFolder
    case nativeHostRegistrationConflict
    case registrationWriteFailed

    var errorDescription: String? {
        switch self {
        case .chromeNotInstalled:
            "Google Chrome is not installed. Install Chrome, then try the setup again."
        case .userHomeUnavailable:
            "CaptionGrab couldn't locate your Mac account's home folder. Restart the app and try again."
        case .nativeHostMissing:
            "CaptionGrab's Chrome helper is missing. Reinstall CaptionGrab from its ZIP, then try again."
        case .extensionAssetsMissing:
            "CaptionGrab's Chrome extension files are missing. Reinstall CaptionGrab from its ZIP."
        case .wrongChromeFolder:
            "Select the Google Chrome folder at Library/Application Support/Google/Chrome."
        case .nativeHostRegistrationConflict:
            "A different program already uses CaptionGrab's Chrome helper name. Its registration was left unchanged."
        case .registrationWriteFailed:
            "CaptionGrab couldn't register its local Chrome helper. Check the selected Chrome folder's access and try again."
        }
    }
}

enum ChromeCompanionSetup {
    private static var expectedChromeRoot: URL? {
        guard let chromeRoot = ChromeCompanionConstants.chromeProfileDirectory() else { return nil }
        return ChromeCompanionConstants.canonicalFileURL(chromeRoot)
    }

    static func savedChromeRoot() -> URL? {
        guard let expectedChromeRoot,
              let data = UserDefaults.standard.data(forKey: ChromeCompanionConstants.chromeFolderBookmarkKey) else { return nil }
        var stale = false
        guard let folder = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale,
           ChromeCompanionConstants.canonicalFileURL(folder) == expectedChromeRoot else { return nil }
        return folder
    }

    static func isRegistered(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        guard let chromeRoot = savedChromeRoot() else { return false }
        guard chromeRoot.startAccessingSecurityScopedResource() else { return false }
        defer { chromeRoot.stopAccessingSecurityScopedResource() }

        let expectedHost = ChromeCompanionConstants.nativeHostExecutable(bundleURL: bundleURL.resolvingSymlinksInPath()).standardizedFileURL.path
        let manifestURL = ChromeCompanionConstants.chromeNativeMessagingDirectory(chromeRootURL: chromeRoot)
            .appendingPathComponent(ChromeCompanionConstants.nativeHostManifestFileName)
        guard FileManager.default.isExecutableFile(atPath: expectedHost),
              FileManager.default.fileExists(atPath: ChromeCompanionConstants.extensionDirectory(bundleURL: bundleURL).appendingPathComponent("manifest.json").path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ChromeNativeMessagingManifest.self, from: data) else { return false }
        return manifest.name == ChromeCompanionConstants.nativeHostName &&
            manifest.path == expectedHost &&
            manifest.type == "stdio" &&
            manifest.allowed_origins == ["chrome-extension://\(ChromeCompanionConstants.extensionID)/"]
    }

    @MainActor
    static func install() throws -> URL? {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else {
            throw ChromeCompanionSetupError.chromeNotInstalled
        }
        guard let accountHome = ChromeCompanionConstants.currentUserHomeDirectory(),
              let expectedChromeDirectory = ChromeCompanionConstants.chromeProfileDirectory(homeURL: accountHome) else {
            throw ChromeCompanionSetupError.userHomeUnavailable
        }
        let expectedChromeRoot = ChromeCompanionConstants.canonicalFileURL(expectedChromeDirectory)
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let hostURL = ChromeCompanionConstants.nativeHostExecutable(bundleURL: appURL)
        let extensionURL = ChromeCompanionConstants.extensionDirectory(bundleURL: appURL)
        guard FileManager.default.isExecutableFile(atPath: hostURL.path) else {
            throw ChromeCompanionSetupError.nativeHostMissing
        }
        guard FileManager.default.fileExists(atPath: extensionURL.appendingPathComponent("manifest.json").path) else {
            throw ChromeCompanionSetupError.extensionAssetsMissing
        }

        var scopedURLToStop: URL?
        defer { scopedURLToStop?.stopAccessingSecurityScopedResource() }

        let chromeRoot: URL
        if let saved = savedChromeRoot(), saved.startAccessingSecurityScopedResource() {
            chromeRoot = saved
            scopedURLToStop = saved
        } else {
            UserDefaults.standard.removeObject(forKey: ChromeCompanionConstants.chromeFolderBookmarkKey)
            let panel = NSOpenPanel()
            panel.title = "Allow CaptionGrab to connect to Chrome"
            panel.message = "Select the Google Chrome folder inside Library/Application Support/Google/Chrome. CaptionGrab will add its Native Messaging helper there."
            panel.prompt = "Select Chrome Folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = expectedChromeRoot
            guard panel.runModal() == .OK, let selected = panel.url else { return nil }
            scopedURLToStop = selected
            guard ChromeCompanionConstants.isChromeProfileDirectory(
                selectedURL: selected,
                homeURL: accountHome
            ) else {
                throw ChromeCompanionSetupError.wrongChromeFolder
            }
            chromeRoot = selected
        }

        let chromeDirectory = ChromeCompanionConstants.chromeNativeMessagingDirectory(chromeRootURL: chromeRoot)
        let registrationURL = chromeDirectory.appendingPathComponent(ChromeCompanionConstants.nativeHostManifestFileName)
        let allowedOrigin = "chrome-extension://\(ChromeCompanionConstants.extensionID)/"
        let description = "Receives the transcript from CaptionGrab's YouTube-only Chrome extension."
        if FileManager.default.fileExists(atPath: registrationURL.path) {
            guard let existingData = try? Data(contentsOf: registrationURL),
                  let existing = try? JSONDecoder().decode(ChromeNativeMessagingManifest.self, from: existingData),
                  existing.name == ChromeCompanionConstants.nativeHostName,
                  existing.description == description,
                  existing.type == "stdio",
                  existing.allowed_origins == [allowedOrigin],
                  URL(fileURLWithPath: existing.path).lastPathComponent == "CaptionGrabNativeHost" else {
                throw ChromeCompanionSetupError.nativeHostRegistrationConflict
            }
        }

        let inbox = ChromeCompanionConstants.inboxDirectory(chromeRootURL: chromeRoot)
        let manifest = ChromeNativeMessagingManifest(
            name: ChromeCompanionConstants.nativeHostName,
            description: description,
            path: hostURL.path,
            type: "stdio",
            allowed_origins: [allowedOrigin]
        )

        do {
            try FileManager.default.createDirectory(at: chromeDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let bookmark = try chromeRoot.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try encoder.encode(manifest).write(to: registrationURL, options: .atomic)
            UserDefaults.standard.set(bookmark, forKey: ChromeCompanionConstants.chromeFolderBookmarkKey)
        } catch {
            throw ChromeCompanionSetupError.registrationWriteFailed
        }
        return extensionURL
    }
}
