import Foundation
import XCTest
@testable import MacSvnCore

final class WorkingCopyActionsViewModelTests: XCTestCase {
    @MainActor
    func testUpdateStoresSummaryAndRefreshesStatuses() async {
        let summary = UpdateSummary(updated: 2, conflicted: 1, revision: Revision(8))
        let actionProvider = FakeWorkingCopyActionProvider(updateResult: summary)
        let statusProvider = ActionStatusProvider(result: .success([
            FileStatus(path: "conflict.swift", itemStatus: .conflicted, revision: Revision(8), isTreeConflict: false)
        ]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.update(paths: ["Sources"], revision: Revision(7), setDepth: .immediates)
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .updateCompleted(summary))
        XCTAssertEqual(viewModel.lastUpdateSummary, summary)
        XCTAssertEqual(viewModel.refreshedStatuses.map(\.path), ["conflict.swift"])
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .update,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["Sources"],
                revision: Revision(7),
                setDepth: .immediates,
                recursive: false
            )
        ])
    }

    @MainActor
    func testCleanupRunsWithoutPathsAndRefreshesStatuses() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.cleanup()
        let actionCalls = await actionProvider.recordedCalls()
        let statusRequests = await statusProvider.requestedWorkingCopies()

        XCTAssertEqual(viewModel.state, .completed(.cleanup))
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .cleanup,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: [],
                revision: nil,
                setDepth: nil,
                recursive: false
            )
        ])
        XCTAssertEqual(statusRequests, [URL(fileURLWithPath: "/tmp/wc")])
    }

    @MainActor
    func testAddDeleteAndConfirmedRevertUsePathsAndRefreshStatuses() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.add(paths: ["new.swift"])
        await viewModel.delete(paths: ["old.swift"])
        await viewModel.revert(paths: ["changed.swift"], recursive: true, confirmed: true)
        let actionCalls = await actionProvider.recordedCalls()
        let statusRequests = await statusProvider.requestedWorkingCopies()

        XCTAssertEqual(viewModel.state, .completed(.revert))
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .add,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["new.swift"],
                revision: nil,
                setDepth: nil,
                recursive: false
            ),
            ActionCall(
                operation: .delete,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["old.swift"],
                revision: nil,
                setDepth: nil,
                recursive: false
            ),
            ActionCall(
                operation: .revert,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["changed.swift"],
                revision: nil,
                setDepth: nil,
                recursive: true
            )
        ])
        XCTAssertEqual(statusRequests, [
            URL(fileURLWithPath: "/tmp/wc"),
            URL(fileURLWithPath: "/tmp/wc"),
            URL(fileURLWithPath: "/tmp/wc")
        ])
    }

    @MainActor
    func testCopyMoveValidatesThenCallsProvider() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.copyMove(
            kind: .move,
            sourcePath: "a.txt",
            destinationPath: "dir/a.txt",
            existingPaths: ["a.txt"]
        )
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(.move))
        XCTAssertEqual(actionCalls.map(\.operation), [.repairMove])
        XCTAssertEqual(actionCalls.first?.paths, ["a.txt", "dir/a.txt"])
    }

    @MainActor
    func testCopyMoveRejectsInvalidDestinationWithoutCallingProvider() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.copyMove(
            kind: .copy,
            sourcePath: "a.txt",
            destinationPath: "/abs/a.txt",
            existingPaths: ["a.txt"]
        )
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("目标须为工作副本内相对路径"))
        XCTAssertTrue(actionCalls.isEmpty)
    }

    @MainActor
    func testRenameValidatesThenCallsProviderAndRefreshes() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.rename(
            sourcePath: "src/a.txt",
            newName: "b.txt",
            existingPaths: ["src/a.txt", "src/c.txt"]
        )
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(.rename))
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .rename,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["src/a.txt", "src/b.txt"],
                revision: nil,
                setDepth: nil,
                recursive: false
            )
        ])
    }

    @MainActor
    func testRenameRejectsInvalidNameWithoutCallingProvider() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.rename(sourcePath: "a.txt", newName: "a.txt", existingPaths: ["a.txt"])
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("新名称与当前名称相同"))
        XCTAssertTrue(actionCalls.isEmpty)
    }

    @MainActor
    func testRevertRequiresConfirmationBeforeCallingProvider() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.revert(paths: ["changed.swift"], recursive: false, confirmed: false)
        let actionCalls = await actionProvider.recordedCalls()
        let statusRequests = await statusProvider.requestedWorkingCopies()

        XCTAssertEqual(viewModel.state, .confirmationRequired(.revert, ["changed.swift"]))
        XCTAssertTrue(actionCalls.isEmpty)
        XCTAssertTrue(statusRequests.isEmpty)
    }

    @MainActor
    func testPathActionsRejectEmptyPathsBeforeCallingProvider() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.add(paths: [])
        XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))

        await viewModel.delete(paths: [])
        XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))

        await viewModel.revert(paths: [], recursive: false, confirmed: true)
        let actionCalls = await actionProvider.recordedCalls()
        XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))
        XCTAssertTrue(actionCalls.isEmpty)
    }

    @MainActor
    func testActionFailureStoresErrorAndDoesNotRefreshStatuses() async {
        let actionProvider = FakeWorkingCopyActionProvider(addError: .wcLocked)
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.add(paths: ["new.swift"])
        let statusRequests = await statusProvider.requestedWorkingCopies()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.wcLocked)))
        XCTAssertTrue(statusRequests.isEmpty)
    }

    @MainActor
    func testRepairMovePairsMissingAndUnversionedThenRefreshes() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([
            FileStatus(path: "new.txt", itemStatus: .added, revision: nil, isTreeConflict: false)
        ]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )
        let statuses = [
            FileStatus(path: "old.txt", itemStatus: .missing, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "new.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        await viewModel.repairMove(selectedPaths: ["old.txt", "new.txt"], statuses: statuses)
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(.repairMove))
        XCTAssertEqual(viewModel.refreshedStatuses.map(\.path), ["new.txt"])
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .repairMove,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["old.txt", "new.txt"],
                revision: nil,
                setDepth: nil,
                recursive: false
            )
        ])
    }

    @MainActor
    func testRepairCopyPairsVersionedAndUnversionedThenRefreshes() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )
        let statuses = [
            FileStatus(path: "foo.txt", itemStatus: .modified, revision: Revision(2), isTreeConflict: false),
            FileStatus(path: "foo-copy.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        await viewModel.repairCopy(selectedPaths: ["foo.txt", "foo-copy.txt"], statuses: statuses)
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(.repairCopy))
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .repairCopy,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["foo.txt", "foo-copy.txt"],
                revision: nil,
                setDepth: nil,
                recursive: false
            )
        ])
    }

    @MainActor
    func testRepairMoveRejectsInvalidPairWithoutCallingProvider() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )
        let statuses = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "b.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        await viewModel.repairMove(selectedPaths: ["a.txt", "b.txt"], statuses: statuses)
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(
            viewModel.state,
            .error(RepairMoveCopyPairing.ValidationError.invalidMovePair.localizedDescription)
        )
        XCTAssertTrue(actionCalls.isEmpty)
    }
}

