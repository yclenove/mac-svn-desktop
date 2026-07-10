import Foundation
import Observation

public protocol WorkingCopyActionProviding: Sendable {
    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?, ignoreExternals: Bool) async throws -> UpdateSummary
    func add(wc: URL, paths: [String]) async throws
    func delete(wc: URL, paths: [String]) async throws
    func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws
    func renameInWorkingCopy(wc: URL, source: String, destination: String) async throws
    func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func cleanup(wc: URL, options: SvnCleanupOptions) async throws
}

public enum WorkingCopyOperation: Equatable, Sendable {
    case update
    case add
    case delete
    case rename
    case copy
    case move
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

    public func update(
        paths: [String] = [],
        revision: Revision? = nil,
        setDepth: SvnDepth? = nil,
        ignoreExternals: Bool = false
    ) async {
        state = .running(.update)

        do {
            let summary = try await actionProvider.update(
                wc: workingCopy,
                paths: paths,
                revision: revision,
                setDepth: setDepth,
                ignoreExternals: ignoreExternals
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

    /// 同目录重命名：先校验新名，再 `svn rename`。
    public func rename(sourcePath: String, newName: String, existingPaths: Set<String>) async {
        switch RenameValidationPolicy.resolve(
            sourcePath: sourcePath,
            newName: newName,
            existingRelativePaths: existingPaths
        ) {
        case .failure(let error):
            state = .error(error.localizedDescription)
        case .success(let plan):
            await perform(.rename) {
                try await actionProvider.renameInWorkingCopy(
                    wc: workingCopy,
                    source: plan.sourcePath,
                    destination: plan.destinationPath
                )
            }
        }
    }

    /// 跨目录复制/移动向导：校验目标后 `svn copy` / `svn move`。
    public func copyMove(
        kind: CopyMoveKind,
        sourcePath: String,
        destinationPath: String,
        existingPaths: Set<String>
    ) async {
        switch CopyMoveValidationPolicy.resolve(
            kind: kind,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            existingRelativePaths: existingPaths
        ) {
        case .failure(let error):
            state = .error(error.localizedDescription)
        case .success(let plan):
            let operation: WorkingCopyOperation = plan.kind == .copy ? .copy : .move
            await perform(operation) {
                switch plan.kind {
                case .copy:
                    try await actionProvider.copyInWorkingCopy(
                        wc: workingCopy,
                        source: plan.sourcePath,
                        destination: plan.destinationPath
                    )
                case .move:
                    try await actionProvider.moveInWorkingCopy(
                        wc: workingCopy,
                        source: plan.sourcePath,
                        destination: plan.destinationPath
                    )
                }
            }
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

    public func cleanup(options: SvnCleanupOptions = .default) async {
        await perform(.cleanup) {
            try await actionProvider.cleanup(wc: workingCopy, options: options)
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
