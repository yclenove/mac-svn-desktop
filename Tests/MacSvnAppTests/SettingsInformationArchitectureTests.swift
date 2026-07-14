import Foundation
import XCTest
@testable import MacSvnApp

final class SettingsInformationArchitectureTests: XCTestCase {
    func testSettingsCategoryModelKeepsRequiredCategoriesAndTitlesInStableOrder() {
        XCTAssertEqual(
            MacSvnSettingsCategory.allCases,
            [.general, .dialogs, .colours, .network, .externalPrograms, .savedData,
             .finder, .revisionGraph, .ai]
        )
        XCTAssertEqual(
            MacSvnSettingsCategory.allCases.map(\.title),
            ["General", "Dialogs", "Colours", "Network", "External Programs", "Saved Data",
             "Finder", "Revision Graph", "AI"]
        )
        XCTAssertTrue(MacSvnSettingsCategory.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    func testSettingsPageProvidesTortoiseParityCategoryNavigation() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift"
        )

        XCTAssertTrue(source.contains("@State private var selectedCategory: MacSvnSettingsCategory? = .general"))
        XCTAssertTrue(source.contains("List(selection: $selectedCategory)"))
        XCTAssertTrue(source.contains("ForEach(MacSvnSettingsCategory.allCases"))
        XCTAssertTrue(source.contains(".tag(category)"))
        for category in [
            "case .general:",
            "case .dialogs:",
            "case .colours:",
            "case .network:",
            "case .externalPrograms:",
            "case .savedData:",
            "case .finder:",
            "case .revisionGraph:",
            "case .ai:",
        ] {
            XCTAssertTrue(source.contains(category), "missing settings category branch: \(category)")
        }
    }

    func testSettingsPageKeepsExistingLoadAndSaveMappings() throws {
        let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift")
        let load = try Self.sourceSection(source, from: "private func load()", to: "private func save()")
        let save = try Self.sourceSection(source, from: "private func save()", to: "private func clearLogCache()")

        let mappings = [
            ("svnPath", "settings.svnPath"),
            ("logBatchSize", "settings.logBatchSize"),
            ("processTimeout", "settings.processTimeout"),
            ("progressAutoCloseMode", "settings.progressAutoCloseMode"),
            ("shelvingVersion", "settings.shelvingVersion"),
            ("logCacheEnabled", "settings.logCachePolicy"),
            ("logCacheRetentionDays", "settings.logCachePolicy"),
            ("logCacheMaxEntries", "settings.logCachePolicy"),
            ("clientHooks", "settings.clientHooks"),
            ("finderSyncCacheMode", "settings.finderSyncCacheMode"),
            ("finderSyncIncludedPaths", "settings.finderSyncOverlaySettings"),
            ("finderSyncExcludedPaths", "settings.finderSyncOverlaySettings"),
            ("finderSyncEnabledBadges", "settings.finderSyncOverlaySettings"),
            ("finderSyncPromotedCommandIDs", "settings.finderSyncContextMenuSettings"),
            ("finderSyncPromoteLockForNeedsLock", "settings.finderSyncContextMenuSettings"),
            ("finderSyncHideUnversionedMenus", "settings.finderSyncContextMenuSettings"),
            ("finderSyncMenuExcludedPaths", "settings.finderSyncContextMenuSettings"),
            ("hardBlockConflictMarkers", "settings.commitGuardHardBlockConflictMarkers"),
            ("trunk", "settings.branchLayout"),
            ("branches", "settings.branchLayout"),
            ("tags", "settings.branchLayout"),
            ("graphTrunkPatterns", "settings.revisionGraph"),
            ("graphBranchPatterns", "settings.revisionGraph"),
            ("graphTagPatterns", "settings.revisionGraph"),
            ("graphBlendCopyColors", "settings.revisionGraph"),
            ("graphTrunkHex", "settings.revisionGraph"),
            ("graphBranchHex", "settings.revisionGraph"),
            ("graphTagHex", "settings.revisionGraph"),
            ("graphUnclassifiedHex", "settings.revisionGraph"),
            ("externalDiffName", "settings.externalDiffTool"),
            ("externalDiffPath", "settings.externalDiffTool"),
        ]
        for (state, setting) in mappings {
            XCTAssertTrue(load.contains(state), "load no longer maps \(state)")
            XCTAssertTrue(load.contains(setting), "load no longer reads \(setting)")
            XCTAssertTrue(save.contains(state), "save no longer maps \(state)")
            XCTAssertTrue(save.contains(setting), "save no longer writes \(setting)")
        }
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

    private static func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }
}
