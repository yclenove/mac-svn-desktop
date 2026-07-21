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

    func testCoreModeErrorPresentationSummarizesTransportFailures() {
        XCTAssertEqual(
            MacSvnCoreModeErrorPresentation.message(
                #"network(detail: "svn: E170013: Unable to connect\nsvn: E215004: Authentication failed\n")"#
            ),
            "仓库认证失败。请检查凭据或证书信任设置后重试。"
        )
        XCTAssertEqual(
            MacSvnCoreModeErrorPresentation.message(
                #"network(detail: "svn: E170013: SSL certificate verification failed\n")"#
            ),
            "SSL 证书校验失败。请检查服务器地址和证书信任设置后重试。"
        )
        XCTAssertEqual(
            MacSvnCoreModeErrorPresentation.message("network(detail: \"Process timed out after 120 seconds.\")"),
            "连接仓库超时。请检查网络后重试。"
        )
        XCTAssertEqual(
            MacSvnCoreModeErrorPresentation.message("名称不能为空"),
            "名称不能为空"
        )
    }

    func testRootPinsIntrinsicEmptyAndErrorStatesToFullTopLeadingWorkspace() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/App/MacSvnRootView.swift"
        )

        XCTAssertTrue(
            source.contains(
                ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"
            )
        )
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

    func testConflictWorkspaceSeparatesRowFocusBatchSelectionAndMergeActions() throws {
        let conflict = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift"
        )
        let merge = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift"
        )
        let mergeRun = try Self.sourceSection(
            merge,
            from: "private func run(dryRun:",
            to: "private func mergeActionColour("
        )

        XCTAssertTrue(conflict.contains("private var conflictToolbar"))
        XCTAssertTrue(conflict.contains("private var conflictFilterBar"))
        XCTAssertTrue(conflict.contains("private var bulkSelectionMenu"))
        XCTAssertTrue(conflict.contains("@State private var conflictReloadGeneration = 0"))
        XCTAssertTrue(conflict.contains("conflictReloadGeneration &+= 1"))
        XCTAssertTrue(conflict.contains("guard generation == conflictReloadGeneration"))
        XCTAssertTrue(conflict.contains("MacSvnCoreModeMetrics.masterIdealWidth"))
        XCTAssertTrue(conflict.contains("HStack(spacing: 0)"))
        XCTAssertTrue(conflict.contains("set: { listVM.setChecked(conflict.path, isChecked: $0) }"))
        XCTAssertTrue(conflict.contains("listVM.selectConflict(path: path)"))
        XCTAssertTrue(
            conflict.contains(".disabled(!ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict))")
        )
        XCTAssertFalse(conflict.contains("HSplitView"))
        XCTAssertTrue(merge.contains("private var mergeParameterPane"))
        XCTAssertTrue(merge.contains("private var mergeActions"))
        XCTAssertTrue(merge.contains("private var mergeResultPane"))
        XCTAssertEqual(
            merge.components(separatedBy: ".buttonStyle(.borderedProminent)").count - 1,
            1
        )
        XCTAssertFalse(merge.contains("affectedPaths.prefix("))
        XCTAssertTrue(merge.contains(".truncationMode(.middle)"))
        XCTAssertTrue(merge.contains(".help(affected.path)"))
        XCTAssertTrue(mergeRun.contains("viewModel.discardResults()"))
    }

    func testTextConflictDetailKeepsContextVisibleAndMovesAssistantsOutOfPrimaryActions() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift"
        )
        let detail = try Self.sourceSection(
            source,
            from: "private struct MacSvnMergeEditorPane",
            to: "private struct MacSvnTreeConflictPane"
        )
        let primaryActions = try Self.sourceSection(
            detail,
            from: "private func conflictPrimaryActions(",
            to: "private func conflictAssistMenu("
        )

        XCTAssertTrue(detail.contains("private var conflictDetailHeader"))
        XCTAssertTrue(detail.contains("Text(conflict.path)"))
        XCTAssertTrue(primaryActions.contains("conflictAssistMenu(editorVM)"))
        XCTAssertFalse(primaryActions.contains("AI 建议当前"))
        XCTAssertFalse(primaryActions.contains("外置 Merge"))
        XCTAssertTrue(detail.contains("hunk.resolvedLines()"))
        XCTAssertTrue(detail.contains("pane(\"Result\""))
        XCTAssertTrue(detail.contains("case .suggested, .previewed:"))
        XCTAssertFalse(detail.contains("else {\n            statusText = success"))
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
