import Foundation

/// Resolves a stable installed bundle when macOS launches the app from an App Translocation copy.
public enum CaptionGrabInstallationLocator {
    public static func isAppTranslocated(bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.pathComponents.contains("AppTranslocation")
    }

    public static func resolvedBundleURL(
        runningBundleURL: URL,
        registeredBundleURLs: [URL],
        expectedBundleIdentifier: String,
        expectedShortVersion: String,
        expectedBuildVersion: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let runningURL = runningBundleURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isAppTranslocated(bundleURL: runningURL) else {
            return runningURL.resolvingSymlinksInPath().standardizedFileURL
        }

        for registeredURL in registeredBundleURLs {
            let candidateURL = registeredURL.standardizedFileURL.resolvingSymlinksInPath()
            guard !isAppTranslocated(bundleURL: registeredURL),
                  !isAppTranslocated(bundleURL: candidateURL),
                  let info = bundleInfo(at: candidateURL, fileManager: fileManager),
                  info["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
                  info["CFBundleShortVersionString"] as? String == expectedShortVersion,
                  info["CFBundleVersion"] as? String == expectedBuildVersion,
                  fileManager.isExecutableFile(atPath: ChromeCompanionConstants.nativeHostExecutable(bundleURL: candidateURL).path),
                  fileManager.fileExists(atPath: ChromeCompanionConstants.extensionDirectory(bundleURL: candidateURL)
                    .appendingPathComponent("manifest.json").path) else {
                continue
            }
            return candidateURL.standardizedFileURL
        }
        return nil
    }

    private static func bundleInfo(at bundleURL: URL, fileManager: FileManager) -> [String: Any]? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: infoURL.path),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = propertyList as? [String: Any] else {
            return nil
        }
        return info
    }
}
