import Foundation

public enum ChromeCompanionConstants {
    public static let nativeHostName = "com.captiongrab.host"
    public static let extensionID = "kajphiodjnkmgeidbcndikaaegghiffi"
    public static let nativeHostManifestFileName = "\(nativeHostName).json"
    public static let supportDirectoryName = "CaptionGrab"
    public static let inboxDirectoryName = "ChromeInbox"
    public static let requestQueryName = "captiongrab_request"
    public static let chromeFolderBookmarkKey = "CaptionGrab.chromeNativeMessagingFolderBookmark"

    // Look up the account home explicitly; NSHomeDirectory() can be redirected to a sandbox container.
    public static func currentUserHomeDirectory(fileManager: FileManager = .default) -> URL? {
        let userName = NSUserName()
        if let accountHome = fileManager.homeDirectory(forUser: userName) {
            return accountHome
        }
        guard let accountHomePath = NSHomeDirectoryForUser(userName) else { return nil }
        return URL(fileURLWithPath: accountHomePath, isDirectory: true)
    }

    public static func canonicalFileURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    public static func chromeProfileDirectory(homeURL: URL? = nil) -> URL? {
        guard let homeURL = homeURL ?? currentUserHomeDirectory() else { return nil }
        return homeURL.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    public static func isChromeProfileDirectory(selectedURL: URL, homeURL: URL? = nil) -> Bool {
        guard let chromeRoot = chromeProfileDirectory(homeURL: homeURL) else { return false }
        return canonicalFileURL(selectedURL) == canonicalFileURL(chromeRoot)
    }

    public static func chromeNativeMessagingDirectory(homeURL: URL? = nil) -> URL? {
        guard let chromeRoot = chromeProfileDirectory(homeURL: homeURL) else { return nil }
        return chromeNativeMessagingDirectory(chromeRootURL: chromeRoot)
    }

    public static func chromeNativeMessagingDirectory(chromeRootURL: URL) -> URL {
        chromeRootURL.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }

    public static func inboxDirectory(homeURL: URL? = nil) -> URL? {
        guard let chromeRoot = chromeProfileDirectory(homeURL: homeURL) else { return nil }
        return inboxDirectory(chromeRootURL: chromeRoot)
    }

    public static func inboxDirectory(chromeRootURL: URL) -> URL {
        chromeRootURL
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(inboxDirectoryName, isDirectory: true)
    }

    public static func nativeHostExecutable(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/MacOS/CaptionGrabNativeHost")
    }

    public static func extensionDirectory(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension", isDirectory: true)
    }
}
