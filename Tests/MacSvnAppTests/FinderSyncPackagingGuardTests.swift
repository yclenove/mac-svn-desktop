import Foundation
import XCTest

final class FinderSyncPackagingGuardTests: XCTestCase {
    func testFinderExtensionIsSandboxedAndUsesItsContainerSupportDirectory() throws {
        let project = try Self.readRepoSource(at: "MacSVN.xcodeproj/project.pbxproj")
        let source = try Self.readFinderSyncSource()
        let verifier = try Self.readRepoSource(at: "scripts/verify-finder-sync-appex.sh")
        let entitlements = try Self.readRepoSource(
            at: "Packaging/FinderSync/SVNStudioFinderSync.entitlements"
        )
        let finderConfigurations = project
            .components(separatedBy: "INFOPLIST_FILE = Packaging/FinderSync/Info.plist;")

        XCTAssertEqual(finderConfigurations.count, 3)
        for configurationPrefix in finderConfigurations.dropLast() {
            XCTAssertTrue(configurationPrefix.suffix(700).contains("ENABLE_APP_SANDBOX = YES;"))
            XCTAssertFalse(configurationPrefix.suffix(700).contains("ENABLE_APP_SANDBOX = NO;"))
        }
        XCTAssertTrue(source.contains("ProductBranding.supportDirectoryURL"))
        XCTAssertFalse(source.contains("homeDirectoryForCurrentUser"))
        XCTAssertFalse(source.contains("URL(fileURLWithPath: \"/usr/bin/env\")"))
        XCTAssertTrue(source.contains("/opt/homebrew/bin/svn"))
        XCTAssertTrue(source.contains("/usr/local/bin/svn"))
        XCTAssertTrue(verifier.contains("com.apple.security.app-sandbox"))
        XCTAssertTrue(verifier.contains("temporary-exception.files.absolute-path.read-only"))
        XCTAssertTrue(entitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertTrue(entitlements.contains("temporary-exception.files.absolute-path.read-only"))
        XCTAssertTrue(entitlements.contains("/opt/homebrew/"))
        XCTAssertTrue(entitlements.contains("/usr/local/"))
        for workingCopyPrefix in ["/Users/", "/Volumes/", "/private/tmp/"] {
            XCTAssertTrue(
                entitlements.contains(workingCopyPrefix),
                "Finder Sync must be able to read working copies under \(workingCopyPrefix)"
            )
            XCTAssertTrue(
                verifier.contains(workingCopyPrefix),
                "appex verifier must enforce working-copy access for \(workingCopyPrefix)"
            )
        }
    }

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

    func testExtensionDoesNotSilentlyDiscardStatusCommandFailures() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("Logger("))
        XCTAssertTrue(source.contains("process.standardError = stderr"))
        XCTAssertTrue(source.contains("svn command failed"))
        XCTAssertTrue(source.contains("svn command succeeded"))
        XCTAssertTrue(source.contains("let outputReaders = DispatchGroup()"))
        XCTAssertTrue(source.contains("drainOutput("))
        XCTAssertTrue(source.contains("outputReaders.wait()"))
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

    func testExtensionProvidesNormalAndTortoiseExtendedFinderMenus() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("更多命令…"))
        XCTAssertTrue(source.contains("menuPlan.promotedCommandIDs"))
        XCTAssertTrue(source.contains("menuPlan.submenuCommandIDs"))
        XCTAssertTrue(source.contains("SvnCommandCatalog.descriptor(for: commandID)"))
        XCTAssertTrue(source.contains("descriptor.displayName"))
        XCTAssertTrue(source.contains("commandID"))
        XCTAssertTrue(source.contains("submenu"))
        XCTAssertTrue(source.contains("selectedItemURLs()"))
        XCTAssertTrue(source.contains(".map(\\.path)"))
        XCTAssertTrue(source.contains("paths: paths"))
    }

    func testExtensionBuildsConfiguredMenusFromSynchronousStatusSnapshots() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("FinderSyncContextMenuBuilder"))
        XCTAssertTrue(source.contains("FinderSyncMenuStateSnapshot"))
        XCTAssertTrue(source.contains("configuration.contextMenuSettings"))
        XCTAssertTrue(source.contains("menuStateSnapshot.plan(for: paths)"))
        XCTAssertTrue(source.contains("menuPlan.isHidden"))
        XCTAssertTrue(source.contains("menuPlan.promotedCommandIDs"))
        XCTAssertTrue(source.contains("menuPlan.submenuCommandIDs"))
        XCTAssertTrue(source.contains("menuSnapshot.update(root: root, statuses: statuses)"))
    }

    func testSettingsPersistsAndExportsFinderContextMenuSettings() throws {
        let featureSource = try Self.readFeatureSource(named: "MacSvnSettingsView.swift")
        let sessionSource = try Self.readRepoSource(at: "Sources/MacSvnApp/App/MacSvnAppSession.swift")

        XCTAssertTrue(featureSource.contains("Section(\"Finder 菜单\")"))
        XCTAssertTrue(featureSource.contains("finderSyncPromotedCommandIDs"))
        XCTAssertTrue(featureSource.contains("finderSyncPromoteLockForNeedsLock"))
        XCTAssertTrue(featureSource.contains("finderSyncHideUnversionedMenus"))
        XCTAssertTrue(featureSource.contains("finderSyncMenuExcludedPaths"))
        XCTAssertTrue(featureSource.contains("contextMenuSettings: settings.finderSyncContextMenuSettings"))
        XCTAssertTrue(sessionSource.contains("contextMenuSettings: settings.finderSyncContextMenuSettings"))
    }

    func testChangesPageConsumesFinderCopyMoveIntentAndOpensSheet() throws {
        let source = try Self.readFeatureSource(named: "MacSvnChangesView.swift")

        XCTAssertTrue(source.contains("navigator?.pendingCopyMoveIntent"))
        XCTAssertTrue(source.contains("consumePendingCopyMoveIntent"))
        XCTAssertTrue(source.contains("relativePaths(under: record.localPath)"))
        XCTAssertTrue(source.contains("showCopyMoveSheet = true"))
    }

    func testPropertiesPageProvidesTortoiseEquivalentSVNInformationSummary() throws {
        let source = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")

        XCTAssertTrue(source.contains("SVN 信息"))
        XCTAssertTrue(source.contains("最后作者"))
        XCTAssertTrue(source.contains("仓库 URL"))
        XCTAssertTrue(source.contains("工作副本状态"))
        XCTAssertTrue(source.contains("锁定"))
        XCTAssertTrue(source.contains("属性摘要"))
        XCTAssertTrue(source.contains("session.svnService.info"))
        XCTAssertTrue(source.contains("session.svnService.status"))
    }

    func testPropertiesPageDiscardsStaleInformationLoadsAfterTargetChanges() throws {
        let source = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")

        XCTAssertTrue(source.contains("@State private var loadGeneration"))
        XCTAssertTrue(source.contains("loadGeneration += 1"))
        XCTAssertTrue(source.contains("guard generation == loadGeneration else { return }"))
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
