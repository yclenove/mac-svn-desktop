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

    func testShelveSeparatesCreationRecordSelectionAndPreviewActions() throws {
        let source = try Self.readFeatureSource(named: "MacSvnShelveView.swift")

        XCTAssertTrue(source.contains("@State private var showCreateShelfSheet"))
        XCTAssertTrue(source.contains("@State private var selectedShelfID"))
        XCTAssertTrue(source.contains("private var shelveToolbar"))
        XCTAssertTrue(source.contains("private var shelveFeedback"))
        XCTAssertTrue(source.contains("private var shelveWorkspace"))
        XCTAssertTrue(source.contains("private var shelfRecordList"))
        XCTAssertTrue(source.contains("private var shelfDetailPane"))
        XCTAssertTrue(source.contains("private var createShelfSheet"))
        XCTAssertTrue(source.contains("private var patchSheet"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shelve.patch.menu\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shelve.create.button\")"))
        XCTAssertTrue(source.contains(".fixedSize()"))
        XCTAssertTrue(source.contains("private func normalizedWorkingCopyPaths("))
        XCTAssertTrue(source.contains("selected = Set(normalizedWorkingCopyPaths(intent.paths))"))
        XCTAssertTrue(source.contains("normalizedWorkingCopyPaths(pendingPaths)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains("DiffPerformanceLimits.truncatedDisplayText("))
        XCTAssertTrue(source.contains("previewRunner.cancel()"))
        XCTAssertTrue(source.contains("previewRunner.enqueue("))
        XCTAssertTrue(source.contains("previewRequestID"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryLatestRequestPolicy.shouldApply("))
        XCTAssertTrue(source.contains("private var sheetErrorText"))
        XCTAssertTrue(source.contains("if let sheetErrorText"))
        XCTAssertTrue(source.contains("case .error(let message):"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有搁置记录\""))
        XCTAssertTrue(source.contains("确认删除官方 shelf"))
        XCTAssertTrue(source.contains("确认删除本地快照"))
        XCTAssertTrue(source.contains("确认迁移到官方 shelf"))
        XCTAssertTrue(source.contains("pendingMigrationSnapshot"))
        XCTAssertTrue(source.contains("Text(LocalizedStringKey(scope.rawValue))"))
        XCTAssertTrue(source.contains("Text(LocalizedStringKey(kind.rawValue))"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: ".macSvnDismissibleSheet()").count - 1,
            2,
            "创建搁置和 Patch sheet 都必须有统一关闭入口"
        )
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    func testLatestAuxiliaryRequestPolicyOnlyAppliesCurrentNonCancelledResult() {
        let current = UUID()
        let stale = UUID()

        XCTAssertTrue(
            MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                requestID: current,
                currentRequestID: current,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                requestID: stale,
                currentRequestID: current,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                requestID: current,
                currentRequestID: current,
                isCancelled: true
            )
        )
    }

    @MainActor
    func testLatestAuxiliaryRequestRunnerDebouncesSupersededWork() async throws {
        let runner = MacSvnAuxiliaryLatestRequestRunner()
        let probe = AuxiliaryRequestProbe()
        var received: [String] = []

        runner.enqueue(
            debounce: .milliseconds(60),
            operation: { await probe.run("stale") },
            receive: { _, result in
                if case .success(let value) = result { received.append(value) }
            }
        )
        runner.enqueue(
            debounce: .milliseconds(60),
            operation: { await probe.run("latest") },
            receive: { _, result in
                if case .success(let value) = result { received.append(value) }
            }
        )

        try await Task.sleep(for: .milliseconds(180))
        let started = await probe.startedValues()

        XCTAssertEqual(started, ["latest"])
        XCTAssertEqual(received, ["latest"])
    }

    func testShelveDynamicLabelsHaveEnglishResources() throws {
        let english = try String(
            contentsOf: Self.repoRoot
                .appendingPathComponent("Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )

        for key in [
            "本地搁置",
            "安全快照",
            "创建官方 Shelf",
            "创建本地搁置",
            "还没有官方 shelf",
            "还没有本地快照",
            "将所选工作副本变更写入 Patch 文件。",
            "从 Patch 文件恢复变更到当前工作副本。",
            "输出文件路径",
            "Patch 文件路径",
        ] {
            XCTAssertTrue(english.contains("\"\(key)\" = "), key)
            XCTAssertFalse(english.contains("\"\(key)\" = \"\(key)\";"), key)
        }
    }

    func testShelveFeedbackPresentationNeverReportsSuccessForFailures() {
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.loadOutcome(
                state: .error("offline"),
                officialError: nil
            ),
            .localFailure("offline")
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.loadOutcome(
                state: .loaded,
                officialError: "unsupported"
            ),
            .officialFailure("unsupported")
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.loadOutcome(
                state: .loaded,
                officialError: nil
            ),
            .refreshed
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.operationOutcome(
                state: .error("write failed"),
                expected: .officialShelve
            ),
            .failure("write failed")
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.operationOutcome(
                state: .completed(.officialShelve),
                expected: .officialShelve
            ),
            .success
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

private actor AuxiliaryRequestProbe {
    private var started: [String] = []

    func run(_ value: String) -> String {
        started.append(value)
        return value
    }

    func startedValues() -> [String] {
        started
    }
}
