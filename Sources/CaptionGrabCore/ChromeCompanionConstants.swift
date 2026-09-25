import Foundation

public enum ChromeCompanionConstants {
    public static let nativeHostName = "com.captiongrab.host"
    public static let extensionID = "kajphiodjnkmgeidbcndikaaegghiffi"
    public static let nativeHostManifestFileName = "\(nativeHostName).json"
    public static let applicationBundleIdentifier = "com.captiongrab.app"
    public static let supportDirectoryName = "CaptionGrab"
    public static let inboxDirectoryName = "ChromeInbox"
    public static let requestQueryName = "captiongrab_request"
    public static let chromeFolderBookmarkKey = "CaptionGrab.chromeNativeMessagingFolderBookmark"

    public static func chromeProfileDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeURL.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    public static func chromeNativeMessagingDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        chromeNativeMessagingDirectory(chromeRootURL: chromeProfileDirectory(homeURL: homeURL))
    }

    public static func chromeNativeMessagingDirectory(chromeRootURL: URL) -> URL {
        chromeRootURL.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }

    public static func inboxDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeURL
            .appendingPathComponent("Library/Containers/\(applicationBundleIdentifier)/Data/Library/Application Support", isDirectory: true)
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
