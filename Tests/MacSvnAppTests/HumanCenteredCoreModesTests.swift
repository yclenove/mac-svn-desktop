import Foundation
import XCTest
@testable import MacSvnApp

@MainActor
final class HumanCenteredCoreModesTests: XCTestCase {
    func testCoreModeWidthClassChangesAtDailyBaseline() {
        XCTAssertEqual(MacSvnCoreModeWidthClass.resolve(width: 1_179), .compact)
        XCTAssertEqual(MacSvnCoreModeWidthClass.resolve(width: 1_180), .regular)
    }

    func testLogFilterSummaryCountsEveryCombinableFilter() {
        XCTAssertEqual(
            MacSvnLogFilterSummary.activeCount(
                author: "alice",
                message: "fix",
                path: "Sources",
                stopOnCopy: true,
                offline: true
            ),
            5
        )
        XCTAssertEqual(
            MacSvnLogFilterSummary.activeCount(
                author: "  ",
                message: "",
                path: "",
                stopOnCopy: false,
                offline: false
            ),
            0
        )
    }

    func testCoreModeMetricsKeepMasterAndInspectorReadable() {
        XCTAssertEqual(MacSvnCoreModeMetrics.toolbarHeight, 48)
        XCTAssertGreaterThanOrEqual(MacSvnCoreModeMetrics.masterMinimumWidth, 320)
        XCTAssertGreaterThanOrEqual(MacSvnCoreModeMetrics.inspectorMinimumWidth, 360)
    }

    func testHistoryUsesCompactToolbarCombinableFiltersAndStableMasterDetail() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnLogView.swift"
        )
        let toolbar = try Self.sourceSection(
            source,
            from: "private var historyToolbar",
            to: "private var historyFilterBar"
        )
        let detailActions = try Self.sourceSection(
            source,
            from: "private func detailActions(",
            to: "private func logPathContextMenu("
        )

        XCTAssertTrue(source.contains("@State private var showFilterPopover"))
        XCTAssertTrue(source.contains("@FocusState private var isMessageFilterFocused"))
        XCTAssertTrue(toolbar.contains("historyLoadMenu"))
        XCTAssertTrue(toolbar.contains("historyMoreActionsMenu"))
        XCTAssertFalse(toolbar.contains("Button(\"AI Release Notes\")"))
        XCTAssertTrue(source.contains("MacSvnLogFilterSummary.activeCount"))
        XCTAssertTrue(source.contains("MacSvnCoreModeMetrics.masterIdealWidth"))
        XCTAssertTrue(detailActions.contains("Menu"))
    }

    func testRepositoryBrowserPrioritizesDirectoryAndUsesResponsiveInspector() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnRepoBrowserView.swift"
        )

        XCTAssertTrue(source.contains("GeometryReader"))
        XCTAssertTrue(source.contains("private func repositoryWorkspace(width:"))
        XCTAssertTrue(source.contains("private var favoritesMenu"))
        XCTAssertTrue(source.contains("private var selectedEntryActionsMenu"))
        XCTAssertTrue(source.contains("@State private var showInspectorPopover"))
        XCTAssertTrue(source.contains(".onTapGesture(count: 2)"))
        XCTAssertTrue(source.contains("private func openDirectory("))
        XCTAssertFalse(source.contains("HSplitView"))
    }

    func testBranchesUseSelectionDrivenInspectorAndCreateSheet() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnBranchesView.swift"
        )
        let mergeWizardSource = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift"
        )

        XCTAssertTrue(source.contains("@State private var selectedReferenceURL"))
        XCTAssertTrue(source.contains("@State private var referenceFilter"))
        XCTAssertTrue(source.contains("@State private var showCreateSheet"))
        XCTAssertTrue(source.contains("private var branchInspector"))
        XCTAssertTrue(source.contains("navigator.openMerge(sourceURL:"))
        XCTAssertFalse(source.contains("HSplitView"))
        XCTAssertTrue(mergeWizardSource.contains("navigator.consumePendingMergeSourceURL()"))
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func readRepoSource(at path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private static func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
