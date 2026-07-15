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
