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
    func testDeleteKeepingLocalUsesDedicatedOperationAndRefreshesStatuses() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.deleteKeepingLocal(paths: ["old.txt"])

        XCTAssertEqual(viewModel.state, .completed(.deleteKeepLocal))
        let actionCalls = await actionProvider.recordedCalls()
        XCTAssertEqual(actionCalls.map(\.operation), [.deleteKeepLocal])
    }

    @MainActor
    func testDeleteUnversionedPreparesCandidatesAndUsesDedicatedOperation() async {
        let actionProvider = FakeWorkingCopyActionProvider(
            unversionedResult: [
                FileStatus(path: "scratch.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
            ]
        )
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        let candidates = await viewModel.prepareUnversionedDeletion()
        await viewModel.deleteUnversioned(paths: candidates.map(\.path))

        XCTAssertEqual(candidates.map(\.path), ["scratch.txt"])
        XCTAssertEqual(viewModel.state, .completed(.deleteUnversioned))
        let actionCalls = await actionProvider.recordedCalls()
        XCTAssertEqual(actionCalls.map(\.operation), [.deleteUnversioned])
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
    func testFilenameCaseConflictRepairValidatesCallsProviderAndRefreshes() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.repairFilenameCaseConflict(
            sourcePath: "src/Foo.txt",
            newName: "foo.txt",
            existingPaths: ["src/Foo.txt"]
        )
        let actionCalls = await actionProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(.repairFilenameCaseConflict))
        XCTAssertEqual(actionCalls, [
            ActionCall(
                operation: .repairFilenameCaseConflict,
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["src/Foo.txt", "src/foo.txt"],
                revision: nil,
                setDepth: nil,
                recursive: false
            )
        ])
    }

    @MainActor
    func testFilenameCaseConflictRepairRejectsNonCaseOnlyRename() async {
        let actionProvider = FakeWorkingCopyActionProvider()
        let statusProvider = ActionStatusProvider(result: .success([]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            actionProvider: actionProvider,
            statusProvider: statusProvider
        )

        await viewModel.repairFilenameCaseConflict(
            sourcePath: "Foo.txt",
            newName: "bar.txt",
            existingPaths: ["Foo.txt"]
        )

        XCTAssertEqual(viewModel.state, .error("目标必须与当前名称仅大小写不同"))
        let actionCalls = await actionProvider.recordedCalls()
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
    func testRevertTrashSafetyRestoresLocalContentWhenSvnRevertFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingCopyRevert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("changed.swift")
        try Data("local changes".utf8).write(to: file)
        let status = FileStatus(
            path: "changed.swift",
            itemStatus: .modified,
            revision: Revision(1),
            isTreeConflict: false
        )
        let trashStore = ActionRevertTrashStore(root: root.appendingPathComponent("trash"))
        let actionProvider = FakeWorkingCopyActionProvider(
            revertError: .other(code: nil, stderr: "revert failed")
        )
        let statusProvider = ActionStatusProvider(result: .success([status]))
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: root,
            actionProvider: actionProvider,
            statusProvider: statusProvider,
            useTrashWhenReverting: true,
            revertSafetyService: RevertSafetyService(store: trashStore)
        )

        await viewModel.revert(paths: ["changed.swift"], confirmed: true)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "local changes")
        if case .error(let message) = viewModel.state {
            XCTAssertTrue(message.contains("revert failed"))
        } else {
            XCTFail("Expected revert error")
        }
    }

    @MainActor
    func testRevertSafetySettingCanUpdateWithoutRecreatingViewModel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingCopyRevertSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("changed.swift")
        try Data("local changes".utf8).write(to: file)
        let status = FileStatus(
            path: "changed.swift",
            itemStatus: .modified,
            revision: Revision(1),
            isTreeConflict: false
        )
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: root,
            actionProvider: FakeWorkingCopyActionProvider(
                revertError: .other(code: nil, stderr: "revert failed")
            ),
            statusProvider: ActionStatusProvider(result: .success([status])),
            useTrashWhenReverting: false,
            revertSafetyService: RevertSafetyService(store: ActionRevertTrashStore(
                root: root.appendingPathComponent("trash")
            ))
        )

        viewModel.updateSettings(useTrashWhenReverting: true)
        await viewModel.revert(paths: ["changed.swift"], confirmed: true)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "local changes")
    }

    @MainActor
    func testRevertTrashSafetyReportsRestoreFailureWithoutHidingSvnFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingCopyRevert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("changed.swift")
        try Data("local changes".utf8).write(to: file)
        let status = FileStatus(
            path: "changed.swift",
            itemStatus: .modified,
            revision: Revision(1),
            isTreeConflict: false
        )
        let viewModel = WorkingCopyActionsViewModel(
            workingCopy: root,
            actionProvider: FakeWorkingCopyActionProvider(
                revertError: .other(code: nil, stderr: "svn revert failed")
            ),
            statusProvider: ActionStatusProvider(result: .success([status])),
            useTrashWhenReverting: true,
            revertSafetyService: RevertSafetyService(store: ActionRevertTrashStore(
                root: root.appendingPathComponent("trash"),
                failOnRestore: true
            ))
        )

        await viewModel.revert(paths: ["changed.swift"], confirmed: true)

        if case .error(let message) = viewModel.state {
            XCTAssertTrue(message.contains("svn revert failed"))
            XCTAssertTrue(message.contains("trash restore failed"))
        } else {
            XCTFail("Expected combined revert recovery error")
        }
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
    private let unversionedResult: [FileStatus]
    private var calls: [ActionCall] = []

    init(
        updateResult: UpdateSummary = UpdateSummary(),
        updateError: SvnError? = nil,
        addError: SvnError? = nil,
        deleteError: SvnError? = nil,
        repairMoveError: SvnError? = nil,
        repairCopyError: SvnError? = nil,
        revertError: SvnError? = nil,
        cleanupError: SvnError? = nil,
        unversionedResult: [FileStatus] = []
    ) {
        self.updateResult = updateResult
        self.updateError = updateError
        self.addError = addError
        self.deleteError = deleteError
        self.repairMoveError = repairMoveError
        self.repairCopyError = repairCopyError
        self.revertError = revertError
        self.cleanupError = cleanupError
        self.unversionedResult = unversionedResult
    }

    func recordedCalls() -> [ActionCall] {
        calls
    }

    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?, ignoreExternals: Bool) async throws -> UpdateSummary {
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

    func deleteKeepingLocal(wc: URL, paths: [String]) async throws {
        calls.append(ActionCall(operation: .deleteKeepLocal, wc: wc, paths: paths, revision: nil, setDepth: nil, recursive: false))
    }

    func deleteUnversioned(wc: URL, paths: [String]) async throws {
        calls.append(ActionCall(operation: .deleteUnversioned, wc: wc, paths: paths, revision: nil, setDepth: nil, recursive: false))
    }

    func unversionedPaths(wc: URL) async throws -> [FileStatus] {
        unversionedResult
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

    func repairFilenameCaseConflict(wc: URL, source: String, destination: String) async throws {
        calls.append(ActionCall(
            operation: .repairFilenameCaseConflict,
            wc: wc,
            paths: [source, destination],
            revision: nil,
            setDepth: nil,
            recursive: false
        ))
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

private final class ActionRevertTrashStore: RevertTrashStoring, @unchecked Sendable {
    private let root: URL
    private let failOnRestore: Bool

    init(root: URL, failOnRestore: Bool = false) {
        self.root = root
        self.failOnRestore = failOnRestore
    }

    func moveToTrash(_ sourceURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(sourceURL.lastPathComponent)
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }

    func restoreFromTrash(_ trashURL: URL, to originalURL: URL) throws {
        if failOnRestore {
            throw SvnError.parse(detail: "trash restore failed")
        }
        try FileManager.default.moveItem(at: trashURL, to: originalURL)
    }
}
