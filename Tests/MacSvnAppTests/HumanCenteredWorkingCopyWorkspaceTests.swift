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