private struct ActionCall: Equatable, Sendable {
    let operation: WorkingCopyOperation
    let wc: URL
    let paths: [String]
    let revision: Revision?
    let setDepth: SvnDepth?
    let recursive: Bool
}

private actor FakeWorkingCopyActionProvider: WorkingCopyActionProviding {
    private let updateResult: UpdateSummary
    private let updateError: SvnError?
    private let addError: SvnError?
    private let deleteError: SvnError?
    private let repairMoveError: SvnError?
    private let repairCopyError: SvnError?
    private let revertError: SvnError?
    private let cleanupError: SvnError?
    private var calls: [ActionCall] = []

    init(
        updateResult: UpdateSummary = UpdateSummary(),
        updateError: SvnError? = nil,
        addError: SvnError? = nil,
        deleteError: SvnError? = nil,
        repairMoveError: SvnError? = nil,
        repairCopyError: SvnError? = nil,
        revertError: SvnError? = nil,
        cleanupError: SvnError? = nil
    ) {
        self.updateResult = updateResult
        self.updateError = updateError
        self.addError = addError
        self.deleteError = deleteError
        self.repairMoveError = repairMoveError
        self.repairCopyError = repairCopyError
        self.revertError = revertError
        self.cleanupError = cleanupError
    }

    func recordedCalls() -> [ActionCall] {
        calls
    }

    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?) async throws -> UpdateSummary {
        calls.append(ActionCall(
            operation: .update,
            wc: wc,
            paths: paths,
            revision: revision,
            setDepth: setDepth,
            recursive: false
        ))
        if let updateError {
            throw updateError
        }

        return updateResult
    }

    func add(wc: URL, paths: [String]) async throws {
        calls.append(ActionCall(operation: .add, wc: wc, paths: paths, revision: nil, setDepth: nil, recursive: false))
        if let addError {
            throw addError
        }
    }

    func delete(wc: URL, paths: [String]) async throws {
        calls.append(ActionCall(operation: .delete, wc: wc, paths: paths, revision: nil, setDepth: nil, recursive: false))
        if let deleteError {
            throw deleteError
        }
    }

    func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        calls.append(ActionCall(
            operation: .repairMove,
            wc: wc,
            paths: [source, destination],
            revision: nil,
            setDepth: nil,
            recursive: false
        ))
        if let repairMoveError {
            throw repairMoveError
        }
    }

    func renameInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        calls.append(ActionCall(
            operation: .rename,
            wc: wc,
            paths: [source, destination],
            revision: nil,
            setDepth: nil,
            recursive: false
        ))
    }

    func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        calls.append(ActionCall(
            operation: .repairCopy,
            wc: wc,
            paths: [source, destination],
            revision: nil,
            setDepth: nil,
            recursive: false
        ))
        if let repairCopyError {
            throw repairCopyError
        }
    }

    func revert(wc: URL, paths: [String], recursive: Bool) async throws {
        calls.append(ActionCall(operation: .revert, wc: wc, paths: paths, revision: nil, setDepth: nil, recursive: recursive))
        if let revertError {
            throw revertError
        }
    }

    func cleanup(wc: URL, options: SvnCleanupOptions) async throws {
        calls.append(ActionCall(operation: .cleanup, wc: wc, paths: [], revision: nil, setDepth: nil, recursive: false))
        if let cleanupError {
            throw cleanupError
        }
    }
}

private actor ActionStatusProvider: StatusProviding {
    private let result: Result<[FileStatus], Error>
    private var requests: [URL] = []

    init(result: Result<[FileStatus], Error>) {
        self.result = result
    }

    func requestedWorkingCopies() -> [URL] {
        requests
    }

    func status(wc: URL) async throws -> [FileStatus] {
        requests.append(wc)
        return try result.get()
    }
}
