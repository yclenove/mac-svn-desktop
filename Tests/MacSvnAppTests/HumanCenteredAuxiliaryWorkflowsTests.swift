import Foundation
import XCTest
@testable import MacSvnApp
import MacSvnCore

final class HumanCenteredAuxiliaryWorkflowsTests: XCTestCase {
    func testAuxiliaryMetricsKeepMasterAndDetailReadable() {
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.toolbarHeight, 48)
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.masterWidth, 300)
        XCTAssertGreaterThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.masterMinimumWidth, 280)
        XCTAssertLessThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.masterMaximumWidth, 340)
        XCTAssertGreaterThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.detailMinimumWidth, 420)
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.feedbackHeight, 30)
    }

    func testAuxiliaryPathPresentationOnlyRelativizesTargetsInsideWorkingCopy() {
        let workingCopy = URL(fileURLWithPath: "/tmp/wc", isDirectory: true)

        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath("/tmp/wc", workingCopy: workingCopy),
            "."
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath(
                "/tmp/wc/src/a.swift",
                workingCopy: workingCopy
            ),
            "src/a.swift"
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath(
                "/tmp/wc-other/a.swift",
                workingCopy: workingCopy
            ),
            "/tmp/wc-other/a.swift"
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath("src/a.swift", workingCopy: workingCopy),
            "src/a.swift"
        )
    }

    func testAuxiliaryPathPresentationNamesWorkingCopyRootWithoutExposingDot() {
        XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "."), "工作副本根目录")
        XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "src/a.swift"), "src/a.swift")
    }

    func testPropertiesUseSearchableStableMasterDetailAndVisibleEditorAction() throws {
        let source = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")

        XCTAssertTrue(source.contains("@State private var searchText"))
        XCTAssertTrue(source.contains("@State private var selectedTemplateName"))
        XCTAssertTrue(source.contains("private var propertiesToolbar"))
        XCTAssertTrue(source.contains("private var propertiesWorkspace"))
        XCTAssertTrue(source.contains("private var propertiesMasterPane"))
        XCTAssertTrue(source.contains("private var propertyInspector"))
        XCTAssertTrue(source.contains("private var propertyList"))
        XCTAssertTrue(source.contains("private var propertyEditor"))
        XCTAssertTrue(source.contains("private var propertyEditorActions"))
        XCTAssertTrue(source.contains("Picker(\"模板\", selection: $selectedTemplateName)"))
        XCTAssertTrue(source.contains("HStack(spacing: 0)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains(".truncationMode(.middle)"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有属性\""))
        XCTAssertTrue(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryPathPresentation.relativePath("))
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    func testLocksUseTargetMasterDetailAndQualificationDrivenActions() throws {
        let source = try Self.readFeatureSource(named: "MacSvnLocksView.swift")

        XCTAssertTrue(source.contains("@State private var searchText"))
        XCTAssertTrue(source.contains("@State private var isApplyingLockIntent"))
        XCTAssertTrue(source.contains("private var locksToolbar"))
        XCTAssertTrue(source.contains("private var locksFeedback"))
        XCTAssertTrue(source.contains("private var locksWorkspace"))
        XCTAssertTrue(source.contains("private var locksMasterPane"))
        XCTAssertTrue(source.contains("private var lockDetailPane"))
        XCTAssertTrue(source.contains("private var eligibleReleasePaths"))
        XCTAssertTrue(source.contains("private var eligibleBreakPaths"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryPathList("))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有锁记录\""))
        XCTAssertTrue(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(source.contains("MacSvnLockActionPresentation.eligibleReleasePaths("))
        XCTAssertTrue(source.contains("LockActionPolicy.pathsEligibleForBreak("))
        XCTAssertTrue(source.contains("guard !isApplyingLockIntent else { return }"))
        XCTAssertTrue(source.contains("确认夺锁（svn lock --force）"))
        XCTAssertTrue(source.contains("确认打断锁（svn unlock --force）"))
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    func testLockActionPresentationRequiresOwnedLockEvidenceBeforeOfferingRelease() {
        let owned = SvnLock(
            target: "owned.txt",
            token: "token",
            owner: "me",
            comment: nil,
            created: nil,
            isOwnedByWorkingCopy: true,
            isRepositoryLocked: true
        )
        let other = SvnLock(
            target: "other.txt",
            token: nil,
            owner: "other",
            comment: nil,
            created: nil,
            isOwnedByWorkingCopy: false,
            isRepositoryLocked: true
        )

        XCTAssertEqual(
            MacSvnLockActionPresentation.eligibleReleasePaths(
                selected: ["owned.txt"],
                locks: []
            ),
            []
        )
        XCTAssertEqual(
            MacSvnLockActionPresentation.eligibleReleasePaths(
                selected: ["owned.txt", "other.txt"],
                locks: [owned, other]
            ),
            ["owned.txt"]
        )
        XCTAssertEqual(
            MacSvnLockActionPresentation.eligibleReleasePaths(
                selected: ["other.txt"],
                locks: [owned, other]
            ),
            []
        )
    }

    private static func readFeatureSource(named fileName: String) throws -> String {
        try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources/MacSvnApp/Features", isDirectory: true)
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
