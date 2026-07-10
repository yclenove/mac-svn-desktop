import Foundation
import Observation

public protocol WorkingCopyActionProviding: Sendable {
    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?) async throws -> UpdateSummary
    func add(wc: URL, paths: [String]) async throws
    func delete(wc: URL, paths: [String]) async throws
    func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws
    func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func cleanup(wc: URL) async throws
}

public enum WorkingCopyOperation: Equatable, Sendable {
    case update
    case add
    case delete
    case repairMove
    case repairCopy
    case revert
    case cleanup
}

public enum WorkingCopyActionState: Equatable, Sendable {
    case idle
    case running(WorkingCopyOperation)
    case updateCompleted(UpdateSummary)
    case completed(WorkingCopyOperation)
    case confirmationRequired(WorkingCopyOperation, [String])
    case error(String)
}

@MainActor
@Observable
public final class WorkingCopyActionsViewModel {
    private let workingCopy: URL
    private let actionProvider: any WorkingCopyActionProviding
    private let statusProvider: any StatusProviding

    public private(set) var state: WorkingCopyActionState = .idle
    public private(set) var lastUpdateSummary: UpdateSummary?
    public private(set) var refreshedStatuses: [FileStatus] = []

    public init(
        workingCopy: URL,
        actionProvider: any WorkingCopyActionProviding,
        statusProvider: any StatusProviding
    ) {
        self.workingCopy = workingCopy
        self.actionProvider = actionProvider
        self.statusProvider = statusProvider
    }

    public var isRunning: Bool {
        if case .running = state {
            return true
        }

        return false
    }

    public func update(paths: [String] = [], revision: Revision? = nil, setDepth: SvnDepth? = nil) async {
        state = .running(.update)

        do {
            let summary = try await actionProvider.update(
                wc: workingCopy,
                paths: paths,
                revision: revision,
                setDepth: setDepth
            )
            lastUpdateSummary = summary
            refreshedStatuses = try await statusProvider.status(wc: workingCopy)
            state = .updateCompleted(summary)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func add(paths: [String]) async {
        await performPathAction(.add, paths: paths) {
            try await actionProvider.add(wc: workingCopy, paths: paths)
        }
    }

    public func delete(paths: [String]) async {
        await performPathAction(.delete, paths: paths) {
            try await actionProvider.delete(wc: workingCopy, paths: paths)
        }
    }

    /// CFM Repair Move：先配对校验，再 `svn move --force`，成功后刷新 status。
    public func repairMove(selectedPaths: Set<String>, statuses: [FileStatus]) async {
        await performRepair(kind: .move, selectedPaths: selectedPaths, statuses: statuses)
    }

    /// CFM Repair Copy：先配对校验，再 `svn copy --force`，成功后刷新 status。
    public func repairCopy(selectedPaths: Set<String>, statuses: [FileStatus]) async {
        await performRepair(kind: .copy, selectedPaths: selectedPaths, statuses: statuses)
    }

    public func revert(paths: [String], recursive: Bool = false, confirmed: Bool) async {
        guard validateSelectedPaths(paths) else {
            return
        }

        guard confirmed else {
            state = .confirmationRequired(.revert, paths)
            return
        }

        await perform(.revert) {
            try await actionProvider.revert(wc: workingCopy, paths: paths, recursive: recursive)
        }
    }

    public func cleanup() async {
        await perform(.cleanup) {
            try await actionProvider.cleanup(wc: workingCopy)
        }
    }

    private func performRepair(
        kind: RepairMoveCopyKind,
        selectedPaths: Set<String>,
        statuses: [FileStatus]
    ) async {
        switch RepairMoveCopyPairing.resolve(kind: kind, selectedPaths: selectedPaths, statuses: statuses) {
        case .failure(let error):
            state = .error(error.localizedDescription)
        case .success(let pair):
            let operation: WorkingCopyOperation = kind == .move ? .repairMove : .repairCopy
            await perform(operation) {
                switch kind {
                case .move:
                    try await actionProvider.moveInWorkingCopy(
                        wc: workingCopy,
                        source: pair.sourcePath,
                        destination: pair.destinationPath
                    )
                case .copy:
                    try await actionProvider.copyInWorkingCopy(
                        wc: workingCopy,
                        source: pair.sourcePath,
                        destination: pair.destinationPath
                    )
                }
            }
        }
    }

    private func performPathAction(
        _ operation: WorkingCopyOperation,
        paths: [String],
        action: () async throws -> Void
    ) async {
        guard validateSelectedPaths(paths) else {
            return
        }

        await perform(operation, action: action)
    }

    private func validateSelectedPaths(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            state = .error("noSelectedPaths")
            return false
        }

        return true
    }

    private func perform(
        _ operation: WorkingCopyOperation,
        action: () async throws -> Void
    ) async {
        state = .running(operation)

        do {
            try await action()
            refreshedStatuses = try await statusProvider.status(wc: workingCopy)
            state = .completed(operation)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: WorkingCopyActionProviding {}
