import Foundation
import XCTest
@testable import CaptionGrabCore

final class CaptionGrabInstallationLocatorTests: XCTestCase {
    private let bundleIdentifier = "com.captiongrab.app"
    private let shortVersion = "1.2.2"
    private let buildVersion = "6"

    func testDetectsAppTranslocationByPathComponent() {
        let translocatedURL = URL(fileURLWithPath: "/var/folders/ab/AppTranslocation/1234/d/CaptionGrab.app")
        let ordinaryURL = URL(fileURLWithPath: "/Applications/CaptionGrab.app")

        XCTAssertTrue(CaptionGrabInstallationLocator.isAppTranslocated(bundleURL: translocatedURL))
        XCTAssertFalse(CaptionGrabInstallationLocator.isAppTranslocated(bundleURL: ordinaryURL))
    }

    func testKeepsTheRunningBundleWhenItIsNotTranslocated() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let runningURL = temporaryDirectory.appendingPathComponent("CaptionGrab.app", isDirectory: true)
        let otherURL = temporaryDirectory.appendingPathComponent("Other.app", isDirectory: true)

        let resolved = CaptionGrabInstallationLocator.resolvedBundleURL(
            runningBundleURL: runningURL,
            registeredBundleURLs: [otherURL],
            expectedBundleIdentifier: bundleIdentifier,
            expectedShortVersion: shortVersion,
            expectedBuildVersion: buildVersion
        )

        XCTAssertEqual(resolved?.path, runningURL.standardizedFileURL.path)
    }

    func testFindsMatchingStableLaunchServicesInstallationAndSkipsWrongOrTranslocatedCopies() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let runningURL = URL(fileURLWithPath: "/var/folders/ab/AppTranslocation/1234/d/CaptionGrab.app")
        let wrongVersionURL = temporaryDirectory.appendingPathComponent("Old.app", isDirectory: true)
        let nestedTranslocationURL = temporaryDirectory
            .appendingPathComponent("AppTranslocation/5678/d/CaptionGrab.app", isDirectory: true)
        let installedURL = temporaryDirectory.appendingPathComponent("Applications/CaptionGrab.app", isDirectory: true)
        try makeAppBundle(at: wrongVersionURL, shortVersion: "1.2.1", buildVersion: "5")
        try makeAppBundle(at: nestedTranslocationURL)
        try makeAppBundle(at: installedURL)

        let resolved = CaptionGrabInstallationLocator.resolvedBundleURL(
            runningBundleURL: runningURL,
            registeredBundleURLs: [wrongVersionURL, nestedTranslocationURL, installedURL],
            expectedBundleIdentifier: bundleIdentifier,
            expectedShortVersion: shortVersion,
            expectedBuildVersion: buildVersion
        )

        XCTAssertEqual(resolved, installedURL.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testRejectsStableBundleWithWrongIdentifierOrMissingNativeHost() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let wrongIdentifierURL = temporaryDirectory.appendingPathComponent("Wrong.app", isDirectory: true)
        let missingHostURL = temporaryDirectory.appendingPathComponent("Incomplete.app", isDirectory: true)
        let missingExtensionURL = temporaryDirectory.appendingPathComponent("NoExtension.app", isDirectory: true)
        try makeAppBundle(at: wrongIdentifierURL, bundleIdentifier: "com.example.other")
        try makeAppBundle(at: missingHostURL, includeNativeHost: false)
        try makeAppBundle(at: missingExtensionURL, includeExtension: false)

        let resolved = CaptionGrabInstallationLocator.resolvedBundleURL(
            runningBundleURL: URL(fileURLWithPath: "/var/folders/ab/AppTranslocation/1234/d/CaptionGrab.app"),
            registeredBundleURLs: [wrongIdentifierURL, missingHostURL, missingExtensionURL],
            expectedBundleIdentifier: bundleIdentifier,
            expectedShortVersion: shortVersion,
            expectedBuildVersion: buildVersion
        )

        XCTAssertNil(resolved)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionGrabInstallationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeAppBundle(
        at bundleURL: URL,
        bundleIdentifier: String? = nil,
        shortVersion: String? = nil,
        buildVersion: String? = nil,
        includeNativeHost: Bool = true,
        includeExtension: Bool = true
    ) throws {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let info: [String: String] = [
            "CFBundleIdentifier": bundleIdentifier ?? self.bundleIdentifier,
            "CFBundleShortVersionString": shortVersion ?? self.shortVersion,
            "CFBundleVersion": buildVersion ?? self.buildVersion,
            "CFBundleExecutable": "CaptionGrab"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        if includeNativeHost {
            let hostURL = ChromeCompanionConstants.nativeHostExecutable(bundleURL: bundleURL)
            try Data("fixture".utf8).write(to: hostURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostURL.path)
        }
        if includeExtension {
            let extensionURL = ChromeCompanionConstants.extensionDirectory(bundleURL: bundleURL)
            try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: extensionURL.appendingPathComponent("manifest.json"))
        }
    }
}
