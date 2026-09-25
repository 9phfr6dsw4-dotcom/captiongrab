import Foundation

public enum ChromeCompanionConstants {
    public static let nativeHostName = "com.captiongrab.host"
    public static let extensionID = "kajphiodjnkmgeidbcndikaaegghiffi"
    public static let nativeHostManifestFileName = "\(nativeHostName).json"
    public static let supportDirectoryName = "CaptionGrab"
    public static let inboxDirectoryName = "ChromeInbox"
    public static let requestQueryName = "captiongrab_request"
    public static let legacyChromeFolderBookmarkKey = "CaptionGrab.chromeNativeMessagingFolderBookmark"

    public static func applicationSupportDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeURL.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    public static func chromeNativeMessagingDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupportDirectory(homeURL: homeURL)
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }

    public static func chromeNativeMessagingDirectory(chromeRootURL: URL) -> URL {
        chromeRootURL.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }

    public static func captionGrabSupportDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupportDirectory(homeURL: homeURL).appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    public static func transcriptInboxDirectory(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        captionGrabSupportDirectory(homeURL: homeURL).appendingPathComponent(inboxDirectoryName, isDirectory: true)
    }

    public static func clearLegacyChromeFolderBookmark(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyChromeFolderBookmarkKey)
    }

    public static func nativeHostExecutable(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/MacOS/CaptionGrabNativeHost")
    }

    public static func extensionDirectory(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension", isDirectory: true)
    }
}
