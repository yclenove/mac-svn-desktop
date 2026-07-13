import Foundation
import XCTest

final class FinderSyncPackagingGuardTests: XCTestCase {
    func testExtensionRegistersEveryTortoiseParityBadge() throws {
        let source = try Self.readFinderSyncSource()
        let badges = [
            "normal", "modified", "conflicted", "added", "deleted", "missing", "replaced",
            "locked", "needsLock", "ignored", "unversioned", "shallow", "nested", "external",
            "switched", "mergeInfo", "incomplete", "obstructed"
        ]

        for badge in badges {
            XCTAssertTrue(source.contains("(.\(badge),"), "Finder Sync must register .\(badge)")
        }
        XCTAssertFalse(source.contains("presentation.badge == .normal ? \"\""))
    }

    func testExtensionCollectsVerboseIgnoredAndOverlayMetadata() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("\"--verbose\""))
        XCTAssertTrue(source.contains("\"--no-ignore\""))
        XCTAssertTrue(source.contains("FinderSyncInfoXMLParser.parseDepths"))
        XCTAssertTrue(source.contains("PropertyXMLParser.parse"))
        XCTAssertTrue(source.contains("FinderSyncStatusEnricher.enrich"))
    }

    func testExtensionCoalescesConcurrentStatusRefreshesPerWorkingCopy() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("private var inFlight:"))
        XCTAssertTrue(source.contains("if let task = inFlight[key]"))
        XCTAssertTrue(source.contains("inFlight[key] = task"))
        XCTAssertTrue(source.contains("inFlight[key] = nil"))
    }

    func testExtensionHonorsDefaultShellAndNoneCacheModes() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("FinderSyncRootsExporter.loadConfiguration"))
        XCTAssertTrue(source.contains("FinderSyncCachePolicy(mode:"))
        XCTAssertTrue(source.contains("statusScope(requestedTarget:"))
        XCTAssertTrue(source.contains("guard policy.collectsBadges"))
        XCTAssertTrue(source.contains("requestedTarget:"))
    }

    func testConfigurationChangesDiscardOldInFlightResultsBeforeRegisteringDirectories() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("private var configurationGeneration"))
        XCTAssertTrue(source.contains("guard generation == configurationGeneration"))
        XCTAssertTrue(source.contains("await cache.updateConfiguration(configuration)"))
        XCTAssertTrue(source.contains("await MainActor.run"))
    }

    func testExtensionWatchesConfigurationDirectoryAcrossAtomicReplacements() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("let directoryPath = support.path"))
        XCTAssertTrue(source.contains("open(directoryPath, O_EVTONLY)"))
        XCTAssertFalse(source.contains("open(fileURL.path, O_EVTONLY)"))
    }

    func testSettingsPersistsAndExportsFinderSyncCacheMode() throws {
        let source = try Self.readFeatureSource(named: "MacSvnSettingsView.swift")

        XCTAssertTrue(source.contains("@State private var finderSyncCacheMode"))
        XCTAssertTrue(source.contains("Picker(\"Status Cache\""))
        XCTAssertTrue(source.contains("settings.finderSyncCacheMode = finderSyncCacheMode"))
        XCTAssertTrue(source.contains("cacheMode: settings.finderSyncCacheMode"))
    }

    func testSettingsExportsFinderSyncOverlayFiltersAndEnabledBadges() throws {
        let featureSource = try Self.readFeatureSource(named: "MacSvnSettingsView.swift")
        let sessionSource = try Self.readRepoSource(at: "Sources/MacSvnApp/App/MacSvnAppSession.swift")

        XCTAssertTrue(featureSource.contains("finderSyncOverlaySettings"))
        XCTAssertTrue(featureSource.contains("finderSyncIncludedPaths"))
        XCTAssertTrue(featureSource.contains("finderSyncExcludedPaths"))
        XCTAssertTrue(featureSource.contains("finderSyncEnabledBadges"))
        XCTAssertTrue(sessionSource.contains("overlaySettings: settings.finderSyncOverlaySettings"))
    }

    func testExtensionAppliesFinderSyncOverlaySettingsBeforeCollectingBadges() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("overlaySettings.allows(path: normalized)"))
        XCTAssertTrue(source.contains("configuration.overlaySettings"))
        XCTAssertTrue(source.contains(".monitoredDirectories(for: configuration.roots)"))
        XCTAssertTrue(source.contains("overlaySettings: context.overlaySettings"))
    }

    private static func readFinderSyncSource() throws -> String {
        try readRepoSource(at: "Packaging/FinderSync/MacSvnFinderSync.swift")
    }

    private static func readFeatureSource(named fileName: String) throws -> String {
        try readRepoSource(at: "Sources/MacSvnApp/Features/\(fileName)")
    }

    private static func readRepoSource(at path: String) throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
