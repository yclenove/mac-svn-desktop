import Foundation
import XCTest
import MacSvnCore
@testable import MacSvnApp

@MainActor
final class HumanCenteredWorkingCopyWorkspaceTests: XCTestCase {
    func testRowSelectionChangesDiffWithoutChangingCommitSelection() {
        let state = MacSvnWorkingCopyWorkspaceState()
        state.reconcileCommitCandidates(
            available: ["a.swift", "b.swift"],
            defaultSelected: ["a.swift", "b.swift"]
        )

        state.selectRows(["a.swift"], focusedPath: "a.swift")

        XCTAssertEqual(state.selectedPaths, ["a.swift"])
        XCTAssertEqual(state.focusedPath, "a.swift")
        XCTAssertEqual(state.commitPaths, ["a.swift", "b.swift"])
    }

    func testEditedCommitSelectionDoesNotAutoSelectNewCandidates() {
        let state = MacSvnWorkingCopyWorkspaceState()
        state.reconcileCommitCandidates(
            available: ["a", "b"],
            defaultSelected: ["a", "b"]
        )
        state.setCommitSelected(false, path: "b", userInitiated: true)
        state.reconcileCommitCandidates(
            available: ["a", "b", "c"],
            defaultSelected: ["a", "b", "c"]
        )

        XCTAssertEqual(state.commitPaths, ["a"])
    }

    func testReconcilingCommitCandidatesDoesNotClearNonCandidateDiffSelection() {
        let state = MacSvnWorkingCopyWorkspaceState()
        state.selectRows(["ignored.log"], focusedPath: "ignored.log")

        state.reconcileCommitCandidates(
            available: ["source.swift"],
            defaultSelected: ["source.swift"]
        )

        XCTAssertEqual(state.selectedPaths, ["ignored.log"])
        XCTAssertEqual(state.focusedPath, "ignored.log")
    }

    func testResetForWorkingCopyClearsAllSelectionState() {
        let state = MacSvnWorkingCopyWorkspaceState()
        state.selectRows(["old.swift"], focusedPath: "old.swift")
        state.reconcileCommitCandidates(
            available: ["old.swift"],
            defaultSelected: ["old.swift"]
        )
        state.setCommitSelected(false, path: "old.swift", userInitiated: true)

        state.resetForWorkingCopy()

        XCTAssertTrue(state.selectedPaths.isEmpty)
        XCTAssertNil(state.focusedPath)
        XCTAssertTrue(state.commitPaths.isEmpty)
        XCTAssertFalse(state.commitSelectionWasEdited)
    }

    func testCommitCompletionRequestsAChangesRefresh() {
        let state = MacSvnWorkingCopyWorkspaceState()

        state.requestChangesRefresh()
        state.requestChangesRefresh()

        XCTAssertEqual(state.changesRefreshGeneration, 2)
    }

    func testDiffPresentationTreatsIdleWithoutPathAsNoSelection() {
        XCTAssertEqual(
            MacSvnEmbeddedDiffPresentation.resolve(path: nil, state: .idle, diffText: ""),
            .noSelection
        )
        XCTAssertEqual(
            MacSvnEmbeddedDiffPresentation.resolve(path: "a", state: .loaded, diffText: ""),
            .noChanges(path: "a")
        )
    }

    func testWidthClassUsesCompactLayoutBelowBaseline() {
        XCTAssertEqual(MacSvnWorkspaceWidthClass.resolve(width: 1_179), .compact)
        XCTAssertEqual(MacSvnWorkspaceWidthClass.resolve(width: 1_180), .regular)
    }

    func testSidebarAndContextBarKeepStableHumanReadableLayout() throws {
        let root = try Self.readRepoSource(at: "Sources/MacSvnApp/App/MacSvnRootView.swift")
        let shell = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift"
        )

        XCTAssertTrue(
            root.contains("navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 320)")
        )
        XCTAssertTrue(root.contains("private func showInFinder("))
        XCTAssertTrue(root.contains("accessibilityLabel(\"添加工作副本\")"))
        XCTAssertTrue(root.contains("在 Finder 中显示"))
        XCTAssertTrue(shell.contains("private func repositoryContext("))
        XCTAssertTrue(shell.contains("Label(\"更多功能\", systemImage: \"ellipsis.circle\")"))
        XCTAssertTrue(shell.contains("Label(\"工具\", systemImage: \"wrench.and.screwdriver\")"))
    }

    func testEmbeddedChangesUsesLayeredToolbarsAndSharedCommitCheckboxes() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnChangesView.swift"
        )
        let primary = try Self.sourceSection(
            source,
            from: "private var primaryActions",
            to: "private var moreActionsMenu"
        )

        XCTAssertTrue(source.contains("private var primaryStatusBar"))
        XCTAssertTrue(source.contains("private var filterAndViewBar"))
        XCTAssertTrue(
            source.contains("Label(\"更多操作\", systemImage: \"ellipsis.circle\")")
        )
        XCTAssertTrue(source.contains("private func commitSelectionToggle("))
        XCTAssertTrue(source.contains("workspaceState?.setCommitSelected"))
        XCTAssertFalse(primary.contains("修复大小写"))
        XCTAssertFalse(primary.contains("复制/移动"))
        XCTAssertTrue(source.contains("Button(\"修复大小写…\")"))
    }

    func testWorkspaceCompositionOwnsOneSharedInteractionState() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift"
        )

        XCTAssertTrue(
            source.contains("@State private var workspaceState = MacSvnWorkingCopyWorkspaceState()")
        )
        XCTAssertTrue(source.contains("workspaceState: workspaceState"))
        XCTAssertTrue(source.contains("workspaceState.resetForWorkingCopy()"))
    }

    func testEmbeddedDiffShowsRealNoSelectionAndMovesRareActionsIntoMenu() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnDiffView.swift"
        )
        let toolbar = try Self.sourceSection(
            source,
            from: "private var embeddedToolbar",
            to: "private var standaloneToolbar"
        )

        XCTAssertTrue(source.contains("MacSvnEmbeddedDiffPresentation.resolve"))
        XCTAssertTrue(source.contains("选择一个文件查看差异"))
        XCTAssertTrue(source.contains("此文件没有可显示的文本差异"))
        XCTAssertTrue(
            source.contains("Label(\"更多 Diff 操作\", systemImage: \"ellipsis.circle\")")
        )
        XCTAssertFalse(toolbar.contains("与 URL 比较"))
        XCTAssertTrue(source.contains("private var moreDiffActionsMenu"))
    }

    func testEmbeddedCommitIsCollapsibleAndKeepsAIInAssistanceMenu() throws {
        let workspace = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift"
        )
        let commit = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnCommitView.swift"
        )

        XCTAssertTrue(workspace.contains("isCommitInspectorExpanded"))
        XCTAssertTrue(workspace.contains("MacSvnCommitInspectorMetrics.collapsedHeight"))
        XCTAssertTrue(
            commit.contains("Label(\"说明辅助\", systemImage: \"wand.and.stars\")")
        )
        XCTAssertFalse(commit.contains("Button(\"AI 生成说明\")"))
        XCTAssertFalse(commit.contains("Button(\"AI 预检\")"))
        XCTAssertTrue(commit.contains("workspaceState?.reconcileCommitCandidates"))
        XCTAssertTrue(commit.contains("private var embeddedInspectorHeader"))
        XCTAssertTrue(commit.contains(".buttonStyle(.borderedProminent)"))
    }

    func testMinimumWidthLayoutHidesRedundantLabelsAndKeepsFilePathsSingleLine() throws {
        let shell = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift"
        )
        let changes = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnChangesView.swift"
        )
        let commit = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnCommitView.swift"
        )
        let modeControl = try Self.sourceSection(
            shell,
            from: "private var modeControl",
            to: "private func repositoryContext("
        )
        let filterPicker = try Self.sourceSection(
            changes,
            from: "private var filterPicker",
            to: "private var columnsMenu"
        )
        let assistance = try Self.sourceSection(
            commit,
            from: "private var assistanceMenu",
            to: "private var selectedCommitCount"
        )

        XCTAssertTrue(modeControl.contains(".labelsHidden()"))
        XCTAssertGreaterThanOrEqual(
            filterPicker.components(separatedBy: ".labelsHidden()").count - 1,
            2
        )
        XCTAssertTrue(changes.contains("private func compactFlatRow("))
        XCTAssertTrue(changes.contains("private func detailedFlatRow("))
        XCTAssertTrue(changes.contains(".truncationMode(.middle)"))
        XCTAssertTrue(assistance.contains(".menuStyle(.borderlessButton)"))
        XCTAssertTrue(assistance.contains(".fixedSize()"))
    }

    func testCompactPaneMenusKeepIndicatorsAttachedAndDiffMoreActionVisible() throws {
        let shell = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift"
        )
        let changes = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnChangesView.swift"
        )
        let diff = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnDiffView.swift"
        )
        let columnsMenu = try Self.sourceSection(
            changes,
            from: "private var columnsMenu",
            to: "private var primaryActions"
        )
        let moreActions = try Self.sourceSection(
            changes,
            from: "private var moreActionsMenu",
            to: "private var deleteActionsMenu"
        )
        let diffToolbar = try Self.sourceSection(
            diff,
            from: "private var embeddedToolbar",
            to: "private var standaloneToolbar"
        )
        let advancedFeatures = try Self.sourceSection(
            shell,
            from: "private var advancedFeaturesMenu",
            to: "private var toolsMenu"
        )
        let tools = try Self.sourceSection(
            shell,
            from: "private var toolsMenu",
            to: "private func repositorySubtitle("
        )
        let diffMoreActions = try Self.sourceSection(
            diff,
            from: "private var moreDiffActionsMenu",
            to: "private var standaloneContent"
        )

        XCTAssertTrue(columnsMenu.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(moreActions.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(advancedFeatures.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(tools.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(diffMoreActions.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(diffToolbar.contains("minWidth: 44"))
        XCTAssertTrue(diffToolbar.contains("moreDiffActionsMenu"))
        XCTAssertTrue(diffToolbar.contains("Text(\"未选择文件\")\n                        .font(.caption2)\n                        .foregroundStyle(.tertiary)\n                        .lineLimit(1)"))
    }

    func testDesktopWindowDefaultsToDailyWorkingSizeAboveMinimum() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift"
        )

        XCTAssertTrue(source.contains(".frame(minWidth: 980, minHeight: 640)"))
        XCTAssertTrue(source.contains(".defaultSize(width: 1_180, height: 760)"))
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
